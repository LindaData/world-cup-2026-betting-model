#!/usr/bin/env python3
"""
build_data_lake.py
==================

Reads dataset definitions from config/datasets.yml, downloads source CSV/JSON
from the public LindaData GitHub mirror (or local paths), and writes a tiered
data lake under ./build/:

  build/bronze/api-sports/<sport>/<endpoint>/fetched_date=<YYYY-MM-DD>/*.json.gz
  build/silver/sport=<sport>/dataset=<dataset>/season=<season>/data.parquet
  build/samples/<sport>/<dataset>/<season>/sample_100.csv
  build/metadata/<dataset_id>/schema.json
  build/metadata/<dataset_id>/profile.json   (written by profile_datasets.py)
  build/metadata/<dataset_id>/quality.json   (written by validate_datasets.py)
  build/catalog/catalog.json

Lineage columns are added rather than replacing source values. No API keys,
auth headers, or private request data are persisted.

Designed to run inside GitHub Actions. If R2_* secrets are present, the
companion workflow uploads ./build/ to Cloudflare R2.
"""
from __future__ import annotations

import gzip
import io
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    print("PyYAML required: pip install pyyaml", file=sys.stderr)
    raise

try:
    import duckdb  # type: ignore
    import pandas as pd  # type: ignore
    import requests  # type: ignore
except ImportError:
    print("Install: pip install duckdb pandas requests pyyaml", file=sys.stderr)
    raise


GITHUB_RAW = "https://raw.githubusercontent.com/LindaData/world-cup-2026-betting-model/main"
ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
CONFIG = ROOT / "config" / "datasets.yml"
SCHEMA_VERSION = "v1"
NOW = datetime.now(timezone.utc)


def utc_iso() -> str:
    return NOW.strftime("%Y-%m-%dT%H:%M:%SZ")


def fetched_date() -> str:
    return NOW.strftime("%Y-%m-%d")


def mkdirs(*parts: str | Path) -> Path:
    p = Path(*parts)
    p.mkdir(parents=True, exist_ok=True)
    return p


def fetch_text(url: str) -> str:
    print(f"  GET {url}")
    r = requests.get(url, timeout=60)
    r.raise_for_status()
    return r.text


def normalize_endpoint(endpoint: str) -> str:
    return endpoint.strip("/").replace("/", "_").replace("?", "_q_").replace("=", "_eq_")


def write_bronze(ds: dict[str, Any], raw_text: str, ext: str) -> Path:
    sport = ds["sport"].lower()
    endpoint = normalize_endpoint(ds["source_endpoint"])
    target = mkdirs(
        BUILD, "bronze", "api-sports", sport, endpoint, f"fetched_date={fetched_date()}"
    ) / f"{ds['id']}.{ext}.gz"
    with gzip.open(target, "wb") as f:
        f.write(raw_text.encode("utf-8"))
    return target


def add_lineage(df: "pd.DataFrame", ds: dict[str, Any], source_file: str) -> "pd.DataFrame":
    df = df.copy()
    df["source_api"] = ds["source_api"]
    df["source_endpoint"] = ds["source_endpoint"]
    df["source_file"] = source_file
    df["source_fetched_at_utc"] = utc_iso()
    df["ingested_at_utc"] = utc_iso()
    df["schema_version"] = SCHEMA_VERSION
    df["sport"] = ds["sport"]
    if ds.get("league_id") is not None:
        df["league_id"] = ds["league_id"]
    if ds.get("season"):
        df["season"] = ds["season"]
    return df


def write_silver(ds: dict[str, Any], df: "pd.DataFrame") -> Path:
    sport = ds["sport"].lower()
    season = ds.get("season") or "current"
    target_dir = mkdirs(
        BUILD, "silver", f"sport={sport}", f"dataset={ds['id']}", f"season={season}"
    )
    target = target_dir / "data.parquet"
    # zstd compression keeps files small; pyarrow default writer
    df.to_parquet(target, compression="zstd", index=False)
    return target


def write_sample(ds: dict[str, Any], df: "pd.DataFrame") -> Path:
    sport = ds["sport"].lower()
    season = ds.get("season") or "current"
    target_dir = mkdirs(BUILD, "samples", sport, ds["id"], season)
    target = target_dir / "sample_100.csv"
    df.head(100).to_csv(target, index=False)
    return target


def write_schema(ds: dict[str, Any], df: "pd.DataFrame") -> Path:
    target = mkdirs(BUILD, "metadata", ds["id"]) / "schema.json"
    schema = {
        "dataset_id": ds["id"],
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": utc_iso(),
        "primary_key": ds.get("primary_key"),
        "partition_columns": ds.get("partition_columns", []),
        "columns": [
            {"name": str(c), "type": str(df[c].dtype)} for c in df.columns
        ],
    }
    target.write_text(json.dumps(schema, indent=2))
    return target


