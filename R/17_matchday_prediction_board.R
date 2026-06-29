# Matchday prediction board.
#
# Builds the one-table output meant to be checked before matches. It combines
# the locally trained model outputs with live-enrichment fields when those API
# tables are populated.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

fixture_predictions_path <- file.path(model_dir, "world_cup_2026_fixture_predictions.csv")
if (!file.exists(fixture_predictions_path)) {
  stop("Fixture predictions were missing. Run R/16_score_2026_fixtures.R first.")
}

predictions <- readr::read_csv(fixture_predictions_path, show_col_types = FALSE)
predictions$date <- as.Date(predictions$date)

norm_team <- function(x) {
  tolower(gsub("[^a-z0-9]", "", x))
}

poisson_match_probabilities <- function(home_lambda, away_lambda, max_goals = 10) {
  if (!is.finite(home_lambda) || !is.finite(away_lambda)) {
    return(data.frame(
      poisson_home_win_prob = NA_real_,
      poisson_draw_prob = NA_real_,
      poisson_away_win_prob = NA_real_,
      over_2_5_prob = NA_real_,
      both_teams_to_score_prob = NA_real_,
      most_likely_score = NA_character_,
      stringsAsFactors = FALSE
    ))
  }

  goals <- 0:max_goals
  grid <- expand.grid(home_goals = goals, away_goals = goals)
  grid$probability <- stats::dpois(grid$home_goals, home_lambda) *
    stats::dpois(grid$away_goals, away_lambda)
  total_probability <- sum(grid$probability, na.rm = TRUE)
  if (total_probability > 0) {
    grid$probability <- grid$probability / total_probability
  }

  likely <- grid[which.max(grid$probability), ]

  data.frame(
    poisson_home_win_prob = sum(grid$probability[grid$home_goals > grid$away_goals], na.rm = TRUE),
    poisson_draw_prob = sum(grid$probability[grid$home_goals == grid$away_goals], na.rm = TRUE),
    poisson_away_win_prob = sum(grid$probability[grid$home_goals < grid$away_goals], na.rm = TRUE),
    over_2_5_prob = sum(grid$probability[grid$home_goals + grid$away_goals >= 3], na.rm = TRUE),
    both_teams_to_score_prob = sum(grid$probability[grid$home_goals > 0 & grid$away_goals > 0], na.rm = TRUE),
    most_likely_score = paste0(likely$home_goals, "-", likely$away_goals),
    stringsAsFactors = FALSE
  )
}

poisson_rows <- do.call(
  rbind,
  lapply(seq_len(nrow(predictions)), function(i) {
    poisson_match_probabilities(
      predictions$pred_home_goals_poisson[[i]],
      predictions$pred_away_goals_poisson[[i]]
    )
  })
)

board <- cbind(predictions, poisson_rows)

board$ordinal_predicted_outcome <- board$predicted_result
board$ordinal_predicted_winner <- ifelse(
  board$ordinal_predicted_outcome == "home win",
  board$home_team,
  ifelse(board$ordinal_predicted_outcome == "away win", board$away_team, "Draw")
)
board$poisson_predicted_outcome <- c("home win", "draw", "away win")[
  max.col(as.matrix(board[, c(
    "poisson_home_win_prob",
    "poisson_draw_prob",
    "poisson_away_win_prob"
  )]), ties.method = "first")
]
board$poisson_predicted_winner <- ifelse(
  board$poisson_predicted_outcome == "home win",
  board$home_team,
  ifelse(board$poisson_predicted_outcome == "away win", board$away_team, "Draw")
)
board$ols_predicted_outcome <- ifelse(
  abs(board$pred_home_goals_ols - board$pred_away_goals_ols) < 0.15,
  "draw",
  ifelse(board$pred_home_goals_ols > board$pred_away_goals_ols, "home win", "away win")
)
board$ols_predicted_winner <- ifelse(
  board$ols_predicted_outcome == "home win",
  board$home_team,
  ifelse(board$ols_predicted_outcome == "away win", board$away_team, "Draw")
)

board$ensemble_home_win_prob <- rowMeans(
  cbind(board$pred_home_win_prob, board$poisson_home_win_prob),
  na.rm = TRUE
)
board$ensemble_draw_prob <- rowMeans(
  cbind(board$pred_draw_prob, board$poisson_draw_prob),
  na.rm = TRUE
)
board$ensemble_away_win_prob <- rowMeans(
  cbind(board$pred_away_win_prob, board$poisson_away_win_prob),
  na.rm = TRUE
)

