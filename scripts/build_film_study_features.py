from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd


ATTACKING_EVENTS = {"pass", "attack_entry", "shot", "goal"}
DISCIPLINE_EVENTS = {"foul", "yellow_card", "red_card"}
TERMINAL_EVENTS = {"goal", "turnover", "save", "red_card"}
PITCH_GRID_COLS = 12
PITCH_GRID_ROWS = 8
PITCH_FILES = "ABCDEFGHIJKL"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def safe_numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def clamp_pct(value: float) -> float:
    if pd.isna(value):
        return np.nan
    return float(np.clip(value, 0.0, 100.0))


def assign_x_zone(x_pct: float) -> str:
    if pd.isna(x_pct):
        return "unknown"
    if x_pct < 33.333:
        return "defensive_third"
    if x_pct < 66.667:
        return "middle_third"
    return "final_third"


def assign_y_lane(y_pct: float) -> str:
    if pd.isna(y_pct):
        return "unknown"
    if y_pct < 33.333:
        return "left_lane"
    if y_pct < 66.667:
        return "center_lane"
    return "right_lane"


def assign_pitch_col(x_pct: float, cols: int = PITCH_GRID_COLS) -> float:
    if pd.isna(x_pct):
        return np.nan
    value = clamp_pct(x_pct)
    return min(cols, max(1, int(np.floor((value / 100.0) * cols)) + 1))


def assign_pitch_row(y_pct: float, rows: int = PITCH_GRID_ROWS) -> float:
    if pd.isna(y_pct):
        return np.nan
    value = clamp_pct(y_pct)
    return min(rows, max(1, int(np.floor((value / 100.0) * rows)) + 1))


def assign_pitch_cell(x_pct: float, y_pct: float) -> str:
    col = assign_pitch_col(x_pct)
    row = assign_pitch_row(y_pct)
    if pd.isna(col) or pd.isna(row):
        return "unknown"
    return f"C{int(col):02d}_R{int(row):02d}"


def assign_pitch_file(col: float) -> str:
    if pd.isna(col):
        return "unknown"
    index = int(col) - 1
    if index < 0 or index >= len(PITCH_FILES):
        return "unknown"
    return PITCH_FILES[index]


def assign_pitch_rank(row: float, rows: int = PITCH_GRID_ROWS) -> float:
    if pd.isna(row):
        return np.nan
    return (rows - int(row)) + 1


def assign_pitch_board_cell(col: float, row: float) -> str:
    file_label = assign_pitch_file(col)
    rank_value = assign_pitch_rank(row)
    if file_label == "unknown" or pd.isna(rank_value):
        return "unknown"
    return f"{file_label}{int(rank_value)}"


def movement_direction(delta_x: float, delta_y: float) -> str:
    if pd.isna(delta_x) or pd.isna(delta_y):
        return "unknown"
    if abs(delta_x) < 2 and abs(delta_y) < 2:
        return "stationary"
    horizontal = "forward" if delta_x > 0 else "backward"
    if abs(delta_y) < 5:
        return horizontal
    vertical = "right" if delta_y > 0 else "left"
    return f"{horizontal}_{vertical}"


def signed_int(value: float) -> str:
    if pd.isna(value):
        return "NA"
    return f"{int(value):+d}"


def transition_vector(delta_col: float, delta_row: float) -> str:
    if pd.isna(delta_col) or pd.isna(delta_row):
        return "unknown"
    return f"dc{signed_int(delta_col)}_dr{signed_int(delta_row)}"


def transition_shape(delta_col: float, delta_row: float) -> str:
    if pd.isna(delta_col) or pd.isna(delta_row):
        return "unknown"
    abs_col = abs(int(delta_col))
    abs_row = abs(int(delta_row))
    if abs_col == 0 and abs_row == 0:
        return "same_cell"
    if abs_col <= 1 and abs_row <= 1:
        return "adjacent_step"
    if abs_col >= 3 and abs_row == 0:
        return "long_forward_or_back_jump"
    if abs_col == 0 and abs_row >= 2:
        return "lane_switch"
    if abs_col >= 2 and abs_row >= 2:
        return "diagonal_jump"
    return "multi_cell_shift"


