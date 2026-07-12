"""Publish World Cup fixtures and standings from ESPN's public API.

Keyless replacement for publish_api_football.py: the API-Football free plan
does not cover season 2026, so this script feeds the Sports Hub football files
(football_fixtures.json, football_standings.json, football_manifest.json)
from the same ESPN endpoints already used by fetch_live_scoreboards.py.
Output schema matches publish_api_football.py so consumers need no changes.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LEAGUE_SLUG = os.environ.get("FOOTBALL_ESPN_LEAGUE", "fifa.world")
LEAGUE_NAME = os.environ.get("FOOTBALL_ESPN_LEAGUE_NAME", "FIFA World Cup")
SEASON = os.environ.get("API_FOOTBALL_SEASON", "2026").strip()

SCOREBOARD_URL = f"https://site.api.espn.com/apis/site/v2/sports/soccer/{LEAGUE_SLUG}/scoreboard"
STANDINGS_URL = f"https://site.api.espn.com/apis/v2/sports/soccer/{LEAGUE_SLUG}/standings"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def fetch_json(url: str) -> dict[str, Any]:
    request = Request(url, headers={"User-Agent": "LindaData-Sports-Hub/1.0", "Accept": "application/json"})
    try:
        with urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not fetch {url}: {exc}") from exc


def normalize_fixture(event: dict[str, Any]) -> dict[str, Any]:
    competition = (event.get("competitions") or [{}])[0]
    competitors = competition.get("competitors") or []
    home = next((x for x in competitors if x.get("homeAway") == "home"), {})
    away = next((x for x in competitors if x.get("homeAway") == "away"), {})
    status_type = (event.get("status") or {}).get("type") or {}
    venue = competition.get("venue") or {}
    notes = competition.get("notes") or []
    state = status_type.get("state", "")
    completed = bool(status_type.get("completed"))

    def team(item: dict[str, Any]) -> dict[str, Any]:
        return item.get("team") or {}

    def score(item: dict[str, Any]) -> int | None:
        raw = item.get("score")
        if raw in (None, "") or state == "pre":
            return None
        try:
            return int(raw)
        except (TypeError, ValueError):
            return None

    return {
        "sport": "Football",
        "game_id": str(event.get("id") or ""),
        "date_utc": event.get("date"),
        "timezone": "UTC",
        "status": status_type.get("description") or status_type.get("detail"),
        "status_code": "FT" if completed else status_type.get("state"),
        "elapsed": None,
        "league_id": LEAGUE_SLUG,
        "league": LEAGUE_NAME,
        "country": None,
        "season": SEASON,
        "round": next((n.get("headline") for n in notes if n.get("headline")), None),
        "home_team_id": str(team(home).get("id") or ""),
        "home_team": team(home).get("displayName") or team(home).get("name"),
        "home_logo": team(home).get("logo"),
        "away_team_id": str(team(away).get("id") or ""),
        "away_team": team(away).get("displayName") or team(away).get("name"),
        "away_logo": team(away).get("logo"),
        "home_score": score(home),
        "away_score": score(away),
        "halftime_home": None,
        "halftime_away": None,
        "venue": venue.get("fullName"),
        "city": (venue.get("address") or {}).get("city"),
        "referee": None,
    }


def stat_map(entry: dict[str, Any]) -> dict[str, Any]:
    stats: dict[str, Any] = {}
    for item in entry.get("stats") or []:
        name = item.get("name") or item.get("abbreviation")
        if name:
            stats[name] = item.get("value")
    return stats


def normalize_standings(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    groups = payload.get("children") or []
    # Some responses nest a single ungrouped table under "standings" directly.
    if not groups and payload.get("standings"):
        groups = [{"name": "Overall", "standings": payload.get("standings")}]
    for group in groups:
        group_name = group.get("name") or group.get("abbreviation") or "Overall"
        entries = (group.get("standings") or {}).get("entries") or []
        for entry in entries:
            team = entry.get("team") or {}
            stats = stat_map(entry)

            def num(name: str) -> int | None:
                value = stats.get(name)
                if value is None:
                    return None
                try:
                    return int(value)
                except (TypeError, ValueError):
                    return None

            played = num("gamesPlayed") or 0
            wins = num("wins") or 0
            logos = team.get("logos") or []
            rows.append(
                {
                    "sport": "Football",
                    "position": num("rank"),
                    "group": group_name,
                    "team_id": str(team.get("id") or ""),
                    "team": team.get("displayName") or team.get("name") or "",
                    "logo": (logos[0] or {}).get("href") if logos else None,
                    "played": played,
                    "wins": wins,
                    "draws": num("ties"),
                    "losses": num("losses"),
                    "goals_for": num("pointsFor"),
                    "goals_against": num("pointsAgainst"),
                    "goal_difference": num("pointDifferential"),
                    "points": num("points"),
                    "percentage": (wins / played) if played else None,
                    "form": None,
                    "description": None,
                    "league_id": LEAGUE_SLUG,
                    "league": LEAGUE_NAME,
                    "country": None,
                    "season": SEASON,
                }
            )
    rows.sort(key=lambda r: (r["group"], r["position"] if r["position"] is not None else 99))
    return rows


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    output = Path(os.environ.get("SPORTS_HUB_DATA_DIR", "docs/sports-data/data"))
    raw = Path(os.environ.get("FOOTBALL_ESPN_RAW_DIR", "data/raw/football_espn/latest"))
    date_range = os.environ.get("FOOTBALL_ESPN_DATES", f"{SEASON}0101-{SEASON}1231")

    scoreboard = fetch_json(f"{SCOREBOARD_URL}?dates={date_range}&limit=1000")
    standings_payload = fetch_json(f"{STANDINGS_URL}?season={SEASON}")

    fixtures = [normalize_fixture(event) for event in scoreboard.get("events") or []]
    fixtures.sort(key=lambda f: f.get("date_utc") or "")
    standings = normalize_standings(standings_payload)

    if not fixtures:
        raise SystemExit(f"ESPN returned no {LEAGUE_NAME} events for {date_range}; refusing to publish empty feed.")

    write_json(raw / "scoreboard.json", scoreboard)
    write_json(raw / "standings.json", standings_payload)
    write_json(output / "football_fixtures.json", fixtures)
    write_json(output / "football_standings.json", standings)

    manifest = {
        "refreshed_at_utc": utc_now(),
        "provider": "ESPN",
        "host": "site.api.espn.com",
        "league_id": LEAGUE_SLUG,
        "league_name": LEAGUE_NAME,
        "country": None,
        "season": SEASON,
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
