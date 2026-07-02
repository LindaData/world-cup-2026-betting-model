from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def quality_tier(width: float, height: float, fps: float) -> str:
    if pd.isna(width) or pd.isna(height) or pd.isna(fps):
        return "unknown"
    if width >= 1920 and height >= 1080 and fps >= 50:
        return "excellent"
    if width >= 1280 and height >= 720 and fps >= 25:
        return "good"
    if width >= 854 and height >= 480 and fps >= 20:
        return "usable"
    return "low"


def resolution_label(width: float, height: float) -> str:
    if pd.isna(width) or pd.isna(height):
        return "unknown"
    return f"{int(width)}x{int(height)}"


def main() -> None:
    root = repo_root()
    video_library_dir = root / "data" / "private" / "video_library"
    previews_root = video_library_dir / "previews"
    processed_dir = root / "data" / "processed" / "film_study"
    processed_dir.mkdir(parents=True, exist_ok=True)
    film_tags_dir = root / "data" / "private" / "film_tags"
    clips_csv = root / "data" / "private" / "clips" / "film_study_clips.csv"

    clip_counts = {}
    if clips_csv.exists():
      clips = pd.read_csv(clips_csv)
      if not clips.empty:
          clip_counts = (
              clips.groupby("match_key")
              .agg(
                  extracted_clip_rows=("event_index", "size"),
                  ok_clips=("clip_status", lambda s: int((s == "ok").sum())),
                  skipped_clips=("clip_status", lambda s: int((s != "ok").sum()))
              )
              .reset_index()
              .set_index("match_key")
              .to_dict(orient="index")
          )

    records: list[dict[str, object]] = []
    for metadata_path in sorted(video_library_dir.glob("*__video_metadata.json")):
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        match_key = metadata.get("match_key", "")
        preview_dir = Path(metadata.get("preview_dir", "")) if metadata.get("preview_dir") else None
        tag_output_file = Path(metadata.get("tag_output_file", "")) if metadata.get("tag_output_file") else None

        clip_info = clip_counts.get(match_key, {})
        width = pd.to_numeric(metadata.get("width"), errors="coerce")
        height = pd.to_numeric(metadata.get("height"), errors="coerce")
        fps = pd.to_numeric(metadata.get("fps"), errors="coerce")
        duration_seconds = pd.to_numeric(metadata.get("duration_seconds"), errors="coerce")
        file_size_mb = pd.to_numeric(metadata.get("file_size_mb"), errors="coerce")

        estimated_mbps = None
        if pd.notna(duration_seconds) and duration_seconds > 0 and pd.notna(file_size_mb):
            estimated_mbps = round((file_size_mb * 8) / duration_seconds, 3)

        records.append(
            {
                "match_key": match_key,
                "competition": metadata.get("competition", ""),
                "home_team": metadata.get("home_team", ""),
                "away_team": metadata.get("away_team", ""),
                "file_name": metadata.get("file_name", ""),
                "video_file": metadata.get("video_file", ""),
                "resolution": resolution_label(width, height),
                "width": width,
                "height": height,
                "fps": fps,
                "duration_seconds": duration_seconds,
                "file_size_mb": file_size_mb,
                "estimated_mbps": estimated_mbps,
                "has_preview_dir": bool(preview_dir and preview_dir.exists()),
                "preview_image_count": len(list(preview_dir.glob("*.jpg"))) if preview_dir and preview_dir.exists() else 0,
                "has_contact_sheet": bool(metadata.get("contact_sheet_path") and Path(metadata["contact_sheet_path"]).exists()),
                "tag_file_exists": bool(tag_output_file and tag_output_file.exists()),
                "analysis_ready_resolution": bool(pd.notna(width) and pd.notna(height) and width >= 1280 and height >= 720),
                "analysis_ready_fps": bool(pd.notna(fps) and fps >= 25),
                "quality_tier": quality_tier(width, height, fps),
                "extracted_clip_rows": clip_info.get("extracted_clip_rows", 0),
                "ok_clips": clip_info.get("ok_clips", 0),
                "skipped_clips": clip_info.get("skipped_clips", 0),
            }
        )

    audit = pd.DataFrame(records)
    audit_csv = processed_dir / "video_quality_audit.csv"
    audit.to_csv(audit_csv, index=False)

    summary = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "video_library_dir": str(video_library_dir),
        "audit_csv": str(audit_csv),
        "videos": int(len(audit)),
        "quality_tier_counts": audit["quality_tier"].value_counts(dropna=False).to_dict() if not audit.empty else {},
        "ready_for_analysis_count": int((audit["analysis_ready_resolution"] & audit["analysis_ready_fps"]).sum()) if not audit.empty else 0,
    }
    summary_path = processed_dir / "video_quality_audit_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Wrote {audit_csv}")
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