def event_group(event_type: str) -> str:
    if event_type in ATTACKING_EVENTS:
        return "attack"
    if event_type in DISCIPLINE_EVENTS:
        return "discipline"
    if event_type in {"save", "defensive_action"}:
        return "defense"
    if event_type == "turnover":
        return "transition"
    if event_type == "note":
        return "note"
    return "other"


def load_events(input_path: Path) -> pd.DataFrame:
    events = pd.read_csv(input_path)
    if events.empty:
        return events

    events["time_seconds"] = safe_numeric(events["time_seconds"])
    events["frame_index"] = safe_numeric(events["frame_index"])
    events["x_pct"] = safe_numeric(events["x_pct"])
    events["y_pct"] = safe_numeric(events["y_pct"])
    events["event_type"] = events["event_type"].fillna("unknown").astype(str)
    events["team"] = events["team"].fillna("").astype(str).str.strip()
    events["player"] = events["player"].fillna("").astype(str).str.strip()
    events["outcome"] = events["outcome"].fillna("").astype(str).str.strip()
    events["notes"] = events["notes"].fillna("").astype(str)

    events = events.sort_values(
        ["match_key", "time_seconds", "frame_index", "recorded_at_utc"],
        na_position="last",
    ).reset_index(drop=True)

    return events


def enrich_events(events: pd.DataFrame) -> pd.DataFrame:
    enriched = events.copy()
    if enriched.empty:
        return enriched

    enriched["event_index"] = enriched.groupby("match_key").cumcount() + 1
    enriched["seconds_since_prev_event"] = (
        enriched.groupby("match_key")["time_seconds"].diff().fillna(0.0)
    )
    enriched["event_group"] = enriched["event_type"].map(event_group)
    enriched["x_zone"] = enriched["x_pct"].map(assign_x_zone)
    enriched["y_lane"] = enriched["y_pct"].map(assign_y_lane)
    enriched["pitch_col_12"] = enriched["x_pct"].map(assign_pitch_col)
    enriched["pitch_row_8"] = enriched["y_pct"].map(assign_pitch_row)
    enriched["pitch_file_12"] = enriched["pitch_col_12"].map(assign_pitch_file)
    enriched["pitch_rank_8"] = enriched["pitch_row_8"].map(assign_pitch_rank)
    enriched["pitch_cell_12x8"] = [
        assign_pitch_cell(x, y) for x, y in zip(enriched["x_pct"], enriched["y_pct"])
    ]
    enriched["pitch_board_cell"] = [
        assign_pitch_board_cell(col, row)
        for col, row in zip(enriched["pitch_col_12"], enriched["pitch_row_8"])
    ]
    enriched["is_shot"] = enriched["event_type"].isin({"shot", "goal"})
    enriched["is_goal"] = enriched["event_type"].eq("goal")
    enriched["is_card"] = enriched["event_type"].isin({"yellow_card", "red_card"})
    enriched["is_attacking_event"] = enriched["event_type"].isin(ATTACKING_EVENTS)
    enriched["is_terminal_event"] = enriched["event_type"].isin(TERMINAL_EVENTS)
    enriched["is_on_target"] = enriched["outcome"].str.lower().isin(
        {"on_target", "goal", "saved"}
    )
    enriched["team_clean"] = enriched["team"].replace("", pd.NA)

    previous_team = enriched.groupby("match_key")["team_clean"].shift(1)
    previous_event = enriched.groupby("match_key")["event_type"].shift(1)
    previous_gap = enriched.groupby("match_key")["time_seconds"].diff().fillna(0.0)

    team_changed = (
        previous_team.notna()
        & enriched["team_clean"].notna()
        & (enriched["team_clean"] != previous_team)
    )
    long_gap = previous_gap >= 25
    forced_new = previous_event.isin(TERMINAL_EVENTS)

    possession_start = (
        enriched["event_index"].eq(1)
        | team_changed
        | long_gap
        | forced_new.fillna(False)
    )
    enriched["possession_id"] = possession_start.groupby(enriched["match_key"]).cumsum()
    enriched["team_inferred"] = enriched["team_clean"].groupby(enriched["match_key"]).ffill().fillna("Unknown")
    enriched["next_event_type"] = enriched.groupby("match_key")["event_type"].shift(-1).fillna("END")
    enriched["next_team_inferred"] = (
        enriched.groupby("match_key")["team_inferred"].shift(-1).fillna("END")
    )
    enriched["next_x_pct"] = enriched.groupby("match_key")["x_pct"].shift(-1)
    enriched["next_y_pct"] = enriched.groupby("match_key")["y_pct"].shift(-1)
    enriched["next_pitch_col_12"] = enriched.groupby("match_key")["pitch_col_12"].shift(-1)
    enriched["next_pitch_row_8"] = enriched.groupby("match_key")["pitch_row_8"].shift(-1)
    enriched["next_pitch_cell_12x8"] = (
        enriched.groupby("match_key")["pitch_cell_12x8"].shift(-1).fillna("END")
    )
    enriched["next_pitch_board_cell"] = (
        enriched.groupby("match_key")["pitch_board_cell"].shift(-1).fillna("END")
    )
    enriched["delta_x_pct"] = enriched["next_x_pct"] - enriched["x_pct"]
    enriched["delta_y_pct"] = enriched["next_y_pct"] - enriched["y_pct"]
    enriched["delta_col_12"] = enriched["next_pitch_col_12"] - enriched["pitch_col_12"]
    enriched["delta_row_8"] = enriched["next_pitch_row_8"] - enriched["pitch_row_8"]
    enriched["move_distance_pct"] = np.sqrt(
        np.square(enriched["delta_x_pct"]) + np.square(enriched["delta_y_pct"])
    )
    enriched["manhattan_cell_distance"] = (
        enriched["delta_col_12"].abs() + enriched["delta_row_8"].abs()
    )
    enriched["chebyshev_cell_distance"] = enriched[["delta_col_12", "delta_row_8"]].abs().max(axis=1)
    enriched["movement_direction"] = [
        movement_direction(dx, dy)
        for dx, dy in zip(enriched["delta_x_pct"], enriched["delta_y_pct"])
    ]
    enriched["transition_vector_12x8"] = [
        transition_vector(dc, dr)
        for dc, dr in zip(enriched["delta_col_12"], enriched["delta_row_8"])
    ]
    enriched["transition_shape"] = [
        transition_shape(dc, dr)
        for dc, dr in zip(enriched["delta_col_12"], enriched["delta_row_8"])
    ]
    enriched["same_cell_transition"] = (
        enriched["delta_col_12"].fillna(999).eq(0) & enriched["delta_row_8"].fillna(999).eq(0)
    )
    enriched["adjacent_cell_transition"] = (
        enriched["delta_col_12"].abs().fillna(999).le(1)
        & enriched["delta_row_8"].abs().fillna(999).le(1)
        & ~enriched["same_cell_transition"]
    )
    enriched["forward_cell_progress"] = enriched["delta_col_12"].fillna(0)
    enriched["lateral_cell_shift"] = enriched["delta_row_8"].fillna(0)
    enriched["progressive_forward_move"] = enriched["delta_x_pct"].fillna(0).ge(8)
    enriched["entered_final_third_next"] = (
        enriched["x_zone"].ne("final_third")
        & enriched.groupby("match_key")["x_zone"].shift(-1).fillna("END").eq("final_third")
    )
    return enriched


