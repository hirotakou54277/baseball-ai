"""
NPB試合データ収集スクリプト
GitHub Actionsで毎日実行される
"""

import json
import os
import re
from datetime import datetime, timedelta, timezone
import requests
from bs4 import BeautifulSoup

JST = timezone(timedelta(hours=9))

TEAM_IDS = {
    "読売": "giants",
    "ジャイアンツ": "giants",
    "Giants": "giants",
    "阪神": "tigers",
    "タイガース": "tigers",
    "Tigers": "tigers",
    "DeNA": "baystars",
    "ベイスターズ": "baystars",
    "BayStars": "baystars",
    "広島": "carp",
    "カープ": "carp",
    "Carp": "carp",
    "ヤクルト": "swallows",
    "スワローズ": "swallows",
    "Swallows": "swallows",
    "中日": "dragons",
    "ドラゴンズ": "dragons",
    "Dragons": "dragons",
    "楽天": "eagles",
    "イーグルス": "eagles",
    "Eagles": "eagles",
    "ソフトバンク": "hawks",
    "ホークス": "hawks",
    "Hawks": "hawks",
    "西武": "lions",
    "ライオンズ": "lions",
    "Lions": "lions",
    "ロッテ": "marines",
    "マリーンズ": "marines",
    "Marines": "marines",
    "日本ハム": "fighters",
    "ファイターズ": "fighters",
    "Fighters": "fighters",
    "オリックス": "buffaloes",
    "バファローズ": "buffaloes",
    "Buffaloes": "buffaloes",
}

TEAM_NAMES = {
    "giants": "読売ジャイアンツ",
    "tigers": "阪神タイガース",
    "baystars": "横浜DeNAベイスターズ",
    "carp": "広島東洋カープ",
    "swallows": "東京ヤクルトスワローズ",
    "dragons": "中日ドラゴンズ",
    "eagles": "東北楽天ゴールデンイーグルス",
    "hawks": "福岡ソフトバンクホークス",
    "lions": "埼玉西武ライオンズ",
    "marines": "千葉ロッテマリーンズ",
    "fighters": "北海道日本ハムファイターズ",
    "buffaloes": "オリックス・バファローズ",
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}


def load_existing() -> dict:
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"teams": [], "games": [], "results": []}


def fetch_standings() -> list[dict]:
    """NPB公式サイトから順位表をスクレイピング"""
    teams_data = []
    for league_id in ["cl", "pl"]:
        url = f"https://npb.jp/standings/{league_id}/"
        try:
            res = requests.get(url, headers=HEADERS, timeout=10)
            res.raise_for_status()
            soup = BeautifulSoup(res.text, "html.parser")

            table = soup.find("table", class_="standings-table")
            if not table:
                continue

            for row in table.find_all("tr")[1:]:
                cols = row.find_all("td")
                if len(cols) < 6:
                    continue

                team_name_raw = cols[0].get_text(strip=True)
                team_id = None
                for key, tid in TEAM_IDS.items():
                    if key in team_name_raw:
                        team_id = tid
                        break
                if not team_id:
                    continue

                try:
                    win = int(cols[1].get_text(strip=True))
                    loss = int(cols[2].get_text(strip=True))
                    draw = int(cols[3].get_text(strip=True))
                    total = win + loss + draw
                    win_rate = win / total if total > 0 else 0.5
                except (ValueError, ZeroDivisionError):
                    win_rate = 0.5

                teams_data.append({
                    "id": team_id,
                    "win_rate": round(win_rate, 3),
                })
        except Exception as e:
            print(f"standings fetch error ({league_id}): {e}")

    return teams_data


