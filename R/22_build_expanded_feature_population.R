# Expanded historical feature population for challenger models.
#
# This builds a richer team-match modeling frame from local DuckDB data. It
# uses only information available before each match: Elo strength, rolling team
# form, opponent form, head-to-head history, rest days, and tournament context.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

matches <- DBI::dbGetQuery(con, "
  SELECT
    source_match_id,
    date,
    tournament,
    city,
    country,
    neutral,
    k_factor,
    goal_multiplier,
    team,
    opponent,
    listed_home,
    goals_for,
    goals_against,
    pre_elo,
    opponent_pre_elo,
    expected_result,
    actual_result,
    elo_change,
    post_elo
  FROM fact_team_elo_match_history
  WHERE date IS NOT NULL
    AND team IS NOT NULL
    AND opponent IS NOT NULL
    AND goals_for IS NOT NULL
    AND goals_against IS NOT NULL
")

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

matches$date <- as.Date(matches$date)
matches$match_year <- as.integer(format(matches$date, "%Y"))
matches$neutral <- as.logical(matches$neutral)
matches$listed_home <- as.logical(matches$listed_home)
matches$goals_for <- as.numeric(matches$goals_for)
matches$goals_against <- as.numeric(matches$goals_against)
matches$goal_diff <- matches$goals_for - matches$goals_against
matches$points <- ifelse(matches$goals_for > matches$goals_against, 3, ifelse(matches$goals_for == matches$goals_against, 1, 0))
matches$win <- as.integer(matches$goals_for > matches$goals_against)
matches$draw <- as.integer(matches$goals_for == matches$goals_against)
matches$loss <- as.integer(matches$goals_for < matches$goals_against)
matches$scored_any <- as.integer(matches$goals_for > 0)
matches$clean_sheet <- as.integer(matches$goals_against == 0)
matches$failed_to_score <- as.integer(matches$goals_for == 0)
matches$y_result_ordered <- factor(
  ifelse(matches$goals_for > matches$goals_against, "win", ifelse(matches$goals_for == matches$goals_against, "draw", "loss")),
  levels = c("loss", "draw", "win")
)

tournament_lower <- tolower(matches$tournament)
matches$is_world_cup <- tournament_lower == "fifa world cup"
matches$is_world_cup_qualifier <- grepl("world cup qualification", tournament_lower, fixed = TRUE)
matches$is_friendly <- tournament_lower == "friendly"
matches$is_qualifier <- grepl("qualification", tournament_lower, fixed = TRUE)
matches$is_nations_league <- grepl("nations league", tournament_lower, fixed = TRUE)
matches$is_continental_championship <- grepl(
  "uefa euro|copa am.rica|african cup of nations|asian cup|gold cup|oceania nations cup",
  tournament_lower
)
matches$is_major_tournament <- matches$is_world_cup | matches$is_continental_championship
matches$is_modern_era <- matches$match_year >= 1990
matches$is_recent_era <- matches$match_year >= 2000
matches$elo_diff <- matches$pre_elo - matches$opponent_pre_elo

roll_prev_mean <- function(x, n) {
  x <- as.numeric(x)
  ok <- !is.na(x)
  x0 <- ifelse(ok, x, 0)
  cs <- c(0, cumsum(x0))
  cn <- c(0, cumsum(as.integer(ok)))
  idx <- seq_along(x)
  start <- pmax(1, idx - n)
  num <- cs[idx] - cs[start]
  den <- cn[idx] - cn[start]
  ifelse(den > 0, num / den, NA_real_)
}

roll_prev_sum <- function(x, n) {
  x <- as.numeric(x)
  ok <- !is.na(x)
  x0 <- ifelse(ok, x, 0)
  cs <- c(0, cumsum(x0))
  idx <- seq_along(x)
  start <- pmax(1, idx - n)
  cs[idx] - cs[start]
}

add_rolling_features <- function(df, prefix, windows = c(3, 5, 10, 20)) {
  df <- df[order(df$date, df$source_match_id, df$team, df$opponent), ]
  df[[paste0(prefix, "matches_prior")]] <- seq_len(nrow(df)) - 1
  prior_date <- dplyr::lag(df$date)
  df[[paste0(prefix, "days_since_match")]] <- as.numeric(df$date - prior_date)

  for (window in windows) {
    suffix <- paste0("_l", window)
    df[[paste0(prefix, "points_pg", suffix)]] <- roll_prev_mean(df$points, window)
    df[[paste0(prefix, "wins_pg", suffix)]] <- roll_prev_mean(df$win, window)
    df[[paste0(prefix, "draws_pg", suffix)]] <- roll_prev_mean(df$draw, window)
    df[[paste0(prefix, "goals_for_pg", suffix)]] <- roll_prev_mean(df$goals_for, window)
    df[[paste0(prefix, "goals_against_pg", suffix)]] <- roll_prev_mean(df$goals_against, window)
    df[[paste0(prefix, "goal_diff_pg", suffix)]] <- roll_prev_mean(df$goal_diff, window)
    df[[paste0(prefix, "scored_any_pg", suffix)]] <- roll_prev_mean(df$scored_any, window)
    df[[paste0(prefix, "clean_sheet_pg", suffix)]] <- roll_prev_mean(df$clean_sheet, window)
    df[[paste0(prefix, "failed_to_score_pg", suffix)]] <- roll_prev_mean(df$failed_to_score, window)
    df[[paste0(prefix, "points_total", suffix)]] <- roll_prev_sum(df$points, window)
  }

  df
}

team_split <- split(matches, matches$team)
team_features <- dplyr::bind_rows(lapply(team_split, add_rolling_features, prefix = "team_"))

opponent_columns <- names(team_features)[startsWith(names(team_features), "team_")]
opponent_lookup <- team_features[, c("source_match_id", "team", "opponent", opponent_columns)]
names(opponent_lookup)[2:3] <- c("opponent", "team")
names(opponent_lookup)[match(opponent_columns, names(opponent_lookup))] <- sub("^team_", "opp_", opponent_columns)

expanded <- dplyr::left_join(
  team_features,
  opponent_lookup,
  by = c("source_match_id", "team", "opponent")
)

h2h_base <- expanded
h2h_base$pair_key <- ifelse(h2h_base$team < h2h_base$opponent,
  paste(h2h_base$team, h2h_base$opponent, sep = " | "),
  paste(h2h_base$opponent, h2h_base$team, sep = " | ")
)
h2h_split <- split(h2h_base, paste(h2h_base$team, h2h_base$opponent, sep = " | "))
h2h_features <- dplyr::bind_rows(lapply(h2h_split, add_rolling_features, prefix = "h2h_", windows = c(3, 5, 10)))
h2h_columns <- names(h2h_features)[startsWith(names(h2h_features), "h2h_")]
h2h_lookup <- h2h_features[, c("source_match_id", "team", "opponent", h2h_columns)]

expanded <- dplyr::left_join(
  expanded,
  h2h_lookup,
  by = c("source_match_id", "team", "opponent")
)

for (window in c(3, 5, 10, 20)) {
  suffix <- paste0("_l", window)
  if (all(c(paste0("team_points_pg", suffix), paste0("opp_points_pg", suffix)) %in% names(expanded))) {
    expanded[[paste0("form_points_diff", suffix)]] <- expanded[[paste0("team_points_pg", suffix)]] - expanded[[paste0("opp_points_pg", suffix)]]
    expanded[[paste0("form_goal_diff", suffix)]] <- expanded[[paste0("team_goal_diff_pg", suffix)]] - expanded[[paste0("opp_goal_diff_pg", suffix)]]
    expanded[[paste0("attack_vs_defense", suffix)]] <- expanded[[paste0("team_goals_for_pg", suffix)]] - expanded[[paste0("opp_goals_against_pg", suffix)]]
    expanded[[paste0("defense_vs_attack", suffix)]] <- expanded[[paste0("team_goals_against_pg", suffix)]] - expanded[[paste0("opp_goals_for_pg", suffix)]]
  }
}

expanded$team_days_since_match_capped <- pmin(expanded$team_days_since_match, 120)
expanded$opp_days_since_match_capped <- pmin(expanded$opp_days_since_match, 120)
expanded$team_experience_log <- log1p(expanded$team_matches_prior)
expanded$opp_experience_log <- log1p(expanded$opp_matches_prior)
expanded$experience_diff_log <- expanded$team_experience_log - expanded$opp_experience_log

expanded <- expanded[order(expanded$date, expanded$source_match_id, expanded$team, expanded$opponent), ]

metadata <- data.frame(
  field = names(expanded),
  source = dplyr::case_when(
    names(expanded) %in% names(matches) ~ "fact_team_elo_match_history",
    startsWith(names(expanded), "team_") ~ "pre-match rolling team history",
    startsWith(names(expanded), "opp_") ~ "pre-match rolling opponent history",
    startsWith(names(expanded), "h2h_") ~ "pre-match head-to-head history",
    grepl("^form_|^attack_|^defense_|experience", names(expanded)) ~ "derived pre-match comparison",
    TRUE ~ "derived feature"
  ),
  leakage_rule = "Uses only rows dated before the current team-match row.",
  stringsAsFactors = FALSE
)

summary <- data.frame(
  metric = c(
    "rows",
    "matches",
    "teams",
    "first_match",
    "last_match",
    "feature_columns",
    "world_cup_team_rows",
    "friendly_team_rows",
    "recent_era_team_rows"
  ),
  value = c(
    as.character(nrow(expanded)),
    as.character(length(unique(expanded$source_match_id))),
    as.character(length(unique(expanded$team))),
    as.character(min(expanded$date, na.rm = TRUE)),
    as.character(max(expanded$date, na.rm = TRUE)),
    as.character(ncol(expanded)),
    as.character(sum(expanded$is_world_cup, na.rm = TRUE)),
    as.character(sum(expanded$is_friendly, na.rm = TRUE)),
    as.character(sum(expanded$is_recent_era, na.rm = TRUE))
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(expanded, file.path(model_dir, "expanded_population_model_frame.csv"))
readr::write_csv(utils::head(expanded, 1000), file.path(model_dir, "expanded_population_model_sample_1000.csv"))
readr::write_csv(metadata, file.path(model_dir, "expanded_population_metadata.csv"))
readr::write_csv(summary, file.path(model_dir, "expanded_population_summary.csv"))

cat("\nExpanded population feature frame complete.\n")
cat("Rows: ", nrow(expanded), "\n", sep = "")
cat("Columns: ", ncol(expanded), "\n", sep = "")
cat("Output: ", file.path(model_dir, "expanded_population_model_frame.csv"), "\n", sep = "")
print(summary)