def build_possessions(enriched: pd.DataFrame) -> pd.DataFrame:
    if enriched.empty:
        return pd.DataFrame()

    grouped = enriched.groupby(["match_key", "possession_id"], dropna=False)
    possessions = grouped.agg(
        home_team=("home_team", "first"),
        away_team=("away_team", "first"),
        team_inferred=("team_inferred", "first"),
        possession_start_seconds=("time_seconds", "min"),
        possession_end_seconds=("time_seconds", "max"),
        possession_events=("event_type", "size"),
        shots=("is_shot", "sum"),
        goals=("is_goal", "sum"),
        passes=("event_type", lambda s: int((s == "pass").sum())),
        attack_entries=("event_type", lambda s: int((s == "attack_entry").sum())),
        turnovers=("event_type", lambda s: int((s == "turnover").sum())),
        fouls=("event_type", lambda s: int((s == "foul").sum())),
        cards=("is_card", "sum"),
        notes_logged=("event_type", lambda s: int((s == "note").sum())),
        first_x_zone=("x_zone", "first"),
        last_x_zone=("x_zone", "last"),
        first_y_lane=("y_lane", "first"),
        last_y_lane=("y_lane", "last"),
        first_pitch_cell=("pitch_cell_12x8", "first"),
        last_pitch_cell=("pitch_cell_12x8", "last"),
        first_pitch_board_cell=("pitch_board_cell", "first"),
        last_pitch_board_cell=("pitch_board_cell", "last"),
        avg_move_distance_pct=("move_distance_pct", "mean"),
        avg_manhattan_cell_distance=("manhattan_cell_distance", "mean"),
        avg_chebyshev_cell_distance=("chebyshev_cell_distance", "mean"),
        progressive_forward_moves=("progressive_forward_move", "sum"),
        adjacent_steps=("adjacent_cell_transition", "sum"),
        same_cell_repeats=("same_cell_transition", "sum"),
        forward_cell_progress_sum=("forward_cell_progress", "sum"),
    ).reset_index()

    possessions["possession_duration_seconds"] = (
        possessions["possession_end_seconds"] - possessions["possession_start_seconds"]
    ).clip(lower=0.0)
    possessions["shot_rate_per_event"] = np.where(
        possessions["possession_events"] > 0,
        possessions["shots"] / possessions["possession_events"],
        np.nan,
    )
    return possessions