ensemble_total <- board$ensemble_home_win_prob + board$ensemble_draw_prob + board$ensemble_away_win_prob
valid_ensemble_total <- is.finite(ensemble_total) & ensemble_total > 0
board$ensemble_home_win_prob[valid_ensemble_total] <- board$ensemble_home_win_prob[valid_ensemble_total] /
  ensemble_total[valid_ensemble_total]
board$ensemble_draw_prob[valid_ensemble_total] <- board$ensemble_draw_prob[valid_ensemble_total] /
  ensemble_total[valid_ensemble_total]
board$ensemble_away_win_prob[valid_ensemble_total] <- board$ensemble_away_win_prob[valid_ensemble_total] /
  ensemble_total[valid_ensemble_total]

ensemble_matrix <- as.matrix(board[, c(
  "ensemble_home_win_prob",
  "ensemble_draw_prob",
  "ensemble_away_win_prob"
)])
outcome_index <- max.col(ensemble_matrix, ties.method = "first")
board$predicted_outcome <- c("home win", "draw", "away win")[outcome_index]
board$predicted_winner <- ifelse(
  board$predicted_outcome == "home win",
  board$home_team,
  ifelse(board$predicted_outcome == "away win", board$away_team, "Draw")
)
board$prediction_confidence <- apply(ensemble_matrix, 1, max, na.rm = TRUE)
board$confidence_band <- cut(
  board$prediction_confidence,
  breaks = c(-Inf, 0.45, 0.60, Inf),
  labels = c("Lean", "Medium", "Strong"),
  right = FALSE
)
board$expected_total_goals <- board$pred_home_goals_poisson + board$pred_away_goals_poisson

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)
tables <- DBI::dbListTables(con)

read_table_if_exists <- function(table_name) {
  if (!table_name %in% tables) {
    return(data.frame())
  }
  DBI::dbGetQuery(con, paste("SELECT * FROM", table_name))
}

api_fixtures <- read_table_if_exists("api_football_world_cup_fixtures")
lineups <- read_table_if_exists("api_football_fixture_lineups")
api_predictions <- read_table_if_exists("api_football_fixture_predictions")
api_players <- read_table_if_exists("api_football_world_cup_players")
events <- read_table_if_exists("api_football_fixture_events")
fixture_times <- read_table_if_exists("fact_2026_world_cup_fixture_times")

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

if (nrow(fixture_times) > 0) {
  fixture_times <- fixture_times[
    !is.na(fixture_times$source_match_id),
    c(
      "source_match_id",
      "local_time",
      "utc_offset",
      "kickoff_local_iso",
      "kickoff_utc_iso",
      "refresh_utc_iso",
      "venue_label"
    )
  ]
  fixture_times <- fixture_times[!duplicated(fixture_times$source_match_id), ]
  board <- merge(board, fixture_times, by = "source_match_id", all.x = TRUE, sort = FALSE)
} else {
  board$local_time <- NA_character_
  board$utc_offset <- NA_character_
  board$kickoff_local_iso <- NA_character_
  board$kickoff_utc_iso <- NA_character_
  board$refresh_utc_iso <- NA_character_
  board$venue_label <- NA_character_
}

if (nrow(api_fixtures) > 0) {
  api_fixtures$fixture_day <- as.Date(api_fixtures$fixture_date)
  api_fixtures$join_key <- paste(
    api_fixtures$fixture_day,
    norm_team(api_fixtures$home_team),
    norm_team(api_fixtures$away_team),
    sep = "|"
  )
  board$join_key <- paste(
    board$date,
    norm_team(board$home_team),
    norm_team(board$away_team),
    sep = "|"
  )
  api_lookup <- api_fixtures[, c("join_key", "api_fixture_id", "status_long", "status_short")]
  api_lookup <- api_lookup[!duplicated(api_lookup$join_key), ]
  board <- merge(board, api_lookup, by = "join_key", all.x = TRUE, sort = FALSE)
} else {
  board$api_fixture_id <- NA
  board$status_long <- NA
  board$status_short <- NA
}

