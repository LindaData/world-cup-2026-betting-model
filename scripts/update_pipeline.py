from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]


@dataclass
class Step:
    name: str
    command: list[str]
    required: bool = True


@dataclass
class StepResult:
    name: str
    command: list[str]
    required: bool
    status: str
    returncode: int | None
    started_at_utc: str
    finished_at_utc: str
    seconds: float
    stdout_log: str
    stderr_log: str


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def stamp_for_path(value: datetime) -> str:
    return value.strftime("%Y%m%dT%H%M%SZ")


def iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def find_rscript(explicit: str | None = None) -> str:
    candidates: list[str | None] = [
        explicit,
        os.environ.get("RSCRIPT_EXE"),
        shutil.which("Rscript"),
        "C:/Program Files/R/R-4.1.1/bin/Rscript.exe",
        "C:/Program Files/R/R-4.1.1/bin/x64/Rscript.exe",
    ]

    r_root = Path("C:/Program Files/R")
    if r_root.exists():
        candidates.extend(str(path) for path in sorted(r_root.glob("R-*/bin/Rscript.exe"), reverse=True))
        candidates.extend(
            str(path) for path in sorted(r_root.glob("R-*/bin/x64/Rscript.exe"), reverse=True)
        )

    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(Path(candidate))
        if candidate and shutil.which(candidate):
            return str(candidate)

    raise FileNotFoundError(
        "Could not find Rscript. Set RSCRIPT_EXE to your Rscript.exe path, for example "
        "C:/Program Files/R/R-4.1.1/bin/Rscript.exe."
    )


