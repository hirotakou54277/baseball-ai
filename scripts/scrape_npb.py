"""
NPB試合データ収集スクリプト
GitHub Actionsで毎日実行される

NPB URLパターン:
  トップページ:     https://npb.jp/games/{year}/
  月別スケジュール: https://npb.jp/games/{year}/schedule_{mm}_detail.html
  スコアページ:     https://npb.jp/scores/{year}/{mmdd}/{home}-{away}-01/
  順位表(セ):       https://npb.jp/standings/cl/
  順位表(パ):       https://npb.jp/standings/pl/
"""

import json
import os
import re
import time
from datetime import datetime, timedelta, timezone, date
import requests
from bs4 import BeautifulSoup

JST = timezone(timedelta(hours=9))

ABBR_TO_ID = {
    "g":  "giants",
    "t":  "tigers",
    "db": "baystars",
    "c":  "carp",
    "s":  "swallows",
    "d":  "dragons",
    "e":  "eagles",
    "h":  "hawks",
    "l":  "lions",
    "m":  "marines",
    "f":  "fighters",
    "b":  "buffaloes",
}

TEAM_NAMES = {
    "giants":    "読売ジャイアンツ",
    "tigers":    "阪神タイガース",
    "baystars":  "横浜DeNAベイスターズ",
    "carp":      "広島東洋カープ",
    "swallows":  "東京ヤクルトスワローズ",
    "dragons":   "中日ドラゴンズ",
    "eagles":    "東北楽天ゴールデンイーグルス",
    "hawks":     "福岡ソフトバンクホークス",
    "lions":     "埼玉西武ライオンズ",
    "marines":   "千葉ロッテマリーンズ",
    "fighters":  "北海道日本ハムファイターズ",
    "buffaloes": "オリックス・バファローズ",
}

NAME_TO_ID = {
    "巨人": "giants", "阪神": "tigers",
    "ＤｅＮＡ": "baystars", "DeNA": "baystars",
    "広島": "carp", "ヤクルト": "swallows",
    "中日": "dragons", "楽天": "eagles",
    "ソフトバンク": "hawks", "西武": "lions",
    "ロッテ": "marines", "日本ハム": "fighters",
    "オリックス": "buffaloes",
}

BASE_URL = "https://npb.jp"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}

# 過去何ヶ月分を取得するか（シーズン開幕月から）
SEASON_START_MONTH = 3   # 3月開幕
HISTORY_MONTHS = 4       # 最大4ヶ月さかのぼる


