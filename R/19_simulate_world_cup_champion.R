# Simulate the World Cup tournament path from existing fixture predictions.
#
# This script does not refit the match models. It reads the current fixture
# forecasts, projected group seeds, and team strength signals, then produces
# champion and round-reach probabilities for the public site.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
public_dir <- file.path(here::here(), "data", "processed", "public_csv")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

predictions_path <- file.path(model_dir, "world_cup_2026_fixture_predictions.csv")
squads_path <- file.path(public_dir, "dim_2026_world_cup_squad_players.csv")

if (!file.exists(predictions_path)) {
  stop("Fixture predictions were missing. Run R/16_score_2026_fixtures.R first.")
}
if (!file.exists(squads_path)) {
  stop("Squad group metadata was missing. Rebuild processed public CSVs first.")
}

predictions <- readr::read_csv(predictions_path, show_col_types = FALSE)
squads <- readr::read_csv(squads_path, show_col_types = FALSE)

team_key <- function(x) {
  tolower(gsub("[^a-z0-9]", "", x))
}

clip_prob <- function(x, fallback = 0.5) {
  value <- suppressWarnings(as.numeric(x))
  value[!is.finite(value)] <- fallback
  pmax(0.001, pmin(0.999, value))
}

team_groups <- squads |>
  dplyr::select(team, group_name) |>
  dplyr::distinct() |>
  dplyr::mutate(
    group = gsub("^Group\\s+", "", group_name),
    team_join_key = team_key(team)
  ) |>
  dplyr::select(team_join_key, group)

predictions <- predictions |>
  dplyr::mutate(
    date = as.Date(date),
    is_knockout_match = as.logical(is_knockout_match),
    home_join_key = team_key(home_team),
    away_join_key = team_key(away_team)
  ) |>
  dplyr::left_join(team_groups, by = c("home_join_key" = "team_join_key")) |>
  dplyr::rename(home_group = group) |>
  dplyr::left_join(team_groups, by = c("away_join_key" = "team_join_key")) |>
  dplyr::rename(away_group = group)

home_strength <- predictions |>
  dplyr::select(team = home_team, team_key = home_join_key, elo = home_latest_elo)
away_strength <- predictions |>
  dplyr::select(team = away_team, team_key = away_join_key, elo = away_latest_elo)

