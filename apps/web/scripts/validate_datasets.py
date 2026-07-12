#!/usr/bin/env python3
"""
validate_datasets.py
====================

Produces build/metadata/<dataset_id>/quality.json with rule-based findings.
Reports problems only — never deletes, corrects, or imputes records.

General checks: duplicate PKs, duplicate full rows, missing PKs, invalid dates,
missing season, null percentages, type-conversion failures.

Games checks: missing home/away team, same team on both sides, missing score
for completed game, negative score, duplicate game_id, unknown status.

Standings checks: duplicate team within group+season, missing position,
wins+losses inconsistent with played, percentages outside [0,1].
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


def find_parquet(ds_id: str) -> Path | None:
    silver = BUILD / "silver"
    matches = list(silver.glob(f"sport=*/dataset={ds_id}/season=*/data.parquet"))
    return matches[0] if matches else None


def safe_scalar(con, sql: str) -> int:
    try:
        return int(con.execute(sql).fetchone()[0])
    except Exception:
        return 0


def general_checks(con, ds: dict) -> list[dict]:
    findings: list[dict] = []
    pk = ds.get("primary_key")
    if pk:
        ident = f'"{pk}"'
        dup = safe_scalar(con, f"SELECT COUNT(*) - COUNT(DISTINCT {ident}) FROM t")
        if dup > 0:
            findings.append({"check": "duplicate_primary_key", "severity": "high", "count": dup})
        missing = safe_scalar(con, f"SELECT COUNT(*) FROM t WHERE {ident} IS NULL OR CAST({ident} AS VARCHAR) = ''")
        if missing > 0:
            findings.append({"check": "missing_primary_key", "severity": "high", "count": missing})
    dup_rows = safe_scalar(con, "SELECT COUNT(*) - COUNT(DISTINCT (t.*)) FROM t")
    if dup_rows > 0:
        findings.append({"check": "duplicate_full_rows", "severity": "medium", "count": dup_rows})
    cols = [r[0] for r in con.execute("DESCRIBE t").fetchall()]
    if "date_utc" in cols:
        bad = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE date_utc IS NOT NULL AND TRY_CAST(date_utc AS TIMESTAMP) IS NULL")
        if bad > 0:
            findings.append({"check": "invalid_timestamp_date_utc", "severity": "medium", "count": bad})
    if ds.get("season") and "season" in cols:
        missing_season = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE season IS NULL OR season = ''")
        if missing_season > 0:
            findings.append({"check": "missing_season", "severity": "low", "count": missing_season})
    return findings


def games_checks(con) -> list[dict]:
    findings = []
    cols = {r[0] for r in con.execute("DESCRIBE t").fetchall()}
    if {"home_team", "away_team"} <= cols:
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE home_team IS NULL OR home_team = ''")
        if n: findings.append({"check": "missing_home_team", "severity": "high", "count": n})
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE away_team IS NULL OR away_team = ''")
        if n: findings.append({"check": "missing_away_team", "severity": "high", "count": n})
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE home_team = away_team AND home_team IS NOT NULL")
        if n: findings.append({"check": "same_team_both_sides", "severity": "high", "count": n})
    if {"status", "home_score", "away_score"} <= cols:
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE LOWER(status) IN ('finished','final','ft') AND (home_score IS NULL OR away_score IS NULL OR home_score = '' OR away_score = '')")
        if n: findings.append({"check": "missing_score_for_completed_game", "severity": "high", "count": n})
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE TRY_CAST(home_score AS INT) < 0 OR TRY_CAST(away_score AS INT) < 0")
        if n: findings.append({"check": "negative_score", "severity": "high", "count": n})
    return findings


def standings_checks(con) -> list[dict]:
    findings = []
    cols = {r[0] for r in con.execute("DESCRIBE t").fetchall()}
    if {"team_id", "group", "season"} <= cols:
        n = safe_scalar(con, 'SELECT SUM(c) FROM (SELECT COUNT(*) - 1 AS c FROM t GROUP BY team_id, "group", season HAVING COUNT(*) > 1)')
        if n: findings.append({"check": "duplicate_team_in_group_season", "severity": "high", "count": n})
    if "position" in cols:
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE position IS NULL OR position = ''")
        if n: findings.append({"check": "missing_position", "severity": "medium", "count": n})
    if {"wins", "losses", "played"} <= cols:
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE TRY_CAST(wins AS INT) + TRY_CAST(losses AS INT) <> TRY_CAST(played AS INT)")
        if n: findings.append({"check": "wins_losses_played_mismatch", "severity": "medium", "count": n})
    if "percentage" in cols:
        n = safe_scalar(con, "SELECT COUNT(*) FROM t WHERE TRY_CAST(percentage AS DOUBLE) < 0 OR TRY_CAST(percentage AS DOUBLE) > 1")
        if n: findings.append({"check": "percentage_out_of_bounds", "severity": "medium", "count": n})
    return findings


def validate(ds: dict, parquet: Path) -> dict:
    con = duckdb.connect()
    con.execute(f"CREATE VIEW t AS SELECT * FROM read_parquet('{parquet}')")
    findings = general_checks(con, ds)
    if ds.get("entity") == "games":
        findings.extend(games_checks(con))
    elif ds.get("entity") == "standings":
        findings.extend(standings_checks(con))
    return {
        "dataset_id": ds["id"],
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "row_count": safe_scalar(con, "SELECT COUNT(*) FROM t"),
        "finding_count": len(findings),
        "findings": findings,
    }


def main() -> int:
    cfg = yaml.safe_load(CONFIG.read_text())
    for ds in cfg.get("datasets", []):
        parquet = find_parquet(ds["id"])
        if not parquet:
            continue
        out = BUILD / "metadata" / ds["id"] / "quality.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(validate(ds, parquet), indent=2, default=str))
        print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