def build_match_features(enriched: pd.DataFrame, possessions: pd.DataFrame) -> pd.DataFrame:
    if enriched.empty:
        return pd.DataFrame()

    match_features = enriched.groupby("match_key", dropna=False).agg(
        home_team=("home_team", "first"),
        away_team=("away_team", "first"),
        tagged_events=("event_type", "size"),
        unique_players_tagged=("player", lambda s: int(s.replace("", pd.NA).dropna().nunique())),
        unique_teams_tagged=("team_inferred", "nunique"),
        tagged_shots=("is_shot", "sum"),
        tagged_goals=("is_goal", "sum"),
        shots_on_target=("is_on_target", "sum"),
        tagged_cards=("is_card", "sum"),
        tagged_fouls=("event_type", lambda s: int((s == "foul").sum())),
        tagged_turnovers=("event_type", lambda s: int((s == "turnover").sum())),
        tagged_notes=("event_type", lambda s: int((s == "note").sum())),
        avg_seconds_between_events=("seconds_since_prev_event", "mean"),
        median_seconds_between_events=("seconds_since_prev_event", "median"),
    ).reset_index()

    if not possessions.empty:
        possession_features = possessions.groupby("match_key", dropna=False).agg(
            tagged_possessions=("possession_id", "nunique"),
            avg_possession_seconds=("possession_duration_seconds", "mean"),
            median_possession_seconds=("possession_duration_seconds", "median"),
            max_possession_seconds=("possession_duration_seconds", "max"),
            avg_events_per_possession=("possession_events", "mean"),
            max_events_in_possession=("possession_events", "max"),
        ).reset_index()
        match_features = match_features.merge(possession_features, on="match_key", how="left")

    return match_features


def build_zone_summary(enriched: pd.DataFrame) -> pd.DataFrame:
    if enriched.empty:
        return pd.DataFrame()
    zone_summary = (
        enriched.groupby(["match_key", "team_inferred", "x_zone", "y_lane"], dropna=False)
        .agg(events=("event_type", "size"), shots=("is_shot", "sum"), goals=("is_goal", "sum"))
        .reset_index()
    )
    return zone_summary


