from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def main() -> None:
    root = repo_root()
    input_dir = root / "data" / "private" / "film_tags"
    output_dir = root / "data" / "processed" / "film_study"
    output_dir.mkdir(parents=True, exist_ok=True)

    csv_paths = sorted(path for path in input_dir.glob("*.csv") if path.is_file())
    if not csv_paths:
        print(f"No film tag CSV files found in {input_dir}")
        return

    frames = []
    for path in csv_paths:
        frame = pd.read_csv(path)
        frame["source_file"] = path.name
        frames.append(frame)

    combined = pd.concat(frames, ignore_index=True)
    combined["time_seconds"] = pd.to_numeric(combined["time_seconds"], errors="coerce")
    combined["x_pct"] = pd.to_numeric(combined["x_pct"], errors="coerce")
    combined["y_pct"] = pd.to_numeric(combined["y_pct"], errors="coerce")

    combined_path = output_dir / "film_study_tags.csv"
    combined.to_csv(combined_path, index=False)

    summary = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_directory": str(input_dir),
        "output_csv": str(combined_path),
        "source_files": [path.name for path in csv_paths],
        "rows": int(len(combined)),
        "matches": int(combined["match_key"].nunique()) if "match_key" in combined.columns else 0,
        "event_types": (
            combined["event_type"].value_counts(dropna=False).to_dict()
            if "event_type" in combined.columns
            else {}
        ),
    }

    summary_path = output_dir / "film_study_metadata.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Wrote {combined_path}")
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
