from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def slugify(value: str) -> str:
    keep = []
    for char in value.lower():
        if char.isalnum():
            keep.append(char)
        elif char in {" ", "-", "_"}:
            keep.append("-")
    slug = "".join(keep).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "match"


def load_mss():
    try:
        import mss  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "Package 'mss' is required for local screen capture. "
            "Install it with: py -m pip install mss"
        ) from exc
    return mss


def open_mss_session(mss_module):
    if hasattr(mss_module, "MSS"):
        return mss_module.MSS()
    return mss_module.mss()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Record a local screen region into a private video file and register "
            "it for film-study review."
        )
    )
    parser.add_argument("--match-key", default="", help="Stable match identifier.")
    parser.add_argument("--home-team", default="", help="Home team label.")
    parser.add_argument("--away-team", default="", help="Away team label.")
    parser.add_argument("--competition", default="World Cup 2026", help="Competition label.")
    parser.add_argument("--kickoff-utc", default="", help="Optional kickoff timestamp in UTC ISO format.")
    parser.add_argument("--monitor", type=int, default=1, help="Monitor number from the list-monitors output.")
    parser.add_argument(
        "--region",
        nargs=4,
        type=int,
        metavar=("LEFT", "TOP", "WIDTH", "HEIGHT"),
        help="Absolute screen region in pixels. If omitted, use --select-region or the full monitor.",
    )
    parser.add_argument(
        "--select-region",
        action="store_true",
        help="Open an interactive ROI selector before recording.",
    )
    parser.add_argument("--fps", type=float, default=30.0, help="Target frames per second.")
    parser.add_argument(
        "--quality-profile",
        choices=("archive", "compact"),
        default="archive",
        help="Archive uses MJPG AVI for higher quality. Compact uses MP4V MP4 for smaller files.",
    )
    parser.add_argument(
        "--output-dir",
        default="data/private/recordings",
        help="Project-relative output folder for the captured video.",
    )
    parser.add_argument(
        "--max-seconds",
        type=float,
        default=0.0,
        help="Optional maximum duration. Zero means record until you stop it.",
    )
    parser.add_argument(
        "--no-preview",
        action="store_true",
        help="Do not open the live preview window. Stop with Ctrl+C instead.",
    )
    parser.add_argument(
        "--window-scale",
        type=float,
        default=0.6,
        help="Preview window scale factor.",
    )
    parser.add_argument(
        "--launch-tagger",
        action="store_true",
        help="Launch the local tagger after the capture is registered.",
    )
    parser.add_argument(
        "--skip-previews",
        action="store_true",
        help="Skip still-image preview generation during registration.",
    )
    parser.add_argument(
        "--list-monitors",
        action="store_true",
        help="Print monitor metadata and exit.",
    )
    parser.add_argument(
        "--mock-video",
        default="",
        help="Optional local video file to import through the same capture-registration path without live screen capture.",
    )
    parser.add_argument(
        "--profile-name",
        default="",
        help="Optional saved capture profile name.",
    )
    parser.add_argument(
        "--profiles-dir",
        default="data/private/capture_profiles",
        help="Project-relative directory for saved capture profiles.",
    )
    parser.add_argument(
        "--save-profile",
        action="store_true",
        help="Save the resolved capture region to the profile name.",
    )
    parser.add_argument(
        "--save-profile-only",
        action="store_true",
        help="Resolve and save a capture profile, then exit without recording.",
    )
    return parser.parse_args()


def list_monitors(mss_module) -> None:
    with open_mss_session(mss_module) as sct:
        for index, monitor in enumerate(sct.monitors[1:], start=1):
            payload = {
                "monitor": index,
                "left": int(monitor["left"]),
                "top": int(monitor["top"]),
                "width": int(monitor["width"]),
                "height": int(monitor["height"]),
            }
            print(json.dumps(payload))


def choose_region(mss_module, monitor_index: int) -> dict[str, int]:
    with open_mss_session(mss_module) as sct:
        if monitor_index < 1 or monitor_index >= len(sct.monitors):
            raise ValueError(f"Monitor {monitor_index} is not available.")
        monitor = sct.monitors[monitor_index]
        frame = np.array(sct.grab(monitor))
        bgr = cv2.cvtColor(frame, cv2.COLOR_BGRA2BGR)
        selection = cv2.selectROI(
            "Select capture region and press Enter",
            bgr,
            showCrosshair=True,
            fromCenter=False,
        )
        cv2.destroyWindow("Select capture region and press Enter")

    x, y, width, height = [int(value) for value in selection]
    if width <= 0 or height <= 0:
        raise ValueError("No capture region was selected.")

    return {
        "left": int(monitor["left"]) + x,
        "top": int(monitor["top"]) + y,
        "width": width,
        "height": height,
        "monitor": monitor_index,
    }


