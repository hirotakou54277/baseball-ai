"""
NPB試合データ収集スクリプト
GitHub Actionsで毎日実行される

NPB URLパターン:
  月別スケジュール: https://npb.jp/games/{year}/schedule_{mm}_detail.html
  スコアページ:     https://npb.jp/scores/{year}/{mmdd}/{home}-{away}-01/
  順位表(セ):       https://npb.jp/standings/cl/
  順位表(パ):       https://npb.jp/standings/pl/
"""

import json
import os
import re
import time
from datetime import datetime, timedelta, timezone
import requests
from bs4 import BeautifulSoup

JST = timezone(timedelta(hours=9))

# NPBサイトのチーム略称 → アプリ内ID
ABBR_TO_ID = {
    "g":  "giants",    # 読売ジャイアンツ
    "t":  "tigers",    # 阪神タイガース
    "db": "baystars",  # 横浜DeNAベイスターズ
    "c":  "carp",      # 広島東洋カープ
    "s":  "swallows",  # 東京ヤクルトスワローズ
    "d":  "dragons",   # 中日ドラゴンズ
    "e":  "eagles",    # 東北楽天ゴールデンイーグルス
    "h":  "hawks",     # 福岡ソフトバンクホークス
    "l":  "lions",     # 埼玉西武ライオンズ
    "m":  "marines",   # 千葉ロッテマリーンズ
    "f":  "fighters",  # 北海道日本ハムファイターズ
    "b":  "buffaloes", # オリックス・バファローズ
}

TEAM_NAMES = {
    "giants":   "読売ジャイアンツ",
    "tigers":   "阪神タイガース",
    "baystars": "横浜DeNAベイスターズ",
    "carp":     "広島東洋カープ",
    "swallows": "東京ヤクルトスワローズ",
    "dragons":  "中日ドラゴンズ",
    "eagles":   "東北楽天ゴールデンイーグルス",
    "hawks":    "福岡ソフトバンクホークス",
    "lions":    "埼玉西武ライオンズ",
    "marines":  "千葉ロッテマリーンズ",
    "fighters": "北海道日本ハムファイターズ",
    "buffaloes":"オリックス・バファローズ",
}

# 順位表のチーム名テキスト → ID
NAME_TO_ID = {
    "巨人":       "giants",
    "阪神":       "tigers",
    "ＤｅＮＡ":   "baystars",
    "DeNA":       "baystars",
    "広島":       "carp",
    "ヤクルト":   "swallows",
    "中日":       "dragons",
    "楽天":       "eagles",
    "ソフトバンク":"hawks",
    "西武":       "lions",
    "ロッテ":     "marines",
    "日本ハム":   "fighters",
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


def get(url: str):
    """GETしてBeautifulSoupを返す。失敗時はNone。"""
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return BeautifulSoup(r.content, "html.parser")
    except Exception as e:
        print(f"  [WARN] GET failed: {url}  ({e})")
        return None


# ─── 1. スケジュール取得 ─────────────────────────────────────

def parse_score_link(href: str):
    """
    /scores/2026/0605/g-m-01/ のようなURLから試合情報を抽出する。
    戻り値: {date, home, away} または None
    """
    m = re.search(r"/scores/\d+/(\d{4})/([a-z]+)-([a-z]+)-\d+/?$", href)
    if not m:
        return None
    mmdd, home_abbr, away_abbr = m.group(1), m.group(2), m.group(3)
    home_id = ABBR_TO_ID.get(home_abbr)
    away_id = ABBR_TO_ID.get(away_abbr)
    if not home_id or not away_id:
        print(f"  [WARN] unknown abbr in {href}")
        return None
    now = datetime.now(JST)
    date_str = f"{now.year}-{mmdd[:2]}-{mmdd[2:]}"
    return {"date": date_str, "home": home_id, "away": away_id, "href": href}


def fetch_month_schedule(year: int, month: int) -> list[dict]:
    """
    試合スケジュールをNPBから取得する。
    - まず /games/{year}/ トップページから当月・翌月分のリンクを取得
    - 次に月別詳細ページからも補完
    """
    games = []
    seen = set()

    def extract_links(soup):
        if not soup:
            return
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if "/scores/" not in href:
                continue
            # 対象月のみ抽出
            if f"/{month:02d}" not in href and f"0{month}" not in href:
                # 月またぎ対応のため月フィルタは緩く
                pass
            info = parse_score_link(href)
            if not info:
                continue
            key = f"{info['date']}_{info['home']}_{info['away']}"
            if key not in seen:
                seen.add(key)
                games.append(info)

    # ① トップページ（今日・明日の試合リンクが含まれる）
    top_url = f"{BASE_URL}/games/{year}/"
    print(f"  Fetching top page: {top_url}")
    extract_links(get(top_url))

    # ② 月別詳細ページ（過去試合の結果リンクが含まれる）
    month_url = f"{BASE_URL}/games/{year}/schedule_{month:02d}_detail.html"
    print(f"  Fetching month page: {month_url}")
    extract_links(get(month_url))

    print(f"  Found {len(games)} games total")
    return games


def fetch_score(href: str):
    """
    スコアページから最終スコアを取得する。
    戻り値: (home_score, away_score) または None（試合前/取得失敗）
    """
    url = BASE_URL + href if href.startswith("/") else href
    soup = get(url)
    if not soup:
        return None

    # スコアボードのtable を探す
    # NPBスコアページは <table> にイニングスコアが入る
    # 合計点は「計」列の値
    for table in soup.find_all("table"):
        rows = table.find_all("tr")
        if len(rows) < 2:
            continue

        headers = [th.get_text(strip=True) for th in rows[0].find_all(["th", "td"])]
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
            # NPBページは表示順: 先攻(away)が上、後攻(home)が下
            away_score, home_score = scores[0], scores[1]
            return home_score, away_score

    # 試合前や取得失敗
    return None


# ─── 2. 順位表取得 ────────────────────────────────────────────

def fetch_standings() -> dict[str, dict]:
    """セ・パ両リーグの順位表を取得して {team_id: {win_rate}} を返す。"""
    result: dict[str, dict] = {}
    for league in ["cl", "pl"]:
        url = f"{BASE_URL}/standings/{league}/"
        print(f"  Fetching standings: {url}")
        soup = get(url)
        if not soup:
            continue

        for table in soup.find_all("table"):
            for row in table.find_all("tr")[1:]:
                cols = row.find_all(["td", "th"])
                if len(cols) < 4:
                    continue

                # チーム名セル（最初のtd）
                name_raw = cols[0].get_text(strip=True)
                team_id = None
                for key, tid in NAME_TO_ID.items():
                    if key in name_raw:
                        team_id = tid
                        break
                if not team_id:
                    continue

                # 勝・敗・引分を探す（数字列）
                nums = []
                for col in cols[1:]:
                    t = col.get_text(strip=True)
                    if t.isdigit():
                        nums.append(int(t))
                    if len(nums) == 3:
                        break

                if len(nums) >= 2:
                    win, loss = nums[0], nums[1]
                    draw = nums[2] if len(nums) >= 3 else 0
                    total = win + loss + draw
                    win_rate = round(win / total, 3) if total > 0 else 0.500
                    result[team_id] = {"win_rate": win_rate}

    print(f"  Got standings for {len(result)} teams")
    return result


# ─── 3. ファイル入出力 ────────────────────────────────────────

def load_existing() -> dict:
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"teams": [], "games": [], "results": []}


