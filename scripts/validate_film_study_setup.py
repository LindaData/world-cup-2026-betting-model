from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def check_import(name: str) -> dict[str, object]:
    try:
        module = __import__(name)
        version = getattr(module, "__version__", "")
        return {"ok": True, "module": name, "version": str(version)}
    except Exception as exc:
        return {"ok": False, "module": name, "error": str(exc)}


def check_directory(path: Path) -> dict[str, object]:
    return {
        "path": str(path),
        "exists": path.exists(),
        "is_dir": path.is_dir(),
        "writable_expected": True,
    }


def check_file(path: Path) -> dict[str, object]:
    return {
        "path": str(path),
        "exists": path.exists(),
        "size_bytes": path.stat().st_size if path.exists() else 0,
    }


def monitor_summary() -> dict[str, object]:
    try:
        import mss  # type: ignore

        session = mss.MSS() if hasattr(mss, "MSS") else mss.mss()
        with session as sct:
            monitors = [
                {
                    "monitor": index,
                    "left": int(monitor["left"]),
                    "top": int(monitor["top"]),
                    "width": int(monitor["width"]),
                    "height": int(monitor["height"]),
                }
                for index, monitor in enumerate(sct.monitors[1:], start=1)
            ]
        return {"ok": True, "monitor_count": len(monitors), "monitors": monitors}
    except Exception as exc:
        return {"ok": False, "error": str(exc), "monitor_count": 0, "monitors": []}


def main() -> None:
    root = repo_root()
    checks = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "python_executable": sys.executable,
        "imports": {
            name: check_import(name)
            for name in ["cv2", "mss", "numpy", "pandas", "duckdb", "json"]
        },
        "directories": {
            "recordings": check_directory(root / "data" / "private" / "recordings"),
            "capture_profiles": check_directory(root / "data" / "private" / "capture_profiles"),
            "film_tags": check_directory(root / "data" / "private" / "film_tags"),
            "video_library": check_directory(root / "data" / "private" / "video_library"),
            "tagger_presets": check_directory(root / "data" / "private" / "tagger_presets"),
            "reports": check_directory(root / "data" / "private" / "reports"),
            "processed_film_study": check_directory(root / "data" / "processed" / "film_study"),
        },
        "files": {
            "capture_script": check_file(root / "scripts" / "capture_film_study_screen.py"),
            "tagger_script": check_file(root / "scripts" / "video_tagger.py"),
            "session_runner": check_file(root / "R" / "38_capture_and_process_film_study_session.R"),
            "workbench_app": check_file(root / "apps" / "shiny_film_study" / "app.R"),
        },
        "monitors": monitor_summary(),
    }

    import_ok = all(item.get("ok") for item in checks["imports"].values())
    dir_ok = all(item["exists"] and item["is_dir"] for item in checks["directories"].values())
    file_ok = all(item["exists"] for item in checks["files"].values())
    monitor_ok = checks["monitors"].get("ok", False) and checks["monitors"].get("monitor_count", 0) >= 1

    checks["overall_ok"] = bool(import_ok and dir_ok and file_ok and monitor_ok)

    output_path = root / "data" / "processed" / "film_study" / "film_study_setup_validation.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(checks, indent=2), encoding="utf-8")

    print(json.dumps(checks, indent=2))
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
