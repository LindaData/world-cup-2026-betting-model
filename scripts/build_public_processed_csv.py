from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.parsers.wikipedia_squads import parse_squads  # noqa: E402


def latest_snapshot(raw_root: Path) -> Path:
    snapshots = [
        path
        for path in raw_root.iterdir()
        if path.is_dir() and (path / "manifest.json").exists() and snapshot_has_model_data(path)
    ]
    if not snapshots:
        raise FileNotFoundError("No usable raw snapshots found. Run scripts/fetch_raw_data.py first.")
    return max(snapshots, key=lambda path: path.stat().st_mtime)


def snapshot_has_model_data(snapshot: Path) -> bool:
    expected_files = [
        "international_results.csv",
        "international_goalscorers.csv",
        "api_football_world_cup_fixtures.json",
        "api_football_world_cup_teams.json",
        "api_football_world_cup_standings.json",
    ]
    return any((snapshot / filename).exists() for filename in expected_files)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def read_csv_if_exists(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    return read_csv(path)


def read_json_if_exists(path: Path) -> object:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def nested(value: object, *keys: str, default: object = "") -> object:
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key, default)
    return "" if current is None else current


def response_rows(payload: object) -> list[object]:
    if isinstance(payload, dict) and isinstance(payload.get("response"), list):
        return payload["response"]
    return []


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
            count += 1
    return count


def parse_int(value: str) -> int | None:
    if value in ("", None):
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def parse_date(value: str) -> date | None:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def result_for(score_for: int | None, score_against: int | None) -> str:
    if score_for is None or score_against is None:
        return "scheduled"
    if score_for > score_against:
        return "win"
    if score_for == score_against:
        return "draw"
    return "loss"