def build_transition_summary(enriched: pd.DataFrame) -> pd.DataFrame:
    if enriched.empty:
        return pd.DataFrame()
    transitions = (
        enriched.groupby(
            ["match_key", "team_inferred", "event_type", "next_event_type"],
            dropna=False,
        )
        .size()
        .reset_index(name="transition_count")
    )
    totals = transitions.groupby(["match_key", "team_inferred", "event_type"])["transition_count"].transform("sum")
    transitions["transition_rate"] = np.where(
        totals > 0,
        transitions["transition_count"] / totals,
        np.nan,
    )
    return transitions


def build_grid_transition_summary(enriched: pd.DataFrame) -> pd.DataFrame:
    if enriched.empty:
        return pd.DataFrame()

    grid_rows = enriched[enriched["next_pitch_cell_12x8"].ne("END")].copy()
    if grid_rows.empty:
        return pd.DataFrame()

    transitions = (
        grid_rows.groupby(
            [
                "match_key",
                "team_inferred",
                "pitch_cell_12x8",
                "pitch_board_cell",
                "next_pitch_cell_12x8",
                "next_pitch_board_cell",
                "movement_direction",
                "transition_vector_12x8",
                "transition_shape",
            ],
            dropna=False,
        )
        .agg(
            transition_count=("event_type", "size"),
            avg_move_distance_pct=("move_distance_pct", "mean"),
            avg_manhattan_cell_distance=("manhattan_cell_distance", "mean"),
            goals_from_origin=("is_goal", "sum"),
            shots_from_origin=("is_shot", "sum"),
            progressive_moves=("progressive_forward_move", "sum"),
        )
        .reset_index()
    )
    totals = transitions.groupby(
        ["match_key", "team_inferred", "pitch_cell_12x8", "pitch_board_cell"]
    )["transition_count"].transform("sum")
    transitions["transition_rate_from_cell"] = np.where(
        totals > 0,
        transitions["transition_count"] / totals,
        np.nan,
    )
    return transitions.sort_values(
        [
            "match_key",
            "team_inferred",
            "pitch_cell_12x8",
            "transition_rate_from_cell",
            "transition_count",
        ],
        ascending=[True, True, True, False, False],
    ).reset_index(drop=True)


def write_outputs(output_dir: Path, outputs: dict[str, pd.DataFrame]) -> dict[str, str]:
    output_paths: dict[str, str] = {}
    for name, frame in outputs.items():
        path = output_dir / f"{name}.csv"
        frame.to_csv(path, index=False)
        output_paths[name] = str(path)
    return output_paths