lineup_status <- data.frame()
if (nrow(lineups) > 0 && "lineup_role" %in% names(lineups)) {
  starters <- lineups[lineups$lineup_role == "start", ]
  if (nrow(starters) > 0) {
    lineup_status <- aggregate(
      player_name ~ api_fixture_id + team_name + formation,
      data = starters,
      FUN = function(x) paste(head(x, 11), collapse = ", ")
    )
    names(lineup_status)[names(lineup_status) == "player_name"] <- "starting_lineup"
  }
}

board$home_lineup_status <- "Pending"
board$away_lineup_status <- "Pending"
board$home_starting_lineup <- NA_character_
board$away_starting_lineup <- NA_character_
board$home_formation <- NA_character_
board$away_formation <- NA_character_

if (nrow(lineup_status) > 0) {
  for (i in seq_len(nrow(board))) {
    fixture_id <- board$api_fixture_id[[i]]
    if (is.na(fixture_id)) {
      next
    }
    home_hit <- lineup_status[
      lineup_status$api_fixture_id == fixture_id &
        norm_team(lineup_status$team_name) == norm_team(board$home_team[[i]]),
    ]
    away_hit <- lineup_status[
      lineup_status$api_fixture_id == fixture_id &
        norm_team(lineup_status$team_name) == norm_team(board$away_team[[i]]),
    ]
    if (nrow(home_hit) > 0) {
      board$home_lineup_status[[i]] <- "Confirmed"
      board$home_starting_lineup[[i]] <- home_hit$starting_lineup[[1]]
      board$home_formation[[i]] <- home_hit$formation[[1]]
    }
    if (nrow(away_hit) > 0) {
      board$away_lineup_status[[i]] <- "Confirmed"
      board$away_starting_lineup[[i]] <- away_hit$starting_lineup[[1]]
      board$away_formation[[i]] <- away_hit$formation[[1]]
    }
  }
}

board$home_projected_yellow_cards <- NA_real_
board$away_projected_yellow_cards <- NA_real_
board$yellow_card_model_status <- "Card model pending API card history"

if (nrow(api_players) > 0 && all(c("team_name", "yellow_cards", "appearances") %in% names(api_players))) {
  api_players$yellow_cards <- suppressWarnings(as.numeric(api_players$yellow_cards))
  api_players$appearances <- suppressWarnings(as.numeric(api_players$appearances))
  card_rates <- aggregate(
    cbind(yellow_cards, appearances) ~ team_name,
    data = api_players,
    FUN = function(x) sum(x, na.rm = TRUE)
  )
  card_rates$projected_yellow_cards <- ifelse(
    card_rates$appearances > 0,
    11 * card_rates$yellow_cards / card_rates$appearances,
    NA_real_
  )
  for (i in seq_len(nrow(board))) {
    home_rate <- card_rates$projected_yellow_cards[
      norm_team(card_rates$team_name) == norm_team(board$home_team[[i]])
    ]
    away_rate <- card_rates$projected_yellow_cards[
      norm_team(card_rates$team_name) == norm_team(board$away_team[[i]])
    ]
    if (length(home_rate) > 0) {
      board$home_projected_yellow_cards[[i]] <- home_rate[[1]]
    }
    if (length(away_rate) > 0) {
      board$away_projected_yellow_cards[[i]] <- away_rate[[1]]
    }
  }
  if (any(is.finite(board$home_projected_yellow_cards) | is.finite(board$away_projected_yellow_cards))) {
    board$yellow_card_model_status <- "Projected from API player card rates"
  }
}

if (nrow(events) > 0 && all(c("api_fixture_id", "event_type", "event_detail") %in% names(events))) {
  card_events <- events[
    tolower(events$event_type) == "card" &
      grepl("yellow", tolower(events$event_detail)),
  ]
  if (nrow(card_events) > 0) {
    card_counts <- aggregate(
      event_detail ~ api_fixture_id + team_name,
      data = card_events,
      FUN = length
    )
    names(card_counts)[names(card_counts) == "event_detail"] <- "observed_yellow_cards"
    readr::write_csv(card_counts, file.path(model_dir, "matchday_observed_card_events.csv"))
  }
}

parse_provider_percent <- function(x) {
  as.numeric(gsub("%", "", as.character(x))) / 100
}

