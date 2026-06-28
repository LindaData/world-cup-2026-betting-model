from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


HOST = "v3.football.api-sports.io"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def api_key() -> str:
    key = (os.environ.get("API_FOOTBALL_KEY") or os.environ.get("API_SPORTS_KEY") or "").strip()
    if not key:
        raise SystemExit("Set API_FOOTBALL_KEY or API_SPORTS_KEY.")
    return key


def request_json(endpoint: str, params: dict[str, Any]) -> dict[str, Any]:
    url = f"https://{HOST}/{endpoint}?{urlencode(params)}"
    req = Request(
        url,
        headers={
            "x-apisports-key": api_key(),
            "Accept": "application/json",
            "User-Agent": "LindaData-Sports-Hub/1.0",
        },
    )
    try:
        with urlopen(req, timeout=90) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"API-Football HTTP {exc.code}: {body[:1000]}") from exc
    except (URLError, TimeoutError) as exc:
        raise RuntimeError(f"API-Football request failed: {exc}") from exc

    errors = payload.get("errors")
    if errors and errors not in ({}, []):
        raise RuntimeError(f"API-Football returned errors: {errors}")
    return payload


def normalize_fixture(item: dict[str, Any]) -> dict[str, Any]:
    fixture = item.get("fixture") or {}
    league = item.get("league") or {}
    teams = item.get("teams") or {}
    goals = item.get("goals") or {}
    score = item.get("score") or {}
    status = fixture.get("status") or {}
    venue = fixture.get("venue") or {}
    home = teams.get("home") or {}
    away = teams.get("away") or {}

    return {
        "sport": "Football",
        "game_id": str(fixture.get("id") or ""),
        "date_utc": fixture.get("date"),
        "timezone": fixture.get("timezone"),
        "status": status.get("long") or status.get("short"),
        "status_code": status.get("short"),
        "elapsed": status.get("elapsed"),
        "league_id": str(league.get("id") or ""),
        "league": league.get("name"),
        "country": league.get("country"),
        "season": str(league.get("season") or ""),
        "round": league.get("round"),
        "home_team_id": str(home.get("id") or ""),
        "home_team": home.get("name"),
        "home_logo": home.get("logo"),
        "away_team_id": str(away.get("id") or ""),
        "away_team": away.get("name"),
        "away_logo": away.get("logo"),
        "home_score": goals.get("home"),
        "away_score": goals.get("away"),
        "halftime_home": (score.get("halftime") or {}).get("home"),
        "halftime_away": (score.get("halftime") or {}).get("away"),
        "venue": venue.get("name"),
        "city": venue.get("city"),
        "referee": fixture.get("referee"),
    }


def normalize_standings(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for block in payload.get("response") or []:
        league = block.get("league") or {}
        for group_rows in league.get("standings") or []:
            for row in group_rows or []:
                team = row.get("team") or {}
                all_stats = row.get("all") or {}
                win = all_stats.get("win") or 0
                draw = all_stats.get("draw") or 0
                lose = all_stats.get("lose") or 0
                goals = all_stats.get("goals") or {}
                played = all_stats.get("played") or 0
                rows.append(
                    {
                        "sport": "Football",
                        "position": row.get("rank"),
                        "group": row.get("group") or "Overall",
                        "team_id": str(team.get("id") or ""),
                        "team": team.get("name") or "",
                        "logo": team.get("logo"),
                        "played": played,
                        "wins": win,
                        "draws": draw,
                        "losses": lose,
                        "goals_for": goals.get("for"),
                        "goals_against": goals.get("against"),
                        "goal_difference": row.get("goalsDiff"),
                        "points": row.get("points"),
                        "percentage": (win / played) if played else None,
                        "form": row.get("form"),
                        "description": row.get("description"),
                        "league_id": str(league.get("id") or ""),
                        "league": league.get("name"),
                        "country": league.get("country"),
                        "season": str(league.get("season") or ""),
                    }
                )
    return rows


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    league_id = os.environ.get("API_FOOTBALL_LEAGUE_ID", "1").strip()
    season = os.environ.get("API_FOOTBALL_SEASON", "2026").strip()
    output = Path(os.environ.get("SPORTS_HUB_DATA_DIR", "docs/sports-data/data"))
    raw = Path(os.environ.get("API_FOOTBALL_RAW_DIR", "data/raw/api_football/latest"))
    params = {"league": league_id, "season": season}

    fixtures_payload = request_json("fixtures", params)
    standings_payload = request_json("standings", params)
    fixtures = [normalize_fixture(item) for item in fixtures_payload.get("response") or []]
    standings = normalize_standings(standings_payload)

    write_json(raw / "fixtures.json", fixtures_payload)
    write_json(raw / "standings.json", standings_payload)
    write_json(output / "football_fixtures.json", fixtures)
    write_json(output / "football_standings.json", standings)

    first = (fixtures_payload.get("response") or [{}])[0]
    league = first.get("league") or {}
    manifest = {
        "refreshed_at_utc": utc_now(),
        "provider": "API-Football",
        "host": HOST,
        "league_id": int(league_id),
        "league_name": league.get("name") or "World Cup",
        "country": league.get("country"),
        "season": season,
        "fixtures_rows": len(fixtures),
        "standings_rows": len(standings),
        "files": {
            "fixtures": "football_fixtures.json",
            "standings": "football_standings.json",
        },
    }
    write_json(output / "football_manifest.json", manifest)
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
