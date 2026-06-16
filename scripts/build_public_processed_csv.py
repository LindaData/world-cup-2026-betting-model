from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.parsers.wikipedia_squads import parse_squads  # noqa: E402


def latest_snapshot(raw_root: Path) -> Path:
    snapshots = [path for path in raw_root.iterdir() if path.is_dir() and (path / "manifest.json").exists()]
    if not snapshots:
        raise FileNotFoundError("No raw snapshots found. Run scripts/fetch_raw_data.py first.")
    return max(snapshots, key=lambda path: path.stat().st_mtime)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


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

    matches = read_csv(snapshot / "international_results.csv")
    goalscorers = read_csv(snapshot / "international_goalscorers.csv")
    team_long = build_team_match_long(matches)
    elo_history, elo_latest = build_elo_tables(matches)

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
            build_2026_fixtures(matches),
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
