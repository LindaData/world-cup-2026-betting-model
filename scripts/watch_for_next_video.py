from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path


VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".m4v"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Wait for the next local video file in a folder, then register it for film study."
    )
    parser.add_argument("--source-dir", required=True, help="Folder to monitor for local video files.")
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
        "--poll-seconds",
        type=float,
        default=10.0,
        help="Polling interval while waiting for a new file.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=0.0,
        help="Optional timeout. Zero means wait indefinitely.",
    )
    parser.add_argument(
        "--allow-existing-latest",
        action="store_true",
        help="Use the current newest local video immediately instead of waiting for a file created after startup.",
    )
    parser.add_argument(
        "--launch-tagger",
        action="store_true",
        help="Open the keyboard tagger after registration.",
    )
    parser.add_argument(
        "--skip-previews",
        action="store_true",
        help="Skip still-image preview generation.",
    )
    return parser.parse_args()


def newest_video_file(source_dir: Path) -> Path | None:
    candidates = [
        path for path in source_dir.iterdir()
        if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def main() -> None:
    args = parse_args()
    root = repo_root()
    source_dir = Path(args.source_dir).expanduser().resolve()
    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    start_time = time.time()
    baseline_path = newest_video_file(source_dir)
    baseline_mtime = baseline_path.stat().st_mtime if baseline_path else 0.0

    if args.allow_existing_latest and baseline_path is not None:
        selected = baseline_path
    else:
        selected = None
        while selected is None:
            latest = newest_video_file(source_dir)
            if latest is not None and latest.stat().st_mtime > baseline_mtime:
                selected = latest
                break

            if args.timeout_seconds > 0 and (time.time() - start_time) >= args.timeout_seconds:
                raise TimeoutError(
                    f"No new video file appeared in {source_dir} within {args.timeout_seconds} seconds."
                )

            print(f"Waiting for a new video in {source_dir} ...")
            time.sleep(max(1.0, args.poll_seconds))

    print(f"Selected video: {selected}")

    command = [
        sys.executable,
        str(root / "scripts" / "prepare_film_study_session.py"),
        "--video",
        str(selected),
        "--match-key",
        args.match_key,
        "--home-team",
        args.home_team,
        "--away-team",
        args.away_team,
        "--competition",
        args.competition,
    ]

    if args.kickoff_utc:
        command.extend(["--kickoff-utc", args.kickoff_utc])
    if args.launch_tagger:
        command.append("--launch-tagger")
    if args.skip_previews:
        command.append("--skip-previews")

    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
