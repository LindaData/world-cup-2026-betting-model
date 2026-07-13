#!/usr/bin/env python3
"""Fetch limited API-Football samples for schema and domain approval.

The API key is read only from ``API_FOOTBALL_KEY``. Each configured endpoint is
queried once, the full API response is retained as raw JSON, and at most the
configured number of response rows is normalized for Parquet/CSV preview. This
keeps every discovered field while intentionally avoiding a full historical
row pull during the approval phase.
"""
from __future__ import annotations

import gzip
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd
import requests
import yaml

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
CONFIG = ROOT / "config" / "api_football_endpoints.yml"
CATALOG = BUILD / "catalog" / "catalog.json"
API_BASE = os.environ.get("API_FOOTBALL_BASE_URL", "https://v3.football.api-sports.io").rstrip("/")
API_KEY = os.environ.get("API_FOOTBALL_KEY", "").strip()
PUBLIC_BASE = os.environ.get("R2_PUBLIC_BASE_URL", "").rstrip("/")
REQUEST_DELAY_SECONDS = float(os.environ.get("API_FOOTBALL_REQUEST_DELAY_SECONDS", "6.5"))
SCHEMA_VERSION = "api-football-v1"
NOW = datetime.now(timezone.utc)
LAST_REQUEST_AT = 0.0


class SafeFormat(dict[str, Any]):
    def __missing__(self, key: str) -> str:
        raise KeyError(key)


def utc_iso() -> str:
    return NOW.strftime("%Y-%m-%dT%H:%M:%SZ")


def fetched_date() -> str:
    return NOW.strftime("%Y-%m-%d")


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def wait_for_rate_limit() -> None:
    global LAST_REQUEST_AT
    if REQUEST_DELAY_SECONDS <= 0:
        return
    elapsed = time.monotonic() - LAST_REQUEST_AT
    if LAST_REQUEST_AT and elapsed < REQUEST_DELAY_SECONDS:
        time.sleep(REQUEST_DELAY_SECONDS - elapsed)
    LAST_REQUEST_AT = time.monotonic()


def api_get(endpoint: str, params: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, str]]:
    url = f"{API_BASE}/{endpoint.lstrip('/')}"
    wait_for_rate_limit()
    response = requests.get(
        url,
        headers={"x-apisports-key": API_KEY},
        params=params or {},
        timeout=60,
    )
    response.raise_for_status()
    data = response.json()
    if not isinstance(data, dict):
        raise ValueError(f"Unexpected API response type for {endpoint}: {type(data).__name__}")
    headers = {
        "requests_remaining": response.headers.get("x-ratelimit-requests-remaining", ""),
        "requests_limit": response.headers.get("x-ratelimit-requests-limit", ""),
    }
    return data, headers


def response_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    response = payload.get("response", [])
    if isinstance(response, dict):
        return [response]
    if isinstance(response, list):
        return [row for row in response if isinstance(row, dict)]
    return []


def json_safe_scalar(value: Any) -> Any:
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    return value


def normalize_rows(rows: list[dict[str, Any]], limit: int) -> pd.DataFrame:
    if not rows:
        return pd.DataFrame()
    frame = pd.json_normalize(rows[:limit], sep=".")
    for column in frame.columns:
        frame[column] = frame[column].map(json_safe_scalar)
    return frame


def write_raw(dataset_id: str, endpoint: str, payload: dict[str, Any]) -> tuple[Path, Path]:
    endpoint_slug = endpoint.strip("/").replace("/", "_") or "root"
    bronze_dir = ensure_dir(
        BUILD / "bronze" / "api-football" / endpoint_slug / f"fetched_date={fetched_date()}"
    )
    bronze = bronze_dir / f"{dataset_id}.json.gz"
    encoded = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    with gzip.open(bronze, "wb") as handle:
        handle.write(encoded)

    public_dir = ensure_dir(BUILD / "raw" / "api-football" / dataset_id)
    public_json = public_dir / "sample.json"
    public_json.write_bytes(encoded)
    return bronze, public_json


def write_normalized(dataset_id: str, frame: pd.DataFrame, sample_limit: int) -> tuple[Path | None, Path | None, Path]:
    metadata_dir = ensure_dir(BUILD / "metadata" / dataset_id)
    schema_path = metadata_dir / "schema.json"
    schema = {
        "dataset_id": dataset_id,
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": utc_iso(),
        "review_scope": "all_discovered_columns_limited_rows",
        "sample_row_limit": sample_limit,
        "columns": [{"name": str(column), "type": str(frame[column].dtype)} for column in frame.columns],
    }
    schema_path.write_text(json.dumps(schema, indent=2), encoding="utf-8")

    if frame.empty and not len(frame.columns):
        return None, None, schema_path

    silver_dir = ensure_dir(
        BUILD / "silver" / "sport=football" / f"dataset={dataset_id}" / "season=review"
    )
    parquet_path = silver_dir / "data.parquet"
    frame.to_parquet(parquet_path, compression="zstd", index=False)

    sample_dir = ensure_dir(BUILD / "samples" / "football" / dataset_id / "review")
    sample_path = sample_dir / f"sample_{sample_limit}.csv"
    frame.to_csv(sample_path, index=False)
    return parquet_path, sample_path, schema_path


