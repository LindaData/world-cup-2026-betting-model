"""Publish LindaData R model outputs to the Sports Hub data directory.

Reads the daily R pipeline outputs (matchday prediction board and champion
simulation summary CSVs) and publishes them as Sports Hub JSON feeds:

- docs/sports-data/data/model_predictions.json: per-match win/draw/loss
  probabilities keyed by ESPN game_id, joined to football_fixtures.json by
  normalized team names plus kickoff date (+/- 1 day).
- docs/sports-data/data/model_champion.json: tournament title chances from the
  champion simulation.

Both files match the placeholder schema committed on main, so the frontend
needs no changes. If the R outputs are missing entirely, the script prints a
"nothing to publish" message and exits 0 so the model run never fails on this
step.
"""

from __future__ import annotations

import csv
import json
import os
import sys
import unicodedata
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

MODELING_DIR = Path(os.environ.get("MODEL_PREDICTIONS_SOURCE_DIR", ROOT / "data" / "processed" / "modeling"))
PUBLIC_MODELING_DIR = Path(os.environ.get("MODEL_PREDICTIONS_PUBLIC_DIR", ROOT / "data" / "public" / "modeling"))
SPORTS_HUB_DIR = Path(os.environ.get("SPORTS_HUB_DATA_DIR", ROOT / "docs" / "sports-data" / "data"))

BOARD_CSV = "matchday_prediction_board.csv"
FIXTURE_PREDICTIONS_CSV = "world_cup_2026_fixture_predictions.csv"
CHAMPION_SUMMARY_CSV = "world_cup_2026_champion_simulation_summary.csv"

PROVIDER = "lindadata-model"

# Team names differ slightly between the R fixture shell and ESPN. Both sides
# are normalized (lowercase, accents stripped, non-alphanumerics removed) and
# then mapped through this alias table so either naming convention matches.
TEAM_ALIASES = {
    "usa": "unitedstates",
    "unitedstatesofamerica": "unitedstates",
    "turkiye": "turkey",
    "czechia": "czechrepublic",
    "bosniaherzegovina": "bosniaandherzegovina",
    "congodr": "drcongo",
    "democraticrepublicofcongo": "drcongo",
    "democraticrepublicofthecongo": "drcongo",
    "korearepublic": "southkorea",
    "koreadpr": "northkorea",
    "iriran": "iran",
    "cotedivoire": "ivorycoast",
    "caboverde": "capeverde",
    "capeverdeislands": "capeverde",
    "chinapr": "china",
    "uae": "unitedarabemirates",
    "holland": "netherlands",
}


def log(message: str) -> None:
    print(f"publish_model_predictions: {message}", file=sys.stderr)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_team(name: str | None) -> str:
    if not name:
        return ""
    decomposed = unicodedata.normalize("NFKD", name)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    key = "".join(ch for ch in stripped.lower() if ch.isalnum())
    return TEAM_ALIASES.get(key, key)


def parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value.strip()[:10])
    except ValueError:
        return None


def parse_probability(value: str | None) -> float | None:
    if value is None:
        return None
    text = value.strip()
    if not text or text.upper() in {"NA", "NAN", "NULL"}:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    if not 0.0 <= number <= 1.0:
        return None
    return number


def first_existing(filename: str) -> Path | None:
    for directory in (MODELING_DIR, PUBLIC_MODELING_DIR):
        candidate = directory / filename
        if candidate.is_file():
            return candidate
    return None


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def model_version() -> str:
    run_date = datetime.now(timezone.utc).strftime("%Y%m%d")
    sha = os.environ.get("GITHUB_SHA", "").strip()
    return f"r-ensemble-{run_date}-{sha[:7] if sha else 'local'}"


def load_fixture_index() -> dict[tuple[str, str], list[dict[str, Any]]]:
    """Index ESPN fixtures by normalized (home, away) team pair."""
    fixtures_path = SPORTS_HUB_DIR / "football_fixtures.json"
    if not fixtures_path.is_file():
        log(f"missing {fixtures_path}; cannot join match predictions to ESPN game ids")
        return {}
    fixtures = json.loads(fixtures_path.read_text(encoding="utf-8"))
    index: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for fixture in fixtures:
        game_id = str(fixture.get("game_id") or "")
        home = normalize_team(fixture.get("home_team"))
        away = normalize_team(fixture.get("away_team"))
        kickoff = parse_date(fixture.get("date_utc"))
        if not game_id or not home or not away or kickoff is None:
            continue
        index.setdefault((home, away), []).append({"game_id": game_id, "date": kickoff})
    return index


