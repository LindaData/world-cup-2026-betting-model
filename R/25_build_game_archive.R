source("R/00_setup.R")

model_dir <- file.path("data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

board_path <- file.path(model_dir, "matchday_prediction_board.csv")
accuracy_path <- file.path(model_dir, "matchday_model_accuracy_detail.csv")

if (!file.exists(board_path)) {
  stop("Missing matchday_prediction_board.csv. Run R/17_matchday_prediction_board.R first.")
}

board <- readr::read_csv(board_path, show_col_types = FALSE)
accuracy <- if (file.exists(accuracy_path)) {
  readr::read_csv(accuracy_path, show_col_types = FALSE)
} else {
  data.frame()
}

safe_text <- function(x) {
  ifelse(is.na(x), "", as.character(x))
}

bool_text <- function(x) {
  tolower(safe_text(x)) %in% c("true", "t", "1", "yes")
}

build_match_key <- function(date_value, home_team, away_team, source_match_id = NA) {
  source_value <- safe_text(source_match_id)
  ifelse(
    nzchar(source_value),
    paste0("wc2026-", source_value),
    paste0(
      "wc2026-",
      gsub("[^a-z0-9]+", "-", tolower(safe_text(date_value))),
      "-",
      gsub("[^a-z0-9]+", "-", tolower(safe_text(home_team))),
      "-",
      gsub("[^a-z0-9]+", "-", tolower(safe_text(away_team)))
    )
  )
}

board <- board |>
  dplyr::mutate(
    match_key = build_match_key(date, home_team, away_team, source_match_id),
    is_knockout_flag = bool_text(is_knockout_match),
    match_phase = dplyr::if_else(is_knockout_flag, "Knockout", "Group"),
    replay_status = dplyr::case_when(
      match_timing == "Completed" ~ "Replay likely available on Peacock",
      match_timing %in% c("Today", "Upcoming") ~ "Live window pending",
      TRUE ~ "Status pending update"
    ),
    archive_status = dplyr::case_when(
      match_timing == "Completed" ~ "Completed",
      match_timing == "Today" ~ "Today",
      match_timing == "Upcoming" ~ "Upcoming",
      TRUE ~ safe_text(match_timing)
    ),
    official_watch_platform = "Peacock",
    official_watch_url = "https://www.peacocktv.com/",
    replay_home_url = "https://www.peacocktv.com/",
    replay_lookup_hint = paste0(home_team, " vs ", away_team, " World Cup replay"),
    replay_last_checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    review_notes_path = file.path("data", "private", "game_notes", paste0(match_key, ".md")),
    rights_note = "Use official Peacock live or replay access. This project stores metadata and review notes only.",
    actual_score = dplyr::coalesce(score_state, extra_time_score, penalty_score, ""),
    venue_label = trimws(paste(city, country, sep = ", "))
  )

watch_registry <- board |>
  dplyr::transmute(
    match_key,
    source_match_id,
    api_fixture_id,
    date,
    kickoff_local_iso,
    kickoff_utc_iso,
    match_phase,
    archive_status,
    match_label,
    home_team,
    away_team,
    venue_label,
    official_watch_platform,
    official_watch_url,
    replay_home_url,
    replay_lookup_hint,
    replay_status,
    replay_last_checked_utc,
    review_notes_path,
    rights_note
  ) |>
  dplyr::arrange(date, match_label)

completed_board <- board |>
  dplyr::filter(match_timing == "Completed") |>
  dplyr::select(
    match_key,
    source_match_id,
    date,
    match_label,
    home_team,
    away_team,
    match_phase,
    venue_label,
    predicted_winner,
    predicted_outcome,
    most_likely_score,
    pred_home_goals_poisson,
    pred_away_goals_poisson,
    over_2_5_prob,
    both_teams_to_score_prob,
    prediction_confidence,
    final_result_mode,
    actual_score,
    actual_result,
    actual_advancing_team
  )

review_table <- completed_board
if (nrow(accuracy) > 0) {
  review_table <- completed_board |>
    dplyr::left_join(
      accuracy |>
        dplyr::mutate(match_key = build_match_key(date, sub(" vs .*", "", match_label), sub(".* vs ", "", match_label), source_match_id)) |>
        dplyr::select(
          match_key,
          source_match_id,
          date,
          match_label,
          ensemble_correct,
          ensemble_probability_actual,
          poisson_total_goal_error,
          poisson_team_goal_mae
        ),
      by = c("match_key", "source_match_id", "date", "match_label")
    )
}

review_table <- review_table |>
  dplyr::mutate(
    ensemble_correct = if ("ensemble_correct" %in% names(review_table)) ensemble_correct else NA,
    ensemble_probability_actual = if ("ensemble_probability_actual" %in% names(review_table)) ensemble_probability_actual else NA_real_,
    poisson_total_goal_error = if ("poisson_total_goal_error" %in% names(review_table)) poisson_total_goal_error else NA_real_,
    poisson_team_goal_mae = if ("poisson_team_goal_mae" %in% names(review_table)) poisson_team_goal_mae else NA_real_,
    review_outcome = dplyr::case_when(
      !is.na(ensemble_correct) & ensemble_correct ~ "Model hit",
      !is.na(ensemble_correct) & !ensemble_correct ~ "Model miss",
      TRUE ~ "Review pending"
    ),
    upset_check = dplyr::case_when(
      !is.na(ensemble_correct) & !ensemble_correct & !is.na(ensemble_probability_actual) & ensemble_probability_actual < 0.35 ~ "Upset check",
      TRUE ~ ""
    ),
    score_error_band = dplyr::case_when(
      !is.na(poisson_total_goal_error) & poisson_total_goal_error <= 0.5 ~ "Tight score read",
      !is.na(poisson_total_goal_error) & poisson_total_goal_error <= 1.5 ~ "Manageable score miss",
      !is.na(poisson_total_goal_error) ~ "Large score miss",
      TRUE ~ "Score review pending"
    ),
    replay_status = "Replay likely available on Peacock",
    replay_last_checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  ) |>
  dplyr::transmute(
    match_key,
    source_match_id,
    date,
    match_phase,
    match_label,
    home_team,
    away_team,
    venue_label,
    predicted_winner,
    predicted_outcome,
    predicted_score = most_likely_score,
    expected_goals = paste0(round(pred_home_goals_poisson, 2), " - ", round(pred_away_goals_poisson, 2)),
    actual_score,
    actual_result,
    actual_advancing_team,
    final_result_mode,
    review_outcome,
    model_correct = ensemble_correct,
    actual_result_probability = ensemble_probability_actual,
    total_goal_error = poisson_total_goal_error,
    team_goal_mae = poisson_team_goal_mae,
    score_error_band,
    upset_check,
    over_2_5_prob,
    both_teams_to_score_prob,
    prediction_confidence,
    replay_status,
    replay_last_checked_utc
  ) |>
  dplyr::arrange(dplyr::desc(date), match_label)

summary_table <- data.frame(
  metric = c(
    "matches_tracked",
    "completed_matches",
    "upcoming_matches",
    "today_matches",
    "peacock_registry_rows",
    "review_rows",
    "model_hit_rate",
    "average_goal_error"
  ),
  value = c(
    nrow(board),
    sum(board$match_timing == "Completed", na.rm = TRUE),
    sum(board$match_timing == "Upcoming", na.rm = TRUE),
    sum(board$match_timing == "Today", na.rm = TRUE),
    nrow(watch_registry),
    nrow(review_table),
    if (nrow(review_table) > 0 && "model_correct" %in% names(review_table) && any(!is.na(review_table$model_correct))) {
      mean(review_table$model_correct, na.rm = TRUE)
    } else {
      NA_real_
    },
    if (nrow(review_table) > 0 && any(!is.na(review_table$total_goal_error))) {
      mean(review_table$total_goal_error, na.rm = TRUE)
    } else {
      NA_real_
    }
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(watch_registry, file.path(model_dir, "game_archive_watch_registry.csv"))
readr::write_csv(review_table, file.path(model_dir, "game_archive_review_board.csv"))
readr::write_csv(summary_table, file.path(model_dir, "game_archive_summary.csv"))

message("Built game archive outputs:")
message(" - ", file.path(model_dir, "game_archive_watch_registry.csv"))
message(" - ", file.path(model_dir, "game_archive_review_board.csv"))
message(" - ", file.path(model_dir, "game_archive_summary.csv"))