def get_soup(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return BeautifulSoup(r.content, "html.parser")
    except Exception as e:
        print(f"  [WARN] GET failed: {url}  ({e})")
        return None


def parse_score_link(href, year):
    """
    /scores/2026/0605/g-m-01/ → {date, home, away, href}
    """
    m = re.search(r"/scores/\d+/(\d{4})/([a-z]+)-([a-z]+)-\d+/?", href)
    if not m:
        return None
    mmdd, home_abbr, away_abbr = m.group(1), m.group(2), m.group(3)
    home_id = ABBR_TO_ID.get(home_abbr)
    away_id = ABBR_TO_ID.get(away_abbr)
    if not home_id or not away_id:
        return None
    date_str = f"{year}-{mmdd[:2]}-{mmdd[2:]}"
    return {"date": date_str, "home": home_id, "away": away_id, "href": href}


def collect_all_game_links(year, now_date):
    """
    ① トップページ + ② 月別ページ(シーズン開幕〜現在月) から全試合リンクを収集
    """
    games = {}  # key: "date_home_away" → info dict

    def extract(soup):
        if not soup:
            return
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if "/scores/" not in href:
                continue
            info = parse_score_link(href, year)
            if not info:
                continue
            key = f"{info['date']}_{info['home']}_{info['away']}"
            if key not in games:
                games[key] = info

    # ① トップページ（今日・明日の試合リンクあり）
    print("  [1/2] Fetching top page...")
    extract(get_soup(f"{BASE_URL}/games/{year}/"))

    # ② 月別スケジュールページ（過去試合の結果リンクあり）
    current_month = now_date.month
    for month in range(SEASON_START_MONTH, current_month + 1):
        url = f"{BASE_URL}/games/{year}/schedule_{month:02d}_detail.html"
        print(f"  [2/2] Fetching month {month:02d}...")
        extract(get_soup(url))
        time.sleep(0.3)

    print(f"  Total game links found: {len(games)}")
    return games


def fetch_score(href):
    """スコアページから (home_score, away_score) を取得。未終了はNone。"""
    url = BASE_URL + href if href.startswith("/") else href
    soup = get_soup(url)
    if not soup:
        return None

    for table in soup.find_all("table"):
        rows = table.find_all("tr")
        if len(rows) < 2:
            continue
        headers = [th.get_text(strip=True)
                   for th in rows[0].find_all(["th", "td"])]
        if "計" not in headers:
            continue
        calc_idx = headers.index("計")
        scores = []
        for row in rows[1:]:
            cols = row.find_all(["th", "td"])
            if len(cols) > calc_idx:
                val = cols[calc_idx].get_text(strip=True)
                if val.isdigit():
                    scores.append(int(val))
        if len(scores) >= 2:
            # NPB: 先攻(away)が上、後攻(home)が下
            return scores[1], scores[0]   # (home, away)
    return None


def fetch_standings(year):
    result = {}
    for league in ["cl", "pl"]:
        url = f"{BASE_URL}/standings/{league}/"
        print(f"  Fetching standings: {url}")
        soup = get_soup(url)
        if not soup:
            continue
        for table in soup.find_all("table"):
            for row in table.find_all("tr")[1:]:
                cols = row.find_all(["td", "th"])
                if len(cols) < 4:
                    continue
                name_raw = cols[0].get_text(strip=True)
                team_id = next(
                    (tid for k, tid in NAME_TO_ID.items() if k in name_raw),
                    None)
                if not team_id:
                    continue
                nums = [int(c.get_text(strip=True))
                        for c in cols[1:]
                        if c.get_text(strip=True).isdigit()][:3]
                if len(nums) >= 2:
                    w, l = nums[0], nums[1]
                    d = nums[2] if len(nums) >= 3 else 0
                    total = w + l + d
                    result[team_id] = {
                        "win_rate": round(w / total, 3) if total > 0 else 0.500
                    }
    print(f"  Standings: {len(result)} teams")
    return result


def load_existing():
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"teams": [], "games": [], "results": []}


def save(data):
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  Saved → {path}")


def build_teams(existing_teams, standings, results):
    existing_map = {t["id"]: t for t in existing_teams}

    # 全結果から各チームの平均得点・失点を計算
    team_scores = {tid: {"scored": [], "conceded": []}
                   for tid in TEAM_NAMES}
    for r in results:
        hs, as_ = r.get("home_score"), r.get("away_score")
        if hs is None or as_ is None:
            continue
        if r["home"] in team_scores:
            team_scores[r["home"]]["scored"].append(hs)
            team_scores[r["home"]]["conceded"].append(as_)
        if r["away"] in team_scores:
            team_scores[r["away"]]["scored"].append(as_)
            team_scores[r["away"]]["conceded"].append(hs)

    teams = []
    for team_id, name in TEAM_NAMES.items():
        base = existing_map.get(team_id) or {
            "id": team_id, "name": name,
            "win_rate": 0.500, "recent_5": [],
            "avg_score": 3.5, "avg_concede": 3.5,
            "home_win_rate": 0.500, "away_win_rate": 0.500,
        }
        base["name"] = name

        # 順位表から勝率を更新
        if team_id in standings:
            base["win_rate"] = standings[team_id]["win_rate"]

        # 全結果から平均得点・失点を計算
        sc = team_scores[team_id]
        if len(sc["scored"]) >= 3:
            base["avg_score"] = round(
                sum(sc["scored"]) / len(sc["scored"]), 2)
            base["avg_concede"] = round(
                sum(sc["conceded"]) / len(sc["conceded"]), 2)

        # ホーム/アウェイ勝率を計算
        home_results = [(r["home_score"], r["away_score"])
                        for r in results
                        if r["home"] == team_id
                        and r.get("home_score") is not None]
        away_results = [(r["away_score"], r["home_score"])
                        for r in results
                        if r["away"] == team_id
                        and r.get("away_score") is not None]

        if len(home_results) >= 3:
            hw = sum(1 for s, c in home_results if s > c)
            base["home_win_rate"] = round(hw / len(home_results), 3)
        if len(away_results) >= 3:
            aw = sum(1 for s, c in away_results if s > c)
            base["away_win_rate"] = round(aw / len(away_results), 3)

        # recent_5（直近5試合）
        team_results_sorted = sorted(
            [r for r in results
             if (r["home"] == team_id or r["away"] == team_id)
             and r.get("home_score") is not None],
            key=lambda r: r["date"], reverse=True
        )
        wl = []
        for r in team_results_sorted:
            hs, as_ = r["home_score"], r["away_score"]
            if r["home"] == team_id:
                wl.append("W" if hs > as_ else "L")
            else:
                wl.append("W" if as_ > hs else "L")
            if len(wl) >= 5:
                break
        if wl:
            base["recent_5"] = wl

        teams.append(base)
    return teams