def build_team_match_long(matches: list[dict[str, str]]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for match_id, match in enumerate(matches, start=1):
        home_score = parse_int(match.get("home_score", ""))
        away_score = parse_int(match.get("away_score", ""))
        common = {
            "source_match_id": match_id,
            "date": match.get("date", ""),
            "tournament": match.get("tournament", ""),
            "city": match.get("city", ""),
            "country": match.get("country", ""),
            "neutral": match.get("neutral", ""),
        }
        rows.append(
            {
                **common,
                "team": match.get("home_team", ""),
                "opponent": match.get("away_team", ""),
                "listed_home": True,
                "goals_for": home_score,
                "goals_against": away_score,
                "goal_diff": None if home_score is None or away_score is None else home_score - away_score,
                "result": result_for(home_score, away_score),
            }
        )
        rows.append(
            {
                **common,
                "team": match.get("away_team", ""),
                "opponent": match.get("home_team", ""),
                "listed_home": False,
                "goals_for": away_score,
                "goals_against": home_score,
                "goal_diff": None if home_score is None or away_score is None else away_score - home_score,
                "result": result_for(away_score, home_score),
            }
        )
    return rows


def summarize_team_history(team_rows: list[dict[str, object]]) -> list[dict[str, object]]:
    agg: dict[str, dict[str, object]] = {}
    for row in team_rows:
        if row["result"] == "scheduled":
            continue
        team = str(row["team"])
        stats = agg.setdefault(
            team,
            {
                "team": team,
                "matches": 0,
                "wins": 0,
                "draws": 0,
                "losses": 0,
                "goals_for": 0,
                "goals_against": 0,
                "first_match_date": "",
                "last_match_date": "",
            },
        )
        stats["matches"] = int(stats["matches"]) + 1
        result_key = {"win": "wins", "draw": "draws", "loss": "losses"}[str(row["result"])]
        stats[result_key] = int(stats[result_key]) + 1
        stats["goals_for"] = int(stats["goals_for"]) + int(row["goals_for"] or 0)
        stats["goals_against"] = int(stats["goals_against"]) + int(row["goals_against"] or 0)
        d = str(row["date"])
        stats["first_match_date"] = d if not stats["first_match_date"] else min(str(stats["first_match_date"]), d)
        stats["last_match_date"] = d if not stats["last_match_date"] else max(str(stats["last_match_date"]), d)

    rows = []
    for stats in agg.values():
        matches = int(stats["matches"])
        goals_for = int(stats["goals_for"])
        goals_against = int(stats["goals_against"])
        rows.append(
            {
                **stats,
                "avg_goals_for": round(goals_for / matches, 4) if matches else None,
                "avg_goals_against": round(goals_against / matches, 4) if matches else None,
                "avg_goal_diff": round((goals_for - goals_against) / matches, 4) if matches else None,
                "win_pct": round(int(stats["wins"]) / matches, 4) if matches else None,
            }
        )
    return sorted(rows, key=lambda row: str(row["team"]))


def summarize_team_recent_form(
    team_rows: list[dict[str, object]],
    since: date = date(2022, 1, 1),
) -> list[dict[str, object]]:
    filtered = []
    for row in team_rows:
        row_date = parse_date(str(row["date"]))
        if row_date and row_date >= since:
            filtered.append(row)
    rows = summarize_team_history(filtered)
    for row in rows:
        row["since_date"] = since.isoformat()
    return rows


def summarize_player_goals(goalscorers: list[dict[str, str]]) -> list[dict[str, object]]:
    agg: dict[tuple[str, str], dict[str, object]] = {}
    for goal in goalscorers:
        scorer = goal.get("scorer", "")
        team = goal.get("team", "")
        if not scorer or not team:
            continue
        key = (team, scorer)
        stats = agg.setdefault(
            key,
            {
                "team": team,
                "player_name": scorer,
                "international_goals_in_dataset": 0,
                "penalty_goals": 0,
                "own_goals": 0,
                "first_goal_date": "",
                "last_goal_date": "",
                "tournaments_scored_in": set(),
            },
        )
        stats["international_goals_in_dataset"] = int(stats["international_goals_in_dataset"]) + 1
        stats["penalty_goals"] = int(stats["penalty_goals"]) + int(str(goal.get("penalty", "")).upper() == "TRUE")
        stats["own_goals"] = int(stats["own_goals"]) + int(str(goal.get("own_goal", "")).upper() == "TRUE")
        goal_date = goal.get("date", "")
        stats["first_goal_date"] = (
            goal_date if not stats["first_goal_date"] else min(str(stats["first_goal_date"]), goal_date)
        )
        stats["last_goal_date"] = (
            goal_date if not stats["last_goal_date"] else max(str(stats["last_goal_date"]), goal_date)
        )
        stats["tournaments_scored_in"].add(goal.get("tournament", ""))

    rows = []
    for stats in agg.values():
        tournaments = sorted(t for t in stats.pop("tournaments_scored_in") if t)
        rows.append({**stats, "tournaments_scored_in": "|".join(tournaments)})
    return sorted(rows, key=lambda row: (str(row["team"]), str(row["player_name"])))


def build_2026_fixtures(matches: list[dict[str, str]]) -> list[dict[str, object]]:
    rows = []
    for match_id, match in enumerate(matches, start=1):
        match_date = parse_date(match.get("date", ""))
        if match.get("tournament") != "FIFA World Cup" or not match_date or match_date.year != 2026:
            continue
        home_score = parse_int(match.get("home_score", ""))
        away_score = parse_int(match.get("away_score", ""))
        rows.append(
            {
                "source_match_id": match_id,
                "date": match.get("date", ""),
                "home_team": match.get("home_team", ""),
                "away_team": match.get("away_team", ""),
                "home_score": home_score,
                "away_score": away_score,
                "status": "scheduled" if home_score is None or away_score is None else "finished",
                "city": match.get("city", ""),
                "country": match.get("country", ""),
                "neutral": match.get("neutral", ""),
            }
        )
    return rows


def normalize_join_key(value: str) -> str:
    value = value.replace("&", "and")
    value = value.replace("USA", "United States")
    value = re.sub(r"[^A-Za-z0-9]+", "", value).lower()
    aliases = {
        "usa": "unitedstates",
        "unitedstatesofamerica": "unitedstates",
        "bosniaherzegovina": "bosniaandherzegovina",
        "bosniaandherzegovina": "bosniaandherzegovina",
    }
    return aliases.get(value, value)


def parse_utc_offset(value: str) -> timezone:
    sign = 1
    raw = value.strip()
    if raw.startswith("-"):
        sign = -1
        raw = raw[1:]
    elif raw.startswith("+"):
        raw = raw[1:]
    hours = int(raw)
    return timezone(sign * timedelta(hours=hours))


def parse_fixture_teams(fixture_text: str) -> tuple[str, str] | None:
    scheduled_match = re.match(r"(.+?)\s+v\s+(.+)$", fixture_text)
    if scheduled_match:
        return scheduled_match.group(1).strip(), scheduled_match.group(2).strip()

    finished_match = re.match(
        r"(.+?)\s+\d+\s*-\s*\d+(?:\s+\([^)]+\))?\s+(.+)$",
        fixture_text,
    )
    if finished_match:
        return finished_match.group(1).strip(), finished_match.group(2).strip()

    return None


def build_fixture_times(snapshot: Path, fixtures: list[dict[str, object]]) -> list[dict[str, object]]:
    cup_path = snapshot / "openfootball_cup.txt"
    if not cup_path.exists():
        return []

    fixture_lookup = {}
    for fixture in fixtures:
        key = (
            str(fixture.get("date", "")),
            normalize_join_key(str(fixture.get("home_team", ""))),
            normalize_join_key(str(fixture.get("away_team", ""))),
        )
        fixture_lookup[key] = fixture.get("source_match_id", "")

    month_map = {"june": 6, "jun": 6, "july": 7, "jul": 7}
    current_date: date | None = None
    rows: list[dict[str, object]] = []
    date_re = re.compile(r"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(June|Jun|July|Jul)\s+(\d{1,2})\s*$", re.I)
    fixture_re = re.compile(r"^\s*(\d{1,2}:\d{2})\s+UTC([+-]\d{1,2})\s+(.+?)\s+@\s+(.+?)\s*$")

    for line in cup_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        date_match = date_re.match(stripped)
        if date_match:
            month = month_map[date_match.group(2).lower()]
            current_date = date(2026, month, int(date_match.group(3)))
            continue

        fixture_match = fixture_re.match(line)
        if not fixture_match or current_date is None:
            continue

        local_time_text, utc_offset_text, fixture_text, venue_label = fixture_match.groups()
        teams = parse_fixture_teams(fixture_text.strip())
        if teams is None:
            continue
        home_team, away_team = teams
        hour, minute = [int(part) for part in local_time_text.split(":", 1)]
        tz = parse_utc_offset(utc_offset_text)
        kickoff_local = datetime(2026, current_date.month, current_date.day, hour, minute, tzinfo=tz)
        kickoff_utc = kickoff_local.astimezone(timezone.utc)
        key = (
            current_date.isoformat(),
            normalize_join_key(home_team),
            normalize_join_key(away_team),
        )

        rows.append(
            {
                "source_match_id": fixture_lookup.get(key, ""),
                "date": current_date.isoformat(),
                "local_time": local_time_text,
                "utc_offset": f"UTC{utc_offset_text}",
                "kickoff_local_iso": kickoff_local.isoformat(),
                "kickoff_utc_iso": kickoff_utc.isoformat().replace("+00:00", "Z"),
                "refresh_utc_iso": (kickoff_utc - timedelta(minutes=30)).isoformat().replace("+00:00", "Z"),
                "home_team": home_team,
                "away_team": away_team,
                "home_team_key": key[1],
                "away_team_key": key[2],
                "venue_label": venue_label.strip(),
            }
        )

    return rows


def build_location_dimension(matches: list[dict[str, str]]) -> list[dict[str, object]]:
    counter = Counter(
        (match.get("city", ""), match.get("country", ""))
        for match in matches
        if match.get("city") and match.get("country")
    )
    return [
        {"city": city, "country": country, "matches_in_results_dataset": count}
        for (city, country), count in sorted(counter.items())
    ]


def flatten_api_football_leagues(snapshot: Path) -> list[dict[str, object]]:
    payload = read_json_if_exists(snapshot / "api_football_world_cup_leagues.json")
    rows: list[dict[str, object]] = []
    for item in response_rows(payload):
        if not isinstance(item, dict):
            continue
        seasons = item.get("seasons") if isinstance(item.get("seasons"), list) else [{}]
        for season in seasons:
            if not isinstance(season, dict):
                season = {}
            coverage = season.get("coverage") if isinstance(season.get("coverage"), dict) else {}
            fixtures = coverage.get("fixtures") if isinstance(coverage.get("fixtures"), dict) else {}
            rows.append(
                {
                    "api_league_id": nested(item, "league", "id"),
                    "league_name": nested(item, "league", "name"),
                    "league_type": nested(item, "league", "type"),
                    "country_name": nested(item, "country", "name"),
                    "season": season.get("year", ""),
                    "season_start": season.get("start", ""),
                    "season_end": season.get("end", ""),
                    "season_current": season.get("current", ""),
                    "coverage_events": fixtures.get("events", ""),
                    "coverage_lineups": fixtures.get("lineups", ""),
                    "coverage_fixture_statistics": fixtures.get("statistics_fixtures", ""),
                    "coverage_player_statistics": fixtures.get("statistics_players", ""),
                    "coverage_standings": coverage.get("standings", ""),
                    "coverage_players": coverage.get("players", ""),
                    "coverage_injuries": coverage.get("injuries", ""),
                    "coverage_predictions": coverage.get("predictions", ""),
                    "coverage_odds": coverage.get("odds", ""),
                }
            )
    return rows


def flatten_api_football_fixtures(snapshot: Path) -> list[dict[str, object]]:
    payload = read_json_if_exists(snapshot / "api_football_world_cup_fixtures.json")
    rows: list[dict[str, object]] = []
    for item in response_rows(payload):
        if not isinstance(item, dict):
            continue
        rows.append(
            {
                "api_fixture_id": nested(item, "fixture", "id"),
                "referee": nested(item, "fixture", "referee"),
                "timezone": nested(item, "fixture", "timezone"),
                "fixture_date": nested(item, "fixture", "date"),
                "timestamp": nested(item, "fixture", "timestamp"),
                "venue_id": nested(item, "fixture", "venue", "id"),
                "venue_name": nested(item, "fixture", "venue", "name"),
                "venue_city": nested(item, "fixture", "venue", "city"),
                "status_long": nested(item, "fixture", "status", "long"),
                "status_short": nested(item, "fixture", "status", "short"),
                "elapsed": nested(item, "fixture", "status", "elapsed"),
                "league_id": nested(item, "league", "id"),
                "league_name": nested(item, "league", "name"),
                "season": nested(item, "league", "season"),
                "round": nested(item, "league", "round"),
                "home_team_id": nested(item, "teams", "home", "id"),
                "home_team": nested(item, "teams", "home", "name"),
                "home_winner": nested(item, "teams", "home", "winner"),
                "away_team_id": nested(item, "teams", "away", "id"),
                "away_team": nested(item, "teams", "away", "name"),
                "away_winner": nested(item, "teams", "away", "winner"),
                "home_goals": nested(item, "goals", "home"),
                "away_goals": nested(item, "goals", "away"),
                "halftime_home": nested(item, "score", "halftime", "home"),
                "halftime_away": nested(item, "score", "halftime", "away"),
                "fulltime_home": nested(item, "score", "fulltime", "home"),
                "fulltime_away": nested(item, "score", "fulltime", "away"),
                "extratime_home": nested(item, "score", "extratime", "home"),
                "extratime_away": nested(item, "score", "extratime", "away"),
                "penalty_home": nested(item, "score", "penalty", "home"),
                "penalty_away": nested(item, "score", "penalty", "away"),
            }
        )
    return rows


def build_api_football_team_match_frame(fixtures: list[dict[str, object]]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for fixture in fixtures:
        home_goals = parse_int(str(fixture.get("home_goals", "")))
        away_goals = parse_int(str(fixture.get("away_goals", "")))
        common = {
            "api_fixture_id": fixture.get("api_fixture_id", ""),
            "fixture_date": fixture.get("fixture_date", ""),
            "league_id": fixture.get("league_id", ""),
            "season": fixture.get("season", ""),
            "round": fixture.get("round", ""),
            "venue_id": fixture.get("venue_id", ""),
            "venue_name": fixture.get("venue_name", ""),
            "venue_city": fixture.get("venue_city", ""),
            "status_short": fixture.get("status_short", ""),
        }
        teams = [
            (
                fixture.get("home_team_id", ""),
                fixture.get("home_team", ""),
                fixture.get("away_team_id", ""),
                fixture.get("away_team", ""),
                True,
                home_goals,
                away_goals,
            ),
            (
                fixture.get("away_team_id", ""),
                fixture.get("away_team", ""),
                fixture.get("home_team_id", ""),
                fixture.get("home_team", ""),
                False,
                away_goals,
                home_goals,
            ),
        ]
        for team_id, team, opponent_id, opponent, listed_home, goals_for, goals_against in teams:
            rows.append(
                {
                    **common,
                    "team_id": team_id,
                    "team": team,
                    "opponent_id": opponent_id,
                    "opponent": opponent,
                    "listed_home": listed_home,
                    "goals_for": goals_for,
                    "goals_against": goals_against,
                    "goal_diff": None if goals_for is None or goals_against is None else goals_for - goals_against,
                    "result": result_for(goals_for, goals_against),
                }
            )
    return rows


def flatten_api_football_teams(snapshot: Path) -> list[dict[str, object]]:
    payload = read_json_if_exists(snapshot / "api_football_world_cup_teams.json")
    rows: list[dict[str, object]] = []
    for item in response_rows(payload):
        if not isinstance(item, dict):
            continue
        rows.append(
            {
                "team_id": nested(item, "team", "id"),
                "team_name": nested(item, "team", "name"),
                "team_code": nested(item, "team", "code"),
                "country": nested(item, "team", "country"),
                "founded": nested(item, "team", "founded"),
                "national": nested(item, "team", "national"),
                "venue_id": nested(item, "venue", "id"),
                "venue_name": nested(item, "venue", "name"),
                "venue_city": nested(item, "venue", "city"),
                "venue_capacity": nested(item, "venue", "capacity"),
                "venue_surface": nested(item, "venue", "surface"),
            }
        )
    return rows


def flatten_api_football_standings(snapshot: Path) -> list[dict[str, object]]:
    payload = read_json_if_exists(snapshot / "api_football_world_cup_standings.json")
    rows: list[dict[str, object]] = []
    for item in response_rows(payload):
        if not isinstance(item, dict):
            continue
        league = item.get("league") if isinstance(item.get("league"), dict) else {}
        groups = league.get("standings") if isinstance(league.get("standings"), list) else []
        for group_rows in groups:
            if not isinstance(group_rows, list):
                continue
            for standing in group_rows:
                if not isinstance(standing, dict):
                    continue
                rows.append(
                    {
                        "league_id": league.get("id", ""),
                        "league_name": league.get("name", ""),
                        "season": league.get("season", ""),
                        "rank": standing.get("rank", ""),
                        "team_id": nested(standing, "team", "id"),
                        "team_name": nested(standing, "team", "name"),
                        "points": standing.get("points", ""),
                        "goals_diff": standing.get("goalsDiff", ""),
                        "group_name": standing.get("group", ""),
                        "form": standing.get("form", ""),
                        "status": standing.get("status", ""),
                        "description": standing.get("description", ""),
                        "all_played": nested(standing, "all", "played"),
                        "all_win": nested(standing, "all", "win"),
                        "all_draw": nested(standing, "all", "draw"),
                        "all_lose": nested(standing, "all", "lose"),
                        "all_goals_for": nested(standing, "all", "goals", "for"),
                        "all_goals_against": nested(standing, "all", "goals", "against"),
                    }
                )
    return rows


def flatten_api_football_injuries(snapshot: Path) -> list[dict[str, object]]:
    payload = read_json_if_exists(snapshot / "api_football_world_cup_injuries.json")
    rows: list[dict[str, object]] = []
    for item in response_rows(payload):
        if not isinstance(item, dict):
            continue
        rows.append(
            {
                "player_id": nested(item, "player", "id"),
                "player_name": nested(item, "player", "name"),
                "player_type": nested(item, "player", "type"),
                "player_reason": nested(item, "player", "reason"),
                "team_id": nested(item, "team", "id"),
                "team_name": nested(item, "team", "name"),
                "fixture_id": nested(item, "fixture", "id"),
                "fixture_timezone": nested(item, "fixture", "timezone"),
                "fixture_date": nested(item, "fixture", "date"),
                "league_id": nested(item, "league", "id"),
                "league_name": nested(item, "league", "name"),
                "season": nested(item, "league", "season"),
            }
        )
    return rows


def flatten_api_football_odds(snapshot: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(snapshot.glob("api_football_world_cup_odds_page_*.json")):
        payload = read_json_if_exists(path)
        for item in response_rows(payload):
            if not isinstance(item, dict):
                continue
            bookmakers = item.get("bookmakers") if isinstance(item.get("bookmakers"), list) else []
            for bookmaker in bookmakers:
                if not isinstance(bookmaker, dict):
                    continue
                bets = bookmaker.get("bets") if isinstance(bookmaker.get("bets"), list) else []
                for bet in bets:
                    if not isinstance(bet, dict):
                        continue
                    values = bet.get("values") if isinstance(bet.get("values"), list) else []
                    for outcome in values:
                        if not isinstance(outcome, dict):
                            continue
                        rows.append(
                            {
                                "fixture_id": nested(item, "fixture", "id"),
                                "fixture_timezone": nested(item, "fixture", "timezone"),
                                "fixture_date": nested(item, "fixture", "date"),
                                "league_id": nested(item, "league", "id"),
                                "league_name": nested(item, "league", "name"),
                                "season": nested(item, "league", "season"),
                                "bookmaker_id": bookmaker.get("id", ""),
                                "bookmaker_name": bookmaker.get("name", ""),
                                "bet_id": bet.get("id", ""),
                                "bet_name": bet.get("name", ""),
                                "outcome_value": outcome.get("value", ""),
                                "outcome_odd": outcome.get("odd", ""),
                            }
                        )
    return rows


def flatten_api_football_players(snapshot: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(snapshot.glob("api_football_world_cup_players_page_*.json")):
        payload = read_json_if_exists(path)
        for item in response_rows(payload):
            if not isinstance(item, dict):
                continue
            stats_rows = item.get("statistics") if isinstance(item.get("statistics"), list) else [{}]
            for stat in stats_rows:
                if not isinstance(stat, dict):
                    stat = {}
                rows.append(
                    {
                        "player_id": nested(item, "player", "id"),
                        "player_name": nested(item, "player", "name"),
                        "player_firstname": nested(item, "player", "firstname"),
                        "player_lastname": nested(item, "player", "lastname"),
                        "age": nested(item, "player", "age"),
                        "birth_date": nested(item, "player", "birth", "date"),
                        "birth_place": nested(item, "player", "birth", "place"),
                        "birth_country": nested(item, "player", "birth", "country"),
                        "nationality": nested(item, "player", "nationality"),
                        "height": nested(item, "player", "height"),
                        "weight": nested(item, "player", "weight"),
                        "injured": nested(item, "player", "injured"),
                        "team_id": nested(stat, "team", "id"),
                        "team_name": nested(stat, "team", "name"),
                        "league_id": nested(stat, "league", "id"),
                        "league_name": nested(stat, "league", "name"),
                        "season": nested(stat, "league", "season"),
                        "appearances": nested(stat, "games", "appearences"),
                        "lineups": nested(stat, "games", "lineups"),
                        "minutes": nested(stat, "games", "minutes"),
                        "position": nested(stat, "games", "position"),
                        "rating": nested(stat, "games", "rating"),
                        "captain": nested(stat, "games", "captain"),
                        "goals_total": nested(stat, "goals", "total"),
                        "goals_conceded": nested(stat, "goals", "conceded"),
                        "assists": nested(stat, "goals", "assists"),
                        "shots_total": nested(stat, "shots", "total"),
                        "shots_on": nested(stat, "shots", "on"),
                        "passes_total": nested(stat, "passes", "total"),
                        "passes_key": nested(stat, "passes", "key"),
                        "tackles_total": nested(stat, "tackles", "total"),
                        "duels_total": nested(stat, "duels", "total"),
                        "duels_won": nested(stat, "duels", "won"),
                        "dribbles_attempts": nested(stat, "dribbles", "attempts"),
                        "dribbles_success": nested(stat, "dribbles", "success"),
                        "fouls_drawn": nested(stat, "fouls", "drawn"),
                        "fouls_committed": nested(stat, "fouls", "committed"),
                        "yellow_cards": nested(stat, "cards", "yellow"),
                        "red_cards": nested(stat, "cards", "red"),
                        "penalties_scored": nested(stat, "penalty", "scored"),
                        "penalties_missed": nested(stat, "penalty", "missed"),
                        "penalties_saved": nested(stat, "penalty", "saved"),
                    }
                )
    return rows


def fixture_id_from_detail_path(path: Path) -> str:
    parts = path.stem.split("_")
    if "fixture" not in parts:
        return ""
    index = parts.index("fixture")
    if index + 1 >= len(parts):
        return ""
    return parts[index + 1]


def flatten_api_football_fixture_lineups(snapshot: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(snapshot.glob("api_football_fixture_*_lineups.json")):
        api_fixture_id = fixture_id_from_detail_path(path)
        payload = read_json_if_exists(path)
        for item in response_rows(payload):
            if not isinstance(item, dict):
                continue
            team_id = nested(item, "team", "id")
            team_name = nested(item, "team", "name")
            formation = item.get("formation", "")
            coach_id = nested(item, "coach", "id")
            coach_name = nested(item, "coach", "name")
            groups = [
                ("start", item.get("startXI") if isinstance(item.get("startXI"), list) else []),
                ("substitute", item.get("substitutes") if isinstance(item.get("substitutes"), list) else []),
            ]
            for role, player_rows in groups:
                for player_row in player_rows:
                    if not isinstance(player_row, dict):
                        continue
                    rows.append(
                        {
                            "api_fixture_id": api_fixture_id,
                            "team_id": team_id,
                            "team_name": team_name,
                            "formation": formation,
                            "coach_id": coach_id,
                            "coach_name": coach_name,
                            "lineup_role": role,
                            "player_id": nested(player_row, "player", "id"),
                            "player_name": nested(player_row, "player", "name"),
                            "player_number": nested(player_row, "player", "number"),
                            "player_position": nested(player_row, "player", "pos"),
                            "player_grid": nested(player_row, "player", "grid"),
                        }
                    )
    return rows


def flatten_api_football_fixture_events(snapshot: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(snapshot.glob("api_football_fixture_*_events.json")):
        api_fixture_id = fixture_id_from_detail_path(path)
        payload = read_json_if_exists(path)
        for item in response_rows(payload):
            if not isinstance(item, dict):
                continue
            rows.append(
                {
                    "api_fixture_id": api_fixture_id,
                    "elapsed": nested(item, "time", "elapsed"),
                    "extra": nested(item, "time", "extra"),
                    "team_id": nested(item, "team", "id"),
                    "team_name": nested(item, "team", "name"),
                    "player_id": nested(item, "player", "id"),
                    "player_name": nested(item, "player", "name"),
                    "assist_id": nested(item, "assist", "id"),
                    "assist_name": nested(item, "assist", "name"),
                    "event_type": item.get("type", ""),
                    "event_detail": item.get("detail", ""),
                    "comments": item.get("comments", ""),
                }
            )
    return rows


def flatten_api_football_fixture_predictions(snapshot: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(snapshot.glob("api_football_fixture_*_predictions.json")):
        api_fixture_id = fixture_id_from_detail_path(path)
        payload = read_json_if_exists(path)
        for item in response_rows(payload):
            if not isinstance(item, dict):
                continue
            rows.append(
                {
                    "api_fixture_id": api_fixture_id,
                    "winner_id": nested(item, "predictions", "winner", "id"),
                    "winner_name": nested(item, "predictions", "winner", "name"),
                    "winner_comment": nested(item, "predictions", "winner", "comment"),
                    "win_or_draw": nested(item, "predictions", "win_or_draw"),
                    "under_over": nested(item, "predictions", "under_over"),
                    "goals_home": nested(item, "predictions", "goals", "home"),
                    "goals_away": nested(item, "predictions", "goals", "away"),
                    "advice": nested(item, "predictions", "advice"),
                    "home_percent": nested(item, "predictions", "percent", "home"),
                    "draw_percent": nested(item, "predictions", "percent", "draw"),
                    "away_percent": nested(item, "predictions", "percent", "away"),
                    "home_team_id": nested(item, "teams", "home", "id"),
                    "home_team": nested(item, "teams", "home", "name"),
                    "away_team_id": nested(item, "teams", "away", "id"),
                    "away_team": nested(item, "teams", "away", "name"),
                }
            )
    return rows


def tournament_k_factor(tournament: str) -> int:
    lower = tournament.lower()
    if "fifa world cup" == lower:
        return 60
    if "uefa euro" in lower or "copa am" in lower or "african cup" in lower or "asian cup" in lower:
        return 50
    if "qualification" in lower or "qualifier" in lower or "nations league" in lower:
        return 40
    if "friendly" in lower:
        return 20
    return 30


def goal_difference_multiplier(goal_diff: int) -> float:
    diff = abs(goal_diff)
    if diff <= 1:
        return 1.0
    if diff == 2:
        return 1.5
    return (11 + diff) / 8


def expected_result(team_elo: float, opponent_elo: float, home_advantage: float = 0) -> float:
    diff = team_elo + home_advantage - opponent_elo
    return 1 / (10 ** (-diff / 400) + 1)


def actual_result(team_score: int, opponent_score: int) -> float:
    if team_score > opponent_score:
        return 1.0
    if team_score == opponent_score:
        return 0.5
    return 0.0


def build_elo_tables(matches: list[dict[str, str]]) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    elo: defaultdict[str, float] = defaultdict(lambda: 1500.0)
    rated_matches: Counter[str] = Counter()
    history: list[dict[str, object]] = []

    indexed_matches = []
    for match_id, match in enumerate(matches, start=1):
        match_date = parse_date(match.get("date", ""))
        home_score = parse_int(match.get("home_score", ""))
        away_score = parse_int(match.get("away_score", ""))
        if not match_date or home_score is None or away_score is None:
            continue
        indexed_matches.append((match_date, match_id, match, home_score, away_score))

    for match_date, match_id, match, home_score, away_score in sorted(indexed_matches):
        home = match.get("home_team", "")
        away = match.get("away_team", "")
        if not home or not away:
            continue

        home_pre = elo[home]
        away_pre = elo[away]
        neutral = str(match.get("neutral", "")).upper() == "TRUE"
        home_advantage = 0 if neutral else 100
        home_expected = expected_result(home_pre, away_pre, home_advantage)
        away_expected = 1 - home_expected
        home_actual = actual_result(home_score, away_score)
        away_actual = 1 - home_actual
        k = tournament_k_factor(match.get("tournament", ""))
        multiplier = goal_difference_multiplier(home_score - away_score)
        home_change = round(k * multiplier * (home_actual - home_expected), 4)
        away_change = -home_change

        elo[home] = round(home_pre + home_change, 4)
        elo[away] = round(away_pre + away_change, 4)
        rated_matches[home] += 1
        rated_matches[away] += 1

        common = {
            "source_match_id": match_id,
            "date": match_date.isoformat(),
            "tournament": match.get("tournament", ""),
            "city": match.get("city", ""),
            "country": match.get("country", ""),
            "neutral": neutral,
            "k_factor": k,
            "goal_multiplier": multiplier,
        }
        history.append(
            {
                **common,
                "team": home,
                "opponent": away,
                "listed_home": True,
                "goals_for": home_score,
                "goals_against": away_score,
                "pre_elo": round(home_pre, 4),
                "opponent_pre_elo": round(away_pre, 4),
                "expected_result": round(home_expected, 6),
                "actual_result": home_actual,
                "elo_change": home_change,
                "post_elo": elo[home],
            }
        )
        history.append(
            {
                **common,
                "team": away,
                "opponent": home,
                "listed_home": False,
                "goals_for": away_score,
                "goals_against": home_score,
                "pre_elo": round(away_pre, 4),
                "opponent_pre_elo": round(home_pre, 4),
                "expected_result": round(away_expected, 6),
                "actual_result": away_actual,
                "elo_change": away_change,
                "post_elo": elo[away],
            }
        )

    latest = [
        {
            "team": team,
            "latest_elo": round(rating, 4),
            "rated_matches": rated_matches[team],
        }
        for team, rating in sorted(elo.items())
    ]
    return history, latest


def main() -> int:
    parser = argparse.ArgumentParser(description="Build processed public CSVs from latest raw snapshot.")
    parser.add_argument("--raw-snapshot", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "data" / "processed" / "public_csv")
    args = parser.parse_args()

    snapshot = args.raw_snapshot or latest_snapshot(ROOT / "data" / "raw")
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    matches = read_csv_if_exists(snapshot / "international_results.csv")
    goalscorers = read_csv_if_exists(snapshot / "international_goalscorers.csv")
    team_long = build_team_match_long(matches)
    elo_history, elo_latest = build_elo_tables(matches)
    api_football_fixtures = flatten_api_football_fixtures(snapshot)
    world_cup_2026_fixtures = build_2026_fixtures(matches)
    world_cup_2026_fixture_times = build_fixture_times(snapshot, world_cup_2026_fixtures)

    summary: dict[str, object] = {
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "raw_snapshot": str(snapshot),
        "outputs": {},
    }

    outputs = {
        "fact_international_matches_team_long.csv": (
            team_long,
            [
                "source_match_id",
                "date",
                "tournament",
                "city",
                "country",
                "neutral",
                "team",
                "opponent",
                "listed_home",
                "goals_for",
                "goals_against",
                "goal_diff",
                "result",
            ],
        ),
        "agg_team_history.csv": (
            summarize_team_history(team_long),
            [
                "team",
                "matches",
                "wins",
                "draws",
                "losses",
                "goals_for",
                "goals_against",
                "first_match_date",
                "last_match_date",
                "avg_goals_for",
                "avg_goals_against",
                "avg_goal_diff",
                "win_pct",
            ],
        ),
        "agg_team_recent_form.csv": (
            summarize_team_recent_form(team_long),
            [
                "team",
                "matches",
                "wins",
                "draws",
                "losses",
                "goals_for",
                "goals_against",
                "first_match_date",
                "last_match_date",
                "avg_goals_for",
                "avg_goals_against",
                "avg_goal_diff",
                "win_pct",
                "since_date",
            ],
        ),
        "fact_player_goals.csv": (
            goalscorers,
            [
                "date",
                "home_team",
                "away_team",
                "team",
                "scorer",
                "minute",
                "own_goal",
                "penalty",
            ],
        ),
        "agg_player_international_goals.csv": (
            summarize_player_goals(goalscorers),
            [
                "team",
                "player_name",
                "international_goals_in_dataset",
                "penalty_goals",
                "own_goals",
                "first_goal_date",
                "last_goal_date",
                "tournaments_scored_in",
            ],
        ),
        "fact_2026_world_cup_fixtures.csv": (
            world_cup_2026_fixtures,
            [
                "source_match_id",
                "date",
                "home_team",
                "away_team",
                "home_score",
                "away_score",
                "status",
                "city",
                "country",
                "neutral",
            ],
        ),
        "fact_2026_world_cup_fixture_times.csv": (
            world_cup_2026_fixture_times,
            [
                "source_match_id",
                "date",
                "local_time",
                "utc_offset",
                "kickoff_local_iso",
                "kickoff_utc_iso",
                "refresh_utc_iso",
                "home_team",
                "away_team",
                "home_team_key",
                "away_team_key",
                "venue_label",
            ],
        ),
        "dim_locations_from_results.csv": (
            build_location_dimension(matches),
            ["city", "country", "matches_in_results_dataset"],
        ),
        "fact_team_elo_match_history.csv": (
            elo_history,
            [
                "source_match_id",
                "date",
                "tournament",
                "city",
                "country",
                "neutral",
                "k_factor",
                "goal_multiplier",
                "team",
                "opponent",
                "listed_home",
                "goals_for",
                "goals_against",
                "pre_elo",
                "opponent_pre_elo",
                "expected_result",
                "actual_result",
                "elo_change",
                "post_elo",
            ],
        ),
        "agg_team_elo_latest.csv": (
            elo_latest,
            ["team", "latest_elo", "rated_matches"],
        ),
    }

    api_outputs = {
        "api_football_world_cup_leagues.csv": (
            flatten_api_football_leagues(snapshot),
            [
                "api_league_id",
                "league_name",
                "league_type",
                "country_name",
                "season",
                "season_start",
                "season_end",
                "season_current",
                "coverage_events",
                "coverage_lineups",
                "coverage_fixture_statistics",
                "coverage_player_statistics",
                "coverage_standings",
                "coverage_players",
                "coverage_injuries",
                "coverage_predictions",
                "coverage_odds",
            ],
        ),
        "api_football_world_cup_fixtures.csv": (
            api_football_fixtures,
            [
                "api_fixture_id",
                "referee",
                "timezone",
                "fixture_date",
                "timestamp",
                "venue_id",
                "venue_name",
                "venue_city",
                "status_long",
                "status_short",
                "elapsed",
                "league_id",
                "league_name",
                "season",
                "round",
                "home_team_id",
                "home_team",
                "home_winner",
                "away_team_id",
                "away_team",
                "away_winner",
                "home_goals",
                "away_goals",
                "halftime_home",
                "halftime_away",
                "fulltime_home",
                "fulltime_away",
                "extratime_home",
                "extratime_away",
                "penalty_home",
                "penalty_away",
            ],
        ),
        "api_football_world_cup_team_match_frame.csv": (
            build_api_football_team_match_frame(api_football_fixtures),
            [
                "api_fixture_id",
                "fixture_date",
                "league_id",
                "season",
                "round",
                "venue_id",
                "venue_name",
                "venue_city",
                "status_short",
                "team_id",
                "team",
                "opponent_id",
                "opponent",
                "listed_home",
                "goals_for",
                "goals_against",
                "goal_diff",
                "result",
            ],
        ),
        "api_football_world_cup_teams.csv": (
            flatten_api_football_teams(snapshot),
            [
                "team_id",
                "team_name",
                "team_code",
                "country",
                "founded",
                "national",
                "venue_id",
                "venue_name",
                "venue_city",
                "venue_capacity",
                "venue_surface",
            ],
        ),
        "api_football_world_cup_standings.csv": (
            flatten_api_football_standings(snapshot),
            [
                "league_id",
                "league_name",
                "season",
                "rank",
                "team_id",
                "team_name",
                "points",
                "goals_diff",
                "group_name",
                "form",
                "status",
                "description",
                "all_played",
                "all_win",
                "all_draw",
                "all_lose",
                "all_goals_for",
                "all_goals_against",
            ],
        ),
        "api_football_world_cup_injuries.csv": (
            flatten_api_football_injuries(snapshot),
            [
                "player_id",
                "player_name",
                "player_type",
                "player_reason",
                "team_id",
                "team_name",
                "fixture_id",
                "fixture_timezone",
                "fixture_date",
                "league_id",
                "league_name",
                "season",
            ],
        ),
        "api_football_world_cup_odds.csv": (
            flatten_api_football_odds(snapshot),
            [
                "fixture_id",
                "fixture_timezone",
                "fixture_date",
                "league_id",
                "league_name",
                "season",
                "bookmaker_id",
                "bookmaker_name",
                "bet_id",
                "bet_name",
                "outcome_value",
                "outcome_odd",
            ],
        ),
        "api_football_world_cup_players.csv": (
            flatten_api_football_players(snapshot),
            [
                "player_id",
                "player_name",
                "player_firstname",
                "player_lastname",
                "age",
                "birth_date",
                "birth_place",
                "birth_country",
                "nationality",
                "height",
                "weight",
                "injured",
                "team_id",
                "team_name",
                "league_id",
                "league_name",
                "season",
                "appearances",
                "lineups",
                "minutes",
                "position",
                "rating",
                "captain",
                "goals_total",
                "goals_conceded",
                "assists",
                "shots_total",
                "shots_on",
                "passes_total",
                "passes_key",
                "tackles_total",
                "duels_total",
                "duels_won",
                "dribbles_attempts",
                "dribbles_success",
                "fouls_drawn",
                "fouls_committed",
                "yellow_cards",
                "red_cards",
                "penalties_scored",
                "penalties_missed",
                "penalties_saved",
            ],
        ),
        "api_football_fixture_lineups.csv": (
            flatten_api_football_fixture_lineups(snapshot),
            [
                "api_fixture_id",
                "team_id",
                "team_name",
                "formation",
                "coach_id",
                "coach_name",
                "lineup_role",
                "player_id",
                "player_name",
                "player_number",
                "player_position",
                "player_grid",
            ],
        ),
        "api_football_fixture_events.csv": (
            flatten_api_football_fixture_events(snapshot),
            [
                "api_fixture_id",
                "elapsed",
                "extra",
                "team_id",
                "team_name",
                "player_id",
                "player_name",
                "assist_id",
                "assist_name",
                "event_type",
                "event_detail",
                "comments",
            ],
        ),
        "api_football_fixture_predictions.csv": (
            flatten_api_football_fixture_predictions(snapshot),
            [
                "api_fixture_id",
                "winner_id",
                "winner_name",
                "winner_comment",
                "win_or_draw",
                "under_over",
                "goals_home",
                "goals_away",
                "advice",
                "home_percent",
                "draw_percent",
                "away_percent",
                "home_team_id",
                "home_team",
                "away_team_id",
                "away_team",
            ],
        ),
    }

    for filename, (rows, fieldnames) in api_outputs.items():
        if rows:
            outputs[filename] = (rows, fieldnames)

    squads_path = snapshot / "wikimedia_2026_fifa_world_cup_squads.wikitext"
    if squads_path.exists():
        squad_rows = parse_squads(squads_path.read_text(encoding="utf-8"))
        outputs["dim_2026_world_cup_squad_players.csv"] = (
            squad_rows,
            [
                "group_name",
                "team",
                "shirt_number",
                "position",
                "player_name",
                "player_wiki_title",
                "sort_name",
                "birth_date",
                "age_years_as_of_2026_06_11",
                "caps_before_tournament",
                "goals_before_tournament",
                "club",
                "club_wiki_title",
                "club_country_code",
                "notes",
                "is_captain",
            ],
        )

    for filename, (rows, fieldnames) in outputs.items():
        count = write_csv(output_dir / filename, rows, fieldnames)
        summary["outputs"][filename] = {"rows": count}

    (output_dir / "build_manifest.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