def detect_date_range(df: "pd.DataFrame") -> tuple[str | None, str | None]:
    for col in df.columns:
        if col.lower() in {"date_utc", "date", "timestamp", "game_date"}:
            try:
                s = pd.to_datetime(df[col], errors="coerce", utc=True).dropna()
                if not s.empty:
                    return s.min().isoformat(), s.max().isoformat()
            except Exception:
                continue
    return None, None


def process_dataset(ds: dict[str, Any]) -> dict[str, Any]:
    print(f"\n→ Building dataset: {ds['id']}")
    src_csv = ds.get("source_csv")
    src_json = ds.get("source_json")

    raw_path = None
    if src_csv:
        url = f"{GITHUB_RAW}/{src_csv}"
        text = fetch_text(url)
        raw_path = write_bronze(ds, text, "csv")
        df = pd.read_csv(io.StringIO(text), dtype=str, keep_default_na=False, na_values=[""])
    elif src_json:
        url = f"{GITHUB_RAW}/{src_json}"
        text = fetch_text(url)
        raw_path = write_bronze(ds, text, "json")
        data = json.loads(text)
        events = data.get("events", data) if isinstance(data, dict) else data
        df = pd.json_normalize(events) if isinstance(events, list) else pd.json_normalize([events])
    else:
        raise ValueError(f"Dataset {ds['id']} has no source_csv or source_json")

    df = add_lineage(df, ds, str(raw_path))

    silver = write_silver(ds, df)
    sample = write_sample(ds, df)
    schema = write_schema(ds, df)

    earliest, latest = detect_date_range(df)
    size = silver.stat().st_size

    entry = {
        "dataset_id": ds["id"],
        "display_name": ds["display_name"],
        "description": ds["description"],
        "sport": ds["sport"],
        "source_api": ds["source_api"],
        "source_endpoint": ds["source_endpoint"],
        "entity": ds["entity"],
        "granularity": ds["granularity"],
        "league_id": ds.get("league_id"),
        "league_name": ds.get("league_name"),
        "season": ds.get("season"),
        "row_count": int(len(df)),
        "column_count": int(len(df.columns)),
        "file_size_bytes": size,
        "generated_at_utc": utc_iso(),
        "earliest_date": earliest,
        "latest_date": latest,
        "parquet_url": str(silver.relative_to(BUILD)),
        "sample_csv_url": str(sample.relative_to(BUILD)),
        "raw_json_url": str(raw_path.relative_to(BUILD)) if src_json else None,
        "raw_json_prefix": f"bronze/api-sports/{ds['sport'].lower()}/{normalize_endpoint(ds['source_endpoint'])}/" if src_json else None,
        "schema_url": str(schema.relative_to(BUILD)),
        "profile_url": f"metadata/{ds['id']}/profile.json",
        "quality_url": f"metadata/{ds['id']}/quality.json",
        "primary_key": ds.get("primary_key"),
        "partition_columns": ds.get("partition_columns", []),
        "schema_version": SCHEMA_VERSION,
        "availability_status": "available",
    }
    return entry


def main() -> int:
    if not CONFIG.exists():
        print(f"Missing config: {CONFIG}", file=sys.stderr)
        return 1
    with CONFIG.open() as f:
        cfg = yaml.safe_load(f)

    public_base = os.environ.get("R2_PUBLIC_BASE_URL", "").rstrip("/")
    entries: list[dict[str, Any]] = []
    for ds in cfg.get("datasets", []):
        try:
            entry = process_dataset(ds)
            if public_base:
                for k in ("parquet_url", "sample_csv_url", "raw_json_url", "schema_url", "profile_url", "quality_url"):
                    if entry.get(k):
                        entry[k] = f"{public_base}/{entry[k]}"
                if entry.get("raw_json_prefix"):
                    entry["raw_json_prefix"] = f"{public_base}/{entry['raw_json_prefix']}"
            entries.append(entry)
        except Exception as e:  # pragma: no cover
            print(f"  ! failed {ds.get('id')}: {e}", file=sys.stderr)
            entries.append({
                "dataset_id": ds.get("id"),
                "display_name": ds.get("display_name", ds.get("id")),
                "description": ds.get("description", ""),
                "sport": ds.get("sport"),
                "entity": ds.get("entity"),
                "availability_status": "missing",
                "error": str(e),
                "schema_version": SCHEMA_VERSION,
            })

    catalog_dir = mkdirs(BUILD, "catalog")
    catalog = {
        "generated_at_utc": utc_iso(),
        "source": "r2" if public_base else "github-actions-local",
        "entries": entries,
    }
    (catalog_dir / "catalog.json").write_text(json.dumps(catalog, indent=2))
    print(f"\nCatalog written: {catalog_dir / 'catalog.json'}")
    print(f"Datasets: {len(entries)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