board$provider_prediction <- NA_character_
board$provider_home_win_prob <- NA_real_
board$provider_draw_prob <- NA_real_
board$provider_away_win_prob <- NA_real_

if (nrow(api_predictions) > 0 && "api_fixture_id" %in% names(api_predictions)) {
  api_predictions$provider_home_win_prob <- parse_provider_percent(api_predictions$home_percent)
  api_predictions$provider_draw_prob <- parse_provider_percent(api_predictions$draw_percent)
  api_predictions$provider_away_win_prob <- parse_provider_percent(api_predictions$away_percent)
  provider_lookup <- api_predictions[, c(
    "api_fixture_id",
    "winner_name",
    "advice",
    "provider_home_win_prob",
    "provider_draw_prob",
    "provider_away_win_prob"
  )]
  provider_lookup <- provider_lookup[!duplicated(provider_lookup$api_fixture_id), ]
  board <- merge(board, provider_lookup, by = "api_fixture_id", all.x = TRUE, sort = FALSE)
  board$provider_prediction <- ifelse(
    is.na(board$winner_name),
    board$provider_prediction,
    paste(board$winner_name, board$advice, sep = " | ")
  )
}

board$match_label <- paste(board$home_team, "vs", board$away_team)
board$score_state <- ifelse(
  !is.na(board$home_score) & !is.na(board$away_score),
  paste0(board$home_score, "-", board$away_score),
  ""
)

