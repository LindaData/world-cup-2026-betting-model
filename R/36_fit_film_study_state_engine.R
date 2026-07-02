# Build a simple private soccer state engine from tagged film-study events.
#
# In RStudio:
# source("R/36_fit_film_study_state_engine.R")
# fit_film_study_state_engine()

find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "_quarto.yml"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root.")
    }
    current <- parent
  }
}

safe_read_csv <- function(path) {
  if (!file.exists(path)) {
    stop("Missing required file: ", path, call. = FALSE)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
}

coerce_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  tolower(as.character(x)) %in% c("true", "1", "t", "yes")
}

fit_film_study_state_engine <- function() {
  root <- find_project_root()
  processed_dir <- file.path(root, "data", "processed", "film_study")
  dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

  events <- safe_read_csv(file.path(processed_dir, "film_study_events_enriched.csv"))
  if (nrow(events) == 0) {
    stop("No film-study events are available yet.", call. = FALSE)
  }

  events$is_shot <- coerce_logical(events$is_shot)
  events$is_goal <- coerce_logical(events$is_goal)

  events <- events[order(events$match_key, events$event_index), ]
  events$state_event_group <- ifelse(nzchar(events$event_group), events$event_group, "unknown")
  events$state_x_zone <- ifelse(nzchar(events$x_zone), events$x_zone, "unknown")
  events$state_y_lane <- ifelse(nzchar(events$y_lane), events$y_lane, "unknown")
  if (!"pitch_cell_12x8" %in% names(events)) {
    fallback_col <- pmin(12, pmax(1, floor(pmax(0, pmin(100, events$x_pct)) / (100 / 12)) + 1))
    fallback_row <- pmin(8, pmax(1, floor(pmax(0, pmin(100, events$y_pct)) / (100 / 8)) + 1))
    events$pitch_cell_12x8 <- ifelse(
      is.na(fallback_col) | is.na(fallback_row),
      "unknown",
      sprintf("C%02d_R%02d", fallback_col, fallback_row)
    )
  }
  events$state_pitch_cell <- ifelse(nzchar(events$pitch_cell_12x8), events$pitch_cell_12x8, "unknown")
  if ("pitch_board_cell" %in% names(events)) {
    events$state_board_cell <- ifelse(nzchar(events$pitch_board_cell), events$pitch_board_cell, "unknown")
  } else {
    events$state_board_cell <- events$state_pitch_cell
  }
  if ("movement_direction" %in% names(events)) {
    events$state_movement_direction <- ifelse(nzchar(events$movement_direction), events$movement_direction, "unknown")
  } else {
    events$state_movement_direction <- "unknown"
  }
  if ("transition_shape" %in% names(events)) {
    events$state_transition_shape <- ifelse(nzchar(events$transition_shape), events$transition_shape, "unknown")
  } else {
    events$state_transition_shape <- "unknown"
  }
  if ("transition_vector_12x8" %in% names(events)) {
    events$state_transition_vector <- ifelse(nzchar(events$transition_vector_12x8), events$transition_vector_12x8, "unknown")
  } else {
    events$state_transition_vector <- "unknown"
  }
  events$forward_cell_progress <- if ("forward_cell_progress" %in% names(events)) as.numeric(events$forward_cell_progress) else 0
  events$manhattan_cell_distance <- if ("manhattan_cell_distance" %in% names(events)) as.numeric(events$manhattan_cell_distance) else NA_real_
  events$adjacent_cell_transition <- if ("adjacent_cell_transition" %in% names(events)) coerce_logical(events$adjacent_cell_transition) else FALSE
  events$entered_final_third_next <- if ("entered_final_third_next" %in% names(events)) coerce_logical(events$entered_final_third_next) else FALSE
  events$state_id <- paste(events$state_event_group, events$state_pitch_cell, sep = " | ")

  events$next_is_shot <- events$next_event_type %in% c("shot", "goal")
  events$next_is_goal <- events$next_event_type %in% c("goal")
  events$next_is_turnover <- events$next_event_type %in% c("turnover")

  same_possession <- ave(events$possession_id, events$match_key, FUN = function(x) c(x[-1], NA) == x)
  same_possession[is.na(same_possession)] <- FALSE
  events$same_possession_next <- same_possession

  split_keys <- interaction(events$match_key, events$possession_id, drop = TRUE)
  events$remaining_shot_in_possession <- unsplit(
    lapply(split(events$is_shot, split_keys), function(x) rev(cummax(rev(as.integer(x)))) > 0),
    split_keys
  )
  events$remaining_goal_in_possession <- unsplit(
    lapply(split(events$is_goal, split_keys), function(x) rev(cummax(rev(as.integer(x)))) > 0),
    split_keys
  )
  events$remaining_turnover_in_possession <- unsplit(
    lapply(split(events$event_type == "turnover", split_keys), function(x) rev(cummax(rev(as.integer(x)))) > 0),
    split_keys
  )

  state_summary <- stats::aggregate(
    cbind(
      visits = rep(1, nrow(events)),
      next_shot = as.integer(events$next_is_shot),
      next_goal = as.integer(events$next_is_goal),
      next_turnover = as.integer(events$next_is_turnover),
      possession_shot = as.integer(events$remaining_shot_in_possession),
      possession_goal = as.integer(events$remaining_goal_in_possession),
      possession_turnover = as.integer(events$remaining_turnover_in_possession),
      forward_progress_total = ifelse(is.na(events$forward_cell_progress), 0, events$forward_cell_progress),
      manhattan_distance_total = ifelse(is.na(events$manhattan_cell_distance), 0, events$manhattan_cell_distance),
      adjacent_steps = as.integer(events$adjacent_cell_transition),
      final_third_entries = as.integer(events$entered_final_third_next)
    ),
    by = list(
      state_id = events$state_id,
      event_group = events$state_event_group,
      pitch_cell = events$state_pitch_cell,
      board_cell = events$state_board_cell,
      x_zone = events$state_x_zone,
      y_lane = events$state_y_lane,
      movement_direction = events$state_movement_direction,
      transition_shape = events$state_transition_shape
    ),
    FUN = sum
  )

  state_summary$next_shot_prob <- state_summary$next_shot / state_summary$visits
  state_summary$next_goal_prob <- state_summary$next_goal / state_summary$visits
  state_summary$next_turnover_prob <- state_summary$next_turnover / state_summary$visits
  state_summary$possession_shot_prob <- state_summary$possession_shot / state_summary$visits
  state_summary$possession_goal_prob <- state_summary$possession_goal / state_summary$visits
  state_summary$possession_turnover_prob <- state_summary$possession_turnover / state_summary$visits
  state_summary$avg_forward_cell_progress <- state_summary$forward_progress_total / state_summary$visits
  state_summary$avg_manhattan_cell_distance <- state_summary$manhattan_distance_total / state_summary$visits
  state_summary$adjacent_step_rate <- state_summary$adjacent_steps / state_summary$visits
  state_summary$final_third_entry_rate <- state_summary$final_third_entries / state_summary$visits
  state_summary$engine_advantage <- round(
    100 * state_summary$possession_goal_prob +
      25 * state_summary$possession_shot_prob -
      15 * state_summary$possession_turnover_prob +
      3 * state_summary$avg_forward_cell_progress +
      5 * state_summary$final_third_entry_rate,
    3
  )
  state_summary <- state_summary[order(-state_summary$engine_advantage, -state_summary$visits), ]

  transition_rows <- events[events$next_event_type != "END", c("state_id", "next_event_type", "state_event_group", "state_pitch_cell", "state_board_cell", "state_transition_vector", "state_transition_shape")]
  if ("next_pitch_cell_12x8" %in% names(events)) {
    transition_rows$next_pitch_cell <- events[events$next_event_type != "END", "next_pitch_cell_12x8"]
  } else {
    transition_rows$next_pitch_cell <- NA_character_
  }
  if ("next_pitch_board_cell" %in% names(events)) {
    transition_rows$next_board_cell <- events[events$next_event_type != "END", "next_pitch_board_cell"]
  } else {
    transition_rows$next_board_cell <- NA_character_
  }
  names(transition_rows)[1:7] <- c("state_id", "next_event_type", "event_group", "pitch_cell", "board_cell", "transition_vector", "transition_shape")
  transition_counts <- stats::aggregate(
    list(transitions = rep(1, nrow(transition_rows))),
    by = list(
      state_id = transition_rows$state_id,
      event_group = transition_rows$event_group,
      pitch_cell = transition_rows$pitch_cell,
      board_cell = transition_rows$board_cell,
      next_event_type = transition_rows$next_event_type,
      next_pitch_cell = transition_rows$next_pitch_cell,
      next_board_cell = transition_rows$next_board_cell,
      transition_vector = transition_rows$transition_vector,
      transition_shape = transition_rows$transition_shape
    ),
    FUN = sum
  )
  totals <- stats::aggregate(
    transition_counts$transitions,
    by = list(state_id = transition_counts$state_id),
    FUN = sum
  )
  names(totals)[2] <- "transitions_total"
  transition_counts <- merge(transition_counts, totals, by = "state_id", all.x = TRUE)
  transition_counts$transition_prob <- transition_counts$transitions / transition_counts$transitions_total
  transition_counts <- transition_counts[order(transition_counts$state_id, -transition_counts$transition_prob), ]

  top_transition <- transition_counts[order(transition_counts$state_id, -transition_counts$transition_prob, -transition_counts$transitions), ]
  top_transition <- top_transition[!duplicated(top_transition$state_id), c(
    "state_id", "next_event_type", "next_pitch_cell", "next_board_cell", "transition_vector", "transition_shape", "transition_prob"
  )]
  names(top_transition) <- c(
    "state_id", "most_likely_next_event_type", "most_likely_next_pitch_cell", "most_likely_next_board_cell",
    "most_likely_transition_vector", "most_likely_transition_shape", "most_likely_transition_prob"
  )
  state_summary <- merge(state_summary, top_transition, by = "state_id", all.x = TRUE)

  current_state_snapshot <- events[, c(
    "match_key", "event_index", "event_type", "team_inferred", "state_id", "state_pitch_cell", "next_event_type",
    "next_is_shot", "next_is_goal", "next_is_turnover",
    "remaining_shot_in_possession", "remaining_goal_in_possession", "remaining_turnover_in_possession"
  )]
  current_state_snapshot$board_cell <- events$state_board_cell
  current_state_snapshot$transition_vector <- events$state_transition_vector
  current_state_snapshot$transition_shape <- events$state_transition_shape
  if ("next_pitch_cell_12x8" %in% names(events)) {
    current_state_snapshot$next_pitch_cell <- events$next_pitch_cell_12x8
  }
  if ("next_pitch_board_cell" %in% names(events)) {
    current_state_snapshot$next_board_cell <- events$next_pitch_board_cell
  }
  current_state_snapshot <- merge(
    current_state_snapshot,
    state_summary[, c(
      "state_id",
      "pitch_cell",
      "board_cell",
      "movement_direction",
      "transition_shape",
      "next_shot_prob",
      "next_goal_prob",
      "next_turnover_prob",
      "possession_shot_prob",
      "possession_goal_prob",
      "possession_turnover_prob",
      "avg_forward_cell_progress",
      "avg_manhattan_cell_distance",
      "final_third_entry_rate",
      "engine_advantage",
      "most_likely_next_event_type",
      "most_likely_next_board_cell",
      "most_likely_transition_vector"
    )],
    by = "state_id",
    all.x = TRUE
  )

  utils::write.csv(state_summary, file.path(processed_dir, "film_study_state_engine_summary.csv"), row.names = FALSE)
  utils::write.csv(transition_counts, file.path(processed_dir, "film_study_state_engine_transitions.csv"), row.names = FALSE)
  utils::write.csv(current_state_snapshot, file.path(processed_dir, "film_study_state_engine_current_snapshot.csv"), row.names = FALSE)

  summary_list <- list(
    created_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    state_rows = nrow(state_summary),
    transition_rows = nrow(transition_counts),
    event_rows = nrow(events),
    grid = list(
      columns = 12,
      rows = 8,
      state_definition = "event_group + pitch_cell_12x8",
      board_coordinate_system = "files A-L from left to right, ranks 8-1 from top to bottom"
    ),
    note = "This state engine is empirical and updates from tagged local event sequences. It is not a physics or tracking engine."
  )
  jsonlite::write_json(
    summary_list,
    file.path(processed_dir, "film_study_state_engine_summary.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )

  invisible(summary_list)
}