def resolve_region(mss_module, monitor_index: int, region_args: list[int] | None, select_region: bool) -> dict[str, int]:
    with open_mss_session(mss_module) as sct:
        if monitor_index < 1 or monitor_index >= len(sct.monitors):
            raise ValueError(f"Monitor {monitor_index} is not available.")
        monitor = sct.monitors[monitor_index]

    if select_region:
        return choose_region(mss_module, monitor_index)

    if region_args:
        left, top, width, height = [int(value) for value in region_args]
        if width <= 0 or height <= 0:
            raise ValueError("Capture width and height must be positive.")
        return {
            "left": left,
            "top": top,
            "width": width,
            "height": height,
            "monitor": monitor_index,
        }

    return {
        "left": int(monitor["left"]),
        "top": int(monitor["top"]),
        "width": int(monitor["width"]),
        "height": int(monitor["height"]),
        "monitor": monitor_index,
    }


def profile_path(profiles_dir: Path, profile_name: str) -> Path:
    return profiles_dir / f"{slugify(profile_name)}.json"


def load_profile(profiles_dir: Path, profile_name: str) -> dict[str, int]:
    path = profile_path(profiles_dir, profile_name)
    if not path.exists():
        raise FileNotFoundError(f"Capture profile not found: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {
        "left": int(payload["left"]),
        "top": int(payload["top"]),
        "width": int(payload["width"]),
        "height": int(payload["height"]),
        "monitor": int(payload.get("monitor", 1)),
    }


def save_profile(profiles_dir: Path, profile_name: str, region: dict[str, int]) -> Path:
    profiles_dir.mkdir(parents=True, exist_ok=True)
    path = profile_path(profiles_dir, profile_name)
    payload = {
        "profile_name": profile_name,
        "left": int(region["left"]),
        "top": int(region["top"]),
        "width": int(region["width"]),
        "height": int(region["height"]),
        "monitor": int(region.get("monitor", 1)),
        "saved_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return path


def writer_settings(quality_profile: str) -> tuple[str, str]:
    if quality_profile == "archive":
        return "MJPG", ".avi"
    return "mp4v", ".mp4"


def open_writer(output_path: Path, width: int, height: int, fps: float, fourcc_name: str) -> cv2.VideoWriter:
    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*fourcc_name),
        fps,
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError(f"Could not open video writer for {output_path}")
    return writer


