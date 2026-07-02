from __future__ import annotations

import argparse
import json
from pathlib import Path


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a local JSON preset template for the film-study video tagger."
    )
    parser.add_argument("--match-key", required=True, help="Stable match identifier.")
    parser.add_argument("--home-team", required=True, help="Home team label.")
    parser.add_argument("--away-team", required=True, help="Away team label.")
    parser.add_argument(
        "--output-dir",
        default=str(repo_root() / "data" / "private" / "tagger_presets"),
        help="Directory where the preset JSON should be written.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{slugify(args.match_key)}.json"

    payload = {
        "match_key": args.match_key,
        "home_team": args.home_team,
        "away_team": args.away_team,
        "notes": "Blank values fall back to the last tagged value during the session. Use 'h' or 'a' in the Team prompt for home or away.",
        "event_defaults": {
            "shot": {"team": args.home_team, "outcome": "on_target"},
            "goal": {"team": args.home_team, "outcome": "goal"},
            "pass": {"team": args.home_team, "outcome": "complete"},
            "attack_entry": {"team": args.home_team, "outcome": "box_entry"},
            "turnover": {"team": args.away_team, "outcome": "won_ball"},
            "save": {"team": args.away_team, "outcome": "saved"},
            "foul": {"outcome": "foul"},
            "yellow_card": {"outcome": "booked"},
            "red_card": {"outcome": "sent_off"}
        }
    }

    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote preset template: {output_path}")


if __name__ == "__main__":
    main()
