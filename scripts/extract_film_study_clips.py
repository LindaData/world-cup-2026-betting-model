from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import cv2
import pandas as pd


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract short local video clips around tagged film-study events."
    )
    parser.add_argument(
        "--events-csv",
        default=str(repo_root() / "data" / "processed" / "film_study" / "film_study_events_enriched.csv"),
        help="Path to enriched film-study events CSV.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(repo_root() / "data" / "private" / "clips"),
        help="Directory for extracted local MP4 clips.",
    )
    parser.add_argument(
        "--seconds-before",
        type=float,
        default=3.0,
        help="Seconds before the tagged event to include.",
    )
    parser.add_argument(
        "--seconds-after",
        type=float,
        default=4.0,
        help="Seconds after the tagged event to include.",
    )
    parser.add_argument(
        "--event-types",
        nargs="*",
        default=None,
        help="Optional event types to extract. Default extracts all events.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing local clip files.",
    )
    return parser.parse_args()


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
    return slug or "clip"


def ensure_capture(video_path: Path) -> cv2.VideoCapture:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    return capture


def extract_clip(
    video_path: Path,
    output_path: Path,
    center_seconds: float,
    seconds_before: float,
    seconds_after: float,
) -> dict[str, float]:
    capture = ensure_capture(video_path)
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration_seconds = frame_count / fps if fps > 0 and frame_count > 0 else 0.0

    if duration_seconds > 0 and float(center_seconds) > duration_seconds:
        capture.release()
        return {
            "fps": fps,
            "width": width,
            "height": height,
            "clip_start_seconds": None,
            "clip_end_seconds": None,
            "frames_written": 0,
            "clip_status": "skipped_out_of_range",
        }

    clip_start = max(0.0, float(center_seconds) - float(seconds_before))
    clip_end = (
        min(duration_seconds, float(center_seconds) + float(seconds_after))
        if duration_seconds > 0
        else float(center_seconds) + float(seconds_after)
    )
    clip_duration = max(0.0, clip_end - clip_start)
    if clip_duration <= 0:
        capture.release()
        return {
            "fps": fps,
            "width": width,
            "height": height,
            "clip_start_seconds": None,
            "clip_end_seconds": None,
            "frames_written": 0,
            "clip_status": "skipped_invalid_window",
        }

    capture.set(cv2.CAP_PROP_POS_MSEC, clip_start * 1000.0)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(output_path), fourcc, fps or 10.0, (width, height))

    frames_written = 0
    max_frames = int(round(clip_duration * (fps or 10.0)))
    while True:
        if max_frames > 0 and frames_written >= max_frames:
            break
        ok, frame = capture.read()
        if not ok:
            break
        current_seconds = float(capture.get(cv2.CAP_PROP_POS_MSEC) or 0.0) / 1000.0
        if current_seconds > clip_end + 0.05:
            break
        writer.write(frame)
        frames_written += 1

    writer.release()
    capture.release()
    return {
        "fps": fps,
        "width": width,
        "height": height,
        "clip_start_seconds": round(clip_start, 3),
        "clip_end_seconds": round(clip_end, 3),
        "frames_written": frames_written,
        "clip_status": "ok" if frames_written > 0 else "empty",
    }


def main() -> None:
    args = parse_args()
    events_path = Path(args.events_csv).expanduser().resolve()
    if not events_path.exists():
        raise FileNotFoundError(f"Events CSV not found: {events_path}")

    output_dir = Path(args.output_dir).expanduser().resolve()
    events = pd.read_csv(events_path)
    if args.event_types:
      events = events[events["event_type"].isin(args.event_types)].copy()

    if events.empty:
        print("No matching events found for clip extraction.")
        return

    clip_records: list[dict[str, object]] = []
    for row in events.to_dict(orient="records"):
        video_path = Path(str(row["video_file"])).expanduser()
        if not video_path.exists():
            continue

        match_slug = slugify(str(row["match_key"]))
        event_slug = slugify(str(row["event_type"]))
        event_index = int(row.get("event_index", 0) or 0)
        output_path = output_dir / match_slug / f"{match_slug}__event_{event_index:03d}__{event_slug}.mp4"
        if output_path.exists() and not args.overwrite:
            clip_meta = {
                "fps": None,
                "width": None,
                "height": None,
                "clip_start_seconds": max(0.0, float(row["time_seconds"]) - float(args.seconds_before)),
                "clip_end_seconds": float(row["time_seconds"]) + float(args.seconds_after),
                "frames_written": None,
                "clip_status": "existing",
            }
        else:
            clip_meta = extract_clip(
                video_path=video_path,
                output_path=output_path,
                center_seconds=float(row["time_seconds"]),
                seconds_before=float(args.seconds_before),
                seconds_after=float(args.seconds_after),
            )

        clip_records.append(
            {
                "match_key": row["match_key"],
                "event_index": row.get("event_index"),
                "event_type": row.get("event_type"),
                "team_inferred": row.get("team_inferred"),
                "player": row.get("player"),
                "time_seconds": row.get("time_seconds"),
                "video_file": str(video_path),
                "clip_file": str(output_path),
                "seconds_before": args.seconds_before,
                "seconds_after": args.seconds_after,
                **clip_meta,
            }
        )

    clips_df = pd.DataFrame(clip_records)
    clips_csv = output_dir / "film_study_clips.csv"
    clips_df.to_csv(clips_csv, index=False)

    metadata = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "events_csv": str(events_path),
        "output_dir": str(output_dir),
        "clips_csv": str(clips_csv),
        "rows": int(len(clips_df)),
        "seconds_before": args.seconds_before,
        "seconds_after": args.seconds_after,
        "event_types": list(args.event_types) if args.event_types else "all",
    }
    metadata_path = output_dir / "film_study_clips_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print(f"Wrote {clips_csv}")
    print(f"Wrote {metadata_path}")


if __name__ == "__main__":
    main()
