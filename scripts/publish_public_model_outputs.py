from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "processed"
PUBLIC = ROOT / "data" / "public"

ALLOWED_DIRECTORIES = {
    "modeling": ("*.csv", "*.json"),
    "metadata": ("*.csv", "*.json"),
}

BLOCKED_SUFFIXES = {
    ".duckdb",
    ".sqlite",
    ".sqlite3",
    ".rds",
    ".RData",
    ".ubj",
    ".pkl",
    ".pickle",
    ".parquet",
    ".feather",
}


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def is_public_safe(path: Path) -> bool:
    lowered = path.name.lower()
    if path.suffix in BLOCKED_SUFFIXES:
        return False
    blocked_terms = ("credential", "secret", "token", "key", "private", "raw")
    return not any(term in lowered for term in blocked_terms)


def copy_allowed_files() -> list[dict[str, str]]:
    if PUBLIC.exists():
        shutil.rmtree(PUBLIC)
    PUBLIC.mkdir(parents=True, exist_ok=True)

    copied: list[dict[str, str]] = []
    for directory, patterns in ALLOWED_DIRECTORIES.items():
        source_dir = PROCESSED / directory
        destination_dir = PUBLIC / directory
        destination_dir.mkdir(parents=True, exist_ok=True)
        if not source_dir.exists():
            continue
        for pattern in patterns:
            for source in sorted(source_dir.glob(pattern)):
                if not source.is_file() or not is_public_safe(source):
                    continue
                destination = destination_dir / source.name
                shutil.copy2(source, destination)
                copied.append(
                    {
                        "source": str(source.relative_to(ROOT)),
                        "public_path": str(destination.relative_to(ROOT)),
                        "bytes": str(destination.stat().st_size),
                    }
                )

    status_doc = ROOT / "docs" / "current_data_status.md"
    if status_doc.exists() and is_public_safe(status_doc):
        shutil.copy2(status_doc, PUBLIC / "current_data_status.md")
        copied.append(
            {
                "source": str(status_doc.relative_to(ROOT)),
                "public_path": str((PUBLIC / "current_data_status.md").relative_to(ROOT)),
                "bytes": str((PUBLIC / "current_data_status.md").stat().st_size),
            }
        )

    return copied


def write_manifest(copied: list[dict[str, str]]) -> None:
    manifest = {
        "generated_at_utc": iso_now(),
        "policy": "Public-safe model outputs only. Raw snapshots, credentials, private data, model binaries, and local film-study files are excluded.",
        "copied_file_count": len(copied),
        "copied_files": copied,
    }
    (PUBLIC / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    readme = """# LindaData Public Model Output Cache

This folder is written by `scripts/publish_public_model_outputs.py` after a model run.

It is intentionally limited to public-safe CSV, JSON, and status artifacts from `data/processed/modeling`, `data/processed/metadata`, and `docs/current_data_status.md`.

It must not contain raw provider payloads, credentials, private files, model binaries, local film-study files, DuckDB databases, or paid API responses.
"""
    (PUBLIC / "README.md").write_text(readme, encoding="utf-8")


def main() -> int:
    copied = copy_allowed_files()
    write_manifest(copied)
    print(f"Copied {len(copied)} public-safe model output files to {PUBLIC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
