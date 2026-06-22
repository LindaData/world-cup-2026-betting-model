from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "processed" / "multisport"
REQUEST_LOG = PROCESSED / "apisports_training_request_log.csv"
OUTPUT = PROCESSED / "apisports_training_sample_records.csv"


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def response_items(payload: object) -> list[object]:
    if isinstance(payload, dict) and isinstance(payload.get("response"), list):
        return payload["response"]
    response = payload.get("response") if isinstance(payload, dict) else None
    if isinstance(response, dict):
        return [response]
    return []


def compact_json(value: object, limit: int = 700) -> str:
    text = json.dumps(value, sort_keys=True, ensure_ascii=False)
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def main() -> int:
    request_rows = read_csv(REQUEST_LOG)
    sample_rows: list[dict[str, object]] = []
    seen: set[tuple[str, str]] = set()

    for row in request_rows:
        if row.get("status_code") != "200":
            continue
        key = (row.get("sport_key", ""), row.get("endpoint_name", ""))
        if key in seen:
            continue
        raw_file = row.get("raw_file", "")
        raw_path = ROOT / raw_file
        if not raw_file or not raw_path.exists():
            continue
        try:
            payload = json.loads(raw_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        items = response_items(payload)
        if not items:
            continue
        sample = items[0]
        sample_rows.append(
            {
                "sport_key": row.get("sport_key", ""),
                "sport_label": row.get("sport_label", ""),
                "endpoint_name": row.get("endpoint_name", ""),
                "path": row.get("path", ""),
                "params_json": row.get("params_json", ""),
                "results": row.get("results", ""),
                "sample_top_level_fields": ", ".join(sample.keys()) if isinstance(sample, dict) else "",
                "sample_json": compact_json(sample),
            }
        )
        seen.add(key)

    write_csv(
        OUTPUT,
        sample_rows,
        [
            "sport_key",
            "sport_label",
            "endpoint_name",
            "path",
            "params_json",
            "results",
            "sample_top_level_fields",
            "sample_json",
        ],
    )
    print(f"Wrote {len(sample_rows)} sample records to {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