def overlay_status(frame: np.ndarray, elapsed_seconds: float, match_key: str) -> np.ndarray:
    rendered = frame.copy()
    label = f"{match_key}  REC  {elapsed_seconds:0.1f}s  press q to stop"
    cv2.rectangle(rendered, (12, 12), (520, 58), (18, 18, 18), -1)
    cv2.putText(rendered, label, (24, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (245, 245, 245), 2, cv2.LINE_AA)
    return rendered


def record_capture(
    mss_module,
    region: dict[str, int],
    output_path: Path,
    fps: float,
    match_key: str,
    no_preview: bool,
    window_scale: float,
    max_seconds: float,
    quality_profile: str,
) -> dict[str, object]:
    frame_width = int(region["width"])
    frame_height = int(region["height"])
    codec_name, _ = writer_settings(quality_profile)
    writer = open_writer(output_path, frame_width, frame_height, fps, codec_name)

    preview_window = "Film Study Capture"
    if not no_preview:
        cv2.namedWindow(preview_window, cv2.WINDOW_NORMAL)

    frame_counter = 0
    start_time = time.perf_counter()
    next_frame_time = start_time

    try:
        with open_mss_session(mss_module) as sct:
            while True:
                now = time.perf_counter()
                if now < next_frame_time:
                    time.sleep(next_frame_time - now)

                grabbed = np.array(sct.grab(region))
                frame = cv2.cvtColor(grabbed, cv2.COLOR_BGRA2BGR)
                writer.write(frame)
                frame_counter += 1

                elapsed = time.perf_counter() - start_time
                if not no_preview:
                    preview_frame = overlay_status(frame, elapsed, match_key)
                    if window_scale != 1.0:
                        preview_frame = cv2.resize(
                            preview_frame,
                            (
                                max(1, int(preview_frame.shape[1] * window_scale)),
                                max(1, int(preview_frame.shape[0] * window_scale)),
                            ),
                        )
                    cv2.imshow(preview_window, preview_frame)
                    key = cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q"), ord("Q")):
                        break

                if max_seconds > 0 and elapsed >= max_seconds:
                    break

                next_frame_time += 1.0 / fps
    except KeyboardInterrupt:
        pass
    finally:
        writer.release()
        if not no_preview:
            cv2.destroyWindow(preview_window)

    elapsed_total = time.perf_counter() - start_time
    return {
        "frames_written": frame_counter,
        "elapsed_seconds": round(elapsed_total, 3),
        "fps_target": fps,
        "fps_observed": round(frame_counter / elapsed_total, 3) if elapsed_total > 0 else 0.0,
    }


def register_capture(
    output_path: Path,
    match_key: str,
    home_team: str,
    away_team: str,
    competition: str,
    kickoff_utc: str,
    launch_tagger: bool,
    skip_previews: bool,
) -> None:
    root = repo_root()
    command = [
        sys.executable,
        str(root / "scripts" / "prepare_film_study_session.py"),
        "--video",
        str(output_path),
        "--match-key",
        match_key,
        "--home-team",
        home_team,
        "--away-team",
        away_team,
        "--competition",
        competition,
    ]
    if kickoff_utc:
        command.extend(["--kickoff-utc", kickoff_utc])
    if launch_tagger:
        command.append("--launch-tagger")
    if skip_previews:
        command.append("--skip-previews")
    subprocess.run(command, check=True)


def import_mock_video(mock_video: Path, output_path: Path) -> dict[str, object]:
    if not mock_video.exists():
        raise FileNotFoundError(f"Mock video file not found: {mock_video}")
    shutil.copy2(mock_video, output_path)

    capture = cv2.VideoCapture(str(output_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open imported mock video: {output_path}")

    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    capture.release()

    duration_seconds = round(frame_count / fps, 3) if fps > 0 and frame_count > 0 else 0.0
    return {
        "frames_written": frame_count,
        "elapsed_seconds": duration_seconds,
        "fps_target": fps,
        "fps_observed": fps,
        "frame_width": width,
        "frame_height": height,
        "mock_source_video": str(mock_video),
    }


def main() -> None:
    args = parse_args()
    if args.list_monitors:
        mss_module = load_mss()
        list_monitors(mss_module)
        return

    missing = [
        name
        for name, value in {
            "--match-key": args.match_key,
            "--home-team": args.home_team,
            "--away-team": args.away_team,
        }.items()
        if not value
    ]
    if missing:
        raise SystemExit(f"Missing required arguments: {', '.join(missing)}")

    root = repo_root()
    output_dir = root / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    profiles_dir = root / args.profiles_dir

    codec_name, extension = writer_settings(args.quality_profile)
    if args.mock_video:
        mock_source = Path(args.mock_video).expanduser().resolve()
        extension = mock_source.suffix or extension
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_stem = "mock_capture" if args.mock_video else "capture"
    output_path = output_dir / f"{slugify(args.match_key)}__{output_stem}__{timestamp}{extension}"

    region = None
    profile_saved_path = None
    if args.profile_name and not args.mock_video and not args.region and not args.select_region:
        region = load_profile(profiles_dir, args.profile_name)

    if args.mock_video:
        if args.profile_name and args.region:
            region = {
                "left": int(args.region[0]),
                "top": int(args.region[1]),
                "width": int(args.region[2]),
                "height": int(args.region[3]),
                "monitor": int(args.monitor),
            }
        elif args.profile_name and not region and profiles_dir.exists():
            try:
                region = load_profile(profiles_dir, args.profile_name)
            except FileNotFoundError:
                region = None
        if args.profile_name and args.save_profile and region is not None:
            profile_saved_path = save_profile(profiles_dir, args.profile_name, region)
            print(f"Saved capture profile: {profile_saved_path}")
        try:
            capture_summary = import_mock_video(
                mock_video=mock_source,
                output_path=output_path,
            )
        except Exception:
            if output_path.exists():
                output_path.unlink(missing_ok=True)
            raise
    else:
        mss_module = load_mss()
        if region is None:
            region = resolve_region(
                mss_module=mss_module,
                monitor_index=args.monitor,
                region_args=args.region,
                select_region=args.select_region,
            )

        if args.profile_name and (args.save_profile or args.save_profile_only):
            profile_saved_path = save_profile(profiles_dir, args.profile_name, region)
            print(f"Saved capture profile: {profile_saved_path}")
            if args.save_profile_only:
                return

        try:
            capture_summary = record_capture(
                mss_module=mss_module,
                region=region,
                output_path=output_path,
                fps=float(args.fps),
                match_key=args.match_key,
                no_preview=bool(args.no_preview),
                window_scale=float(args.window_scale),
                max_seconds=float(args.max_seconds),
                quality_profile=args.quality_profile,
            )
        except Exception as exc:
            if output_path.exists():
                output_path.unlink(missing_ok=True)
            raise RuntimeError(
                "Screen capture failed. On Windows this usually means the desktop session is locked, "
                "the current session is non-interactive, or screen capture is blocked for this process. "
                "Run the capture from your unlocked local desktop session and try again."
            ) from exc

    manifest = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "match_key": args.match_key,
        "home_team": args.home_team,
        "away_team": args.away_team,
        "competition": args.competition,
        "kickoff_utc": args.kickoff_utc,
        "capture_type": "mock_local_video_import" if args.mock_video else "local_screen_region",
        "quality_profile": args.quality_profile,
        "codec_requested": codec_name,
        "video_file": str(output_path),
        "profile_name": args.profile_name,
        "profile_path": str(profile_path(profiles_dir, args.profile_name)) if args.profile_name else "",
        "region": region,
        "capture_summary": capture_summary,
    }
    manifest_path = output_path.with_suffix(output_path.suffix + ".json")
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    register_capture(
        output_path=output_path,
        match_key=args.match_key,
        home_team=args.home_team,
        away_team=args.away_team,
        competition=args.competition,
        kickoff_utc=args.kickoff_utc,
        launch_tagger=args.launch_tagger,
        skip_previews=args.skip_previews,
    )

    print(f"Captured video: {output_path}")
    print(f"Capture manifest: {manifest_path}")


if __name__ == "__main__":
    main()
