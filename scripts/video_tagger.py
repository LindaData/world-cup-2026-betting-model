from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import cv2


EVENT_KEYMAP = {
    ord("g"): "goal",
    ord("s"): "shot",
    ord("p"): "pass",
    ord("a"): "attack_entry",
    ord("t"): "turnover",
    ord("f"): "foul",
    ord("y"): "yellow_card",
    ord("r"): "red_card",
    ord("x"): "save",
    ord("d"): "defensive_action",
    ord("n"): "note",
}

ARROW_LEFT = 2424832
ARROW_RIGHT = 2555904


@dataclass
class PlaybackState:
    playing: bool = False
    last_click_x_pct: Optional[float] = None
    last_click_y_pct: Optional[float] = None


@dataclass
class TagContext:
    home_team: str
    away_team: str
    last_team: str = ""
    last_player: str = ""
    last_outcome: str = ""


def default_preset_path(match_key: str) -> Path:
    return repo_root() / "data" / "private" / "tagger_presets" / f"{slugify(match_key)}.json"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def to_clock(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


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


def prompt(label: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    response = input(f"{label}{suffix}: ").strip()
    return response if response else default


def load_preset_file(path: Optional[str]) -> dict:
    if not path:
        return {}
    preset_path = Path(path).expanduser().resolve()
    if not preset_path.exists():
        raise FileNotFoundError(f"Preset file not found: {preset_path}")
    with preset_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_team_value(team_value: str, context: TagContext) -> str:
    clean = team_value.strip()
    if not clean:
        return clean
    lowered = clean.lower()
    if lowered in {"h", "home"}:
        return context.home_team
    if lowered in {"a", "away"}:
        return context.away_team
    return clean


def event_defaults(event_type: str, presets: dict) -> dict:
    defaults = (presets.get("event_defaults") or {}).get(event_type, {})
    return defaults if isinstance(defaults, dict) else {}


def append_csv_row(output_path: Path, row: dict[str, object]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(row.keys())
    write_header = not output_path.exists()
    with output_path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def seek_to_seconds(
    capture: cv2.VideoCapture,
    target_seconds: float,
    fps: float,
    frame_count: int,
) -> float:
    safe_seconds = max(0.0, target_seconds)
    if fps > 0 and frame_count > 0:
        max_seconds = max(0.0, (frame_count - 1) / fps)
        safe_seconds = min(safe_seconds, max_seconds)
    capture.set(cv2.CAP_PROP_POS_MSEC, safe_seconds * 1000.0)
    return safe_seconds


def add_overlay(
    frame,
    state: PlaybackState,
    match_label: str,
    clock: str,
    tag_count: int,
    status_text: str,
) -> None:
    overlay_lines = [
        match_label,
        f"{'PLAY' if state.playing else 'PAUSE'}  |  {clock}  |  Tags: {tag_count}",
        "Space play/pause | Left/Right +/-5s | J/L +/-1s | U/O +/-30s",
        "Click pitch area to store x,y | G goal | S shot | P pass | A attack | T turnover",
        "F foul | Y yellow | R red | X save | D defense | N note | Q quit",
    ]

    y = 28
    for line in overlay_lines:
        cv2.putText(
            frame,
            line,
            (12, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (18, 23, 28),
            3,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            line,
            (12, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (245, 247, 250),
            1,
            cv2.LINE_AA,
        )
        y += 22

    if state.last_click_x_pct is not None and state.last_click_y_pct is not None:
        click_text = f"Last click: x={state.last_click_x_pct:.1f}, y={state.last_click_y_pct:.1f}"
        cv2.putText(
            frame,
            click_text,
            (12, y + 4),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (18, 23, 28),
            3,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            click_text,
            (12, y + 4),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (94, 234, 212),
            1,
            cv2.LINE_AA,
        )

    if status_text:
        cv2.putText(
            frame,
            status_text,
            (12, frame.shape[0] - 18),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.58,
            (18, 23, 28),
            3,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            status_text,
            (12, frame.shape[0] - 18),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.58,
            (255, 214, 102),
            1,
            cv2.LINE_AA,
        )


def build_row(
    *,
    event_type: str,
    match_key: str,
    context: TagContext,
    video_path: Path,
    time_seconds: float,
    frame_index: int,
    state: PlaybackState,
    presets: dict,
) -> dict[str, object]:
    print("")
    print(f"Tagging '{event_type}' at {to_clock(time_seconds)}")
    defaults = event_defaults(event_type, presets)
    team_default = defaults.get("team", context.last_team)
    player_default = defaults.get("player", context.last_player)
    outcome_default = defaults.get("outcome", context.last_outcome)

    team_value = resolve_team_value(prompt("Team (h/a allowed)", team_default), context)
    player_value = prompt("Player", player_default)
    outcome_value = prompt("Outcome", outcome_default)
    note_value = prompt("Notes", "")

    if team_value:
        context.last_team = team_value
    if player_value:
        context.last_player = player_value
    if outcome_value:
        context.last_outcome = outcome_value

    return {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "match_key": match_key,
        "home_team": context.home_team,
        "away_team": context.away_team,
        "video_file": str(video_path),
        "event_type": event_type,
        "team": team_value,
        "player": player_value,
        "outcome": outcome_value,
        "time_seconds": round(time_seconds, 3),
        "clock": to_clock(time_seconds),
        "frame_index": frame_index,
        "x_pct": state.last_click_x_pct,
        "y_pct": state.last_click_y_pct,
        "notes": note_value,
    }


def parse_args() -> argparse.Namespace:
    default_output_dir = repo_root() / "data" / "private" / "film_tags"

    parser = argparse.ArgumentParser(
        description="Local keyboard-driven video tagger for film study on user-supplied video files."
    )
    parser.add_argument("--video", required=True, help="Path to a local video file.")
    parser.add_argument("--match-key", required=True, help="Stable match identifier for outputs.")
    parser.add_argument("--home-team", required=True, help="Home team label.")
    parser.add_argument("--away-team", required=True, help="Away team label.")
    parser.add_argument(
        "--output-dir",
        default=str(default_output_dir),
        help="Folder where tag CSVs should be written.",
    )
    parser.add_argument(
        "--scale-width",
        type=int,
        default=1280,
        help="Resize display width for the OpenCV player window.",
    )
    parser.add_argument(
        "--seek-short-seconds",
        type=float,
        default=5.0,
        help="Short seek interval.",
    )
    parser.add_argument(
        "--seek-long-seconds",
        type=float,
        default=30.0,
        help="Long seek interval.",
    )
    parser.add_argument(
        "--start-playing",
        action="store_true",
        help="Start playback immediately instead of paused.",
    )
    parser.add_argument(
        "--preset-file",
        default="",
        help="Optional JSON preset file for event defaults.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    video_path = Path(args.video).expanduser().resolve()
    if not video_path.exists():
        raise FileNotFoundError(f"Video file not found: {video_path}")

    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{slugify(args.match_key)}__film_tags.csv"
    preset_path = args.preset_file or str(default_preset_path(args.match_key))
    presets = load_preset_file(preset_path) if Path(preset_path).exists() else {}

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")

    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    tag_count = 0
    status_text = f"Writing tags to {output_path.name}"
    match_label = f"{args.home_team} vs {args.away_team}"
    state = PlaybackState(playing=args.start_playing)
    context = TagContext(home_team=args.home_team, away_team=args.away_team)

    window_name = "World Cup Film Study Tagger"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)

    def handle_click(event, x, y, _flags, _param):
        if event == cv2.EVENT_LBUTTONDOWN:
            width = max(1, current_frame_holder["frame"].shape[1])
            height = max(1, current_frame_holder["frame"].shape[0])
            state.last_click_x_pct = round((x / width) * 100.0, 2)
            state.last_click_y_pct = round((y / height) * 100.0, 2)

    current_frame_holder = {"frame": None}
    cv2.setMouseCallback(window_name, handle_click)

    last_frame = None
    while True:
        if state.playing or last_frame is None:
            ok, frame = capture.read()
            if not ok:
                state.playing = False
                capture.set(cv2.CAP_PROP_POS_FRAMES, max(frame_count - 1, 0))
                ok, frame = capture.read()
                if not ok:
                    break
            last_frame = frame
        else:
            frame = last_frame.copy()

        if args.scale_width and frame.shape[1] > args.scale_width:
            ratio = args.scale_width / frame.shape[1]
            frame = cv2.resize(frame, (args.scale_width, int(frame.shape[0] * ratio)))

        frame_index = int(capture.get(cv2.CAP_PROP_POS_FRAMES) or 0)
        time_seconds = float(capture.get(cv2.CAP_PROP_POS_MSEC) or 0.0) / 1000.0
        current_frame_holder["frame"] = frame

        display_frame = frame.copy()
        add_overlay(
            display_frame,
            state=state,
            match_label=match_label,
            clock=to_clock(time_seconds),
            tag_count=tag_count,
            status_text=status_text,
        )
        cv2.imshow(window_name, display_frame)

        wait_ms = max(1, int(1000 / fps)) if state.playing else 0
        key = cv2.waitKeyEx(wait_ms)

        if key == -1:
            continue

        lower_key = key
        if 65 <= key <= 90:
            lower_key = ord(chr(key).lower())

        if lower_key in {ord("q"), 27}:
            break
        if lower_key == 32:
            state.playing = not state.playing
            status_text = "Playback resumed" if state.playing else "Playback paused"
            continue
        if lower_key == ord("j"):
            new_seconds = seek_to_seconds(
                capture,
                time_seconds - 1.0,
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if lower_key == ord("l"):
            new_seconds = seek_to_seconds(
                capture,
                time_seconds + 1.0,
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if lower_key == ord("u"):
            new_seconds = seek_to_seconds(
                capture,
                time_seconds - float(args.seek_long_seconds),
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if lower_key == ord("o"):
            new_seconds = seek_to_seconds(
                capture,
                time_seconds + float(args.seek_long_seconds),
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if key == ARROW_LEFT:
            new_seconds = seek_to_seconds(
                capture,
                time_seconds - float(args.seek_short_seconds),
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if key == ARROW_RIGHT:
            new_seconds = seek_to_seconds(
                capture,
                time_seconds + float(args.seek_short_seconds),
                fps=fps,
                frame_count=frame_count,
            )
            last_frame = None
            status_text = f"Moved to {to_clock(new_seconds)}"
            continue
        if lower_key in EVENT_KEYMAP:
            state.playing = False
            row = build_row(
                event_type=EVENT_KEYMAP[lower_key],
                match_key=args.match_key,
                context=context,
                video_path=video_path,
                time_seconds=time_seconds,
                frame_index=frame_index,
                state=state,
                presets=presets,
            )
            append_csv_row(output_path, row)
            tag_count += 1
            status_text = f"Saved {row['event_type']} at {row['clock']}"

    capture.release()
    cv2.destroyAllWindows()
    print("")
    print(f"Finished. Tags saved to: {output_path}")


if __name__ == "__main__":
    main()