def as_public(path: Path | None) -> str | None:
    if path is None:
        return None
    relative = path.relative_to(BUILD).as_posix()
    return f"{PUBLIC_BASE}/{relative}" if PUBLIC_BASE else relative


def format_params(params: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for key, value in params.items():
        if isinstance(value, str):
            output[key] = value.format_map(SafeFormat(context))
        else:
            output[key] = value
    return output


def latest_season(leagues_payload: dict[str, Any]) -> int:
    rows = response_rows(leagues_payload)
    seasons: list[dict[str, Any]] = []
    for row in rows:
        value = row.get("seasons", [])
        if isinstance(value, list):
            seasons.extend(item for item in value if isinstance(item, dict))
    current = [item.get("year") for item in seasons if item.get("current") is True]
    years = [item.get("year") for item in seasons]
    current_candidates = [year for year in current if isinstance(year, int)]
    if current_candidates:
        return max(current_candidates)
    year_candidates = [year for year in years if isinstance(year, int)]
    return max(year_candidates) if year_candidates else NOW.year


def first_nested_id(payload: dict[str, Any], *paths: tuple[str, ...]) -> int | None:
    rows = response_rows(payload)
    for row in rows:
        for path in paths:
            value: Any = row
            for key in path:
                if not isinstance(value, dict):
                    value = None
                    break
                value = value.get(key)
            if isinstance(value, int):
                return value
    return None


def nested_ids(payload: dict[str, Any], path: tuple[str, ...]) -> list[int]:
    ids: list[int] = []
    for row in response_rows(payload):
        value: Any = row
        for key in path:
            if not isinstance(value, dict):
                value = None
                break
            value = value.get(key)
        if isinstance(value, int) and value not in ids:
            ids.append(value)
    return ids


def resolve_context(defaults: dict[str, Any]) -> dict[str, Any]:
    context = dict(defaults)
    league_id = int(context.get("league_id", 39))
    if context.get("season") is None:
        leagues_payload, _ = api_get("leagues", {"id": league_id})
        context["season"] = latest_season(leagues_payload)
    else:
        context["season"] = int(context["season"])

    teams_payload, _ = api_get("teams", {"league": league_id, "season": context["season"]})
    team_ids = nested_ids(teams_payload, ("team", "id"))
    context["team_id"] = team_ids[0] if team_ids else context.get("team_id")
    context["opponent_team_id"] = (
        next((team_id for team_id in team_ids if team_id != context["team_id"]), None)
        or context.get("opponent_team_id")
    )
    if context.get("team_id") and context.get("opponent_team_id"):
        context["h2h"] = f"{context['team_id']}-{context['opponent_team_id']}"

    fixtures_payload, _ = api_get(
        "fixtures",
        {"league": league_id, "season": context["season"]},
    )
    context["fixture_id"] = first_nested_id(fixtures_payload, ("fixture", "id"))

    if context.get("team_id"):
        players_payload, _ = api_get(
            "players",
            {"team": context["team_id"], "season": context["season"], "page": 1},
        )
        context["player_id"] = first_nested_id(players_payload, ("player", "id"))
        coaches_payload, _ = api_get("coachs", {"team": context["team_id"]})
        context["coach_id"] = first_nested_id(coaches_payload, ("id",))
    return context


def append_catalog(entries: list[dict[str, Any]]) -> None:
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    if CATALOG.exists():
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    else:
        catalog = {"generated_at_utc": utc_iso(), "source": "api-football", "entries": []}

    existing = {
        entry.get("dataset_id"): entry
        for entry in catalog.get("entries", [])
        if isinstance(entry, dict) and entry.get("dataset_id")
    }
    for entry in entries:
        existing[entry["dataset_id"]] = entry
    catalog["entries"] = list(existing.values())
    catalog["generated_at_utc"] = utc_iso()
    catalog["source"] = "r2" if PUBLIC_BASE else "github-pages-build"
    CATALOG.write_text(json.dumps(catalog, indent=2), encoding="utf-8")


def catalog_entry(
    spec: dict[str, Any],
    params: dict[str, Any],
    payload: dict[str, Any],
    headers: dict[str, str],
    frame: pd.DataFrame,
    raw_path: Path,
    parquet_path: Path | None,
    sample_path: Path | None,
    schema_path: Path,
    error: str | None,
) -> dict[str, Any]:
    api_errors = payload.get("errors") if isinstance(payload, dict) else None
    has_errors = bool(api_errors)
    status = "missing" if error else "degraded" if has_errors or frame.empty else "available"
    paging = payload.get("paging", {}) if isinstance(payload, dict) else {}
    results = payload.get("results") if isinstance(payload, dict) else None
    return {
        "dataset_id": spec["id"],
        "display_name": spec["display_name"],
        "description": spec.get("description", "API-Football endpoint sample for schema approval."),
        "sport": "Football",
        "source_api": "api-football-v3",
        "source_endpoint": f"/{spec['endpoint'].lstrip('/')}",
        "entity": spec.get("entity", "operational_metadata"),
        "granularity": spec.get("granularity", "sample"),
        "league_id": params.get("league"),
        "league_name": spec.get("league_name"),
        "season": str(params.get("season")) if params.get("season") is not None else None,
        "row_count": int(len(frame)),
        "column_count": int(len(frame.columns)),
        "file_size_bytes": parquet_path.stat().st_size if parquet_path else raw_path.stat().st_size,
        "generated_at_utc": utc_iso(),
        "earliest_date": None,
        "latest_date": None,
        "parquet_url": as_public(parquet_path),
        "sample_csv_url": as_public(sample_path),
        "raw_json_url": as_public(raw_path),
        "raw_json_prefix": None,
        "schema_url": as_public(schema_path),
        "profile_url": None,
        "quality_url": None,
        "primary_key": spec.get("primary_key"),
        "partition_columns": [],
        "schema_version": SCHEMA_VERSION,
        "availability_status": status,
        "review_scope": "all_discovered_columns_limited_rows",
        "sample_row_limit": int(spec.get("sample_row_limit", 25)),
        "api_results": results,
        "api_paging_current": paging.get("current") if isinstance(paging, dict) else None,
        "api_paging_total": paging.get("total") if isinstance(paging, dict) else None,
        "api_errors": api_errors or error,
        "requests_remaining": headers.get("requests_remaining"),
        "request_parameters": params,
    }


def main() -> int:
    global REQUEST_DELAY_SECONDS
    if not API_KEY:
        print("API_FOOTBALL_KEY is not set; skipping API-Football samples.")
        return 0
    if not CONFIG.exists():
        print(f"Missing config: {CONFIG}", file=sys.stderr)
        return 1

    config = yaml.safe_load(CONFIG.read_text(encoding="utf-8")) or {}
    defaults = config.get("defaults", {})
    REQUEST_DELAY_SECONDS = float(defaults.get("request_delay_seconds", REQUEST_DELAY_SECONDS))
    try:
        context = resolve_context(defaults)
    except Exception as exc:
        print(f"Unable to resolve API-Football seed context: {exc}", file=sys.stderr)
        context = dict(defaults)
        context.setdefault("season", NOW.year)

    print("Resolved review context:", {key: value for key, value in context.items() if key != "api_key"})
    entries: list[dict[str, Any]] = []

    for spec in config.get("endpoints", []):
        if not spec.get("enabled", True):
            continue
        dataset_id = spec["id"]
        endpoint = spec["endpoint"]
        limit = int(spec.get("sample_row_limit", defaults.get("sample_row_limit", 25)))
        payload: dict[str, Any] = {"get": endpoint, "parameters": {}, "errors": {"configuration": "not requested"}, "response": []}
        headers: dict[str, str] = {}
        error: str | None = None
        params: dict[str, Any] = {}
        try:
            params = format_params(spec.get("params", {}), context)
            print(f"GET /{endpoint.lstrip('/')} params={params}")
            payload, headers = api_get(endpoint, params)
        except KeyError as exc:
            error = f"Missing seed value: {exc.args[0]}"
            payload["errors"] = {"configuration": error}
        except Exception as exc:
            error = str(exc)
            payload["errors"] = {"request": error}

        _, public_raw = write_raw(dataset_id, endpoint, payload)
        frame = normalize_rows(response_rows(payload), limit)
        parquet, sample, schema = write_normalized(dataset_id, frame, limit)
        entries.append(
            catalog_entry(
                spec,
                params,
                payload,
                headers,
                frame,
                public_raw,
                parquet,
                sample,
                schema,
                error,
            )
        )

    append_catalog(entries)
    print(f"Added {len(entries)} API-Football endpoint samples to {CATALOG}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
