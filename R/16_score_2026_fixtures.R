# Score 2026 World Cup fixtures with locally trained baseline models.
#
# The output is local model-ready prediction data. Quarto embeds only selected
# summary tables and rounded prediction examples in the public website.

source("R/00_setup.R")

if (!requireNamespace("MASS", quietly = TRUE)) {
  install.packages("MASS", repos = "https://cloud.r-project.org")
}

model_dir <- file.path(here::here(), "data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

fixtures <- DBI::dbGetQuery(con, "
  SELECT
    f.source_match_id,
    f.date,
    f.home_team,
    f.away_team,
    f.home_score,
    f.away_score,
    f.status,
    f.city,
    f.country,
    f.neutral,
    f.home_squad_caps_before_tournament,
    f.away_squad_caps_before_tournament,
    f.home_squad_goals_before_tournament,
    f.away_squad_goals_before_tournament,
    f.home_win_pct_since_2022,
    f.away_win_pct_since_2022,
    f.home_avg_goals_for_since_2022,
    f.away_avg_goals_for_since_2022,
    f.home_avg_goals_against_since_2022,
    f.away_avg_goals_against_since_2022,
    f.home_latest_elo,
    f.away_latest_elo,
    f.elo_diff_home_minus_away,
    w.avg_temperature_2m,
    w.max_temperature_2m,
    w.avg_relative_humidity_2m,
    w.total_precipitation,
    w.avg_wind_speed_10m,
    w.max_wind_speed_10m
  FROM vw_2026_fixture_model_frame f
  LEFT JOIN vw_fixture_weather_signals w
    ON f.source_match_id = w.source_match_id
  ORDER BY f.date, f.source_match_id
")

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

if (nrow(fixtures) == 0) {
  readr::write_csv(data.frame(), file.path(model_dir, "world_cup_2026_fixture_predictions.csv"))
  readr::write_csv(data.frame(), file.path(model_dir, "world_cup_2026_fixture_prediction_metrics.csv"))
  stop("No 2026 fixture rows were available to score.")
}

fixtures$neutral <- as.logical(fixtures$neutral)

home_advantage <- ifelse(fixtures$neutral, 0, 100)
home_expected_result <- 1 / (1 + 10^(-((fixtures$home_latest_elo + home_advantage - fixtures$away_latest_elo) / 400)))
away_expected_result <- 1 - home_expected_result

home_rows <- data.frame(
  source_match_id = fixtures$source_match_id,
  date = fixtures$date,
  team = fixtures$home_team,
  opponent = fixtures$away_team,
  side = "home",
  listed_home = TRUE,
  neutral = fixtures$neutral,
  y_goals_for = fixtures$home_score,
  actual_goals_against = fixtures$away_score,
  pre_elo = fixtures$home_latest_elo,
  opponent_pre_elo = fixtures$away_latest_elo,
  pre_match_expected_result = home_expected_result,
  stringsAsFactors = FALSE
)

away_rows <- data.frame(
  source_match_id = fixtures$source_match_id,
  date = fixtures$date,
  team = fixtures$away_team,
  opponent = fixtures$home_team,
  side = "away",
  listed_home = FALSE,
  neutral = fixtures$neutral,
  y_goals_for = fixtures$away_score,
  actual_goals_against = fixtures$home_score,
  pre_elo = fixtures$away_latest_elo,
  opponent_pre_elo = fixtures$home_latest_elo,
  pre_match_expected_result = away_expected_result,
  stringsAsFactors = FALSE
)

team_fixture_rows <- rbind(home_rows, away_rows)
team_fixture_rows$listed_home <- as.logical(team_fixture_rows$listed_home)
team_fixture_rows$neutral <- as.logical(team_fixture_rows$neutral)

complete_feature_rows <- stats::complete.cases(
  team_fixture_rows[, c("pre_elo", "opponent_pre_elo", "pre_match_expected_result", "listed_home", "neutral")]
)

ols_fit_path <- file.path(model_dir, "goals_linear_model_fit.rds")
poisson_fit_path <- file.path(model_dir, "goals_poisson_model_fit_random.rds")
ordinal_fit_path <- file.path(model_dir, "result_ordinal_model_fit.rds")

if (!file.exists(ols_fit_path) || !file.exists(poisson_fit_path) || !file.exists(ordinal_fit_path)) {
  stop("Model fit files were missing. Run the model scripts before fixture scoring.")
}

ols_fit <- readRDS(ols_fit_path)
poisson_fit <- readRDS(poisson_fit_path)
ordinal_fit <- readRDS(ordinal_fit_path)

team_fixture_rows$pred_goals_ols <- NA_real_
team_fixture_rows$pred_goals_poisson <- NA_real_
team_fixture_rows$pred_prob_loss <- NA_real_
team_fixture_rows$pred_prob_draw <- NA_real_
team_fixture_rows$pred_prob_win <- NA_real_

score_rows <- team_fixture_rows[complete_feature_rows, ]
team_fixture_rows$pred_goals_ols[complete_feature_rows] <- pmax(
  as.numeric(stats::predict(ols_fit, newdata = score_rows)),
  0
)
team_fixture_rows$pred_goals_poisson[complete_feature_rows] <- as.numeric(
  stats::predict(poisson_fit, newdata = score_rows, type = "response")
)

ordinal_probabilities <- as.data.frame(stats::predict(ordinal_fit, newdata = score_rows, type = "probs"))
team_fixture_rows$pred_prob_loss[complete_feature_rows] <- ordinal_probabilities$loss
team_fixture_rows$pred_prob_draw[complete_feature_rows] <- ordinal_probabilities$draw
team_fixture_rows$pred_prob_win[complete_feature_rows] <- ordinal_probabilities$win

home_scored <- team_fixture_rows[team_fixture_rows$side == "home", ]
away_scored <- team_fixture_rows[team_fixture_rows$side == "away", ]

home_scored <- home_scored[order(home_scored$source_match_id), ]
away_scored <- away_scored[order(away_scored$source_match_id), ]
fixtures_ordered <- fixtures[order(fixtures$source_match_id), ]

home_probabilities <- home_scored[, c("pred_prob_loss", "pred_prob_draw", "pred_prob_win")]
names(home_probabilities) <- c("pred_away_win_prob", "pred_draw_prob", "pred_home_win_prob")

probability_matrix <- as.matrix(home_probabilities[, c("pred_home_win_prob", "pred_draw_prob", "pred_away_win_prob")])
predicted_result <- rep(NA_character_, nrow(probability_matrix))
result_labels <- c("home win", "draw", "away win")
valid_probability_rows <- stats::complete.cases(probability_matrix)
predicted_result[valid_probability_rows] <- result_labels[
  max.col(probability_matrix[valid_probability_rows, , drop = FALSE], ties.method = "first")
]

actual_result <- ifelse(
  is.na(fixtures_ordered$home_score) | is.na(fixtures_ordered$away_score),
  NA_character_,
  ifelse(
    fixtures_ordered$home_score > fixtures_ordered$away_score,
    "home win",
    ifelse(fixtures_ordered$home_score < fixtures_ordered$away_score, "away win", "draw")
  )
)

# The knockout bracket starts on 2026-06-28 in the local fixture shell. These
# matches can be level after regulation, but they cannot have a final draw. The
# score model still estimates 90-minute result probabilities; the public
# winner call reallocates draw-after-regulation probability through a simple
# strength-based tiebreak path until extra-time/penalty data is available.
knockout_start_date <- as.Date("2026-06-28")
fixture_dates <- as.Date(fixtures_ordered$date)
is_knockout_match <- fixture_dates >= knockout_start_date

home_tiebreak_share <- 1 / (1 + 10^(-(fixtures_ordered$home_latest_elo - fixtures_ordered$away_latest_elo) / 400))
probability_denominator <- home_probabilities$pred_home_win_prob + home_probabilities$pred_away_win_prob
fallback_home_tiebreak_share <- ifelse(
  is.finite(probability_denominator) & probability_denominator > 0,
  home_probabilities$pred_home_win_prob / probability_denominator,
  0.5
)
home_tiebreak_share <- ifelse(
  is.finite(home_tiebreak_share),
  home_tiebreak_share,
  fallback_home_tiebreak_share
)
home_tiebreak_share <- pmax(0, pmin(1, home_tiebreak_share))
away_tiebreak_share <- 1 - home_tiebreak_share

home_advance_prob <- ifelse(
  is_knockout_match,
  home_probabilities$pred_home_win_prob + home_probabilities$pred_draw_prob * home_tiebreak_share,
  home_probabilities$pred_home_win_prob
)
away_advance_prob <- ifelse(
  is_knockout_match,
  home_probabilities$pred_away_win_prob + home_probabilities$pred_draw_prob * away_tiebreak_share,
  home_probabilities$pred_away_win_prob
)
predicted_advancing_team <- ifelse(
  is_knockout_match,
  ifelse(home_advance_prob >= away_advance_prob, fixtures_ordered$home_team, fixtures_ordered$away_team),
  NA_character_
)
predicted_advancement_outcome <- ifelse(
  is_knockout_match,
  ifelse(home_advance_prob >= away_advance_prob, "home advances", "away advances"),
  NA_character_
)
final_result_mode <- ifelse(
  is_knockout_match,
  "Knockout: final winner includes extra time and penalties",
  "Group stage: final result can be win, draw, or loss"
)

match_predictions <- data.frame(
  source_match_id = fixtures_ordered$source_match_id,
  date = fixtures_ordered$date,
  home_team = fixtures_ordered$home_team,
  away_team = fixtures_ordered$away_team,
  status = fixtures_ordered$status,
  is_knockout_match = is_knockout_match,
  final_result_mode = final_result_mode,
  city = fixtures_ordered$city,
  country = fixtures_ordered$country,
  neutral = fixtures_ordered$neutral,
  home_score = fixtures_ordered$home_score,
  away_score = fixtures_ordered$away_score,
  actual_result = actual_result,
  pred_home_goals_ols = home_scored$pred_goals_ols,
  pred_away_goals_ols = away_scored$pred_goals_ols,
  pred_home_goals_poisson = home_scored$pred_goals_poisson,
  pred_away_goals_poisson = away_scored$pred_goals_poisson,
  pred_home_win_prob = home_probabilities$pred_home_win_prob,
  pred_draw_prob = home_probabilities$pred_draw_prob,
  pred_away_win_prob = home_probabilities$pred_away_win_prob,
  regulation_draw_prob = home_probabilities$pred_draw_prob,
  home_tiebreak_share = home_tiebreak_share,
  away_tiebreak_share = away_tiebreak_share,
  home_advance_prob = home_advance_prob,
  away_advance_prob = away_advance_prob,
  predicted_result = predicted_result,
  predicted_advancing_team = predicted_advancing_team,
  predicted_advancement_outcome = predicted_advancement_outcome,
  home_latest_elo = fixtures_ordered$home_latest_elo,
  away_latest_elo = fixtures_ordered$away_latest_elo,
  elo_diff_home_minus_away = fixtures_ordered$elo_diff_home_minus_away,
  avg_temperature_2m = fixtures_ordered$avg_temperature_2m,
  avg_relative_humidity_2m = fixtures_ordered$avg_relative_humidity_2m,
  total_precipitation = fixtures_ordered$total_precipitation,
  avg_wind_speed_10m = fixtures_ordered$avg_wind_speed_10m,
  stringsAsFactors = FALSE
)

completed_team_rows <- !is.na(team_fixture_rows$y_goals_for)
ols_rmse <- sqrt(mean((team_fixture_rows$y_goals_for[completed_team_rows] - team_fixture_rows$pred_goals_ols[completed_team_rows])^2, na.rm = TRUE))
ols_mae <- mean(abs(team_fixture_rows$y_goals_for[completed_team_rows] - team_fixture_rows$pred_goals_ols[completed_team_rows]), na.rm = TRUE)
poisson_rmse <- sqrt(mean((team_fixture_rows$y_goals_for[completed_team_rows] - team_fixture_rows$pred_goals_poisson[completed_team_rows])^2, na.rm = TRUE))
poisson_mae <- mean(abs(team_fixture_rows$y_goals_for[completed_team_rows] - team_fixture_rows$pred_goals_poisson[completed_team_rows]), na.rm = TRUE)

completed_match_rows <- !is.na(match_predictions$actual_result)
result_accuracy <- mean(
  match_predictions$actual_result[completed_match_rows] == match_predictions$predicted_result[completed_match_rows],
  na.rm = TRUE
)

metrics <- data.frame(
  metric = c(
    "fixtures_scored",
    "fixtures_with_final_scores",
    "fixtures_with_weather_context",
    "team_rows_scored",
    "knockout_fixtures_scored",
    "knockout_draw_probabilities_reallocated",
    "ols_completed_fixture_rmse",
    "ols_completed_fixture_mae",
    "poisson_completed_fixture_rmse",
    "poisson_completed_fixture_mae",
    "ordinal_completed_fixture_accuracy"
  ),
  value = c(
    nrow(match_predictions),
    sum(completed_match_rows, na.rm = TRUE),
    sum(!is.na(match_predictions$avg_temperature_2m), na.rm = TRUE),
    sum(complete_feature_rows, na.rm = TRUE),
    sum(match_predictions$is_knockout_match, na.rm = TRUE),
    sum(match_predictions$is_knockout_match & is.finite(match_predictions$regulation_draw_prob), na.rm = TRUE),
    ols_rmse,
    ols_mae,
    poisson_rmse,
    poisson_mae,
    result_accuracy
  ),
  stringsAsFactors = FALSE
)

metrics$display_label <- c(
  "Fixtures scored",
  "Fixtures with final scores",
  "Fixtures with weather context",
  "Team-fixture rows scored",
  "Knockout fixtures scored",
  "Knockout draw probabilities reallocated",
  "OLS RMSE on completed fixtures",
  "OLS MAE on completed fixtures",
  "Poisson RMSE on completed fixtures",
  "Poisson MAE on completed fixtures",
  "Ordinal accuracy on completed fixtures"
)

metrics$plain_english <- c(
  "2026 matches with model predictions.",
  "Matches available for early score checking.",
  "Matches with joined weather summaries.",
  "Team-perspective rows that had enough features to score.",
  "Knockout-stage matches with advance probabilities.",
  "Knockout-stage rows where draw-after-regulation was allocated to advance probabilities.",
  "Typical OLS goal miss on completed 2026 team rows.",
  "Average OLS absolute goal miss on completed 2026 team rows.",
  "Typical Poisson goal miss on completed 2026 team rows.",
  "Average Poisson absolute goal miss on completed 2026 team rows.",
  "Share of completed matches where the top predicted outcome matched the result."
)

readr::write_csv(match_predictions, file.path(model_dir, "world_cup_2026_fixture_predictions.csv"))
readr::write_csv(metrics, file.path(model_dir, "world_cup_2026_fixture_prediction_metrics.csv"))
readr::write_csv(team_fixture_rows, file.path(model_dir, "world_cup_2026_team_fixture_predictions.csv"))

cat("\n2026 fixture scoring complete.\n")
cat("Predictions: ", file.path(model_dir, "world_cup_2026_fixture_predictions.csv"), "\n", sep = "")
cat("Metrics: ", file.path(model_dir, "world_cup_2026_fixture_prediction_metrics.csv"), "\n", sep = "")
print(metrics)
