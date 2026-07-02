from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from html import escape
from pathlib import Path

import pandas as pd


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_csv_if_exists(path: Path) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    return pd.read_csv(path)


def read_json_if_exists(path: Path):
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export a single local film-study session bundle for one reviewed match."
    )
    parser.add_argument("--match-key", required=True, help="Stable match identifier to package.")
    parser.add_argument(
        "--output-dir",
        default=str(repo_root() / "data" / "private" / "session_exports"),
        help="Directory where per-match session bundles should be written.",
    )
    return parser.parse_args()


def write_subset(frame: pd.DataFrame, path: Path) -> int:
    if frame.empty:
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)
    return int(len(frame))


def newest_matching_file(directory: Path, pattern: str) -> Path | None:
    if not directory.exists():
        return None
    matches = list(directory.glob(pattern))
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def render_session_summary_html(
    session_dir: Path,
    match_key: str,
    video_metadata: dict,
    capture_manifest: dict,
    counts: dict[str, int],
    report_paths: dict[str, str],
    readiness: dict[str, object],
) -> Path:
    summary_path = session_dir / "session_summary.html"

    home_team = video_metadata.get("home_team", "")
    away_team = video_metadata.get("away_team", "")
    match_label = f"{home_team} vs {away_team}".strip(" vs ")
    video_file = video_metadata.get("video_file", "")
    capture_type = capture_manifest.get("capture_type", "")
    profile_name = capture_manifest.get("profile_name", "")
    quality_profile = capture_manifest.get("quality_profile", "")
    session_status = readiness.get("session_status", "unknown")
    resolution = f"{video_metadata.get('width', '')}x{video_metadata.get('height', '')}".strip("x")
    fps = video_metadata.get("fps", "")
    duration = video_metadata.get("duration_seconds", "")

    metric_rows = [
        ("Events", counts.get("events", 0)),
        ("Tags", counts.get("tags", 0)),
        ("Clips", counts.get("clips", 0)),
        ("Possessions", counts.get("possessions", 0)),
        ("State Snapshot", counts.get("state_engine_snapshot", 0)),
    ]

    report_items = "".join(
        f"<li><strong>{escape(name)}</strong><div>{escape(path)}</div></li>"
        for name, path in report_paths.items()
    ) or "<li>No report paths available.</li>"

    metric_cards = "".join(
        f"<div class='metric'><span>{escape(label)}</span><strong>{value}</strong></div>"
        for label, value in metric_rows
    )

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Film Study Session Summary</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 24px; color: #102a43; background: #f7fafc; }}
    h1 {{ margin-bottom: 6px; }}
    p.subtle, li div {{ color: #486581; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin: 20px 0; }}
    .metric {{ background: #ffffff; border: 1px solid #d9e2ec; border-radius: 8px; padding: 12px; }}
    .metric span {{ display: block; font-size: 12px; text-transform: uppercase; color: #486581; margin-bottom: 4px; }}
    .metric strong {{ font-size: 28px; }}
    .panel {{ background: #ffffff; border: 1px solid #d9e2ec; border-radius: 8px; padding: 16px; margin: 16px 0; }}
    dl {{ display: grid; grid-template-columns: max-content 1fr; gap: 8px 16px; margin: 0; }}
    dt {{ font-weight: 700; }}
  </style>
</head>
<body>
  <h1>{escape(match_key)}</h1>
  <p class="subtle">{escape(match_label)} | created {escape(datetime.now(timezone.utc).isoformat())} UTC</p>

  <div class="grid">
    {metric_cards}
  </div>

  <div class="panel">
    <h2>Capture</h2>
    <dl>
      <dt>Session status</dt><dd>{escape(str(session_status))}</dd>
      <dt>Ready for review</dt><dd>{'Yes' if readiness.get('session_ready_for_review') else 'No'}</dd>
      <dt>Ready for annotation</dt><dd>{'Yes' if readiness.get('session_ready_for_annotation') else 'No'}</dd>
      <dt>Ready for analysis</dt><dd>{'Yes' if readiness.get('session_ready_for_analysis') else 'No'}</dd>
      <dt>Capture type</dt><dd>{escape(str(capture_type))}</dd>
      <dt>Profile</dt><dd>{escape(str(profile_name))}</dd>
      <dt>Quality profile</dt><dd>{escape(str(quality_profile))}</dd>
      <dt>Resolution</dt><dd>{escape(str(resolution))}</dd>
      <dt>FPS</dt><dd>{escape(str(fps))}</dd>
      <dt>Duration</dt><dd>{escape(str(duration))}</dd>
      <dt>Video file</dt><dd>{escape(str(video_file))}</dd>
    </dl>
  </div>

  <div class="panel">
    <h2>Reports</h2>
    <ul>
      {report_items}
    </ul>
  </div>

  <div class="panel">
    <h2>Session Folder</h2>
    <div>{escape(str(session_dir))}</div>
  </div>
</body>
</html>"""

    summary_path.write_text(html, encoding="utf-8")
    return summary_path


def main() -> None:
    args = parse_args()
    root = repo_root()
    match_key = args.match_key
    session_dir = Path(args.output_dir).expanduser().resolve() / match_key
    session_dir.mkdir(parents=True, exist_ok=True)

    film_dir = root / "data" / "processed" / "film_study"
    video_library_dir = root / "data" / "private" / "video_library"
    clips_dir = root / "data" / "private" / "clips"
    reports_dir = root / "data" / "private" / "reports"
    recordings_dir = root / "data" / "private" / "recordings"
    presets_dir = root / "data" / "private" / "tagger_presets"

    events = read_csv_if_exists(film_dir / "film_study_events_enriched.csv")
    possessions = read_csv_if_exists(film_dir / "film_study_possessions.csv")
    match_features = read_csv_if_exists(film_dir / "film_study_match_features.csv")
    transitions = read_csv_if_exists(film_dir / "film_study_event_transitions.csv")
    zone_summary = read_csv_if_exists(film_dir / "film_study_zone_summary.csv")
    tags = read_csv_if_exists(film_dir / "film_study_tags.csv")
    quality = read_csv_if_exists(film_dir / "video_quality_audit.csv")
    clips = read_csv_if_exists(clips_dir / "film_study_clips.csv")
    model_summary = read_json_if_exists(film_dir / "film_study_model_summary.json")
    state_engine_summary = read_json_if_exists(film_dir / "film_study_state_engine_summary.json")
    state_engine_rows = read_csv_if_exists(film_dir / "film_study_state_engine_summary.csv")
    state_engine_snapshot = read_csv_if_exists(film_dir / "film_study_state_engine_current_snapshot.csv")

    video_metadata_path = video_library_dir / f"{match_key}__video_metadata.json"
    video_metadata = read_json_if_exists(video_metadata_path)
    preset_path = presets_dir / f"{match_key}.json"
    preset_data = read_json_if_exists(preset_path)
    capture_manifest_path = newest_matching_file(recordings_dir, f"{match_key}__*.json")
    capture_manifest = read_json_if_exists(capture_manifest_path) if capture_manifest_path else {}

    event_subset = events[events["match_key"] == match_key].copy() if not events.empty else pd.DataFrame()
    possession_subset = possessions[possessions["match_key"] == match_key].copy() if not possessions.empty else pd.DataFrame()
    match_feature_subset = match_features[match_features["match_key"] == match_key].copy() if not match_features.empty else pd.DataFrame()
    transition_subset = transitions[transitions["match_key"] == match_key].copy() if not transitions.empty else pd.DataFrame()
    zone_subset = zone_summary[zone_summary["match_key"] == match_key].copy() if not zone_summary.empty else pd.DataFrame()
    tag_subset = tags[tags["match_key"] == match_key].copy() if not tags.empty else pd.DataFrame()
    quality_subset = quality[quality["match_key"] == match_key].copy() if not quality.empty else pd.DataFrame()
    clips_subset = clips[clips["match_key"] == match_key].copy() if not clips.empty else pd.DataFrame()
    state_engine_snapshot_subset = (
        state_engine_snapshot[state_engine_snapshot["match_key"] == match_key].copy()
        if not state_engine_snapshot.empty and "match_key" in state_engine_snapshot.columns
        else pd.DataFrame()
    )

    counts = {
        "events": write_subset(event_subset, session_dir / "events.csv"),
        "possessions": write_subset(possession_subset, session_dir / "possessions.csv"),
        "match_features": write_subset(match_feature_subset, session_dir / "match_features.csv"),
        "transitions": write_subset(transition_subset, session_dir / "transitions.csv"),
        "zone_summary": write_subset(zone_subset, session_dir / "zone_summary.csv"),
        "tags": write_subset(tag_subset, session_dir / "tags.csv"),
        "quality": write_subset(quality_subset, session_dir / "quality.csv"),
        "clips": write_subset(clips_subset, session_dir / "clips.csv"),
        "state_engine_snapshot": write_subset(state_engine_snapshot_subset, session_dir / "state_engine_snapshot.csv"),
    }
    global_state_engine_rows = write_subset(state_engine_rows, session_dir / "state_engine_global.csv")

    report_paths = {}
    for report_name in ["film_study_review.html", "film_study_quality.html", "film_study_modeling.html", "film_study_state_engine.html"]:
        path = reports_dir / report_name
        if path.exists():
            report_paths[report_name] = str(path)

    if preset_path.exists():
        shutil.copy2(preset_path, session_dir / preset_path.name)
    if capture_manifest_path and capture_manifest_path.exists():
        shutil.copy2(capture_manifest_path, session_dir / capture_manifest_path.name)

    session_has_video = bool(video_metadata.get("video_file"))
    session_has_preset = bool(preset_path.exists())
    session_has_capture_manifest = bool(capture_manifest_path and capture_manifest_path.exists())
    session_has_quality_row = bool(counts["quality"] > 0)
    session_has_tags = bool(counts["tags"] > 0)
    readiness = {
        "session_has_video": session_has_video,
        "session_has_capture_manifest": session_has_capture_manifest,
        "session_has_preset": session_has_preset,
        "session_ready_for_review": bool(session_has_video and session_has_quality_row),
        "session_ready_for_annotation": bool(session_has_video and session_has_capture_manifest and session_has_preset),
        "session_ready_for_analysis": bool(session_has_tags),
    }
    if readiness["session_ready_for_analysis"]:
        readiness["session_status"] = "analysis_ready"
    elif readiness["session_ready_for_annotation"]:
        readiness["session_status"] = "ready_for_annotation"
    elif readiness["session_ready_for_review"]:
        readiness["session_status"] = "captured_ready_for_review"
    else:
        readiness["session_status"] = "incomplete_capture"

    manifest = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "match_key": match_key,
        "session_dir": str(session_dir),
        "video_metadata_path": str(video_metadata_path) if video_metadata_path.exists() else "",
        "video_metadata": video_metadata,
        "tagger_preset_path": str(preset_path) if preset_path.exists() else "",
        "tagger_preset": preset_data,
        "capture_manifest_path": str(capture_manifest_path) if capture_manifest_path else "",
        "capture_manifest": capture_manifest,
        "row_counts": counts,
        "session_has_tags": session_has_tags,
        **readiness,
        "global_reference_counts": {
            "state_engine_rows": global_state_engine_rows,
        },
        "quality_summary": quality_subset.to_dict(orient="records"),
        "model_summary": model_summary,
        "state_engine_summary": state_engine_summary,
        "report_paths": report_paths,
        "clip_files": clips_subset["clip_file"].dropna().astype(str).tolist() if not clips_subset.empty else [],
    }

    session_summary_path = render_session_summary_html(
        session_dir=session_dir,
        match_key=match_key,
        video_metadata=video_metadata,
        capture_manifest=capture_manifest,
        counts=counts,
        report_paths=report_paths,
        readiness=readiness,
    )
    manifest["session_summary_html"] = str(session_summary_path)

    manifest_path = session_dir / "session_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    summary_lines = [
        f"Match key: {match_key}",
        f"Created: {manifest['created_at_utc']}",
        f"Events: {counts['events']}",
        f"Possessions: {counts['possessions']}",
        f"Clips: {counts['clips']}",
        f"Quality rows: {counts['quality']}",
        f"State-engine snapshot rows: {counts['state_engine_snapshot']}",
        f"Global engine reference rows: {global_state_engine_rows}",
        f"Session manifest: {manifest_path}",
    ]
    (session_dir / "README.txt").write_text("\n".join(summary_lines), encoding="utf-8")

    print(f"Wrote {manifest_path}")
    print(f"Wrote {session_dir / 'README.txt'}")


if __name__ == "__main__":
    main()