def build_data_dictionary() -> pd.DataFrame:
    rows = [
        ("film_study_tags", "match_key", "Stable identifier for the reviewed match."),
        ("film_study_tags", "event_type", "Tagged football event chosen during review."),
        ("film_study_tags", "team", "Team manually assigned during tagging."),
        ("film_study_tags", "player", "Player manually assigned during tagging."),
        ("film_study_tags", "outcome", "Reviewer-entered result such as complete, saved, or goal."),
        ("film_study_tags", "time_seconds", "Video time in seconds at the tag moment."),
        ("film_study_tags", "x_pct", "Screen-relative horizontal click percentage."),
        ("film_study_tags", "y_pct", "Screen-relative vertical click percentage."),
        ("film_study_events_enriched", "event_index", "Sequential event number within each match."),
        ("film_study_events_enriched", "seconds_since_prev_event", "Gap from the previous tagged event in seconds."),
        ("film_study_events_enriched", "event_group", "Broad event family: attack, defense, discipline, transition, note, or other."),
        ("film_study_events_enriched", "x_zone", "Horizontal zone bucket derived from x_pct."),
        ("film_study_events_enriched", "y_lane", "Vertical lane bucket derived from y_pct."),
        ("film_study_events_enriched", "pitch_col_12", "Column index on a 12-column pitch grid."),
        ("film_study_events_enriched", "pitch_row_8", "Row index on an 8-row pitch grid."),
        ("film_study_events_enriched", "pitch_file_12", "Board-style file label from A to L for the 12-column review grid."),
        ("film_study_events_enriched", "pitch_rank_8", "Board-style rank label from 1 to 8 for the 8-row review grid."),
        ("film_study_events_enriched", "pitch_cell_12x8", "Current pitch cell ID on the 12x8 review grid."),
        ("film_study_events_enriched", "pitch_board_cell", "Board-style pitch cell label such as A8 or L1."),
        ("film_study_events_enriched", "next_pitch_cell_12x8", "Next tagged event's pitch cell on the 12x8 grid."),
        ("film_study_events_enriched", "next_pitch_board_cell", "Board-style label for the next tagged event cell."),
        ("film_study_events_enriched", "delta_x_pct", "Horizontal movement from current event to next tagged event, in percentage points."),
        ("film_study_events_enriched", "delta_y_pct", "Vertical movement from current event to next tagged event, in percentage points."),
        ("film_study_events_enriched", "delta_col_12", "Movement to the next tagged event measured in grid columns."),
        ("film_study_events_enriched", "delta_row_8", "Movement to the next tagged event measured in grid rows."),
        ("film_study_events_enriched", "move_distance_pct", "Euclidean movement distance from current event to next tagged event, in screen-percentage units."),
        ("film_study_events_enriched", "manhattan_cell_distance", "Grid distance to the next tagged event using row-plus-column steps."),
        ("film_study_events_enriched", "chebyshev_cell_distance", "Grid distance to the next tagged event using the maximum row or column step."),
        ("film_study_events_enriched", "movement_direction", "Simplified direction bucket from current event to next tagged event."),
        ("film_study_events_enriched", "transition_vector_12x8", "Signed row and column step notation between consecutive tagged events."),
        ("film_study_events_enriched", "transition_shape", "Board-move bucket such as adjacent step, lane switch, or diagonal jump."),
        ("film_study_events_enriched", "same_cell_transition", "Indicator that consecutive tagged events stayed in the same grid cell."),
        ("film_study_events_enriched", "adjacent_cell_transition", "Indicator that the next tagged event moved to one of the neighboring cells."),
        ("film_study_events_enriched", "forward_cell_progress", "Signed grid-column progress to the next tagged event."),
        ("film_study_events_enriched", "lateral_cell_shift", "Signed grid-row shift to the next tagged event."),
        ("film_study_events_enriched", "progressive_forward_move", "Indicator that the next tagged action advanced at least 8 horizontal percentage points."),
        ("film_study_events_enriched", "entered_final_third_next", "Indicator that the next tagged event entered the final third from an earlier third."),
        ("film_study_events_enriched", "possession_id", "Heuristic possession segment identifier."),
        ("film_study_events_enriched", "team_inferred", "Tagged or forward-filled team label used for sequence summaries."),
        ("film_study_possessions", "possession_duration_seconds", "Elapsed time from the first to last tagged event in the possession."),
        ("film_study_possessions", "possession_events", "Number of tagged events inside the possession."),
        ("film_study_possessions", "shot_rate_per_event", "Shots divided by tagged events inside the possession."),
        ("film_study_possessions", "first_pitch_cell", "Starting pitch cell of the heuristic possession."),
        ("film_study_possessions", "last_pitch_cell", "Ending pitch cell of the heuristic possession."),
        ("film_study_possessions", "first_pitch_board_cell", "Board-style starting cell of the heuristic possession."),
        ("film_study_possessions", "last_pitch_board_cell", "Board-style ending cell of the heuristic possession."),
        ("film_study_possessions", "avg_move_distance_pct", "Average tagged movement distance inside the possession."),
        ("film_study_possessions", "avg_manhattan_cell_distance", "Average row-plus-column grid distance per tagged move in the possession."),
        ("film_study_possessions", "avg_chebyshev_cell_distance", "Average king-style grid distance per tagged move in the possession."),
        ("film_study_possessions", "progressive_forward_moves", "Count of forward jumps of at least 8 horizontal percentage points inside the possession."),
        ("film_study_possessions", "adjacent_steps", "Count of one-cell moves inside the possession."),
        ("film_study_possessions", "same_cell_repeats", "Count of repeated tags inside the same grid cell."),
        ("film_study_possessions", "forward_cell_progress_sum", "Net grid-column progress across the possession."),
        ("film_study_match_features", "tagged_events", "Total tagged events for the match."),
        ("film_study_match_features", "tagged_possessions", "Number of heuristic possessions in the reviewed match."),
        ("film_study_match_features", "avg_possession_seconds", "Average heuristic possession duration in seconds."),
        ("film_study_match_features", "avg_events_per_possession", "Average number of tagged events per possession."),
        ("film_study_zone_summary", "events", "Count of tagged events in the zone/lane bucket."),
        ("film_study_zone_summary", "shots", "Count of tagged shot or goal events in the zone/lane bucket."),
        ("film_study_event_transitions", "next_event_type", "Next tagged event after the current event type."),
        ("film_study_event_transitions", "transition_count", "Observed number of event-to-event transitions."),
        ("film_study_event_transitions", "transition_rate", "Transition share from the current event type to the next one."),
        ("film_study_grid_transitions", "pitch_board_cell", "Board-style origin cell for the observed move."),
        ("film_study_grid_transitions", "next_pitch_board_cell", "Board-style destination cell for the observed move."),
        ("film_study_grid_transitions", "transition_vector_12x8", "Signed row and column step between observed origin and destination cells."),
        ("film_study_grid_transitions", "transition_shape", "Board-move bucket describing the size and style of the transition."),
        ("film_study_grid_transitions", "transition_rate_from_cell", "Observed share of departures from the origin cell that used this move."),
    ]
    return pd.DataFrame(rows, columns=["dataset", "column_name", "description"])


