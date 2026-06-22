from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.providers.api_sports import ApiSportsClient  # noqa: E402


TEAM_LEAGUE_ENDPOINTS = {
    "football": [
        ("fixtures", "/fixtures", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "basketball": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "baseball": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "hockey": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "rugby": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "volleyball": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "handball": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
    "nfl": [
        ("games", "/games", ("league", "season")),
        ("teams", "/teams", ("league", "season")),
        ("standings", "/standings", ("league", "season")),
    ],
}

SEASON_ENDPOINTS = {
    "nba": [
        ("games", "/games", ("season",)),
        ("standings", "/standings", ("league", "season")),
        ("teams", "/teams", tuple()),
    ],
    "afl": [
        ("games", "/games", ("season",)),
        ("standings", "/standings", ("season",)),
        ("teams", "/teams", tuple()),
    ],
    "mma": [
        ("fights", "/fights", ("season",)),
    ],
}

COMPETITION_ENDPOINTS = {
    "formula_1": [
        ("races", "/races", ("competition", "season")),
    ],
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(value: datetime) -> str:
    return value.strftime("%Y%m%dT%H%M%SZ")


def iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def response_items(payload: object) -> list[object]:
    if isinstance(payload, dict) and isinstance(payload.get("response"), list):
        return payload["response"]
    return []


def results_count(payload: object) -> int:
    if isinstance(payload, dict):
        results = payload.get("results")
        if isinstance(results, int):
            return results
        response = payload.get("response")
        if isinstance(response, list):
            return len(response)
        if isinstance(response, dict):
            return 1
    return 0


def compact_errors(payload: object) -> str:
    if not isinstance(payload, dict):
        return ""
    errors = payload.get("errors")
    if errors in ({}, [], None, ""):
        return ""
    return json.dumps(errors, sort_keys=True)


def safe_stem(value: object) -> str:
    text = str(value)
    return "".join(ch if ch.isalnum() or ch in {"_", "-"} else "_" for ch in text.lower())


def latest_inventory_root() -> Path | None:
    root = ROOT / "data" / "raw" / "apisports_inventory"
    if not root.exists():
        return None
    candidates = [path for path in root.iterdir() if path.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def load_sports(config_path: Path, sport_keys: list[str]) -> list[dict[str, Any]]:
    config = read_json(config_path)
    sports = [sport for sport in config.get("sports", []) if isinstance(sport, dict)]
    if not sport_keys or "all" in sport_keys:
        return sports
    wanted = set(sport_keys)
    selected = [sport for sport in sports if sport.get("sport_key") in wanted]
    missing = sorted(wanted - {sport.get("sport_key") for sport in selected})
    if missing:
        raise ValueError("Unknown sport key(s): " + ", ".join(missing))
    return selected


def extract_season_value(value: object) -> int | str | None:
    if isinstance(value, dict):
        for key in ("year", "season"):
            if value.get(key) not in (None, ""):
                return value[key]
    if isinstance(value, (int, str)) and str(value):
        return value
    return None


def sorted_seasons(values: list[object], max_count: int) -> list[int | str]:
    seasons = [extract_season_value(value) for value in values]
    seasons = [season for season in seasons if season not in (None, "")]

    def season_sort_key(value: int | str) -> tuple[int, int | str]:
        text = str(value)
        if text.isdigit():
            return (1, int(text))
        return (0, text)

    unique = sorted(
        set(seasons),
        key=season_sort_key,
        reverse=True,
    )
    return unique[:max_count]


def extract_leagues(payload: object, max_leagues: int, max_seasons: int) -> list[dict[str, object]]:
    leagues: list[dict[str, object]] = []
    for item in response_items(payload):
        if not isinstance(item, dict):
            continue
        league = item.get("league") if isinstance(item.get("league"), dict) else item
        league_id = league.get("id") if isinstance(league, dict) else None
        if league_id in (None, ""):
            continue
        seasons = sorted_seasons(item.get("seasons", []), max_seasons)
        if not seasons:
            continue
        leagues.append(
            {
                "id": league_id,
                "name": league.get("name", "") if isinstance(league, dict) else "",
                "seasons": seasons,
                "season_count": len(item.get("seasons", [])) if isinstance(item.get("seasons"), list) else 0,
            }
        )
    leagues.sort(key=lambda row: (int(row["season_count"]), str(row["name"])), reverse=True)
    return leagues[:max_leagues]


def extract_competitions(payload: object, max_competitions: int) -> list[dict[str, object]]:
    competitions: list[dict[str, object]] = []
    for item in response_items(payload):
        if not isinstance(item, dict):
            continue
        competition = item.get("competition") if isinstance(item.get("competition"), dict) else item
        competition_id = competition.get("id") if isinstance(competition, dict) else None
        if competition_id in (None, ""):
            continue
        competitions.append(
            {
                "id": competition_id,
                "name": competition.get("name", "") if isinstance(competition, dict) else "",
            }
        )
    competitions.sort(key=lambda row: str(row["name"]))
    return competitions[:max_competitions]


def inventory_payload(inventory_root: Path, sport_key: str, name: str) -> dict[str, Any]:
    path = inventory_root / sport_key / f"{name}.json"
    if not path.exists():
        return {}
    return read_json(path)


def call_endpoint(
    client: ApiSportsClient,
    sport_key: str,
    endpoint_name: str,
    path: str,
    params: dict[str, object],
    raw_root: Path,
) -> dict[str, object]:
    param_stem = "_".join(f"{safe_stem(key)}-{safe_stem(value)}" for key, value in params.items())
    file_name = f"{safe_stem(endpoint_name)}_{param_stem or 'all'}.json"
    raw_path = raw_root / sport_key / file_name
    row: dict[str, object] = {
        "sport_key": sport_key,
        "endpoint_name": endpoint_name,
        "path": path,
        "params_json": json.dumps(params, sort_keys=True),
        "status_code": "",
        "results": "",
        "errors": "",
        "raw_file": str(raw_path.relative_to(ROOT)),
    }
    try:
        response = client.get(path, params=params)
        row["status_code"] = response.status_code
        try:
            payload = response.json()
        except json.JSONDecodeError:
            payload = {"raw_text": response.text}
        write_json(raw_path, payload)
        row["results"] = results_count(payload)
        row["errors"] = compact_errors(payload)
    except ConnectionError as exc:
        row["status_code"] = "connection_error"
        row["errors"] = str(exc)
    return row


def task_key(sport_key: str, endpoint_name: str, params: dict[str, object]) -> tuple[str, str, str]:
    return (
        sport_key,
        endpoint_name,
        json.dumps(params, sort_keys=True),
    )


def read_request_log(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def load_completed_task_keys(processed_root: Path) -> set[tuple[str, str, str]]:
    log_paths = [processed_root / "apisports_training_request_log.csv"]
    history_root = processed_root / "history"
    if history_root.exists():
        log_paths.extend(sorted(history_root.glob("apisports_training_request_log_*.csv")))
    completed: set[tuple[str, str, str]] = set()
    for path in log_paths:
        for row in read_request_log(path):
            if row.get("status_code") != "200":
                continue
            try:
                params = json.loads(row.get("params_json", "{}") or "{}")
            except json.JSONDecodeError:
                params = {}
            completed.add(task_key(row.get("sport_key", ""), row.get("endpoint_name", ""), params))
    return completed


def is_rate_limit_response(row: dict[str, object]) -> bool:
    status_code = str(row.get("status_code", ""))
    errors = str(row.get("errors", "")).lower()
    return (
        status_code == "429"
        or "ratelimit" in errors
        or "rate limit" in errors
        or "too many requests" in errors
        or "request limit" in errors
    )


def league_backfill_tasks(
    sport_key: str,
    inventory_root: Path,
    max_leagues: int,
    max_seasons: int,
) -> list[tuple[str, str, dict[str, object]]]:
    leagues = extract_leagues(
        inventory_payload(inventory_root, sport_key, "leagues"),
        max_leagues=max_leagues,
        max_seasons=max_seasons,
    )
    tasks: list[tuple[str, str, dict[str, object]]] = []
    for league in leagues:
        for season in league["seasons"]:
            for endpoint_name, path, params_from in TEAM_LEAGUE_ENDPOINTS[sport_key]:
                params: dict[str, object] = {}
                if "league" in params_from:
                    params["league"] = league["id"]
                if "season" in params_from:
                    params["season"] = season
                tasks.append((endpoint_name, path, params))
    return tasks


def season_backfill_tasks(
    sport_key: str,
    inventory_root: Path,
    max_seasons: int,
) -> list[tuple[str, str, dict[str, object]]]:
    seasons = sorted_seasons(response_items(inventory_payload(inventory_root, sport_key, "seasons")), max_seasons)
    tasks: list[tuple[str, str, dict[str, object]]] = []
    for season in seasons:
        for endpoint_name, path, params_from in SEASON_ENDPOINTS[sport_key]:
            params: dict[str, object] = {}
            if "season" in params_from:
                params["season"] = season
            if "league" in params_from:
                params["league"] = "standard"
            tasks.append((endpoint_name, path, params))
    return tasks


def competition_backfill_tasks(
    sport_key: str,
    inventory_root: Path,
    max_competitions: int,
    max_seasons: int,
) -> list[tuple[str, str, dict[str, object]]]:
    competitions = extract_competitions(
        inventory_payload(inventory_root, sport_key, "competitions"),
        max_competitions=max_competitions,
    )
    seasons = sorted_seasons(response_items(inventory_payload(inventory_root, sport_key, "seasons")), max_seasons)
    tasks: list[tuple[str, str, dict[str, object]]] = []
    for competition in competitions:
        for season in seasons:
            for endpoint_name, path, params_from in COMPETITION_ENDPOINTS[sport_key]:
                params: dict[str, object] = {}
                if "competition" in params_from:
                    params["competition"] = competition["id"]
                if "season" in params_from:
                    params["season"] = season
                tasks.append((endpoint_name, path, params))
    return tasks


def tasks_for_sport(
    sport_key: str,
    inventory_root: Path,
    max_leagues: int,
    max_seasons: int,
) -> list[tuple[str, str, dict[str, object]]]:
    if sport_key in TEAM_LEAGUE_ENDPOINTS:
        return league_backfill_tasks(sport_key, inventory_root, max_leagues, max_seasons)
    if sport_key in SEASON_ENDPOINTS:
        return season_backfill_tasks(sport_key, inventory_root, max_seasons)
    if sport_key in COMPETITION_ENDPOINTS:
        return competition_backfill_tasks(sport_key, inventory_root, max_leagues, max_seasons)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch capped API-Sports training data by sport.")
    parser.add_argument("--config", default="config/sports.json")
    parser.add_argument("--sports", nargs="+", default=["all"])
    parser.add_argument("--max-requests-per-sport", type=int, default=80)
    parser.add_argument("--max-leagues-per-sport", type=int, default=5)
    parser.add_argument("--max-seasons-per-league", type=int, default=4)
    parser.add_argument("--refresh-existing", action="store_true")
    parser.add_argument("--keep-going-after-limit", action="store_true")
    parser.add_argument("--request-delay-seconds", type=float, default=0)
    parser.add_argument("--rate-limit-wait-seconds", type=float, default=20)
    parser.add_argument("--rate-limit-retries", type=int, default=1)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    inventory_root = latest_inventory_root()
    if inventory_root is None:
        raise RuntimeError("Run scripts/fetch_apisports_inventory.py before training data pulls.")

    settings = load_settings()
    api_key = settings.api_sports_key or settings.api_football_key
    if not api_key and not args.dry_run:
        raise RuntimeError("API_SPORTS_KEY or API_FOOTBALL_KEY must be set in .env.")

    sports = load_sports(ROOT / args.config, args.sports)
    pulled_at = utc_now()
    run_id = stamp(pulled_at)
    raw_root = ROOT / "data" / "raw" / "apisports_training" / run_id
    processed_root = ROOT / "data" / "processed" / "multisport"
    history_root = processed_root / "history"
    existing_successes = set()
    if not args.refresh_existing:
        existing_successes = load_completed_task_keys(processed_root)

    request_rows: list[dict[str, object]] = []
    summary_rows: list[dict[str, object]] = []
    manifest: dict[str, object] = {
        "pulled_at_utc": iso(pulled_at),
        "run_id": run_id,
        "inventory_root": str(inventory_root.relative_to(ROOT)),
        "dry_run": args.dry_run,
        "sports": {},
    }

    for sport in sports:
        sport_key = str(sport["sport_key"])
        sport_tasks = tasks_for_sport(
            sport_key=sport_key,
            inventory_root=inventory_root,
            max_leagues=args.max_leagues_per_sport,
            max_seasons=args.max_seasons_per_league,
        )
        planned_task_count = len(sport_tasks)
        skipped_existing = 0
        if existing_successes:
            pending_tasks = []
            for endpoint_name, path, params in sport_tasks:
                if task_key(sport_key, endpoint_name, params) in existing_successes:
                    skipped_existing += 1
                else:
                    pending_tasks.append((endpoint_name, path, params))
            sport_tasks = pending_tasks
        sport_tasks = sport_tasks[: max(0, args.max_requests_per_sport)]
        client = ApiSportsClient(api_key, host=str(sport["host"]))
        completed = 0
        ok = 0
        total_results = 0
        errors = 0
        stopped_on_limit = False

        for endpoint_name, path, params in sport_tasks:
            if args.dry_run:
                row = {
                    "sport_key": sport_key,
                    "endpoint_name": endpoint_name,
                    "path": path,
                    "params_json": json.dumps(params, sort_keys=True),
                    "status_code": "dry_run",
                    "results": "",
                    "errors": "",
                    "raw_file": "",
                }
            else:
                attempts = 0
                while True:
                    row = call_endpoint(client, sport_key, endpoint_name, path, params, raw_root)
                    if not is_rate_limit_response(row) or attempts >= args.rate_limit_retries:
                        break
                    attempts += 1
                    time.sleep(max(0, args.rate_limit_wait_seconds))
                if args.request_delay_seconds > 0:
                    time.sleep(args.request_delay_seconds)
            row["pulled_at_utc"] = iso(pulled_at)
            row["sport_label"] = sport.get("label", sport_key)
            request_rows.append(row)
            completed += 1
            if str(row["status_code"]) == "200":
                ok += 1
            if str(row.get("errors", "")):
                errors += 1
            try:
                total_results += int(row.get("results") or 0)
            except ValueError:
                pass
            if is_rate_limit_response(row) and not args.keep_going_after_limit:
                stopped_on_limit = True
                break

        summary = {
            "pulled_at_utc": iso(pulled_at),
            "sport_key": sport_key,
            "sport_label": sport.get("label", sport_key),
            "host": sport.get("host", ""),
            "tasks_planned": planned_task_count,
            "tasks_skipped_existing": skipped_existing,
            "requests_attempted": completed,
            "requests_ok": ok,
            "requests_with_errors": errors,
            "total_results_reported": total_results,
            "request_cap": args.max_requests_per_sport,
            "stopped_on_limit": stopped_on_limit,
        }
        summary_rows.append(summary)
        manifest["sports"][sport_key] = summary

    write_csv(
        processed_root / "apisports_training_pull_summary.csv",
        summary_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "host",
            "tasks_planned",
            "tasks_skipped_existing",
            "requests_attempted",
            "requests_ok",
            "requests_with_errors",
            "total_results_reported",
            "request_cap",
            "stopped_on_limit",
        ],
    )
    write_csv(
        processed_root / "apisports_training_request_log.csv",
        request_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "endpoint_name",
            "path",
            "params_json",
            "status_code",
            "results",
            "errors",
            "raw_file",
        ],
    )
    write_csv(
        history_root / f"apisports_training_pull_summary_{run_id}.csv",
        summary_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "host",
            "tasks_planned",
            "tasks_skipped_existing",
            "requests_attempted",
            "requests_ok",
            "requests_with_errors",
            "total_results_reported",
            "request_cap",
            "stopped_on_limit",
        ],
    )
    write_csv(
        history_root / f"apisports_training_request_log_{run_id}.csv",
        request_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "endpoint_name",
            "path",
            "params_json",
            "status_code",
            "results",
            "errors",
            "raw_file",
        ],
    )
    write_json(raw_root / "manifest.json", manifest)
    print(f"Wrote API-Sports training raw snapshot: {raw_root}")
    print(f"Wrote training request summaries: {processed_root}")
    print(f"Requests attempted: {len(request_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