def match_probabilities(row: dict[str, str]) -> dict[str, float] | None:
    """Extract home/draw/away probabilities, preferring the ensemble columns."""
    column_sets = (
        ("ensemble_home_win_prob", "ensemble_draw_prob", "ensemble_away_win_prob"),
        ("pred_home_win_prob", "pred_draw_prob", "pred_away_win_prob"),
    )
    for home_col, draw_col, away_col in column_sets:
        home = parse_probability(row.get(home_col))
        draw = parse_probability(row.get(draw_col))
        away = parse_probability(row.get(away_col))
        if home is not None and draw is not None and away is not None:
            return {"home": home, "draw": draw, "away": away}
    return None


def resolve_game_id(
    index: dict[tuple[str, str], list[dict[str, Any]]],
    home_key: str,
    away_key: str,
    match_date: date,
) -> tuple[str | None, bool]:
    """Return (game_id, swapped) for a team pair within +/- 1 day of kickoff."""
    for pair, swapped in (((home_key, away_key), False), ((away_key, home_key), True)):
        for candidate in index.get(pair, []):
            if abs((candidate["date"] - match_date).days) <= 1:
                return candidate["game_id"], swapped
    return None, False


def build_predictions() -> dict[str, dict[str, float]] | None:
    source = first_existing(BOARD_CSV) or first_existing(FIXTURE_PREDICTIONS_CSV)
    if source is None:
        return None

    index = load_fixture_index()
    if not index:
        return None

    predictions: dict[str, dict[str, float]] = {}
    unmatched = 0
    for row in read_csv_rows(source):
        home_team = (row.get("home_team") or "").strip()
        away_team = (row.get("away_team") or "").strip()
        match_date = parse_date(row.get("date"))
        probabilities = match_probabilities(row)
        if not home_team or not away_team or match_date is None or probabilities is None:
            log(f"skipping incomplete row: {home_team or '?'} vs {away_team or '?'} on {row.get('date') or '?'}")
            unmatched += 1
            continue

        game_id, swapped = resolve_game_id(
            index, normalize_team(home_team), normalize_team(away_team), match_date
        )
        if game_id is None:
            log(f"no ESPN fixture match for: {home_team} vs {away_team} on {match_date}")
            unmatched += 1
            continue
        if swapped:
            probabilities = {
                "home": probabilities["away"],
                "draw": probabilities["draw"],
                "away": probabilities["home"],
            }
        predictions[game_id] = {key: round(value, 4) for key, value in probabilities.items()}

    log(f"matched {len(predictions)} predictions from {source} ({unmatched} rows skipped)")
    return predictions or None


def build_title_chances() -> tuple[list[dict[str, Any]], int] | None:
    source = first_existing(CHAMPION_SUMMARY_CSV)
    if source is None:
        return None

    chances: list[dict[str, Any]] = []
    simulations = 0
    for row in read_csv_rows(source):
        team = (row.get("team") or "").strip()
        probability = parse_probability(row.get("champion_probability"))
        if not team or probability is None:
            continue
        try:
            simulations = max(simulations, int(float(row.get("simulations") or 0)))
        except ValueError:
            pass
        chances.append({"team": team, "probability": round(probability, 4)})

    if not chances or simulations <= 0:
        log(f"champion summary {source} had no usable rows; keeping existing feed")
        return None
    chances.sort(key=lambda item: (-item["probability"], item["team"]))
    return chances, simulations


def publish() -> int:
    refreshed_at = utc_now()
    published = 0

    predictions = build_predictions()
    if predictions is None:
        log("no match predictions to publish (missing R outputs or no fixture matches); leaving model_predictions.json untouched")
    else:
        write_json(
            SPORTS_HUB_DIR / "model_predictions.json",
            {
                "refreshed_at_utc": refreshed_at,
                "provider": PROVIDER,
                "model_version": model_version(),
                "predictions": predictions,
            },
        )
        print(f"Published {len(predictions)} match predictions to {SPORTS_HUB_DIR / 'model_predictions.json'}")
        published += 1

    champion = build_title_chances()
    if champion is None:
        log("no champion simulation to publish; leaving model_champion.json untouched")
    else:
        title_chances, simulations = champion
        write_json(
            SPORTS_HUB_DIR / "model_champion.json",
            {
                "refreshed_at_utc": refreshed_at,
                "provider": PROVIDER,
                "simulations": simulations,
                "title_chances": title_chances,
            },
        )
        print(f"Published {len(title_chances)} title chances to {SPORTS_HUB_DIR / 'model_champion.json'}")
        published += 1

    if published == 0:
        print("Nothing to publish: R model outputs were not found. This is not an error.")
    return 0


def main() -> int:
    try:
        return publish()
    except Exception as exc:  # noqa: BLE001 - publishing must never fail the model run.
        log(f"unexpected error, skipping publish: {exc!r}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
