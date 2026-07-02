from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import cv2


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def slugify(value: str) -> str:
    keep = []
    for char in value.lower():
        if char.isalnum():
            keep.append(char)
        elif char in {" ", "-", "_"}:
            keep.append("-")
    slug = "".join(keep).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "match"


def append_or_replace_catalog_row(catalog_path: Path, row: dict[str, object]) -> None:
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    if catalog_path.exists():
        with catalog_path.open("r", newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))

    key = f"{row['match_key']}|{row['video_file']}"
    fieldnames = list(row.keys())
    updated_rows = [existing for existing in rows if f"{existing.get('match_key')}|{existing.get('video_file')}" != key]
    updated_rows.append({name: row.get(name, "") for name in fieldnames})

    with catalog_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(updated_rows)


def generate_preview_assets(
    video_path: Path,
    preview_dir: Path,
    match_key: str,
    sample_count: int = 6,
) -> dict[str, object]:
    preview_dir.mkdir(parents=True, exist_ok=True)
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video file for previews: {video_path}")

    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration_seconds = frame_count / fps if fps > 0 and frame_count > 0 else 0.0

    preview_paths = []
    frames = []
    if duration_seconds <= 0:
        sample_seconds = [0.0]
    else:
        safe_count = max(1, sample_count)
        sample_seconds = [duration_seconds * (index + 1) / (safe_count + 1) for index in range(safe_count)]

    for index, sample_second in enumerate(sample_seconds, start=1):
        capture.set(cv2.CAP_PROP_POS_MSEC, sample_second * 1000.0)
        ok, frame = capture.read()
        if not ok:
            continue
        image_path = preview_dir / f"{slugify(match_key)}__preview_{index:02d}.jpg"
        cv2.imwrite(str(image_path), frame)
        preview_paths.append(str(image_path))
        frames.append(frame)

    contact_sheet_path = None
    if frames:
        resized_frames = []
        target_height = 240
        for frame in frames:
            scale = target_height / max(1, frame.shape[0])
            resized = cv2.resize(frame, (int(frame.shape[1] * scale), target_height))
            resized_frames.append(resized)
        contact_sheet = cv2.hconcat(resized_frames)
        contact_sheet_path = preview_dir / f"{slugify(match_key)}__contact_sheet.jpg"
        cv2.imwrite(str(contact_sheet_path), contact_sheet)

    capture.release()
    return {
        "preview_dir": str(preview_dir),
        "preview_images": preview_paths,
        "contact_sheet_path": str(contact_sheet_path) if contact_sheet_path else "",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Register a local match video for private film study and optionally launch the tagger."
    )
    parser.add_argument("--video", required=True, help="Path to a local video file.")
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
        help="Open the keyboard tagger immediately after metadata is written.",
    )
    parser.add_argument(
        "--skip-previews",
        action="store_true",
        help="Skip still-image preview generation.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = repo_root()
    video_path = Path(args.video).expanduser().resolve()
    if not video_path.exists():
        raise FileNotFoundError(f"Video file not found: {video_path}")

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")

    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    duration_seconds = round(frame_count / fps, 3) if fps > 0 and frame_count > 0 else None
    capture.release()

    output_dir = root / "data" / "private" / "video_library"
    output_dir.mkdir(parents=True, exist_ok=True)
    session_slug = slugify(args.match_key)
    metadata_path = output_dir / f"{session_slug}__video_metadata.json"
    catalog_path = output_dir / "video_catalog.csv"
    preview_dir = output_dir / "previews" / session_slug

    stat = video_path.stat()
    preview_assets = {"preview_dir": "", "preview_images": [], "contact_sheet_path": ""}
    if not args.skip_previews:
        preview_assets = generate_preview_assets(
            video_path=video_path,
            preview_dir=preview_dir,
            match_key=args.match_key,
        )

    metadata = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "match_key": args.match_key,
        "competition": args.competition,
        "home_team": args.home_team,
        "away_team": args.away_team,
        "kickoff_utc": args.kickoff_utc,
        "video_file": str(video_path),
        "file_name": video_path.name,
        "file_size_mb": round(stat.st_size / (1024 * 1024), 3),
        "fps": fps,
        "frame_count": frame_count,
        "duration_seconds": duration_seconds,
        "width": width,
        "height": height,
        "tag_output_file": str(root / "data" / "private" / "film_tags" / f"{session_slug}__film_tags.csv"),
        "preview_dir": preview_assets["preview_dir"],
        "preview_images": preview_assets["preview_images"],
        "contact_sheet_path": preview_assets["contact_sheet_path"],
    }

    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    append_or_replace_catalog_row(catalog_path, metadata)

    print(f"Wrote {metadata_path}")
    print(f"Updated {catalog_path}")

    if args.launch_tagger:
        command = [
            sys.executable,
            str(root / "scripts" / "video_tagger.py"),
            "--video",
            str(video_path),
            "--match-key",
            args.match_key,
            "--home-team",
            args.home_team,
            "--away-team",
            args.away_team,
        ]
        subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
