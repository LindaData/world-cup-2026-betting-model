#!/usr/bin/env python3
"""
profile_datasets.py
===================

For each silver Parquet table produced by build_data_lake.py, write
build/metadata/<dataset_id>/profile.json with per-column statistics:

  - type, non_null_count, null_count, missing_percentage, unique_count
  - numeric: min, max, mean, median
  - date: earliest, latest
  - categorical: top 10 values + counts
  - 5 example values
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import duckdb  # type: ignore
    import yaml  # type: ignore
except ImportError:
    print("Install: pip install duckdb pyyaml", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
CONFIG = ROOT / "config" / "datasets.yml"


def profile_dataset(ds_id: str, parquet_path: Path) -> dict:
    con = duckdb.connect()
    con.execute(f"CREATE VIEW t AS SELECT * FROM read_parquet('{parquet_path}')")
    cols = con.execute("DESCRIBE t").fetchall()
    total = con.execute("SELECT COUNT(*)::BIGINT FROM t").fetchone()[0]

    columns_out = []
    for name, dtype, *_ in cols:
        ident = f'"{name.replace(chr(34), chr(34) * 2)}"'
        non_null = con.execute(f"SELECT COUNT({ident}) FROM t").fetchone()[0]
        unique = con.execute(f"SELECT COUNT(DISTINCT {ident}) FROM t").fetchone()[0]
        examples = [r[0] for r in con.execute(f"SELECT DISTINCT {ident} FROM t WHERE {ident} IS NOT NULL LIMIT 5").fetchall()]
        col = {
            "name": name,
            "type": dtype,
            "non_null_count": int(non_null),
            "null_count": int(total - non_null),
            "missing_percentage": round(100.0 * (total - non_null) / total, 4) if total else 0.0,
            "unique_count": int(unique),
            "examples": [str(e) for e in examples],
        }
        dlow = dtype.lower()
        try:
            if any(t in dlow for t in ("int", "double", "decimal", "float", "bigint")):
                row = con.execute(
                    f"SELECT MIN({ident}), MAX({ident}), AVG({ident}), MEDIAN({ident}) FROM t WHERE {ident} IS NOT NULL"
                ).fetchone()
                col.update({
                    "min": row[0], "max": row[1],
                    "mean": float(row[2]) if row[2] is not None else None,
                    "median": float(row[3]) if row[3] is not None else None,
                })
            elif any(t in dlow for t in ("date", "timestamp", "time")):
                row = con.execute(f"SELECT MIN({ident})::VARCHAR, MAX({ident})::VARCHAR FROM t").fetchone()
                col.update({"earliest": row[0], "latest": row[1]})
            elif "varchar" in dlow or "text" in dlow:
                top = con.execute(
                    f"SELECT {ident}, COUNT(*) AS n FROM t WHERE {ident} IS NOT NULL GROUP BY 1 ORDER BY n DESC LIMIT 10"
                ).fetchall()
                col["top_values"] = [{"value": str(v), "count": int(n)} for v, n in top]
        except Exception as e:
            col["stat_error"] = str(e)
        columns_out.append(col)

    return {
        "dataset_id": ds_id,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "row_count": int(total),
        "columns": columns_out,
    }


def find_parquet(ds_id: str) -> Path | None:
    silver = BUILD / "silver"
    if not silver.exists():
        return None
    matches = list(silver.glob(f"sport=*/dataset={ds_id}/season=*/data.parquet"))
    return matches[0] if matches else None


def main() -> int:
    if not CONFIG.exists():
        print(f"Missing {CONFIG}", file=sys.stderr)
        return 1
    cfg = yaml.safe_load(CONFIG.read_text())
    for ds in cfg.get("datasets", []):
        ds_id = ds["id"]
        parquet = find_parquet(ds_id)
        if not parquet:
            print(f"skip {ds_id}: no parquet")
            continue
        out = BUILD / "metadata" / ds_id / "profile.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        result = profile_dataset(ds_id, parquet)
        out.write_text(json.dumps(result, indent=2, default=str))
        print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