today <- Sys.Date()
now_utc <- as.POSIXct(Sys.time(), tz = "UTC")
kickoff_utc <- as.POSIXct(board$kickoff_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
board$match_timing <- ifelse(
  !is.na(board$home_score) & !is.na(board$away_score),
  "Completed",
  ifelse(
    !is.na(kickoff_utc) & kickoff_utc <= now_utc,
    "Pending score",
    ifelse(board$date < today, "Pending score", ifelse(board$date == today, "Today", "Upcoming"))
  )
)

board <- board[order(
  board$match_timing == "Completed",
  board$date,
  board$source_match_id
), ]

public_columns <- c(
  "source_match_id",
  "api_fixture_id",
  "date",
  "match_timing",
  "match_label",
  "home_team",
  "away_team",
  "score_state",
  "actual_result",
  "kickoff_local_iso",
  "kickoff_utc_iso",
  "refresh_utc_iso",
  "predicted_winner",
  "predicted_outcome",
  "ols_predicted_winner",
  "poisson_predicted_winner",
  "ordinal_predicted_winner",
  "confidence_band",
  "prediction_confidence",
  "ensemble_home_win_prob",
  "ensemble_draw_prob",
  "ensemble_away_win_prob",
  "most_likely_score",
  "pred_home_goals_poisson",
  "pred_away_goals_poisson",
  "expected_total_goals",
  "over_2_5_prob",
  "both_teams_to_score_prob",
  "home_projected_yellow_cards",
  "away_projected_yellow_cards",
  "yellow_card_model_status",
  "home_lineup_status",
  "away_lineup_status",
  "home_formation",
  "away_formation",
  "home_starting_lineup",
  "away_starting_lineup",
  "provider_prediction",
  "city",
  "country",
  "avg_temperature_2m",
  "avg_wind_speed_10m"
)
public_columns <- public_columns[public_columns %in% names(board)]
board_public <- board[, public_columns]

summary <- data.frame(
  metric = c(
    "last_refreshed_local",
    "matches_on_board",
    "matches_today",
    "upcoming_matches",
    "completed_matches",
    "lineup_rows_available",
    "event_rows_available",
    "provider_prediction_rows_available",
    "api_fixture_rows_available",
    "player_card_rows_available"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    nrow(board_public),
    sum(board_public$match_timing == "Today", na.rm = TRUE),
    sum(board_public$match_timing == "Upcoming", na.rm = TRUE),
    sum(board_public$match_timing == "Completed", na.rm = TRUE),
    nrow(lineups),
    nrow(events),
    nrow(api_predictions),
    nrow(api_fixtures),
    nrow(api_players)
  ),
  stringsAsFactors = FALSE
)

data_sources <- data.frame(
  output = c(
    "Winner and outcome",
    "Expected goals",
    "Most likely score",
    "Over 2.5 goals",
    "Both teams to score",
    "Yellow cards",
    "Lineups",
    "Provider prediction"
  ),
  model_or_feed = c(
    "Average of ordinal logistic result probabilities and Poisson score-derived probabilities",
    "Poisson goals model",
    "Independent Poisson score grid",
    "Independent Poisson score grid",
    "Independent Poisson score grid",
    "API player card rates when available",
    "API-Football fixture lineups when posted",
    "API-Football fixture prediction feed when available"
  ),
  current_role = c(
    "Active",
    "Active",
    "Active",
    "Active",
    "Active",
    ifelse(any(is.finite(board_public$home_projected_yellow_cards)), "Active", "Awaiting card-history rows"),
    ifelse(any(board_public$home_lineup_status == "Confirmed"), "Active", "Awaiting posted lineups"),
    ifelse(any(!is.na(board_public$provider_prediction)), "Active", "Awaiting provider prediction rows")
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(board_public, file.path(model_dir, "matchday_prediction_board.csv"))
readr::write_csv(summary, file.path(model_dir, "matchday_prediction_summary.csv"))
readr::write_csv(data_sources, file.path(model_dir, "matchday_prediction_data_sources.csv"))

completed_accuracy <- board[
  !is.na(board$actual_result) &
    nzchar(board$actual_result),
]
accuracy <- data.frame()
accuracy_detail <- data.frame()
if (nrow(completed_accuracy) > 0) {
  completed_accuracy$actual_winner <- ifelse(
    completed_accuracy$actual_result == "home win",
    completed_accuracy$home_team,
    ifelse(completed_accuracy$actual_result == "away win", completed_accuracy$away_team, "Draw")
  )
  completed_accuracy$actual_total_goals <- completed_accuracy$home_score + completed_accuracy$away_score
  completed_accuracy$ols_total_goals <- completed_accuracy$pred_home_goals_ols + completed_accuracy$pred_away_goals_ols
  completed_accuracy$poisson_total_goals <- completed_accuracy$pred_home_goals_poisson + completed_accuracy$pred_away_goals_poisson
  completed_accuracy$ols_total_goal_error <- abs(completed_accuracy$ols_total_goals - completed_accuracy$actual_total_goals)
  completed_accuracy$poisson_total_goal_error <- abs(completed_accuracy$poisson_total_goals - completed_accuracy$actual_total_goals)
  completed_accuracy$ols_team_goal_mae <- (
    abs(completed_accuracy$pred_home_goals_ols - completed_accuracy$home_score) +
      abs(completed_accuracy$pred_away_goals_ols - completed_accuracy$away_score)
  ) / 2
  completed_accuracy$poisson_team_goal_mae <- (
    abs(completed_accuracy$pred_home_goals_poisson - completed_accuracy$home_score) +
      abs(completed_accuracy$pred_away_goals_poisson - completed_accuracy$away_score)
  ) / 2
  completed_accuracy$ensemble_probability_actual <- ifelse(
    completed_accuracy$actual_result == "home win",
    completed_accuracy$ensemble_home_win_prob,
    ifelse(
      completed_accuracy$actual_result == "away win",
      completed_accuracy$ensemble_away_win_prob,
      completed_accuracy$ensemble_draw_prob
    )
  )
  completed_accuracy$poisson_probability_actual <- ifelse(
    completed_accuracy$actual_result == "home win",
    completed_accuracy$poisson_home_win_prob,
    ifelse(
      completed_accuracy$actual_result == "away win",
      completed_accuracy$poisson_away_win_prob,
      completed_accuracy$poisson_draw_prob
    )
  )
  completed_accuracy$ordinal_probability_actual <- ifelse(
    completed_accuracy$actual_result == "home win",
    completed_accuracy$pred_home_win_prob,
    ifelse(
      completed_accuracy$actual_result == "away win",
      completed_accuracy$pred_away_win_prob,
      completed_accuracy$pred_draw_prob
    )
  )

  accuracy <- data.frame(
    model = c("Ensemble", "OLS goals", "Poisson score grid", "Ordinal result"),
    completed_matches = nrow(completed_accuracy),
    outcome_accuracy = c(
      mean(completed_accuracy$predicted_outcome == completed_accuracy$actual_result, na.rm = TRUE),
      mean(completed_accuracy$ols_predicted_outcome == completed_accuracy$actual_result, na.rm = TRUE),
      mean(completed_accuracy$poisson_predicted_outcome == completed_accuracy$actual_result, na.rm = TRUE),
      mean(completed_accuracy$ordinal_predicted_outcome == completed_accuracy$actual_result, na.rm = TRUE)
    ),
    avg_total_goal_error = c(
      mean(completed_accuracy$poisson_total_goal_error, na.rm = TRUE),
      mean(completed_accuracy$ols_total_goal_error, na.rm = TRUE),
      mean(completed_accuracy$poisson_total_goal_error, na.rm = TRUE),
      NA_real_
    ),
    avg_team_goal_mae = c(
      mean(completed_accuracy$poisson_team_goal_mae, na.rm = TRUE),
      mean(completed_accuracy$ols_team_goal_mae, na.rm = TRUE),
      mean(completed_accuracy$poisson_team_goal_mae, na.rm = TRUE),
      NA_real_
    ),
    stringsAsFactors = FALSE
  )
  accuracy$plain_english <- c(
    "Combined result probability from ordinal and Poisson models.",
    "Outcome implied by the OLS expected-goals comparison.",
    "Outcome implied by the Poisson scoreline probability grid.",
    "Direct win/draw/loss ordinal logistic model."
  )

  accuracy_detail <- data.frame(
    source_match_id = completed_accuracy$source_match_id,
    date = completed_accuracy$date,
    match_label = completed_accuracy$match_label,
    actual_score = paste0(completed_accuracy$home_score, "-", completed_accuracy$away_score),
    actual_result = completed_accuracy$actual_result,
    actual_winner = completed_accuracy$actual_winner,
    ensemble_pick = completed_accuracy$predicted_winner,
    ensemble_result = completed_accuracy$predicted_outcome,
    ensemble_correct = completed_accuracy$predicted_outcome == completed_accuracy$actual_result,
    ensemble_probability_actual = completed_accuracy$ensemble_probability_actual,
    ols_pick = completed_accuracy$ols_predicted_winner,
    ols_result = completed_accuracy$ols_predicted_outcome,
    ols_correct = completed_accuracy$ols_predicted_outcome == completed_accuracy$actual_result,
    ols_total_goal_error = completed_accuracy$ols_total_goal_error,
    ols_team_goal_mae = completed_accuracy$ols_team_goal_mae,
    poisson_pick = completed_accuracy$poisson_predicted_winner,
    poisson_result = completed_accuracy$poisson_predicted_outcome,
    poisson_correct = completed_accuracy$poisson_predicted_outcome == completed_accuracy$actual_result,
    poisson_probability_actual = completed_accuracy$poisson_probability_actual,
    poisson_total_goal_error = completed_accuracy$poisson_total_goal_error,
    poisson_team_goal_mae = completed_accuracy$poisson_team_goal_mae,
    ordinal_pick = completed_accuracy$ordinal_predicted_winner,
    ordinal_result = completed_accuracy$ordinal_predicted_outcome,
    ordinal_correct = completed_accuracy$ordinal_predicted_outcome == completed_accuracy$actual_result,
    ordinal_probability_actual = completed_accuracy$ordinal_probability_actual,
    stringsAsFactors = FALSE
  )
  accuracy_detail <- accuracy_detail[order(accuracy_detail$date, accuracy_detail$source_match_id), ]
}
readr::write_csv(accuracy, file.path(model_dir, "matchday_model_accuracy.csv"))
readr::write_csv(accuracy_detail, file.path(model_dir, "matchday_model_accuracy_detail.csv"))

refresh_utc <- as.POSIXct(board$refresh_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
display_tz <- "America/New_York"
future_refresh <- board[
  !is.na(refresh_utc) &
    refresh_utc > now_utc &
    board$match_timing %in% c("Today", "Upcoming"),
]
if (nrow(future_refresh) > 0) {
  future_refresh$refresh_at_local <- format(
    as.POSIXct(future_refresh$refresh_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    tz = display_tz,
    "%Y-%m-%d %H:%M:%S"
  )
  future_refresh$kickoff_at_local <- format(
    as.POSIXct(future_refresh$kickoff_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    tz = display_tz,
    "%Y-%m-%d %H:%M:%S"
  )
  future_refresh$time_zone <- display_tz
  schedule <- future_refresh[, c(
    "source_match_id",
    "date",
    "match_label",
    "kickoff_local_iso",
    "kickoff_utc_iso",
    "refresh_utc_iso",
    "refresh_at_local",
    "kickoff_at_local",
    "time_zone"
  )]
  schedule <- schedule[order(schedule$refresh_utc_iso, schedule$source_match_id), ]
} else {
  schedule <- data.frame(
    source_match_id = integer(),
    date = as.Date(character()),
    match_label = character(),
    kickoff_local_iso = character(),
    kickoff_utc_iso = character(),
    refresh_utc_iso = character(),
    refresh_at_local = character(),
    kickoff_at_local = character(),
    time_zone = character()
  )
}
readr::write_csv(schedule, file.path(model_dir, "matchday_refresh_schedule.csv"))

postmatch_buffer_minutes <- 135
postmatch_kickoff_utc <- as.POSIXct(board$kickoff_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
postmatch_eligible <- board$match_timing %in% c("Today", "Upcoming", "Pending score") &
  !is.na(postmatch_kickoff_utc)
postmatch_candidates <- board[
  postmatch_eligible,
]
postmatch_utc <- postmatch_kickoff_utc[postmatch_eligible] + postmatch_buffer_minutes * 60
postmatch_candidates$postmatch_refresh_utc <- postmatch_utc
postmatch_candidates <- postmatch_candidates[
  !is.na(postmatch_candidates$postmatch_refresh_utc) &
    postmatch_candidates$postmatch_refresh_utc > now_utc,
]

if (nrow(postmatch_candidates) > 0) {
  postmatch_candidates$postmatch_refresh_utc_iso <- format(
    postmatch_candidates$postmatch_refresh_utc,
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
  postmatch_candidates$postmatch_refresh_at_eastern <- format(
    postmatch_candidates$postmatch_refresh_utc,
    "%Y-%m-%d %H:%M:%S",
    tz = display_tz
  )
  postmatch_candidates$kickoff_at_eastern <- format(
    as.POSIXct(postmatch_candidates$kickoff_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    "%Y-%m-%d %H:%M:%S",
    tz = display_tz
  )
  postmatch_candidates$estimated_final_at_eastern <- format(
    as.POSIXct(postmatch_candidates$kickoff_utc_iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") + 120 * 60,
    "%Y-%m-%d %H:%M:%S",
    tz = display_tz
  )
  postmatch_candidates$postmatch_buffer_minutes <- postmatch_buffer_minutes
  postmatch_candidates$time_zone <- "Eastern Time"
  postmatch_candidates$time_zone_detail <- "America/New_York; June 2026 observes EDT (UTC-4)"

  postmatch_schedule <- postmatch_candidates[, c(
    "source_match_id",
    "date",
    "match_label",
    "kickoff_utc_iso",
    "kickoff_at_eastern",
    "estimated_final_at_eastern",
    "postmatch_refresh_utc_iso",
    "postmatch_refresh_at_eastern",
    "postmatch_buffer_minutes",
    "time_zone",
    "time_zone_detail"
  )]
  postmatch_schedule <- postmatch_schedule[
    order(postmatch_schedule$postmatch_refresh_utc_iso, postmatch_schedule$source_match_id),
  ]
} else {
  postmatch_schedule <- data.frame(
    source_match_id = integer(),
    date = as.Date(character()),
    match_label = character(),
    kickoff_utc_iso = character(),
    kickoff_at_eastern = character(),
    estimated_final_at_eastern = character(),
    postmatch_refresh_utc_iso = character(),
    postmatch_refresh_at_eastern = character(),
    postmatch_buffer_minutes = integer(),
    time_zone = character(),
    time_zone_detail = character()
  )
}
readr::write_csv(postmatch_schedule, file.path(model_dir, "matchday_postmatch_refresh_schedule.csv"))

cat("\nMatchday prediction board complete.\n")
cat("Board: ", file.path(model_dir, "matchday_prediction_board.csv"), "\n", sep = "")
cat("Summary: ", file.path(model_dir, "matchday_prediction_summary.csv"), "\n", sep = "")
cat("Refresh schedule: ", file.path(model_dir, "matchday_refresh_schedule.csv"), "\n", sep = "")
cat("Post-match refresh schedule: ", file.path(model_dir, "matchday_postmatch_refresh_schedule.csv"), "\n", sep = "")
print(head(board_public, 12))
