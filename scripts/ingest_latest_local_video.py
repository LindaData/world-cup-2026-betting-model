from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".m4v"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find the newest local video file in a folder and register it for film study."
    )
    parser.add_argument("--source-dir", required=True, help="Folder containing locally saved video files.")
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


def newest_video_file(source_dir: Path) -> Path:
    candidates = [
        path for path in source_dir.iterdir()
        if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
    ]
    if not candidates:
        raise FileNotFoundError(f"No supported video files found in {source_dir}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def main() -> None:
    args = parse_args()
    root = repo_root()
    source_dir = Path(args.source_dir).expanduser().resolve()
    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    video_path = newest_video_file(source_dir)
    print(f"Selected newest video: {video_path}")

    command = [
        sys.executable,
        str(root / "scripts" / "prepare_film_study_session.py"),
        "--video",
        str(video_path),
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