def save(data: dict):
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  Saved → {path}")


# ─── 4. チームデータのマージ・更新 ───────────────────────────

def build_teams(existing_teams: list[dict], standings: dict,
                results: list[dict]) -> list[dict]:
    existing_map = {t["id"]: t for t in existing_teams}
    teams = []
    for team_id, name in TEAM_NAMES.items():
        base = existing_map.get(team_id) or {
            "id": team_id, "name": name,
            "win_rate": 0.500, "recent_5": [],
            "avg_score": 3.5, "avg_concede": 3.5,
            "home_win_rate": 0.500, "away_win_rate": 0.500,
        }
        base["name"] = name
        if team_id in standings:
            base["win_rate"] = standings[team_id]["win_rate"]

        # recent_5 を結果から再計算
        team_results = sorted(
            [r for r in results
             if r.get("home") == team_id or r.get("away") == team_id],
            key=lambda r: r["date"], reverse=True
        )
        wl = []
        for r in team_results:
            hs, as_ = r.get("home_score"), r.get("away_score")
            if hs is None or as_ is None:
                continue
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


# ─── 5. メイン ────────────────────────────────────────────────

def main():
    now = datetime.now(JST)
    today = now.date()
    tomorrow = today + timedelta(days=1)
    today_str = today.strftime("%Y-%m-%d")
    tomorrow_str = tomorrow.strftime("%Y-%m-%d")

    print(f"=== Scraper start: {today_str} ===")

    existing = load_existing()

    # 既存データをマップ化
    all_games: dict[str, dict] = {}
    for g in existing.get("games", []) + existing.get("results", []):
        key = f"{g['date']}_{g['home']}_{g['away']}"
        all_games[key] = g

    # 今月・来月（月またぎ対応）のスケジュールを取得
    months = {(now.year, now.month)}
    if tomorrow.month != now.month:
        months.add((tomorrow.year, tomorrow.month))

    new_game_infos = []
    for year, month in months:
        new_game_infos.extend(fetch_month_schedule(year, month))

    # スケジュールをマージ（新規のみ追加）
    for info in new_game_infos:
        key = f"{info['date']}_{info['home']}_{info['away']}"
        if key not in all_games:
            all_games[key] = {
                "date": info["date"],
                "home": info["home"],
                "away": info["away"],
                "status": "upcoming",
                "_href": info["href"],
            }
        else:
            # href を保存（スコア取得用）
            all_games[key]["_href"] = info["href"]

    # 過去の upcoming 試合のスコアを確認
    print("Fetching scores for recent games...")
    for key, game in list(all_games.items()):
        if game.get("status") == "upcoming" and game["date"] <= today_str:
            href = game.get("_href")
            if not href:
                continue
            print(f"  Checking score: {game['date']} {game['home']} vs {game['away']}")
            score = fetch_score(href)
            if score is not None:
                home_score, away_score = score
                all_games[key]["home_score"] = home_score
                all_games[key]["away_score"] = away_score
                all_games[key]["status"] = "finished"
                print(f"    → {game['home']} {home_score} - {away_score} {game['away']}")
            time.sleep(0.5)  # サーバー負荷軽減

    # _href は保存不要なので除去
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
    )[:60]  # 直近60試合分を保持

    # 順位表取得
    print("Fetching standings...")
    standings = fetch_standings()

    # チームデータ構築
    teams = build_teams(existing.get("teams", []), standings, results)

    data = {
        "updated_at": today_str,
        "teams": teams,
        "games": upcoming,
        "results": results,
    }

    save(data)
    print(f"=== Done: {len(upcoming)} upcoming, {len(results)} results ===")


if __name__ == "__main__":
    main()