team_strength <- dplyr::bind_rows(home_strength, away_strength) |>
  dplyr::group_by(team_key, team) |>
  dplyr::summarise(elo = max(elo, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(elo = ifelse(is.infinite(elo), NA_real_, elo))

teams <- squads |>
  dplyr::select(team, group_name) |>
  dplyr::distinct() |>
  dplyr::mutate(
    group = gsub("^Group\\s+", "", group_name),
    team_key = team_key(team)
  ) |>
  dplyr::left_join(team_strength |> dplyr::select(team_key, elo), by = "team_key") |>
  dplyr::mutate(elo = ifelse(is.na(elo), median(elo, na.rm = TRUE), elo))

group_matches <- predictions |>
  dplyr::filter(!is_knockout_match, !is.na(home_group), !is.na(away_group))

knockout_lookup <- predictions |>
  dplyr::filter(is_knockout_match) |>
  dplyr::mutate(
    pair_key = ifelse(
      home_join_key < away_join_key,
      paste(home_join_key, away_join_key, sep = "|"),
      paste(away_join_key, home_join_key, sep = "|")
    )
  ) |>
  dplyr::select(
    pair_key,
    home_join_key,
    away_join_key,
    home_advance_prob,
    away_advance_prob
  )

slot_pairs <- data.frame(
  match_id = seq_len(16),
  slot_a = c("A2", "F1", "E1", "I1", "K2", "H1", "D1", "G1", "C1", "E2", "A1", "L1", "J1", "D2", "B1", "K1"),
  slot_b = c("B2", "C2", "ABCDF3", "CDFGH3", "L2", "J2", "BEFIJ3", "AEHIJ3", "F2", "I2", "CEFHI3", "EHIJK3", "H2", "G2", "EFGIJ3", "DEIJL3"),
  stringsAsFactors = FALSE
)

empty_counts <- function() {
  data.frame(
    team = teams$team,
    group = teams$group,
    simulations = 0L,
    round_of_32 = 0L,
    round_of_16 = 0L,
    quarterfinal = 0L,
    semifinal = 0L,
    final = 0L,
    champion = 0L,
    stringsAsFactors = FALSE
  )
}

score_match <- function(row) {
  completed <- !is.na(row$home_score) && !is.na(row$away_score)
  if (completed) {
    home_goals <- as.integer(row$home_score)
    away_goals <- as.integer(row$away_score)
  } else {
    home_lambda <- max(0.05, suppressWarnings(as.numeric(row$pred_home_goals_poisson)))
    away_lambda <- max(0.05, suppressWarnings(as.numeric(row$pred_away_goals_poisson)))
    home_goals <- stats::rpois(1, home_lambda)
    away_goals <- stats::rpois(1, away_lambda)
  }

  data.frame(
    group = as.character(row$home_group),
    home_team = as.character(row$home_team),
    away_team = as.character(row$away_team),
    home_goals = home_goals,
    away_goals = away_goals,
    stringsAsFactors = FALSE
  )
}

simulate_group_table <- function() {
  scores <- do.call(
    rbind,
    lapply(seq_len(nrow(group_matches)), function(i) score_match(group_matches[i, ]))
  )

  home_rows <- data.frame(
    group = scores$group,
    team = scores$home_team,
    points = ifelse(scores$home_goals > scores$away_goals, 3, ifelse(scores$home_goals == scores$away_goals, 1, 0)),
    gf = scores$home_goals,
    ga = scores$away_goals,
    stringsAsFactors = FALSE
  )
  away_rows <- data.frame(
    group = scores$group,
    team = scores$away_team,
    points = ifelse(scores$away_goals > scores$home_goals, 3, ifelse(scores$away_goals == scores$home_goals, 1, 0)),
    gf = scores$away_goals,
    ga = scores$home_goals,
    stringsAsFactors = FALSE
  )

  dplyr::bind_rows(home_rows, away_rows) |>
    dplyr::group_by(group, team) |>
    dplyr::summarise(
      points = sum(points, na.rm = TRUE),
      gf = sum(gf, na.rm = TRUE),
      ga = sum(ga, na.rm = TRUE),
      gd = gf - ga,
      .groups = "drop"
    ) |>
    dplyr::left_join(teams |> dplyr::select(team, elo), by = "team") |>
    dplyr::mutate(tie_noise = stats::runif(dplyr::n(), 0, 0.0001)) |>
    dplyr::arrange(group, dplyr::desc(points), dplyr::desc(gd), dplyr::desc(gf), dplyr::desc(elo), dplyr::desc(tie_noise), team) |>
    dplyr::group_by(group) |>
    dplyr::mutate(position = dplyr::row_number()) |>
    dplyr::ungroup()
}

as_team_record <- function(row) {
  if (nrow(row) == 0) {
    return(NULL)
  }
  list(
    team = as.character(row$team[[1]]),
    team_key = team_key(row$team[[1]]),
    group = as.character(row$group[[1]]),
    seed = paste0(row$group[[1]], row$position[[1]]),
    elo = suppressWarnings(as.numeric(row$elo[[1]]))
  )
}

resolve_slots <- function(standings) {
  third_pool <- standings |>
    dplyr::filter(position == 3) |>
    dplyr::arrange(dplyr::desc(points), dplyr::desc(gd), dplyr::desc(gf), dplyr::desc(elo), team) |>
    dplyr::mutate(third_rank = dplyr::row_number(), qualifies = third_rank <= 8)

  used_third_teams <- character()
  resolve_slot <- function(slot) {
    if (grepl("^[A-L][12]$", slot)) {
      group <- substr(slot, 1, 1)
      position <- as.integer(substr(slot, 2, 2))
      return(as_team_record(standings[standings$group == group & standings$position == position, ]))
    }

    if (grepl("3$", slot)) {
      candidate_groups <- strsplit(sub("3$", "", slot), "")[[1]]
      row <- third_pool |>
        dplyr::filter(group %in% candidate_groups, !(team %in% used_third_teams), qualifies) |>
        dplyr::arrange(third_rank) |>
        dplyr::slice_head(n = 1)
      if (nrow(row) > 0) {
        used_third_teams <<- c(used_third_teams, row$team[[1]])
      }
      return(as_team_record(row))
    }

    NULL
  }

  lapply(seq_len(nrow(slot_pairs)), function(i) {
    list(
      team_a = resolve_slot(slot_pairs$slot_a[[i]]),
      team_b = resolve_slot(slot_pairs$slot_b[[i]])
    )
  })
}

pair_probability <- function(team_a, team_b) {
  if (is.null(team_a) || is.null(team_b)) {
    return(NA_real_)
  }

  pair_key <- ifelse(
    team_a$team_key < team_b$team_key,
    paste(team_a$team_key, team_b$team_key, sep = "|"),
    paste(team_b$team_key, team_a$team_key, sep = "|")
  )
  lookup <- knockout_lookup[knockout_lookup$pair_key == pair_key, ]
  if (nrow(lookup) > 0) {
    row <- lookup[1, ]
    if (team_a$team_key == row$home_join_key[[1]]) {
      return(clip_prob(row$home_advance_prob[[1]]))
    }
    if (team_a$team_key == row$away_join_key[[1]]) {
      return(clip_prob(row$away_advance_prob[[1]]))
    }
  }

  elo_a <- ifelse(is.finite(team_a$elo), team_a$elo, median(teams$elo, na.rm = TRUE))
  elo_b <- ifelse(is.finite(team_b$elo), team_b$elo, median(teams$elo, na.rm = TRUE))
  clip_prob(1 / (1 + 10^(-((elo_a - elo_b) / 400))))
}

advance_one <- function(match) {
  team_a <- match$team_a
  team_b <- match$team_b
  if (is.null(team_a)) {
    return(team_b)
  }
  if (is.null(team_b)) {
    return(team_a)
  }
  if (stats::runif(1) <= pair_probability(team_a, team_b)) team_a else team_b
}

simulate_knockout <- function(round32) {
  rounds <- list(round32 = round32)
  winners <- list()
  current <- round32
  round_names <- c("round_of_16", "quarterfinal", "semifinal", "final", "champion")

  for (round_name in round_names) {
    winners_this_round <- lapply(current, advance_one)
    winners[[round_name]] <- winners_this_round
    if (round_name == "champion") {
      break
    }
    next_round <- list()
    for (i in seq(1, length(winners_this_round), by = 2)) {
      next_round[[length(next_round) + 1]] <- list(
        team_a = winners_this_round[[i]],
        team_b = winners_this_round[[i + 1]]
      )
    }
    current <- next_round
  }
  winners
}

increment_counts <- function(counts, round_name, teams_in_round) {
  round_teams <- vapply(teams_in_round, function(x) if (is.null(x)) NA_character_ else x$team, character(1))
  round_teams <- round_teams[!is.na(round_teams)]
  counts[[round_name]] <- counts[[round_name]] + as.integer(counts$team %in% round_teams)
  counts
}

n_simulations <- suppressWarnings(as.integer(Sys.getenv("WC_CHAMPION_SIMS", "5000")))
if (!is.finite(n_simulations) || n_simulations < 100) {
  n_simulations <- 5000L
}

set.seed(20260629)
counts <- empty_counts()
all_group_matches_complete <- all(!is.na(group_matches$home_score) & !is.na(group_matches$away_score))
static_round32 <- NULL
if (all_group_matches_complete) {
  static_round32 <- resolve_slots(simulate_group_table())
}

for (simulation_id in seq_len(n_simulations)) {
  if (all_group_matches_complete) {
    round32 <- static_round32
  } else {
    standings <- simulate_group_table()
    round32 <- resolve_slots(standings)
  }
  knockout <- simulate_knockout(round32)

  counts$simulations <- counts$simulations + 1L
  counts <- increment_counts(counts, "round_of_32", unlist(round32, recursive = FALSE))
  counts <- increment_counts(counts, "round_of_16", knockout$round_of_16)
  counts <- increment_counts(counts, "quarterfinal", knockout$quarterfinal)
  counts <- increment_counts(counts, "semifinal", knockout$semifinal)
  counts <- increment_counts(counts, "final", knockout$final)
  counts <- increment_counts(counts, "champion", knockout$champion)
}

summary <- counts |>
  dplyr::mutate(
    round_of_32_probability = round_of_32 / simulations,
    round_of_16_probability = round_of_16 / simulations,
    quarterfinal_probability = quarterfinal / simulations,
    semifinal_probability = semifinal / simulations,
    final_probability = final / simulations,
    champion_probability = champion / simulations
  ) |>
  dplyr::arrange(dplyr::desc(champion_probability), dplyr::desc(final_probability), team)

metadata <- data.frame(
  metric = c(
    "simulated_at_utc",
    "simulations",
    "teams",
    "group_matches",
    "completed_group_matches",
    "group_seeds_cached",
    "knockout_match_predictions_available",
    "later_round_fallback"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_simulations,
    nrow(teams),
    nrow(group_matches),
    sum(!is.na(group_matches$home_score) & !is.na(group_matches$away_score)),
    all_group_matches_complete,
    nrow(knockout_lookup),
    "Elo-style strength probability when exact fixture-pair forecasts are not available"
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(summary, file.path(model_dir, "world_cup_2026_champion_simulation_summary.csv"))
readr::write_csv(metadata, file.path(model_dir, "world_cup_2026_champion_simulation_metadata.csv"))

cat("\nWorld Cup champion simulation complete.\n")
cat("Simulations: ", n_simulations, "\n", sep = "")
cat("Summary: ", file.path(model_dir, "world_cup_2026_champion_simulation_summary.csv"), "\n", sep = "")
print(head(summary, 12))
