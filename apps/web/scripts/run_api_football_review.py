#!/usr/bin/env python3
"""Run API-Football review ingestion with strict access and sample checks."""
from __future__ import annotations

import json
import sys
from typing import Any

import fetch_api_football as pipeline


def error_text(payload: dict[str, Any]) -> str | None:
    errors = payload.get("errors")
    if not errors:
        return None
    if isinstance(errors, dict):
        values = [f"{key}: {value}" for key, value in errors.items() if value]
        return "; ".join(values) or None
    return str(errors)


def response_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    response = payload.get("response", [])
    if isinstance(response, dict):
        return [response]
    if isinstance(response, list):
        return [item if isinstance(item, dict) else {"value": item} for item in response]
    return [] if response is None else [{"value": response}]


def normalize_rows(rows: list[dict[str, Any]], limit: int):
    if not rows:
        return pipeline.pd.DataFrame()
    frame = pipeline.pd.json_normalize(rows, sep=".").head(limit).copy()
    for column in frame.columns:
        frame[column] = frame[column].map(pipeline.json_safe_scalar)
    return frame


def validate_access() -> None:
    if not pipeline.API_KEY:
        raise RuntimeError("API_FOOTBALL_KEY is missing")
    payload, _ = pipeline.api_get("timezone")
    error = error_text(payload)
    response = payload.get("response")
    if error:
        raise RuntimeError(error)
    if not isinstance(response, list) or not response:
        raise RuntimeError("API-Football returned no data during the access check")


def validate_output() -> None:
    catalog = json.loads(pipeline.CATALOG.read_text(encoding="utf-8"))
    football = [
        entry
        for entry in catalog.get("entries", [])
        if isinstance(entry, dict) and entry.get("source_api") == "api-football-v3"
    ]
    available = [entry for entry in football if entry.get("availability_status") == "available"]
    print(f"API-Football review datasets: {len(available)} available of {len(football)} configured")
    if not available:
        raise RuntimeError("No usable API-Football review datasets were returned")


def main() -> int:
    try:
        validate_access()
        pipeline.response_rows = response_rows
        pipeline.normalize_rows = normalize_rows
        result = pipeline.main()
        if result != 0:
            return result
        validate_output()
        return 0
    except Exception as exc:
        print(f"API-Football review failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
