from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def newest_video_file(source_dir: Path) -> Path:
    video_extensions = {".mp4", ".mkv", ".mov", ".avi", ".m4v"}
    candidates = [
        path for path in source_dir.iterdir()
        if path.is_file() and path.suffix.lower() in video_extensions
    ]
    if not candidates:
        raise FileNotFoundError(f"No supported video files found in {source_dir}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def run_step(command: list[str]) -> None:
    print("Running:", " ".join(command))
    subprocess.run(command, check=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the full local film-study processing pipeline for a user-supplied video file."
    )
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--video", help="Explicit path to a local video file.")
    source_group.add_argument("--source-dir", help="Folder containing local video files; newest file will be used.")

    parser.add_argument("--match-key", required=True, help="Stable match identifier.")
    parser.add_argument("--home-team", required=True, help="Home team label.")
    parser.add_argument("--away-team", required=True, help="Away team label.")
    parser.add_argument(
        "--competition",
        default="World Cup 2026",
        help="Competition label stored in metadata.",
    )
    parser.add_argument(
        "--kickoff-utc",
        default="",
        help="Optional kickoff timestamp in UTC ISO format.",
    )
    parser.add_argument(
        "--skip-previews",
        action="store_true",
        help="Skip still-image preview generation.",
    )
    parser.add_argument(
        "--extract-clips",
        action="store_true",
        help="Extract clips after the film-study datasets are rebuilt.",
    )
    parser.add_argument(
        "--clip-event-types",
        nargs="*",
        default=None,
        help="Optional event types to clip. Default uses shot and goal if clip extraction is requested.",
    )
    parser.add_argument(
        "--clip-seconds-before",
        type=float,
        default=3.0,
        help="Seconds before tagged events to include in extracted clips.",
    )
    parser.add_argument(
        "--clip-seconds-after",
        type=float,
        default=4.0,
        help="Seconds after tagged events to include in extracted clips.",
    )
    parser.add_argument(
        "--overwrite-clips",
        action="store_true",
        help="Overwrite existing local clips.",
    )
    parser.add_argument(
        "--skip-duckdb",
        action="store_true",
        help="Skip rebuilding the local film-study DuckDB database.",
    )
    parser.add_argument(
        "--fit-models",
        action="store_true",
        help="Fit the private film-study models after the datasets are rebuilt.",
    )
    parser.add_argument(
        "--render-review-report",
        action="store_true",
        help="Render the private film-study review report after processing.",
    )
    parser.add_argument(
        "--render-quality-report",
        action="store_true",
        help="Render the private film-study quality report after processing.",
    )
    parser.add_argument(
        "--render-modeling-report",
        action="store_true",
        help="Render the private film-study modeling report after processing.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = repo_root()
    python = str((root / ".venv" / "Scripts" / "python.exe").resolve())
    rscript = "C:\\Program Files\\R\\R-4.1.1\\bin\\Rscript.exe"

    if args.video:
        video_path = Path(args.video).expanduser().resolve()
    else:
        source_dir = Path(args.source_dir).expanduser().resolve()
        if not source_dir.exists():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")
        video_path = newest_video_file(source_dir)

    if not video_path.exists():
        raise FileNotFoundError(f"Video file not found: {video_path}")

    prepare_cmd = [
        python,
        str(root / "scripts" / "prepare_film_study_session.py"),
        "--video", str(video_path),
        "--match-key", args.match_key,
        "--home-team", args.home_team,
        "--away-team", args.away_team,
        "--competition", args.competition,
    ]
    if args.kickoff_utc:
        prepare_cmd.extend(["--kickoff-utc", args.kickoff_utc])
    if args.skip_previews:
        prepare_cmd.append("--skip-previews")
    run_step(prepare_cmd)

    run_step([python, str(root / "scripts" / "build_film_study_dataset.py")])
    run_step([python, str(root / "scripts" / "build_film_study_features.py")])

    if args.extract_clips:
        clip_event_types = args.clip_event_types if args.clip_event_types else ["shot", "goal"]
        clip_cmd = [
            python,
            str(root / "scripts" / "extract_film_study_clips.py"),
            "--seconds-before", str(args.clip_seconds_before),
            "--seconds-after", str(args.clip_seconds_after),
            "--event-types",
            *clip_event_types,
        ]
        if args.overwrite_clips:
            clip_cmd.append("--overwrite")
        run_step(clip_cmd)

    if not args.skip_duckdb:
        run_step([python, str(root / "scripts" / "build_film_study_duckdb.py")])

    run_step([python, str(root / "scripts" / "build_video_quality_audit.py")])

    if args.fit_models:
        run_step([rscript, "-e", "source('R/31_fit_film_study_models.R'); fit_film_study_models()"])
    if args.render_review_report:
        run_step([rscript, "-e", "source('R/29_render_film_study_review.R'); render_film_study_review()"])
    if args.render_quality_report:
        run_step([rscript, "-e", "source('R/33_render_film_study_quality_report.R'); render_film_study_quality_report()"])
    if args.render_modeling_report:
        run_step([rscript, "-e", "source('R/32_render_film_study_modeling_report.R'); render_film_study_modeling_report()"])

    print(f"Processed local film-study session for: {video_path}")


if __name__ == "__main__":
    main()