def main() -> None:
    root = repo_root()
    input_path = root / "data" / "processed" / "film_study" / "film_study_tags.csv"
    output_dir = root / "data" / "processed" / "film_study"
    output_dir.mkdir(parents=True, exist_ok=True)

    if not input_path.exists():
        raise FileNotFoundError(f"Expected combined film-study tags at {input_path}")

    events = load_events(input_path)
    enriched = enrich_events(events)
    possessions = build_possessions(enriched)
    match_features = build_match_features(enriched, possessions)
    zone_summary = build_zone_summary(enriched)
    transition_summary = build_transition_summary(enriched)
    grid_transition_summary = build_grid_transition_summary(enriched)

    outputs = {
        "film_study_events_enriched": enriched,
        "film_study_possessions": possessions,
        "film_study_match_features": match_features,
        "film_study_zone_summary": zone_summary,
        "film_study_event_transitions": transition_summary,
        "film_study_grid_transitions": grid_transition_summary,
    }
    output_paths = write_outputs(output_dir, outputs)
    dictionary_path = output_dir / "film_study_data_dictionary.csv"
    build_data_dictionary().to_csv(dictionary_path, index=False)

    metadata = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_csv": str(input_path),
        "outputs": output_paths,
        "data_dictionary_csv": str(dictionary_path),
        "row_counts": {name: int(len(frame)) for name, frame in outputs.items()},
        "heuristics": {
            "possession_breaks": [
                "first event in match",
                "tagged team changes",
                "25-second or longer event gap",
                "previous event was goal, turnover, save, or red card",
            ],
            "x_zone_definition": "defensive_third < 33.333, middle_third < 66.667, else final_third",
            "y_lane_definition": "left_lane < 33.333, center_lane < 66.667, else right_lane",
            "pitch_grid_definition": "12 columns by 8 rows built from screen-relative x_pct and y_pct.",
            "board_coordinate_note": "Board-style cells use files A-L from left to right and ranks 8-1 from top to bottom so each tag can be treated like a move on a larger board.",
            "directionality_note": "x and y are screen-relative click positions and do not infer team attacking direction unless you tag consistently.",
        },
    }

    metadata_path = output_dir / "film_study_feature_metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    for path in output_paths.values():
        print(f"Wrote {path}")
    print(f"Wrote {dictionary_path}")
    print(f"Wrote {metadata_path}")


if __name__ == "__main__":
    main()
