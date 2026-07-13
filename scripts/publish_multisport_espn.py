"""Publish multi-sport schedules and standings from ESPN's public API.

Keyless data layer for the multi-sport Sports Hub pivot: NFL, NBA, MLB, NHL
and college football (CFB) from the same site.api.espn.com endpoints already
proven by fetch_live_scoreboards.py and publish_football_espn.py.

For each sport this writes into docs/sports-data/data/:
  {sport}_schedule.json        rolling-window scoreboard, GameRow-shaped rows
  {sport}_standings_espn.json  normalized standings rows
plus one multisport_manifest.json.

Per-sport failures are recorded in the manifest and logged, never fatal for
the other sports. Zero events for an offseason sport is valid: the empty
schedule is published with event_count 0. Exit code is 0 unless EVERY sport
failed on both endpoints.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

SITE_API_BASE = "https://site.api.espn.com/apis/site/v2/sports"
STANDINGS_API_BASE = "https://site.api.espn.com/apis/v2/sports"

# Rolling scoreboard window: past 7 days + next 14 days.
DAYS_BACK = 7
DAYS_FORWARD = 14
SCOREBOARD_LIMIT = 400

SPORTS: list[dict[str, str]] = [
    {"key": "nfl", "label": "NFL", "path": "football/nfl"},
    {"key": "nba", "label": "NBA", "path": "basketball/nba"},
    {"key": "mlb", "label": "MLB", "path": "baseball/mlb"},
    {"key": "nhl", "label": "NHL", "path": "hockey/nhl"},
    {"key": "cfb", "label": "College Football", "path": "football/college-football"},
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def fetch_json(url: str) -> dict[str, Any]:
    request = Request(url, headers={"User-Agent": "LindaData-Sports-Hub/1.0", "Accept": "application/json"})
    try:
        with urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not fetch {url}: {exc}") from exc


def payload_season(payload: dict[str, Any]) -> str | None:
    """Best-effort season year from a scoreboard payload."""
    for candidate in (
        (payload.get("season") or {}).get("year"),
        ((payload.get("leagues") or [{}])[0].get("season") or {}).get("year"),
    ):
        if candidate not in (None, ""):
            return str(candidate)
    return None


def payload_league_name(payload: dict[str, Any], fallback: str) -> str:
    league = (payload.get("leagues") or [{}])[0]
    return league.get("name") or league.get("abbreviation") or fallback


def normalize_event(sport: dict[str, str], event: dict[str, Any], season: str | None, league_name: str) -> dict[str, Any]:
    competition = (event.get("competitions") or [{}])[0]
    competitors = competition.get("competitors") or []
    home = next((x for x in competitors if x.get("homeAway") == "home"), {})
    away = next((x for x in competitors if x.get("homeAway") == "away"), {})
    status_type = (event.get("status") or {}).get("type") or {}
    venue = competition.get("venue") or {}
    state = status_type.get("state", "")
    completed = bool(status_type.get("completed"))
    event_season = (event.get("season") or {}).get("year")

    def team(item: dict[str, Any]) -> dict[str, Any]:
        return item.get("team") or {}

    def score(item: dict[str, Any]) -> int | None:
        raw = item.get("score")
        # Live/finished scoreboard scores come back as strings; pre-game rows
        # carry a placeholder "0" that must not read as a real score.
        if raw in (None, "") or state == "pre":
            return None
        try:
            return int(raw)
        except (TypeError, ValueError):
            return None

    return {
        "sport": sport["key"],
        "game_id": str(event.get("id") or ""),
        "date_utc": event.get("date"),
        "status": status_type.get("description") or status_type.get("detail"),
        "status_code": "FT" if completed else state,
        "league_id": sport["path"].split("/")[-1],
        "league": league_name,
        "season": str(event_season) if event_season not in (None, "") else season,
        "home_team_id": str(team(home).get("id") or ""),
        "home_team": team(home).get("displayName") or team(home).get("name") or "",
        "away_team_id": str(team(away).get("id") or ""),
        "away_team": team(away).get("displayName") or team(away).get("name") or "",
        "home_score": score(home),
        "away_score": score(away),
        "venue": venue.get("fullName"),
        "city": (venue.get("address") or {}).get("city"),
    }


def stat_map(entry: dict[str, Any]) -> dict[str, dict[str, Any]]:
    stats: dict[str, dict[str, Any]] = {}
    for item in entry.get("stats") or []:
        if not isinstance(item, dict):
            continue
        for key in (item.get("name"), item.get("type"), item.get("abbreviation")):
            if key and key not in stats:
                stats[key] = item
    return stats


def iter_standing_groups(node: dict[str, Any], name_parts: list[str]) -> Iterator[tuple[str, list[dict[str, Any]]]]:
    """Yield (group_name, entries) pairs, walking nested conference/division children."""
    standings = node.get("standings")
    entries = (standings or {}).get("entries") if isinstance(standings, dict) else None
    if entries:
        yield (" - ".join(part for part in name_parts if part) or "Overall", entries)
    for child in node.get("children") or []:
        if not isinstance(child, dict):
            continue
        child_name = child.get("name") or child.get("displayName") or child.get("abbreviation") or ""
        yield from iter_standing_groups(child, name_parts + ([child_name] if child_name else []))


def normalize_standings(sport: dict[str, str], payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for group_name, entries in iter_standing_groups(payload, []):
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            team = entry.get("team") or {}
            stats = stat_map(entry)

            def value(*names: str) -> Any:
                for name in names:
                    item = stats.get(name)
                    if item is not None and item.get("value") is not None:
                        return item.get("value")
                return None

            def num(*names: str) -> int | None:
                raw = value(*names)
                if raw is None:
                    return None
                try:
                    return int(raw)
                except (TypeError, ValueError):
                    return None

            def fraction(*names: str) -> float | None:
                raw = value(*names)
                if raw is None:
                    return None
                try:
                    return float(raw)
                except (TypeError, ValueError):
                    return None

            def streak() -> str | None:
                item = stats.get("streak") or stats.get("Streak")
                if not item:
                    return None
                display = item.get("displayValue")
                if display not in (None, ""):
                    return str(display)
                raw = item.get("value")
                try:
                    raw = int(raw)
                except (TypeError, ValueError):
                    return None
                if raw > 0:
                    return f"W{raw}"
                if raw < 0:
                    return f"L{-raw}"
                return None

            wins = num("wins")
            losses = num("losses")
            played = num("gamesPlayed")
            if played is None and wins is not None and losses is not None:
                played = wins + losses + (num("ties") or 0) + (num("otLosses", "OTLosses") or 0)
            percentage = fraction("winPercent", "leagueWinPercent", "divisionWinPercent")
            if percentage is None and wins is not None and played:
                percentage = wins / played
            position = num("rank", "playoffSeat", "divisionRank")
            rows.append(
                {
                    "sport": sport["key"],
                    "position": position if position is not None else index + 1,
                    "group": group_name,
                    "team_id": str(team.get("id") or ""),
                    "team": team.get("displayName") or team.get("name") or "",
                    "played": played,
                    "wins": wins,
                    "losses": losses,
                    "percentage": percentage,
                    "form": streak(),
                }
            )
    rows.sort(key=lambda r: (r["group"], r["position"] if r["position"] is not None else 999))
    return rows


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def scoreboard_window(now: datetime) -> str:
    start = (now - timedelta(days=DAYS_BACK)).strftime("%Y%m%d")
    end = (now + timedelta(days=DAYS_FORWARD)).strftime("%Y%m%d")
    return f"{start}-{end}"


def publish_sport(sport: dict[str, str], output: Path, refreshed_at: str, window: str) -> dict[str, Any]:
    errors: list[str] = []
    events: list[dict[str, Any]] = []
    standings: list[dict[str, Any]] = []
    scoreboard_ok = False
    standings_ok = False

    scoreboard_url = f"{SITE_API_BASE}/{sport['path']}/scoreboard?dates={window}&limit={SCOREBOARD_LIMIT}"
    try:
        payload = fetch_json(scoreboard_url)
        season = payload_season(payload)
        league_name = payload_league_name(payload, sport["label"])
        seen: dict[str, dict[str, Any]] = {}
        for event in payload.get("events") or []:
            row = normalize_event(sport, event, season, league_name)
            seen[row["game_id"]] = row
        events = sorted(seen.values(), key=lambda row: row.get("date_utc") or "")
        scoreboard_ok = True
    except RuntimeError as exc:
        errors.append(f"scoreboard: {exc}")
        print(f"[{sport['key']}] scoreboard error: {exc}", file=sys.stderr)

    standings_url = f"{STANDINGS_API_BASE}/{sport['path']}/standings"
    try:
        standings = normalize_standings(sport, fetch_json(standings_url))
        standings_ok = True
    except RuntimeError as exc:
        errors.append(f"standings: {exc}")
        print(f"[{sport['key']}] standings error: {exc}", file=sys.stderr)

    # Offseason sports legitimately return zero events; publish the empty
    # schedule anyway so consumers always find a fresh file.
    write_json(
        output / f"{sport['key']}_schedule.json",
        {
            "sport": sport["key"],
            "league": sport["label"],
            "refreshed_at_utc": refreshed_at,
            "dates_requested": window,
            "event_count": len(events),
            "events": events,
            "errors": errors,
        },
    )
    write_json(
        output / f"{sport['key']}_standings_espn.json",
        {
            "sport": sport["key"],
            "league": sport["label"],
            "refreshed_at_utc": refreshed_at,
            "standings_rows": len(standings),
            "standings": standings,
        },
    )
    return {
        "events": len(events),
        "standings_rows": len(standings),
        "errors": errors,
        "failed": not scoreboard_ok and not standings_ok,
    }


def main() -> int:
    output = Path(os.environ.get("SPORTS_HUB_DATA_DIR", "docs/sports-data/data"))
    refreshed_at = utc_now()
    window = scoreboard_window(datetime.now(timezone.utc))

    manifest: dict[str, Any] = {"refreshed_at_utc": refreshed_at, "provider": "ESPN", "sports": {}}
    failures = 0
    for sport in SPORTS:
        result = publish_sport(sport, output, refreshed_at, window)
        if result.pop("failed"):
            failures += 1
        manifest["sports"][sport["key"]] = result

    write_json(output / "multisport_manifest.json", manifest)
    print(json.dumps(manifest, indent=2))
    if failures == len(SPORTS):
        print("Every sport failed on both endpoints; treating run as failed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
