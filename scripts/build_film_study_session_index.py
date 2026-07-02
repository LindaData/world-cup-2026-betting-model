from __future__ import annotations

import json
from datetime import datetime, timezone
from html import escape
from pathlib import Path

import pandas as pd


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def build_rows(session_exports_dir: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    if not session_exports_dir.exists():
        return rows

    for session_dir in sorted([path for path in session_exports_dir.iterdir() if path.is_dir()]):
        manifest_path = session_dir / "session_manifest.json"
        if not manifest_path.exists():
            continue

        manifest = read_json(manifest_path)
        video = manifest.get("video_metadata", {}) or {}
        capture = manifest.get("capture_manifest", {}) or {}
        counts = manifest.get("row_counts", {}) or {}
        reports = manifest.get("report_paths", {}) or {}
        tags_count = int(counts.get("tags", 0) or 0)

        rows.append(
            {
                "match_key": manifest.get("match_key", ""),
                "created_at_utc": manifest.get("created_at_utc", ""),
                "home_team": video.get("home_team", ""),
                "away_team": video.get("away_team", ""),
                "video_file": video.get("video_file", ""),
                "capture_type": capture.get("capture_type", ""),
                "profile_name": capture.get("profile_name", ""),
                "session_status": manifest.get("session_status", ""),
                "session_ready_for_review": bool(manifest.get("session_ready_for_review", False)),
                "session_ready_for_annotation": bool(manifest.get("session_ready_for_annotation", False)),
                "session_ready_for_analysis": bool(manifest.get("session_ready_for_analysis", False)),
                "session_has_tags": bool(manifest.get("session_has_tags", tags_count > 0)),
                "events": int(counts.get("events", 0) or 0),
                "tags": tags_count,
                "clips": int(counts.get("clips", 0) or 0),
                "state_engine_snapshot": int(counts.get("state_engine_snapshot", 0) or 0),
                "review_report": reports.get("film_study_review.html", ""),
                "quality_report": reports.get("film_study_quality.html", ""),
                "modeling_report": reports.get("film_study_modeling.html", ""),
                "state_engine_report": reports.get("film_study_state_engine.html", ""),
                "session_summary_html": manifest.get("session_summary_html", ""),
                "session_manifest": str(manifest_path),
            }
        )
    return rows


def render_html(rows: list[dict[str, object]], output_path: Path) -> None:
    headers = [
        "Match",
        "Created (UTC)",
        "Capture",
        "Profile",
        "Status",
        "Tags",
        "Events",
        "Clips",
        "State Snapshot",
    ]
    table_rows = []
    for row in rows:
        match_label = escape(f"{row['home_team']} vs {row['away_team']}") if row["home_team"] or row["away_team"] else escape(str(row["match_key"]))
        table_rows.append(
            "<tr>"
            f"<td><strong>{escape(str(row['match_key']))}</strong><div>{match_label}</div></td>"
            f"<td>{escape(str(row['created_at_utc']))}</td>"
            f"<td>{escape(str(row['capture_type']))}</td>"
            f"<td>{escape(str(row['profile_name']))}</td>"
            f"<td>{escape(str(row['session_status']))}</td>"
            f"<td>{'Yes' if row['session_has_tags'] else 'No'}</td>"
            f"<td>{row['events']}</td>"
            f"<td>{row['clips']}</td>"
            f"<td>{row['state_engine_snapshot']}</td>"
            "</tr>"
        )

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Film Study Session Index</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 24px; color: #102a43; background: #f7fafc; }}
    h1 {{ margin-bottom: 8px; }}
    p {{ color: #486581; }}
    table {{ border-collapse: collapse; width: 100%; background: #ffffff; }}
    th, td {{ border: 1px solid #d9e2ec; padding: 10px; text-align: left; vertical-align: top; }}
    th {{ background: #f0f4f8; }}
    .meta {{ margin-bottom: 18px; }}
  </style>
</head>
<body>
  <h1>Film Study Session Index</h1>
  <p class="meta">Created {escape(datetime.now(timezone.utc).isoformat())} UTC</p>
  <table>
    <thead>
      <tr>{''.join(f'<th>{escape(header)}</th>' for header in headers)}</tr>
    </thead>
    <tbody>
      {''.join(table_rows) if table_rows else '<tr><td colspan="9">No session exports found.</td></tr>'}
    </tbody>
  </table>
</body>
</html>"""
    output_path.write_text(html, encoding="utf-8")


def main() -> None:
    root = repo_root()
    session_exports_dir = root / "data" / "private" / "session_exports"
    output_dir = root / "data" / "processed" / "film_study"
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = build_rows(session_exports_dir)
    frame = pd.DataFrame(rows)
    csv_path = output_dir / "film_study_session_index.csv"
    json_path = output_dir / "film_study_session_index.json"
    html_path = root / "data" / "private" / "reports" / "film_study_session_index.html"

    frame.to_csv(csv_path, index=False)
    json_path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    render_html(rows, html_path)

    print(f"Wrote {csv_path}")
    print(f"Wrote {json_path}")
    print(f"Wrote {html_path}")


if __name__ == "__main__":
    main()