def main():
    now = datetime.now(JST)
    today = now.date()
    tomorrow = today + timedelta(days=1)
    today_str = today.strftime("%Y-%m-%d")
    year = today.year

    print(f"=== NPB Scraper: {today_str} ===")

    existing = load_existing()

    # 既存データをマップ化
    all_games = {}
    for g in existing.get("games", []) + existing.get("results", []):
        key = f"{g['date']}_{g['home']}_{g['away']}"
        all_games[key] = g

    # 全試合リンクを収集（トップ + 月別ページ）
    print("\n[Step 1] Collecting game links...")
    new_links = collect_all_game_links(year, today)

    # 新規リンクをマージ
    for key, info in new_links.items():
        if key not in all_games:
            all_games[key] = {
                "date": info["date"],
                "home": info["home"],
                "away": info["away"],
                "status": "upcoming",
                "_href": info["href"],
            }
        else:
            all_games[key]["_href"] = info["href"]

    # 過去試合のスコアを取得（未取得分のみ）
    print("\n[Step 2] Fetching scores for past games...")
    fetch_count = 0
    for key, game in list(all_games.items()):
        # 今日以前の試合でスコア未取得のものを対象
        if game.get("status") == "upcoming" and game["date"] <= today_str:
            href = game.get("_href")
            if not href:
                continue
            score = fetch_score(href)
            if score is not None:
                home_score, away_score = score
                all_games[key]["home_score"] = home_score
                all_games[key]["away_score"] = away_score
                all_games[key]["status"] = "finished"
                print(f"    {game['date']} {game['home']} {home_score}-{away_score} {game['away']}")
                fetch_count += 1
            time.sleep(0.4)

    print(f"  Fetched {fetch_count} new scores")

    # _href除去
    for game in all_games.values():
        game.pop("_href", None)

    # upcoming / results に分類
    upcoming = sorted(
        [g for g in all_games.values() if g["status"] == "upcoming"],
        key=lambda g: g["date"]
    )
    results = sorted(
        [g for g in all_games.values() if g["status"] == "finished"],
        key=lambda g: g["date"], reverse=True
    )

    print(f"\n[Step 3] Fetching standings...")
    standings = fetch_standings(year)

    print(f"\n[Step 4] Building team stats from {len(results)} results...")
    teams = build_teams(existing.get("teams", []), standings, results)

    data = {
        "updated_at": today_str,
        "teams": teams,
        "games": upcoming,
        "results": results,  # 全期間保持
    }

    save(data)
    print(f"\n=== Done: {len(upcoming)} upcoming / {len(results)} results ===")


if __name__ == "__main__":
    main()