def run_step(step: Step, run_dir: Path, continue_on_error: bool) -> StepResult:
    start = utc_now()
    safe_name = step.name.lower().replace(" ", "_").replace("/", "_")
    stdout_log = run_dir / f"{safe_name}.stdout.log"
    stderr_log = run_dir / f"{safe_name}.stderr.log"

    completed = subprocess.run(
        step.command,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    finish = utc_now()

    stdout_log.write_text(completed.stdout, encoding="utf-8")
    stderr_log.write_text(completed.stderr, encoding="utf-8")

    status = "ok" if completed.returncode == 0 else "failed"
    result = StepResult(
        name=step.name,
        command=step.command,
        required=step.required,
        status=status,
        returncode=completed.returncode,
        started_at_utc=iso(start),
        finished_at_utc=iso(finish),
        seconds=round((finish - start).total_seconds(), 3),
        stdout_log=str(stdout_log.relative_to(ROOT)),
        stderr_log=str(stderr_log.relative_to(ROOT)),
    )

    print(f"[{result.status}] {step.name} ({result.seconds}s)")
    if completed.stdout:
        print(completed.stdout[-2000:])
    if completed.stderr:
        print(completed.stderr[-2000:], file=sys.stderr)

    if completed.returncode != 0 and step.required and not continue_on_error:
        raise RuntimeError(f"Pipeline stopped at step: {step.name}")

    return result


def latest_raw_snapshot() -> Path | None:
    raw_root = ROOT / "data" / "raw"
    snapshots = [
        path
        for path in raw_root.iterdir()
        if path.is_dir() and (path / "manifest.json").exists()
    ] if raw_root.exists() else []
    if not snapshots:
        return None
    return max(snapshots, key=lambda path: path.stat().st_mtime)


def latest_manifest_summary() -> list[dict[str, str]]:
    snapshot = latest_raw_snapshot()
    if not snapshot:
        return []

    try:
        manifest = json.loads((snapshot / "manifest.json").read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []

    rows: list[dict[str, str]] = []
    for source, detail in manifest.get("sources", {}).items():
        if isinstance(detail, dict) and "skipped" in detail:
            rows.append({"source": source, "status": "skipped", "detail": str(detail["skipped"])})
            continue

        status_codes: list[str] = []
        if isinstance(detail, dict):
            for value in detail.values():
                if isinstance(value, dict) and "status_code" in value:
                    status_codes.append(str(value["status_code"]))
        status = "pulled" if status_codes else "recorded"
        rows.append(
            {
                "source": source,
                "status": status,
                "detail": ", ".join(sorted(set(status_codes))) if status_codes else "",
            }
        )

    return rows


def copy_if_exists(source: Path, destination: Path) -> bool:
    if not source.exists():
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return True


def sync_publishable_artifacts() -> list[str]:
    docs_dir = ROOT / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    nojekyll = docs_dir / ".nojekyll"
    nojekyll.touch()
    return [str(nojekyll.relative_to(ROOT))]


def table_count_rows() -> list[dict[str, str]]:
    path = ROOT / "data" / "processed" / "metadata" / "table_inventory.csv"
    rows = read_csv(path)
    rows.sort(key=lambda row: row.get("table_name", ""))
    return rows


def markdown_table(headers: list[str], rows: Iterable[list[object]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(str(value) for value in row) + " |")
    return "\n".join(lines)


def write_current_status(
    run_started: datetime,
    run_dir: Path,
    args: argparse.Namespace,
    results: list[StepResult],
    copied: list[str],
) -> None:
    table_rows = table_count_rows()
    source_rows = latest_manifest_summary()
    failures = [result for result in results if result.status != "ok"]

    table_md = markdown_table(
        ["Table/View", "Rows"],
        ([f"`{row.get('table_name', '')}`", row.get("row_count", "")] for row in table_rows),
    )
    source_md = markdown_table(
        ["Source", "Status", "Detail"],
        ([row["source"], row["status"], row["detail"]] for row in source_rows),
    )
    step_md = markdown_table(
        ["Step", "Status", "Seconds"],
        ([result.name, result.status, result.seconds] for result in results),
    )
    copied_md = "\n".join(f"- `{path}`" for path in copied) if copied else "- No public artifacts copied."

    status_text = f"""# Current Data Status

Last refreshed: {iso(run_started)}.

Refresh profile: `{args.profile}`.

Local run folder:

```text
{run_dir.relative_to(ROOT)}
```

## Short Answer

The local refresh pipeline is now the source of truth for this project. It can rebuild from
existing local files or pull free/no-key public sources, then rebuild DuckDB, metadata,
model outputs, and shareable report artifacts.

APIs that have free tiers but require your personal API key are wired but only run when keys
are added to `.env` and the updater is called with `--include-keyed-apis`.

## Stored In DuckDB

Database:

```text
data/processed/world_cup.duckdb
```

Metadata exports:

```text
data/processed/metadata/table_inventory.csv
data/processed/metadata/column_inventory.csv
```

## Table Counts

{table_md}

## Latest Raw Snapshot Sources

{source_md if source_rows else "No raw snapshot manifest was available."}

## Refresh Steps

{step_md}

## Public Artifacts Updated

{copied_md}

## Wired But Waiting For Your Key

| Source | Key needed | What it adds |
| --- | --- | --- |
| football-data.org | Yes | Fixtures, standings, scorers, squads depending on plan |
| The Odds API | Yes | Odds snapshots, market probabilities, historical odds on paid tier |
| API-Football | Yes | Lineups, injuries, events, player stats, odds, predictions |

## Known Missing Model Inputs

These are not fully available from current no-key sources:

- Confirmed starting lineups.
- Substitutions and minutes played.
- Player-match statistics.
- Injuries and suspensions.
- Cards, shots, possession, saves, xG.
- Odds movement and closing lines.
- Complete player identity enrichment for every squad player.
"""

    if failures:
        failure_lines = "\n".join(
            f"- `{result.name}` failed. See `{result.stderr_log}` and `{result.stdout_log}`."
            for result in failures
        )
        status_text += f"\n## Failed Steps\n\n{failure_lines}\n"

    (ROOT / "docs" / "current_data_status.md").write_text(status_text, encoding="utf-8")


def build_steps(args: argparse.Namespace, python_exe: str, rscript_exe: str) -> list[Step]:
    steps: list[Step] = []

    if args.profile != "local-rebuild":
        fetch_sources = ["public", "wikimedia", "official-fifa"]
        if args.include_keyed_apis:
            fetch_sources.extend(["football-data", "odds", "api-football"])

        command = [python_exe, "scripts/fetch_raw_data.py", "--sources", *fetch_sources]
        if args.include_odds_quota:
            command.append("--include-quota-odds")
        if args.api_football_advanced:
            command.append("--api-football-advanced")
        if args.api_football_max_fixtures is not None:
            command.extend(["--api-football-max-fixtures", str(args.api_football_max_fixtures)])
        if args.api_football_max_player_pages is not None:
            command.extend(["--api-football-max-player-pages", str(args.api_football_max_player_pages)])
        steps.append(Step("Fetch raw source snapshots", command))

    steps.append(Step("Build processed public CSVs", [python_exe, "scripts/build_public_processed_csv.py"]))

    if args.profile != "local-rebuild":
        if not args.skip_wikidata:
            steps.append(Step("Fetch Wikidata player enrichment", [python_exe, "scripts/fetch_wikidata_players.py"]))
        if not args.skip_weather:
            weather_command = [python_exe, "scripts/fetch_weather_open_meteo.py"]
            if args.max_weather_fixtures:
                weather_command.extend(["--max-fixtures", str(args.max_weather_fixtures)])
            steps.append(Step("Fetch Open-Meteo fixture weather", weather_command, required=False))
        if not args.skip_news:
            news_command = [python_exe, "scripts/fetch_news_gdelt.py", "--include-team-queries"]
            if args.max_news_records:
                news_command.extend(["--max-records", str(args.max_news_records)])
            if args.news_timespan:
                news_command.extend(["--timespan", args.news_timespan])
            steps.append(Step("Fetch GDELT news metadata", news_command, required=False))

    steps.extend(
        [
            Step("Build DuckDB", [rscript_exe, "R/01_build_duckdb.R"]),
            Step("Export DuckDB metadata", [rscript_exe, "R/07_export_metadata.R"]),
        ]
    )

    if not args.skip_model:
        steps.append(Step("Fit goals model", [rscript_exe, "R/10_fit_linear_goals_model.R"]))
        steps.append(
            Step("Fit ordinal result model", [rscript_exe, "R/11_fit_ordinal_result_model.R"])
        )
        steps.append(Step("Fit KNN similarity model", [rscript_exe, "R/13_fit_knn_similarity_model.R"]))
    if not args.skip_render:
        steps.append(Step("Render R Markdown reports", [rscript_exe, "R/12_render_reports.R"], required=False))

    return steps


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh local World Cup data, DuckDB, metadata, and reports.")
    parser.add_argument(
        "--profile",
        choices=["local-rebuild", "free-refresh"],
        default="free-refresh",
        help=(
            "local-rebuild uses existing raw/processed files. free-refresh pulls free/no-key "
            "sources before rebuilding."
        ),
    )
    parser.add_argument("--rscript", default=None, help="Path to Rscript.exe if it is not on PATH.")
    parser.add_argument(
        "--include-keyed-apis",
        action="store_true",
        help="Also call API providers that require keys in .env. Odds endpoint still needs --include-odds-quota.",
    )
    parser.add_argument(
        "--include-odds-quota",
        action="store_true",
        help="Allow quota-consuming odds pulls when THE_ODDS_API_KEY is configured.",
    )
    parser.add_argument(
        "--api-football-advanced",
        action="store_true",
        help="Fetch API-Football advanced data such as injuries, odds, players, and capped fixture details.",
    )
    parser.add_argument("--api-football-max-fixtures", type=int, default=0)
    parser.add_argument("--api-football-max-player-pages", type=int, default=1)
    parser.add_argument("--skip-wikidata", action="store_true")
    parser.add_argument("--skip-weather", action="store_true")
    parser.add_argument("--skip-news", action="store_true")
    parser.add_argument("--skip-model", action="store_true")
    parser.add_argument("--skip-render", action="store_true")
    parser.add_argument("--continue-on-error", action="store_true")
    parser.add_argument("--max-weather-fixtures", type=int, default=None)
    parser.add_argument("--max-news-records", type=int, default=None)
    parser.add_argument("--news-timespan", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    started = utc_now()
    run_dir = ROOT / "data" / "processed" / "update_runs" / stamp_for_path(started)
    run_dir.mkdir(parents=True, exist_ok=False)

    python_exe = sys.executable
    rscript_exe = find_rscript(args.rscript)
    steps = build_steps(args, python_exe, rscript_exe)

    print(f"Run folder: {run_dir}")
    print(f"Python: {python_exe}")
    print(f"Rscript: {rscript_exe}")
    print(f"Profile: {args.profile}")

    results: list[StepResult] = []
    try:
        for step in steps:
            results.append(run_step(step, run_dir, args.continue_on_error))
    finally:
        copied = sync_publishable_artifacts()
        finished = utc_now()
        run_summary = {
            "started_at_utc": iso(started),
            "finished_at_utc": iso(finished),
            "seconds": round((finished - started).total_seconds(), 3),
            "profile": args.profile,
            "python": python_exe,
            "rscript": rscript_exe,
            "arguments": vars(args),
            "copied_public_artifacts": copied,
            "steps": [asdict(result) for result in results],
        }
        write_json(run_dir / "run_summary.json", run_summary)
        write_json(ROOT / "data" / "processed" / "update_runs" / "latest.json", run_summary)
        write_current_status(started, run_dir, args, results, copied)

    failures = [result for result in results if result.status != "ok" and result.required]
    if failures:
        return 1

    print("Refresh complete.")
    print(f"Status doc: {ROOT / 'docs' / 'current_data_status.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