def fetch_schedule(date: datetime) -> list[dict]:
    """指定日の試合スケジュールを取得"""
    date_str = date.strftime("%Y%m%d")
    url = f"https://npb.jp/games/{date.year}/schedule_{date_str}_detail.html"
    games = []
    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        soup = BeautifulSoup(res.text, "html.parser")

        for game_div in soup.find_all("div", class_="game-score"):
            teams = game_div.find_all("span", class_="team-name")
            if len(teams) < 2:
                continue

            away_raw = teams[0].get_text(strip=True)
            home_raw = teams[1].get_text(strip=True)

            home_id = next(
                (tid for k, tid in TEAM_IDS.items() if k in home_raw), None)
            away_id = next(
                (tid for k, tid in TEAM_IDS.items() if k in away_raw), None)

            if not home_id or not away_id:
                continue

            score_els = game_div.find_all("span", class_="score")
            status = "upcoming"
            home_score = None
            away_score = None

            if len(score_els) >= 2:
                try:
                    away_score = int(score_els[0].get_text(strip=True))
                    home_score = int(score_els[1].get_text(strip=True))
                    status = "finished"
                except ValueError:
                    pass

            game = {
                "date": date.strftime("%Y-%m-%d"),
                "home": home_id,
                "away": away_id,
                "status": status,
            }
            if status == "finished":
                game["home_score"] = home_score
                game["away_score"] = away_score

            games.append(game)

    except Exception as e:
        print(f"schedule fetch error ({date_str}): {e}")

    return games


def merge_teams(existing: list[dict], fetched: list[dict]) -> list[dict]:
    """既存データに取得データをマージ（勝率のみ更新、他は保持）"""
    existing_map = {t["id"]: t for t in existing}
    fetched_map = {t["id"]: t for t in fetched}

    result = []
    for team_id, name in TEAM_NAMES.items():
        base = existing_map.get(team_id, {
            "id": team_id,
            "name": name,
            "win_rate": 0.500,
            "recent_5": [],
            "avg_score": 3.5,
            "avg_concede": 3.5,
            "home_win_rate": 0.500,
            "away_win_rate": 0.500,
        })
        if team_id in fetched_map:
            base["win_rate"] = fetched_map[team_id]["win_rate"]
        base["name"] = name  # 正式名称を常に上書き
        result.append(base)

    return result


def update_recent5(teams: list[dict], results: list[dict]) -> list[dict]:
    """直近試合結果からrecent_5を更新"""
    # 日付降順でソート
    sorted_results = sorted(results, key=lambda r: r["date"], reverse=True)

    for team in teams:
        tid = team["id"]
        wins_losses = []
        for r in sorted_results:
            if r["home"] == tid:
                if r.get("home_score") is not None and r.get("away_score") is not None:
                    wins_losses.append(
                        "W" if r["home_score"] > r["away_score"] else "L")
            elif r["away"] == tid:
                if r.get("home_score") is not None and r.get("away_score") is not None:
                    wins_losses.append(
                        "W" if r["away_score"] > r["home_score"] else "L")
            if len(wins_losses) >= 5:
                break
        if wins_losses:
            team["recent_5"] = wins_losses

    return teams


def save(data: dict):
    path = os.path.join(os.path.dirname(__file__), "..", "data", "games.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Saved to {path}")


def main():
    now = datetime.now(JST)
    today = now.date()
    tomorrow = today + timedelta(days=1)

    print(f"Running scraper for {today}")

    existing = load_existing()

    # 順位表取得
    print("Fetching standings...")
    standings = fetch_standings()

    # 今日・明日のスケジュール取得
    print("Fetching today's schedule...")
    today_games = fetch_schedule(datetime.combine(today, datetime.min.time()))

    print("Fetching tomorrow's schedule...")
    tomorrow_games = fetch_schedule(
        datetime.combine(tomorrow, datetime.min.time()))

    # チームデータをマージ
    teams = merge_teams(existing.get("teams", []), standings)

    # 全試合を日付でマージ（既存 + 新規）
    all_games: dict[str, dict] = {}
    for g in existing.get("games", []) + existing.get("results", []):
        key = f"{g['date']}_{g['home']}_{g['away']}"
        all_games[key] = g
    for g in today_games + tomorrow_games:
        key = f"{g['date']}_{g['home']}_{g['away']}"
        all_games[key] = g

    upcoming = [g for g in all_games.values() if g.get("status") == "upcoming"]
    results = [g for g in all_games.values() if g.get("status") == "finished"]

    # recent_5更新
    teams = update_recent5(teams, results)

    data = {
        "updated_at": today.strftime("%Y-%m-%d"),
        "teams": teams,
        "games": sorted(upcoming, key=lambda g: g["date"]),
        "results": sorted(results, key=lambda g: g["date"], reverse=True)[:30],
    }

    save(data)
    print("Done!")


if __name__ == "__main__":
    main()
