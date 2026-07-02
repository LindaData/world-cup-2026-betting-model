# Reusable presentation helpers for the consumer-facing World Cup pages.
# These helpers read existing model outputs and render HTML. They do not fit
# models, change predictions, or alter data methodology.

read_csv_if_exists <- function(path) {
  if (file.exists(path)) {
    readr::read_csv(path, show_col_types = FALSE)
  } else {
    data.frame()
  }
}

escape_html <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

safe_text <- function(x, fallback = "Not available yet") {
  if (length(x) == 0 || is.null(x)) {
    return(fallback)
  }
  text <- as.character(x[[1]])
  if (is.na(text) || !nzchar(text) || text == "NA" || text == "Pending") {
    fallback
  } else {
    text
  }
}

safe_number <- function(x) {
  if (length(x) == 0 || is.null(x)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(x[[1]]))
}

is_truthy <- function(x) {
  if (length(x) == 0 || is.null(x)) {
    return(FALSE)
  }
  tolower(as.character(x[[1]])) %in% c("true", "1", "yes")
}

is_knockout_forecast <- function(row) {
  is_truthy(row$is_knockout_match)
}

display_percent <- function(x, digits = 1, fallback = "Not available yet") {
  value <- safe_number(x)
  if (is.na(value) || !is.finite(value)) {
    fallback
  } else {
    fmt_percent(value, digits)
  }
}

display_number <- function(x, digits = 2, fallback = "Not available yet") {
  value <- safe_number(x)
  if (is.na(value) || !is.finite(value)) {
    fallback
  } else {
    fmt_number(value, digits)
  }
}

probability_width <- function(x) {
  value <- safe_number(x)
  if (is.na(value) || !is.finite(value)) {
    return(0)
  }
  max(0, min(100, 100 * value))
}

parse_utc_time <- function(x) {
  if (length(x) == 0 || is.null(x)) {
    return(as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"))
  }
  if (inherits(x, "POSIXt")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  text <- as.character(x)
  text <- sub("Z$", "", text)
  text <- gsub("T", " ", text, fixed = TRUE)
  as.POSIXct(text, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

normalize_utc_iso <- function(x) {
  if (length(x) == 0 || is.null(x)) {
    return(NA_character_)
  }
  text <- as.character(x[[1]])
  if (is.na(text) || !nzchar(text)) {
    return(NA_character_)
  }
  if (grepl("Z$", text)) {
    text
  } else {
    paste0(text, "Z")
  }
}

time_tag <- function(x, class_name = "js-local-time", fallback = "Time not posted") {
  iso <- normalize_utc_iso(x)
  parsed <- parse_utc_time(iso)
  if (is.na(iso) || is.na(parsed)) {
    return(paste0('<span class="time-unavailable">', escape_html(fallback), "</span>"))
  }
  fallback_text <- format(parsed, "%b %d, %I:%M %p UTC", tz = "UTC")
  paste0(
    '<time class="', escape_html(class_name), '" datetime="', escape_html(iso), '">',
    escape_html(fallback_text),
    "</time>"
  )
}

match_time_display <- function(row, fallback = "Kickoff time not posted") {
  iso <- normalize_utc_iso(row$kickoff_utc_iso)
  parsed <- parse_utc_time(iso)
  if (!is.na(iso) && !is.na(parsed)) {
    return(time_tag(row$kickoff_utc_iso))
  }

  date_value <- suppressWarnings(as.Date(row$date[[1]]))
  if (!is.na(date_value)) {
    return(paste0(
      '<span class="time-unavailable">',
      escape_html(format(date_value, "%a, %b %d")),
      ' <small>', escape_html(fallback), '</small></span>'
    ))
  }

  paste0('<span class="time-unavailable">', escape_html(fallback), "</span>")
}

refresh_time_display <- function(row) {
  iso <- normalize_utc_iso(row$refresh_utc_iso)
  parsed <- parse_utc_time(iso)
  if (!is.na(iso) && !is.na(parsed)) {
    return(time_tag(row$refresh_utc_iso, "js-local-time forecast-refresh-time", "Refresh time not posted"))
  }
  '<span class="time-unavailable">Refresh will update when kickoff time is posted.</span>'
}

summary_value <- function(summary, metric, fallback = "Not available yet") {
  if (nrow(summary) == 0 || !"metric" %in% names(summary) || !"value" %in% names(summary)) {
    return(fallback)
  }
  value <- summary$value[summary$metric == metric]
  if (length(value) == 0 || is.na(value[[1]]) || !nzchar(as.character(value[[1]]))) {
    fallback
  } else {
    as.character(value[[1]])
  }
}

tournament_phase <- function(summary) {
  completed <- suppressWarnings(as.integer(summary_value(summary, "completed_matches", "0")))
  upcoming <- suppressWarnings(as.integer(summary_value(summary, "upcoming_matches", "0")))
  total <- suppressWarnings(as.integer(summary_value(summary, "matches_on_board", "0")))
  if (is.na(completed)) completed <- 0
  if (is.na(upcoming)) upcoming <- 0
  if (is.na(total)) total <- 0

  dplyr::case_when(
    total >= 88 && completed >= 88 ~ "Tournament complete",
    total >= 88 && completed >= 72 && upcoming > 0 ~ "Knockout stage",
    completed >= 72 && upcoming > 0 ~ "Post-group stage",
    completed > 0 ~ "Group stage in progress",
    TRUE ~ "Pre-tournament"
  )
}

load_matchday_bundle <- function(root) {
  model_dir <- file.path(root, "data", "processed", "modeling")
  list(
    board = read_csv_if_exists(file.path(model_dir, "matchday_prediction_board.csv")),
    summary = read_csv_if_exists(file.path(model_dir, "matchday_prediction_summary.csv")),
    accuracy = read_csv_if_exists(file.path(model_dir, "matchday_model_accuracy.csv")),
    accuracy_detail = read_csv_if_exists(file.path(model_dir, "matchday_model_accuracy_detail.csv")),
    fixture_metrics = read_csv_if_exists(file.path(model_dir, "world_cup_2026_fixture_prediction_metrics.csv")),
    ordinal_metrics = read_csv_if_exists(file.path(model_dir, "result_ordinal_model_metrics.csv")),
    goals_metrics = read_csv_if_exists(file.path(model_dir, "goals_linear_model_metrics.csv")),
    poisson_metrics = read_csv_if_exists(file.path(model_dir, "goals_poisson_model_metrics.csv")),
    data_sources = read_csv_if_exists(file.path(model_dir, "matchday_prediction_data_sources.csv")),
    challenger_metrics = read_csv_if_exists(file.path(model_dir, "model_challenger_metrics.csv")),
    challenger_importance = read_csv_if_exists(file.path(model_dir, "model_challenger_feature_importance.csv")),
    challenger_status = read_csv_if_exists(file.path(model_dir, "model_challenger_status.csv")),
    expanded_goal_metrics = read_csv_if_exists(file.path(model_dir, "population_expansion_goal_metrics.csv")),
    expanded_result_metrics = read_csv_if_exists(file.path(model_dir, "population_expansion_result_metrics.csv")),
    expanded_population_status = read_csv_if_exists(file.path(model_dir, "population_expansion_status.csv")),
    champion_summary = read_csv_if_exists(file.path(model_dir, "world_cup_2026_champion_simulation_summary.csv")),
    champion_metadata = read_csv_if_exists(file.path(model_dir, "world_cup_2026_champion_simulation_metadata.csv")),
    archive_watch_registry = read_csv_if_exists(file.path(model_dir, "game_archive_watch_registry.csv")),
    archive_review_board = read_csv_if_exists(file.path(model_dir, "game_archive_review_board.csv")),
    archive_summary = read_csv_if_exists(file.path(model_dir, "game_archive_summary.csv"))
  )
}

prepare_board <- function(board) {
  if (nrow(board) == 0) {
    return(board)
  }
  board |>
    dplyr::mutate(
      kickoff_utc = parse_utc_time(kickoff_utc_iso),
      render_day = as.Date(kickoff_utc, tz = "UTC")
    ) |>
    dplyr::arrange(kickoff_utc, date, source_match_id)
}

future_board <- function(board) {
  board <- prepare_board(board)
  if (nrow(board) == 0) {
    return(board)
  }
  now_utc <- as.POSIXct(Sys.time(), tz = "UTC")
  board |>
    dplyr::filter(
      match_timing != "Completed",
      is.na(kickoff_utc) | kickoff_utc >= now_utc | match_timing == "Pending score"
    ) |>
    dplyr::arrange(kickoff_utc, date, source_match_id)
}

today_board <- function(board) {
  board <- prepare_board(board)
  if (nrow(board) == 0) {
    return(board)
  }
  today <- Sys.Date()
  board |>
    dplyr::filter(
      match_timing != "Completed",
      as.Date(kickoff_utc, tz = "America/New_York") == today | as.Date(date) == today
    ) |>
    dplyr::arrange(kickoff_utc, date, source_match_id)
}

prediction_strength <- function(row) {
  band <- safe_text(row$confidence_band, "Low")
  dplyr::case_when(
    band == "Lean" ~ "Low",
    band == "Medium" ~ "Moderate",
    band == "Strong" ~ "Strong",
    TRUE ~ band
  )
}

model_agreement <- function(row) {
  pick <- safe_text(row$predicted_winner, "")
  votes <- c(
    safe_text(row$ols_predicted_winner, ""),
    safe_text(row$poisson_predicted_winner, ""),
    safe_text(row$ordinal_predicted_winner, "")
  )
  usable <- nzchar(votes)
  if (!nzchar(pick) || !any(usable)) {
    return("Model agreement not available yet")
  }
  paste0(sum(votes[usable] == pick), " of ", sum(usable), " models")
}

model_suite_count <- function(bundle) {
  names <- character()
  if (!is.null(bundle$challenger_metrics) && nrow(bundle$challenger_metrics) > 0 && "model" %in% names(bundle$challenger_metrics)) {
    names <- c(names, as.character(bundle$challenger_metrics$model))
  }
  if (!is.null(bundle$expanded_goal_metrics) && nrow(bundle$expanded_goal_metrics) > 0 && "model" %in% names(bundle$expanded_goal_metrics)) {
    names <- c(names, as.character(bundle$expanded_goal_metrics$model))
  }
  if (!is.null(bundle$expanded_result_metrics) && nrow(bundle$expanded_result_metrics) > 0 && "model" %in% names(bundle$expanded_result_metrics)) {
    names <- c(names, as.character(bundle$expanded_result_metrics$model))
  }
  length(unique(names[nzchar(names)]))
}

best_metric_row <- function(df, metric, validation = NULL) {
  if (is.null(df) || nrow(df) == 0 || !all(c(metric, "status") %in% names(df))) {
    return(data.frame())
  }
  rows <- df |> dplyr::filter(.data$status == "fit")
  if (!is.null(validation) && "validation_type" %in% names(rows)) {
    filtered <- rows |> dplyr::filter(.data$validation_type == validation)
    if (nrow(filtered) > 0) {
      rows <- filtered
    }
  }
  if (nrow(rows) == 0) {
    return(data.frame())
  }
  rows |>
    dplyr::arrange(.data[[metric]]) |>
    dplyr::slice_head(n = 1)
}

render_model_suite_strip <- function(bundle, compact = TRUE, base_path = "reports/10_model_challengers.html") {
  goal_best <- best_metric_row(bundle$expanded_goal_metrics, "test_rmse", "recent_2000_time_2019_plus")
  result_best <- best_metric_row(bundle$expanded_result_metrics, "test_multiclass_brier", "recent_2000_time_2019_plus")
  small_best <- if (!is.null(bundle$challenger_metrics) && nrow(bundle$challenger_metrics) > 0) {
    bundle$challenger_metrics |>
      dplyr::filter(.data$status == "fit") |>
      dplyr::arrange(.data$test_rmse) |>
      dplyr::slice_head(n = 1)
  } else {
    data.frame()
  }

  suite_total <- model_suite_count(bundle)
  cards <- list(
    data.frame(
      label = "Model bench",
      value = ifelse(suite_total > 0, paste0(suite_total, " models"), "Pending"),
      note = "OLS, Poisson, KNN, ordinal, multinomial, GAM, GBM, XGBoost, random forest, SVM",
      stringsAsFactors = FALSE
    )
  )
  if (nrow(goal_best) > 0) {
    cards[[length(cards) + 1]] <- data.frame(
      label = "Best goals model",
      value = goal_best$model[[1]],
      note = paste0("Recent time split RMSE ", fmt_number(goal_best$test_rmse[[1]], 3)),
      stringsAsFactors = FALSE
    )
  }
  if (nrow(result_best) > 0) {
    cards[[length(cards) + 1]] <- data.frame(
      label = "Best result model",
      value = result_best$model[[1]],
      note = paste0("Recent time split Brier ", fmt_number(result_best$test_multiclass_brier[[1]], 3)),
      stringsAsFactors = FALSE
    )
  }
  if (nrow(small_best) > 0) {
    cards[[length(cards) + 1]] <- data.frame(
      label = "Tree challenger",
      value = small_best$model[[1]],
      note = paste0("Held-out RMSE ", fmt_number(small_best$test_rmse[[1]], 3)),
      stringsAsFactors = FALSE
    )
  }

  cards <- dplyr::bind_rows(cards)
  card_html <- vapply(seq_len(nrow(cards)), function(i) {
    row <- cards[i, ]
    paste0(
      '<article class="model-lab-chip">',
      '<span>', escape_html(row$label[[1]]), '</span>',
      '<strong>', escape_html(row$value[[1]]), '</strong>',
      '<small>', escape_html(row$note[[1]]), '</small>',
      '</article>'
    )
  }, character(1))

  class_name <- if (compact) "model-lab-strip model-lab-strip-compact" else "model-lab-strip"
  paste0(
    '<section class="', class_name, '" aria-label="Expanded model suite summary">',
    '<div class="model-lab-copy">',
    '<span class="section-kicker">Model lab</span>',
    '<h2>Expanded Forecast Bench</h2>',
    '<p>The public pick remains the stable production ensemble. The model lab now runs a larger challenger bench and uses backtesting to decide what earns promotion.</p>',
    '</div>',
    '<div class="model-lab-grid">',
    paste(card_html, collapse = ""),
    '</div>',
    '<a class="button-secondary model-lab-link" href="', escape_html(base_path), '">Open model comparison</a>',
    '</section>'
  )
}

probability_edge <- function(row) {
  probs <- if (is_knockout_forecast(row)) {
    c(
      safe_number(row$home_advance_prob),
      safe_number(row$away_advance_prob)
    )
  } else {
    c(
      safe_number(row$ensemble_home_win_prob),
      safe_number(row$ensemble_draw_prob),
      safe_number(row$ensemble_away_win_prob)
    )
  }
  probs <- probs[is.finite(probs)]
  if (length(probs) < 2) {
    return("Not available yet")
  }
  probs <- sort(probs, decreasing = TRUE)
  paste0(fmt_number(100 * (probs[[1]] - probs[[2]]), 1), " percentage points")
}

probability_row <- function(label, value, class_name) {
  paste0(
    '<div class="forecast-prob-row">',
    '<div class="forecast-prob-label"><span>', escape_html(label), '</span><strong>',
    display_percent(value, 1),
    '</strong></div>',
    '<div class="forecast-prob-track" aria-hidden="true"><span class="', class_name, '" style="width:',
    fmt_number(probability_width(value), 1),
    '%"></span></div>',
    '</div>'
  )
}

lineup_text <- function(row) {
  home <- safe_text(row$home_lineup_status, "Lineup pending")
  away <- safe_text(row$away_lineup_status, "Lineup pending")
  if (home == "Lineup pending" && away == "Lineup pending") {
    "Lineups are not available yet."
  } else {
    paste(home, "/", away)
  }
}

yellow_card_text <- function(row) {
  home_cards <- safe_number(row$home_projected_yellow_cards)
  away_cards <- safe_number(row$away_projected_yellow_cards)
  if (is.finite(home_cards) && is.finite(away_cards)) {
    paste0(display_number(home_cards, 1), " - ", display_number(away_cards, 1))
  } else {
    safe_text(row$yellow_card_model_status, "Card projection is not available yet.")
  }
}

render_forecast_card <- function(row, variant = "standard", initially_open = FALSE) {
  home <- safe_text(row$home_team, "Home team")
  away <- safe_text(row$away_team, "Away team")
  pick <- safe_text(row$predicted_winner, "No model pick yet")
  status <- safe_text(row$match_timing, "Scheduled")
  knockout <- is_knockout_forecast(row)
  pick_label <- if (knockout) "Projected to advance" else "Model pick"
  probability_label <- if (knockout) "Advance and regulation-level probabilities" else "Win draw loss probabilities"
  draw_label <- safe_text(row$draw_probability_label, if (knockout) "Level after regulation" else "Draw")
  strength <- prediction_strength(row)
  expected_goals <- paste0(
    display_number(row$pred_home_goals_poisson, 2),
    " - ",
    display_number(row$pred_away_goals_poisson, 2)
  )
  venue <- paste(
    safe_text(row$city, "Venue"),
    safe_text(row$country, "location"),
    sep = ", "
  )
  refresh <- refresh_time_display(row)
  open_attr <- if (initially_open) " open" else ""
  probability_rows <- if (knockout) {
    paste0(
      probability_row(paste(home, "advance"), row$home_advance_prob, "home-prob"),
      probability_row(draw_label, row$regulation_draw_prob, "draw-prob"),
      probability_row(paste(away, "advance"), row$away_advance_prob, "away-prob")
    )
  } else {
    paste0(
      probability_row(paste(home, "win"), row$ensemble_home_win_prob, "home-prob"),
      probability_row(draw_label, row$ensemble_draw_prob, "draw-prob"),
      probability_row(paste(away, "win"), row$ensemble_away_win_prob, "away-prob")
    )
  }
  knockout_note <- if (knockout) {
    '<p class="forecast-context-note">Knockout match: level after regulation is not a final draw. Advance probability includes the path through extra time or penalties.</p>'
  } else {
    ""
  }
  regulation_detail <- if (knockout) {
    paste0(
      '<dt>90-minute result</dt><dd>',
      escape_html(home), ' win ', display_percent(row$ensemble_home_win_prob, 1),
      '; level ', display_percent(row$regulation_draw_prob, 1),
      '; ', escape_html(away), ' win ', display_percent(row$ensemble_away_win_prob, 1),
      '<small>The level probability is reallocated to advancement because knockout matches need a winner.</small></dd>',
      '<dt>Extra time / penalties</dt><dd>',
      escape_html(safe_text(row$final_result_mode, "Winner can be decided after regulation.")),
      '</dd>'
    )
  } else {
    ""
  }

  paste0(
    '<article class="forecast-card forecast-card-', escape_html(variant), '" data-forecast-card>',
    '<div class="forecast-card-meta">',
    '<span class="status-pill status-', escape_html(tolower(gsub("[^a-z]+", "-", status))), '">', escape_html(status), '</span>',
    match_time_display(row),
    '</div>',
    '<div class="forecast-teams">',
    '<h3>', escape_html(home), ' <span>vs</span> ', escape_html(away), '</h3>',
    '<p>', escape_html(venue), '</p>',
    '</div>',
    '<div class="forecast-pick-panel">',
    '<span>', escape_html(pick_label), '</span>',
    '<strong>', escape_html(pick), '</strong>',
    '<small>Prediction strength: ', escape_html(strength), '. ', escape_html(model_agreement(row)), ' agree.</small>',
    '</div>',
    knockout_note,
    '<div class="forecast-probabilities" aria-label="', escape_html(probability_label), '">',
    probability_rows,
    '</div>',
    '<div class="forecast-stat-grid">',
    '<div><span>Most likely score</span><strong>', escape_html(safe_text(row$most_likely_score, "Not available yet")), '</strong></div>',
    '<div><span>Expected goals</span><strong>', escape_html(expected_goals), '</strong></div>',
    '<div><span>Probability advantage</span><strong>', escape_html(probability_edge(row)), '</strong></div>',
    '<div><span>Last forecast refresh</span><strong>', refresh, '</strong></div>',
    '</div>',
    '<details class="forecast-details"', open_attr, '>',
    '<summary>View details</summary>',
    '<dl>',
    regulation_detail,
    '<dt>Over 2.5 goals</dt><dd>', display_percent(row$over_2_5_prob, 1), '<small>Chance the match has at least 3 total goals.</small></dd>',
    '<dt>Both teams to score</dt><dd>', display_percent(row$both_teams_to_score_prob, 1), '<small>Chance both teams score at least once.</small></dd>',
    '<dt>Yellow cards</dt><dd>', escape_html(yellow_card_text(row)), '</dd>',
    '<dt>Lineups</dt><dd>', escape_html(lineup_text(row)), '</dd>',
    '<dt>Production model votes</dt><dd>OLS: ', escape_html(safe_text(row$ols_predicted_winner, "Not available yet")),
    '; Poisson: ', escape_html(safe_text(row$poisson_predicted_winner, "Not available yet")),
    '; Result model: ', escape_html(safe_text(row$ordinal_predicted_winner, "Not available yet")), '</dd>',
    '<dt>Expanded model bench</dt><dd>Challenger models are evaluated in the Model Lab before any promotion into the public pick.</dd>',
    '<dt>Venue</dt><dd>', escape_html(venue), '</dd>',
    '</dl>',
    '</details>',
    '</article>'
  )
}

render_forecast_list <- function(rows, empty_message, limit = NULL, card_variant = "standard") {
  if (!is.null(limit) && nrow(rows) > limit) {
    rows <- rows |> dplyr::slice_head(n = limit)
  }
  if (nrow(rows) == 0) {
    return(paste0('<div class="empty-state"><strong>', escape_html(empty_message), '</strong></div>'))
  }
  cards <- vapply(seq_len(nrow(rows)), function(i) {
    render_forecast_card(rows[i, ], variant = card_variant, initially_open = i == 1 && card_variant == "next")
  }, character(1))
  paste0('<div class="forecast-grid">', paste(cards, collapse = ""), "</div>")
}

render_home_hero <- function(summary, board) {
  completed <- if (nrow(board) > 0) {
    max(as.Date(board$date[board$match_timing == "Completed"]), na.rm = TRUE)
  } else {
    NA
  }
  completed_text <- if (is.finite(completed)) {
    format(completed, "%B %d, %Y")
  } else {
    "the latest refresh"
  }
  paste0(
    '<section class="product-hero">',
    '<div class="hero-copy">',
    '<div class="status-row">',
    '<span class="status-chip">Beta</span>',
    '<span class="status-chip">', escape_html(tournament_phase(summary)), '</span>',
    '<span class="status-chip muted">Last updated ', escape_html(summary_value(summary, "last_refreshed_local")), '</span>',
    '<span class="status-chip muted">Data current through ', escape_html(completed_text), '</span>',
    '</div>',
    '<h1>World Cup 2026 Forecasting Model</h1>',
    '<p>Match probabilities, projected scores, and tournament simulations powered by historical results and team-strength models.</p>',
    '<p class="hero-context">Forecast summaries come first. Methodology, diagnostics, and source code are available when you want to inspect the model.</p>',
    '<div class="hero-actions product-actions">',
    '<a class="button-primary" href="reports/08_matchday_predictions.html">View today&apos;s predictions</a>',
    '<a class="button-secondary" href="reports/08_matchday_predictions.html#bracket">Explore the bracket</a>',
    '</div>',
    '<p class="timezone-note">Times shown in your local timezone when your browser supports it. UTC is kept as the fallback.</p>',
    '</div>',
    '</section>'
  )
}

render_quick_status <- function(summary) {
  cards <- data.frame(
    label = c("Matches tracked", "Today", "Upcoming", "Completed"),
    value = c(
      summary_value(summary, "matches_on_board", "0"),
      summary_value(summary, "matches_today", "0"),
      summary_value(summary, "upcoming_matches", "0"),
      summary_value(summary, "completed_matches", "0")
    ),
    note = c("fixture board", "current slate", "future fixtures", "graded results"),
    stringsAsFactors = FALSE
  )
  metric_cards(cards)
}

render_today_section <- function(board, summary, heading = "Current Forecasts") {
  today <- today_board(board)
  upcoming <- future_board(board)
  empty <- "No matches are scheduled today. The next available match is shown below."
  next_line <- ""
  if (nrow(today) == 0 && nrow(upcoming) > 0) {
    next_line <- paste0(
      '<p class="section-note">Next match: <strong>',
      escape_html(safe_text(upcoming$home_team[1], "Home team")),
      ' vs ',
      escape_html(safe_text(upcoming$away_team[1], "Away team")),
      '</strong> on ',
      match_time_display(upcoming[1, ]),
      '.</p>'
    )
  }
  paste0(
    '<section id="today" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Today</span>',
    '<h2>', escape_html(heading), '</h2>',
    '<p>Start here for the current slate: model pick, probabilities, expected score, and refresh timing.</p>',
    '</div>',
    next_line,
    render_forecast_list(today, empty, card_variant = "today"),
    '</section>'
  )
}

render_next_match_section <- function(board) {
  upcoming <- future_board(board)
  if (nrow(upcoming) == 0) {
    return(
      '<section id="next-match" class="page-section"><div class="empty-state"><strong>No future matches are available in the current fixture table.</strong></div></section>'
    )
  }
  paste0(
    '<section id="next-match" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Next match</span>',
    '<h2>Next Match Forecast</h2>',
    '<p>The most immediate forecast is expanded by default so the pick and details are visible without hunting.</p>',
    '</div>',
    render_forecast_list(upcoming |> dplyr::slice_head(n = 1), "No next match is available.", card_variant = "next"),
    '</section>'
  )
}

render_upcoming_section <- function(board, limit = 8) {
  upcoming <- future_board(board)
  paste0(
    '<section id="upcoming" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Upcoming</span>',
    '<h2>Upcoming Matches</h2>',
    '<p>Each card shows the public pick, readable probabilities, expected score, and refresh timing. Knockout cards show advance probabilities and keep the regulation-level probability separate.</p>',
    '</div>',
    render_forecast_list(upcoming, "No upcoming matches are available in the current fixture table.", limit = limit, card_variant = "upcoming"),
    '</section>'
  )
}

metadata_value <- function(metadata, metric, fallback = "Not available yet") {
  if (nrow(metadata) == 0 || !"metric" %in% names(metadata) || !"value" %in% names(metadata)) {
    return(fallback)
  }
  value <- metadata$value[metadata$metric == metric]
  if (length(value) == 0 || is.na(value[[1]]) || !nzchar(as.character(value[[1]]))) {
    fallback
  } else {
    as.character(value[[1]])
  }
}

render_champion_section <- function(bundle, compact = TRUE) {
  champion <- bundle$champion_summary
  metadata <- bundle$champion_metadata

  if (nrow(champion) == 0) {
    return(paste0(
      '<section id="champion-outlook" class="page-section champion-section">',
      '<div class="section-heading">',
      '<span class="section-kicker">Tournament outlook</span>',
      '<h2>Champion Outlook</h2>',
      '<p>Champion probabilities will appear after the tournament simulation is refreshed.</p>',
      '</div>',
      '<div class="empty-state"><strong>No champion simulation output is available yet.</strong></div>',
      '</section>'
    ))
  }

  top_n <- if (compact) 6 else 12
  top <- champion |>
    dplyr::arrange(dplyr::desc(champion_probability), dplyr::desc(final_probability), team) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::mutate(rank = dplyr::row_number())

  max_prob <- max(top$champion_probability, na.rm = TRUE)
  if (!is.finite(max_prob) || max_prob <= 0) {
    max_prob <- 1
  }

  cards <- vapply(seq_len(nrow(top)), function(i) {
    row <- top[i, ]
    width <- 100 * safe_number(row$champion_probability) / max_prob
    paste0(
      '<article class="champion-card', ifelse(i == 1, ' is-leader', ''), '">',
      '<div class="champion-rank">#', escape_html(row$rank[[1]]), '</div>',
      '<div class="champion-card-main">',
      '<h3>', escape_html(row$team[[1]]), '</h3>',
      '<span>Group ', escape_html(row$group[[1]]), '</span>',
      '</div>',
      '<div class="champion-probability">',
      '<strong>', display_percent(row$champion_probability, 1), '</strong>',
      '<span>Champion probability</span>',
      '</div>',
      '<p class="champion-uncertainty">Simulation noise about +/- ',
      display_percent(row$champion_probability_95pct_moe, 1),
      '</p>',
      '<div class="champion-bar" aria-hidden="true"><span style="width:', fmt_number(width, 1), '%"></span></div>',
      '<dl>',
      '<div><dt>Reach final</dt><dd>', display_percent(row$final_probability, 1), '</dd></div>',
      '<div><dt>Reach semifinal</dt><dd>', display_percent(row$semifinal_probability, 1), '</dd></div>',
      '<div><dt>Reach quarterfinal</dt><dd>', display_percent(row$quarterfinal_probability, 1), '</dd></div>',
      '</dl>',
      '</article>'
    )
  }, character(1))

  simulated_at <- metadata_value(metadata, "simulated_at_utc")
  simulations <- metadata_value(metadata, "simulations")
  simulations_label <- fmt_integer(safe_number(simulations))
  if (is.na(simulations_label)) {
    simulations_label <- simulations
  }
  top_moe <- metadata_value(metadata, "top_champion_95pct_moe")
  simulation_method <- metadata_value(metadata, "simulation_method")
  fallback <- metadata_value(metadata, "later_round_fallback")

  table_html <- ""
  if (!compact) {
    table_data <- top |>
      dplyr::mutate(
        champion_probability = fmt_percent(champion_probability, 1),
        champion_probability_95pct_moe = fmt_percent(champion_probability_95pct_moe, 1),
        final_probability = fmt_percent(final_probability, 1),
        semifinal_probability = fmt_percent(semifinal_probability, 1),
        quarterfinal_probability = fmt_percent(quarterfinal_probability, 1)
      ) |>
      dplyr::select(rank, team, group, champion_probability, champion_probability_95pct_moe, final_probability, semifinal_probability, quarterfinal_probability)
    names(table_data) <- c("Rank", "Team", "Group", "Champion", "Simulation Noise", "Final", "Semifinal", "Quarterfinal")
    table_html <- paste0(
      '<div class="technical-table-wrap">',
      knitr::kable(
        table_data,
        format = "html",
        escape = TRUE,
        table.attr = 'class="clean-table champion-table"',
        caption = "Top tournament-path probabilities from the current simulation."
      ),
      '</div>'
    )
  }

  paste0(
    '<section id="champion-outlook" class="page-section champion-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Tournament outlook</span>',
    '<h2>Champion Outlook</h2>',
    '<p>These probabilities simulate the remaining tournament from the current match forecasts. Completed group results are locked in; knockout matches use available fixture-pair forecasts, then a strength-based fallback for later-round pairings. More simulations reduce random simulation noise; historical train/test validation is what measures model accuracy.</p>',
    '</div>',
    '<div class="champion-meta-row">',
    '<span class="status-chip">', escape_html(simulations_label), ' simulations</span>',
    '<span class="status-chip muted">Top estimate +/- ', display_percent(top_moe, 1), '</span>',
    '<span class="status-chip muted">Simulated ', time_tag(simulated_at, "js-local-time", "Simulation time unavailable"), '</span>',
    '</div>',
    '<div class="champion-grid">', paste(cards, collapse = ""), '</div>',
    table_html,
    '<p class="section-note">Simulation method: ', escape_html(gsub("_", " ", simulation_method)), '.</p>',
    '<p class="section-note">Later-round fallback: ', escape_html(fallback), '.</p>',
    '</section>'
  )
}

metric_lookup <- function(metrics, name) {
  if (nrow(metrics) == 0 || !"metric" %in% names(metrics)) {
    return(NA_real_)
  }
  value <- metrics$value[metrics$metric == name]
  if (length(value) == 0) NA_real_ else suppressWarnings(as.numeric(value[[1]]))
}

render_performance_section <- function(bundle, compact = FALSE) {
  accuracy <- bundle$accuracy
  detail <- bundle$accuracy_detail
  fixture_metrics <- bundle$fixture_metrics
  ordinal <- bundle$ordinal_metrics
  poisson <- bundle$poisson_metrics

  completed <- if (nrow(detail) > 0) nrow(detail) else metric_lookup(fixture_metrics, "fixtures_with_final_scores")
  ensemble_acc <- if (nrow(accuracy) > 0) {
    row <- accuracy[accuracy$model == "Ensemble", ]
    if (nrow(row) > 0) row$outcome_accuracy[[1]] else NA_real_
  } else {
    metric_lookup(fixture_metrics, "ordinal_completed_fixture_accuracy")
  }
  goal_error <- if (nrow(accuracy) > 0) {
    row <- accuracy[accuracy$model == "Poisson score grid", ]
    if (nrow(row) > 0) row$avg_team_goal_mae[[1]] else NA_real_
  } else {
    metric_lookup(fixture_metrics, "poisson_completed_fixture_mae")
  }
  historical_brier <- if (nrow(ordinal) > 0 && "test_multiclass_brier" %in% names(ordinal)) {
    ordinal$test_multiclass_brier[[1]]
  } else {
    NA_real_
  }
  poisson_rmse <- if (nrow(poisson) > 0 && "test_rmse" %in% names(poisson)) {
    poisson$test_rmse[[1]]
  } else {
    metric_lookup(fixture_metrics, "poisson_completed_fixture_rmse")
  }

  cards <- data.frame(
    label = c("Predictions evaluated", "Current result accuracy", "Avg team-goal miss", "Historical calibration"),
    value = c(
      fmt_integer(completed),
      fmt_percent(ensemble_acc, 1),
      ifelse(is.na(goal_error), "Not available yet", paste0(fmt_number(goal_error, 2), " goals")),
      ifelse(is.na(historical_brier), "In progress", paste0("Brier ", fmt_number(historical_brier, 3)))
    ),
    note = c(
      "completed 2026 fixtures",
      "top outcome matched final result",
      "average absolute miss per team",
      "lower is better; historical validation"
    ),
    stringsAsFactors = FALSE
  )

  body <- paste0(
    '<section id="model-performance" class="page-section performance-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Model trust</span>',
    '<h2>How Reliable Has The Model Been?</h2>',
    '<p>These numbers separate current tournament checks from historical validation. The sample is still small, so treat them as monitoring signals rather than proof.</p>',
    '</div>',
    metric_cards(cards),
    '<div class="performance-note">',
    '<strong>Plain English:</strong> accuracy is the share of completed matches where the top predicted outcome was right. Goal miss is the average distance between projected and actual goals. Brier score measures probability quality; lower is better.',
    '</div>'
  )

  if (!compact && nrow(detail) > 0) {
    recent <- detail |>
      dplyr::arrange(dplyr::desc(as.Date(date)), dplyr::desc(source_match_id)) |>
      dplyr::slice_head(n = 12) |>
      dplyr::mutate(
        result = ifelse(ensemble_correct, "Right", "Wrong"),
        probability_actual = fmt_percent(ensemble_probability_actual, 1),
        goal_miss = fmt_number(poisson_total_goal_error, 2)
      ) |>
      dplyr::select(date, match_label, actual_score, actual_winner, ensemble_pick, result, probability_actual, goal_miss)
    names(recent) <- c("Date", "Match", "Score", "Actual Winner", "Model Pick", "Result", "Actual Result Probability", "Goal Miss")
    table_html <- knitr::kable(
      recent,
      format = "html",
      escape = TRUE,
      table.attr = 'class="clean-table performance-table"',
      caption = "Recent completed-match review."
    )
    body <- paste0(body, '<div class="technical-table-wrap">', table_html, "</div>")
  }

  paste0(body, "</section>")
}

render_methodology_short <- function() {
  paste0(
    '<section id="methodology-short" class="page-section methodology-short">',
    '<div class="section-heading">',
    '<span class="section-kicker">Methodology</span>',
    '<h2>How The Forecast Works</h2>',
    '<p>The site combines historical international results, team-strength features, recent form, venue context, weather, and live football feeds where available. The public forecast is an ensemble of a result model and a score-grid model. In knockout matches, the draw-after-regulation probability is converted into advance probability because the match must produce a team that moves on.</p>',
    '</div>',
    '<div class="method-grid">',
    '<div><strong>Result probabilities</strong><span>Estimates regulation outcome probabilities from team strength and context, then converts knockout ties into advance probabilities.</span></div>',
    '<div><strong>Score forecast</strong><span>Uses a Poisson goals model to project expected goals and likely scorelines.</span></div>',
    '<div><strong>Similarity check</strong><span>Compares fixtures with similar historical matches as a challenger model.</span></div>',
    '<div><strong>Expanded model bench</strong><span>Runs multinomial, negative-binomial, GAM, GBM, XGBoost, random-forest, SVM, and stepwise challengers before any promotion decision.</span></div>',
    '</div>',
    '<p class="responsible-note">This is a forecasting and research project. It does not guarantee accuracy, and it should not be treated as financial advice.</p>',
    '</section>'
  )
}

render_challenger_section <- function(bundle, compact = TRUE) {
  challengers <- bundle$challenger_metrics
  importance <- bundle$challenger_importance
  status <- bundle$challenger_status

  if (nrow(challengers) == 0) {
    return(
      paste0(
        '<section id="model-comparison" class="page-section model-comparison-section">',
        '<div class="empty-state"><strong>Model challenger results will appear after the next full local model run.</strong></div>',
        '</section>'
      )
    )
  }

  challengers <- challengers |>
    dplyr::mutate(
      rank = dplyr::dense_rank(test_rmse),
      rmse_label = paste0(fmt_number(test_rmse, 3), " RMSE"),
      mae_label = paste0(fmt_number(test_mae, 3), " MAE"),
      width = ifelse(is.finite(test_rmse), 100 * min(test_rmse, na.rm = TRUE) / test_rmse, 0),
      status_text = dplyr::case_when(
        status == "fit" ~ "Fit locally",
        TRUE ~ tools::toTitleCase(gsub("_", " ", status))
      )
    ) |>
    dplyr::arrange(test_rmse)

  model_cards <- vapply(seq_len(nrow(challengers)), function(i) {
    row <- challengers[i, ]
    paste0(
      '<article class="model-score-card', ifelse(row$rank[[1]] == 1, ' is-leader', ''), '">',
      '<div class="model-score-top">',
      '<span>', escape_html(row$model_family[[1]]), '</span>',
      '<strong>#', escape_html(row$rank[[1]]), '</strong>',
      '</div>',
      '<h3>', escape_html(row$model[[1]]), '</h3>',
      '<div class="model-score-main">', escape_html(row$rmse_label[[1]]), '</div>',
      '<div class="score-track" aria-hidden="true"><span style="width:', fmt_number(row$width[[1]], 1), '%"></span></div>',
      '<dl>',
      '<div><dt>Average miss</dt><dd>', escape_html(row$mae_label[[1]]), '</dd></div>',
      '<div><dt>Training rows</dt><dd>', escape_html(fmt_integer(row$rows_train[[1]])), '</dd></div>',
      '<div><dt>Status</dt><dd>', escape_html(row$status_text[[1]]), '</dd></div>',
      '</dl>',
      '<p>', escape_html(row$note[[1]]), '</p>',
      '</article>'
    )
  }, character(1))

  status_note <- ""
  if (nrow(status) > 0) {
    status_note <- paste0(
      '<div class="model-status-strip">',
      paste(vapply(seq_len(nrow(status)), function(i) {
        row <- status[i, ]
        paste0(
          '<span><strong>', escape_html(row$component[[1]]), ':</strong> ',
          escape_html(gsub("_", " ", row$status[[1]])), '</span>'
        )
      }, character(1)), collapse = ""),
      '</div>'
    )
  }

  importance_html <- ""
  if (!compact && nrow(importance) > 0) {
    top_importance <- importance |>
      dplyr::group_by(model) |>
      dplyr::slice_max(importance_scaled, n = 5, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::arrange(model, dplyr::desc(importance_scaled))

    bars <- vapply(seq_len(nrow(top_importance)), function(i) {
      row <- top_importance[i, ]
      paste0(
        '<div class="feature-importance-row">',
        '<span>', escape_html(row$model[[1]]), '</span>',
        '<strong>', escape_html(row$feature[[1]]), '</strong>',
        '<i aria-hidden="true"><b style="width:', fmt_number(100 * row$importance_scaled[[1]], 1), '%"></b></i>',
        '</div>'
      )
    }, character(1))

    importance_html <- paste0(
      '<div class="feature-importance-panel">',
      '<h3>What The Challengers Used Most</h3>',
      '<p>Scaled importance is shown within each model, so the top feature for a model is 100%.</p>',
      paste(bars, collapse = ""),
      '</div>'
    )
  }

  paste0(
    '<section id="model-comparison" class="page-section model-comparison-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Model lab</span>',
    '<h2>Challenger Model Comparison</h2>',
    '<p>Stepwise regression and tree-based models run beside the production forecast. Lower RMSE means the model missed team goals by less on held-out rows.</p>',
    '</div>',
    '<div class="model-score-grid">',
    paste(model_cards, collapse = ""),
    '</div>',
    status_note,
    importance_html,
    '<p class="section-note">These challengers are not automatically promoted into the public pick. They need stable backtesting and calibration before replacing the current forecast ensemble.</p>',
    '</section>'
  )
}

render_data_source_section <- function(bundle) {
  sources <- bundle$data_sources
  if (nrow(sources) == 0) {
    return('<div class="empty-state"><strong>Data-source metadata is not available in this render.</strong></div>')
  }
  names(sources) <- label_names(names(sources))
  paste0(
    '<section id="data-used" class="page-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Data</span>',
    '<h2>Data Used In The Forecast</h2>',
    '<p>Only summarized model outputs are published here. Raw datasets, API keys, and private files remain outside the public site.</p>',
    '</div>',
    knitr::kable(
      sources,
      format = "html",
      escape = TRUE,
      table.attr = 'class="clean-table"',
      caption = "Prediction outputs and current data role."
    ),
    '</section>'
  )
}

render_technical_prediction_table <- function(board, limit = 48) {
  rows <- future_board(board)
  if (nrow(rows) == 0) {
    return('<details class="technical-disclosure"><summary>Technical prediction table</summary><div class="empty-state">No future rows are available.</div></details>')
  }
  display <- rows |>
    dplyr::slice_head(n = limit) |>
    dplyr::mutate(
      kickoff_utc = kickoff_utc_iso,
      phase = dplyr::if_else(is_knockout_match, "Knockout", "Group"),
      home_public_probability = dplyr::if_else(
        is_knockout_match,
        fmt_percent(home_advance_prob, 1),
        fmt_percent(ensemble_home_win_prob, 1)
      ),
      level_or_draw_probability = dplyr::if_else(
        is_knockout_match,
        fmt_percent(regulation_draw_prob, 1),
        fmt_percent(ensemble_draw_prob, 1)
      ),
      away_public_probability = dplyr::if_else(
        is_knockout_match,
        fmt_percent(away_advance_prob, 1),
        fmt_percent(ensemble_away_win_prob, 1)
      ),
      expected_goals = paste0(fmt_number(pred_home_goals_poisson, 2), " - ", fmt_number(pred_away_goals_poisson, 2)),
      over_2_5 = fmt_percent(over_2_5_prob, 1),
      both_score = fmt_percent(both_teams_to_score_prob, 1)
    ) |>
    dplyr::select(
      date,
      kickoff_utc,
      match_timing,
      phase,
      match_label,
      predicted_winner,
      home_public_probability,
      level_or_draw_probability,
      away_public_probability,
      expected_goals,
      most_likely_score,
      over_2_5,
      both_score
    )
  names(display) <- label_names(names(display))
  paste0(
    '<details class="technical-disclosure">',
    '<summary>Technical prediction table</summary>',
    knitr::kable(
      display,
      format = "html",
      escape = TRUE,
      table.attr = 'class="clean-table"',
      caption = "Model-ready future prediction rows. Times are stored in UTC."
    ),
    '</details>'
  )
}

team_key <- function(x) {
  x <- iconv(as.character(x), to = "ASCII//TRANSLIT")
  tolower(gsub("[^a-z0-9]", "", x))
}

unordered_match_key <- function(a, b) {
  a <- as.character(a)
  b <- as.character(b)
  ifelse(a < b, paste(a, b, sep = "|"), paste(b, a, sep = "|"))
}

as_plain_record <- function(row) {
  if (nrow(row) == 0) {
    return(NULL)
  }
  list(
    name = as.character(row$team[[1]]),
    group = as.character(row$group[[1]]),
    seed = paste0(row$group[[1]], row$position[[1]]),
    position = as.integer(row$position[[1]]),
    points = round(as.numeric(row$points[[1]]), 2),
    gd = round(as.numeric(row$gd[[1]]), 2),
    gf = round(as.numeric(row$gf[[1]]), 2),
    elo = round(as.numeric(row$elo[[1]]), 0)
  )
}

build_projected_bracket <- function(root) {
  predictions <- read_csv_if_exists(file.path(root, "data", "processed", "modeling", "world_cup_2026_fixture_predictions.csv"))
  board <- read_csv_if_exists(file.path(root, "data", "processed", "modeling", "matchday_prediction_board.csv"))
  squads <- read_csv_if_exists(file.path(root, "data", "processed", "public_csv", "dim_2026_world_cup_squad_players.csv"))

  if (nrow(predictions) == 0 || nrow(squads) == 0) {
    return(NULL)
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
      home_join_key = team_key(home_team),
      away_join_key = team_key(away_team)
    ) |>
    dplyr::left_join(team_groups, by = c("home_join_key" = "team_join_key")) |>
    dplyr::rename(home_group = group) |>
    dplyr::left_join(team_groups, by = c("away_join_key" = "team_join_key")) |>
    dplyr::rename(away_group = group) |>
    dplyr::mutate(
      group = dplyr::coalesce(home_group, away_group),
      completed = !is.na(home_score) & !is.na(away_score),
      home_points = dplyr::case_when(
        completed & home_score > away_score ~ 3,
        completed & home_score == away_score ~ 1,
        completed & home_score < away_score ~ 0,
        TRUE ~ 3 * pred_home_win_prob + pred_draw_prob
      ),
      away_points = dplyr::case_when(
        completed & away_score > home_score ~ 3,
        completed & away_score == home_score ~ 1,
        completed & away_score < home_score ~ 0,
        TRUE ~ 3 * pred_away_win_prob + pred_draw_prob
      ),
      home_goals_for = dplyr::if_else(completed, as.numeric(home_score), pred_home_goals_poisson),
      away_goals_for = dplyr::if_else(completed, as.numeric(away_score), pred_away_goals_poisson),
      home_goals_against = away_goals_for,
      away_goals_against = home_goals_for
    ) |>
    dplyr::filter(!is.na(group))

  home_rows <- data.frame(
    group = predictions$group,
    team = predictions$home_team,
    points = predictions$home_points,
    gf = predictions$home_goals_for,
    ga = predictions$home_goals_against,
    completed = predictions$completed,
    elo = predictions$home_latest_elo
  )
  away_rows <- data.frame(
    group = predictions$group,
    team = predictions$away_team,
    points = predictions$away_points,
    gf = predictions$away_goals_for,
    ga = predictions$away_goals_against,
    completed = predictions$completed,
    elo = predictions$away_latest_elo
  )

  standings <- rbind(home_rows, away_rows) |>
    dplyr::group_by(group, team) |>
    dplyr::summarise(
      matches = dplyr::n(),
      completed = sum(completed, na.rm = TRUE),
      points = sum(points, na.rm = TRUE),
      gf = sum(gf, na.rm = TRUE),
      ga = sum(ga, na.rm = TRUE),
      gd = gf - ga,
      elo = max(elo, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(group, dplyr::desc(points), dplyr::desc(gd), dplyr::desc(gf), dplyr::desc(elo), team) |>
    dplyr::group_by(group) |>
    dplyr::mutate(position = dplyr::row_number()) |>
    dplyr::ungroup()

  standings$elo[is.infinite(standings$elo)] <- NA_real_

  third_pool <- standings |>
    dplyr::filter(position == 3) |>
    dplyr::arrange(dplyr::desc(points), dplyr::desc(gd), dplyr::desc(gf), dplyr::desc(elo), team) |>
    dplyr::mutate(third_rank = dplyr::row_number(), qualifies = third_rank <= 8)

  knockout_lookup <- data.frame()
  if (nrow(board) > 0) {
    knockout_lookup <- board |>
      dplyr::mutate(
        knockout_flag = tolower(as.character(.data$is_knockout_match)) %in% c("true", "t", "1", "yes"),
        home_join_key = team_key(.data$home_team),
        away_join_key = team_key(.data$away_team)
      ) |>
      dplyr::filter(.data$knockout_flag) |>
      dplyr::mutate(
        fixture_key = unordered_match_key(.data$home_join_key, .data$away_join_key),
        official_winner = dplyr::case_when(
          !is.na(.data$actual_advancing_team) & nzchar(as.character(.data$actual_advancing_team)) ~ as.character(.data$actual_advancing_team),
          .data$match_timing == "Completed" & tolower(as.character(.data$actual_result)) %in% c("home win", "home advances") ~ as.character(.data$home_team),
          .data$match_timing == "Completed" & tolower(as.character(.data$actual_result)) %in% c("away win", "away advances") ~ as.character(.data$away_team),
          TRUE ~ NA_character_
        ),
        official_outcome = as.character(.data$actual_result)
      ) |>
      dplyr::arrange(dplyr::desc(.data$match_timing == "Completed"), .data$date, .data$match_label) |>
      dplyr::distinct(.data$fixture_key, .keep_all = TRUE) |>
      dplyr::select(
        "fixture_key",
        "match_label",
        "match_timing",
        "home_team",
        "away_team",
        "predicted_winner",
        "predicted_outcome",
        "official_winner",
        "official_outcome",
        "score_state",
        "final_result_mode",
        "home_advance_prob",
        "away_advance_prob",
        "regulation_draw_prob",
        "prediction_confidence"
      ) |>
      as.data.frame()
  }

  slot_pairs <- data.frame(
    match_id = seq_len(16),
    slot_a = c("A2", "F1", "E1", "I1", "K2", "H1", "D1", "G1", "C1", "E2", "A1", "L1", "J1", "D2", "B1", "K1"),
    slot_b = c("B2", "C2", "ABCDF3", "CDFGH3", "L2", "J2", "BEFIJ3", "AEHIJ3", "F2", "I2", "CEFHI3", "EHIJK3", "H2", "G2", "EFGIJ3", "DEIJL3")
  )

  used_third_teams <- character()
  resolve_slot <- function(slot) {
    if (grepl("^[A-L][12]$", slot)) {
      group <- substr(slot, 1, 1)
      position <- as.integer(substr(slot, 2, 2))
      row <- standings[standings$group == group & standings$position == position, ]
      return(as_plain_record(row))
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
      return(as_plain_record(row))
    }

    NULL
  }

  round32 <- lapply(seq_len(nrow(slot_pairs)), function(i) {
    row <- slot_pairs[i, ]
    team_a <- resolve_slot(as.character(row$slot_a))
    team_b <- resolve_slot(as.character(row$slot_b))

    fixture <- NULL
    if (nrow(knockout_lookup) > 0 && !is.null(team_a) && !is.null(team_b)) {
      fixture_key <- unordered_match_key(team_key(team_a$name), team_key(team_b$name))
      fixture_row <- knockout_lookup[knockout_lookup$fixture_key == fixture_key, , drop = FALSE]
      if (nrow(fixture_row) > 0) {
        fixture_row <- fixture_row[1, , drop = FALSE]
        team_a_is_home <- identical(team_key(fixture_row$home_team[[1]]), team_key(team_a$name))
        team_a_prob <- if (team_a_is_home) fixture_row$home_advance_prob[[1]] else fixture_row$away_advance_prob[[1]]
        team_b_prob <- if (team_a_is_home) fixture_row$away_advance_prob[[1]] else fixture_row$home_advance_prob[[1]]
        fixture <- list(
          label = as.character(fixture_row$match_label[[1]]),
          timing = as.character(fixture_row$match_timing[[1]]),
          homeTeam = as.character(fixture_row$home_team[[1]]),
          awayTeam = as.character(fixture_row$away_team[[1]]),
          modelWinner = as.character(fixture_row$predicted_winner[[1]]),
          modelOutcome = as.character(fixture_row$predicted_outcome[[1]]),
          officialWinner = if (!is.na(fixture_row$official_winner[[1]]) && nzchar(as.character(fixture_row$official_winner[[1]]))) as.character(fixture_row$official_winner[[1]]) else NULL,
          officialOutcome = if (!is.na(fixture_row$official_outcome[[1]]) && nzchar(as.character(fixture_row$official_outcome[[1]]))) as.character(fixture_row$official_outcome[[1]]) else NULL,
          actualScore = if (!is.na(fixture_row$score_state[[1]]) && nzchar(as.character(fixture_row$score_state[[1]]))) as.character(fixture_row$score_state[[1]]) else NULL,
          finalResultMode = if (!is.na(fixture_row$final_result_mode[[1]]) && nzchar(as.character(fixture_row$final_result_mode[[1]]))) as.character(fixture_row$final_result_mode[[1]]) else NULL,
          teamAAdvanceProb = suppressWarnings(as.numeric(team_a_prob)),
          teamBAdvanceProb = suppressWarnings(as.numeric(team_b_prob)),
          regulationDrawProb = suppressWarnings(as.numeric(fixture_row$regulation_draw_prob[[1]])),
          predictionConfidence = suppressWarnings(as.numeric(fixture_row$prediction_confidence[[1]]))
        )
      }
    }

    list(
      match = as.integer(row$match_id),
      slotA = as.character(row$slot_a),
      slotB = as.character(row$slot_b),
      teamA = team_a,
      teamB = team_b,
      fixture = fixture
    )
  })

  group_summary <- standings |>
    dplyr::filter(position <= 3) |>
    dplyr::mutate(
      seed = paste0(group, position),
      points = round(points, 2),
      gd = round(gd, 2),
      gf = round(gf, 2),
      elo = round(elo, 0)
    ) |>
    dplyr::select(group, seed, team, position, points, gd, gf, elo) |>
    as.data.frame()

  third_summary <- third_pool |>
    dplyr::mutate(
      seed = paste0(group, "3"),
      points = round(points, 2),
      gd = round(gd, 2),
      gf = round(gf, 2),
      elo = round(elo, 0)
    ) |>
    dplyr::select(third_rank, qualifies, group, seed, team, points, gd, gf, elo) |>
    as.data.frame()

  list(
    round32 = round32,
    groupSeeds = group_summary,
    thirdWatch = third_summary,
    notes = list(
      seeding = "Projected group tables combine completed results with model expected points for remaining matches.",
      knockout = "Completed knockout results lock into the bracket automatically. Unresolved knockout matches follow the current advance probabilities when they exist, then fall back to the strength signal."
    )
  )
}

archive_summary_value <- function(summary, metric, fallback = NA_character_) {
  if (is.null(summary) || nrow(summary) == 0 || !"metric" %in% names(summary) || !"value" %in% names(summary)) {
    return(fallback)
  }
  value <- summary$value[summary$metric == metric]
  if (length(value) == 0 || is.na(value[[1]]) || !nzchar(as.character(value[[1]]))) {
    fallback
  } else {
    as.character(value[[1]])
  }
}

archive_metric_card <- function(label, value, note = NULL) {
  note_html <- if (!is.null(note) && nzchar(note)) paste0("<small>", escape_html(note), "</small>") else ""
  paste0(
    '<article class="archive-metric-card">',
    '<span>', escape_html(label), '</span>',
    '<strong>', escape_html(value), '</strong>',
    note_html,
    '</article>'
  )
}

render_archive_cards <- function(rows, limit = 6, include_review = FALSE) {
  if (is.null(rows) || nrow(rows) == 0) {
    return('<div class="empty-state"><strong>No archive rows are available yet.</strong></div>')
  }

  rows <- rows |>
    dplyr::slice_head(n = limit)

  paste(vapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    title <- safe_text(row$match_label, "Match")
    venue <- safe_text(row$venue_label, "Venue not posted")
    status <- if ("archive_status" %in% names(row)) safe_text(row$archive_status, safe_text(row$replay_status, "Tracked")) else safe_text(row$review_outcome, "Tracked")
    kicker <- if ("match_phase" %in% names(row)) safe_text(row$match_phase, "Match") else "Match"
    watch_line <- if ("official_watch_platform" %in% names(row)) {
      paste0(
        '<div class="archive-card-line"><span>Watch source</span><strong>',
        escape_html(safe_text(row$official_watch_platform, "Official provider")),
        '</strong></div>'
      )
    } else {
      ""
    }
    detail_block <- if (include_review) {
      paste0(
        '<div class="archive-card-grid">',
        '<div><span>Model result</span><strong>', escape_html(safe_text(row$review_outcome, "Pending")), '</strong></div>',
        '<div><span>Actual result probability</span><strong>', display_percent(row$actual_result_probability, 1), '</strong></div>',
        '<div><span>Total goal error</span><strong>', ifelse(is.na(safe_number(row$total_goal_error)), "Pending", paste0(display_number(row$total_goal_error, 2), " goals")), '</strong></div>',
        '<div><span>Flag</span><strong>', escape_html(safe_text(row$upset_check, safe_text(row$score_error_band, "None"))), '</strong></div>',
        '<div><span>Local film</span><strong>', escape_html(safe_text(row$recording_status, "No local film saved yet")), '</strong></div>',
        '</div>',
        '<p class="archive-card-note">Predicted ', escape_html(safe_text(row$predicted_score, "NA")), '; actual ', escape_html(safe_text(row$actual_score, "NA")), '.</p>'
      )
    } else {
      paste0(
        '<div class="archive-card-grid">',
        '<div><span>Status</span><strong>', escape_html(status), '</strong></div>',
        '<div><span>Replay</span><strong>', escape_html(safe_text(row$replay_status, "Check provider")), '</strong></div>',
        '<div><span>Kickoff</span><strong>', match_time_display(row), '</strong></div>',
        '<div><span>Lookup hint</span><strong>', escape_html(safe_text(row$replay_lookup_hint, "Use match label in Peacock search")), '</strong></div>',
        '<div><span>Local film</span><strong>', escape_html(safe_text(row$recording_status, "No local film saved yet")), '</strong></div>',
        '</div>'
      )
    }
    action_html <- if ("official_watch_url" %in% names(row) && nzchar(safe_text(row$official_watch_url, ""))) {
      paste0(
        '<div class="archive-card-actions">',
        '<a class="button-secondary" href="', escape_html(safe_text(row$official_watch_url, "")), '" target="_blank" rel="noopener">Open provider</a>',
        '</div>'
      )
    } else {
      ""
    }

    paste0(
      '<article class="archive-card">',
      '<div class="archive-card-head">',
      '<span class="archive-card-kicker">', escape_html(kicker), '</span>',
      '<span class="archive-card-status">', escape_html(status), '</span>',
      '</div>',
      '<h3>', escape_html(title), '</h3>',
      '<p class="archive-card-venue">', escape_html(venue), '</p>',
      watch_line,
      detail_block,
      action_html,
      '</article>'
    )
  }, character(1)), collapse = "")
}

render_game_archive_section <- function(bundle, compact = TRUE, limit = 6) {
  registry <- bundle$archive_watch_registry
  review <- bundle$archive_review_board
  summary <- bundle$archive_summary

  metrics <- c(
    archive_metric_card("Tracked matches", archive_summary_value(summary, "matches_tracked", "0"), "Every fixture on the board gets a watch-source row."),
    archive_metric_card("Completed reviews", archive_summary_value(summary, "review_rows", "0"), "Completed matches tied back to model grading."),
    archive_metric_card("Local film saved", archive_summary_value(summary, "local_recordings_found", "0"), "Private recordings detected on this laptop only."),
    archive_metric_card("Model hit rate", display_percent(archive_summary_value(summary, "model_hit_rate", NA), 1), "Share of completed matches where the public pick landed."),
    archive_metric_card("Average goal error", ifelse(is.na(suppressWarnings(as.numeric(archive_summary_value(summary, "average_goal_error", NA)))), "Pending", paste0(display_number(archive_summary_value(summary, "average_goal_error", NA), 2), " goals")), "Average total-goals miss on graded matches.")
  )

  wrap_class <- if (compact) "page-section archive-section archive-section-compact" else "page-section archive-section"
  review_rows <- if (nrow(review) > 0) review else data.frame()
  registry_rows <- if (nrow(registry) > 0) registry |>
    dplyr::arrange(
      factor(.data$archive_status, levels = c("Today", "Upcoming", "Completed")),
      .data$date,
      .data$match_label
    ) else data.frame()

  paste0(
    '<section id="game-archive" class="', wrap_class, '">',
    '<div class="section-heading">',
    '<span class="section-kicker">Archive</span>',
    '<h2>Game Archive</h2>',
    '<p>Official watch-source metadata, replay lookup guidance, and post-match review for each World Cup fixture. The site stores metadata and model-review fields, not broadcast video.</p>',
    '</div>',
    '<div class="archive-metric-grid">', paste(metrics, collapse = ""), '</div>',
    '<div class="archive-grid">',
    '<div class="archive-column">',
    '<div class="archive-column-head"><h3>Watch and replay registry</h3><p>Where to look for the official live or replay listing.</p></div>',
    '<div class="archive-card-stack">', render_archive_cards(registry_rows, limit = limit, include_review = FALSE), '</div>',
    '</div>',
    '<div class="archive-column">',
    '<div class="archive-column-head"><h3>Completed match review</h3><p>How the public model call compared with the official result.</p></div>',
    '<div class="archive-card-stack">', render_archive_cards(review_rows, limit = limit, include_review = TRUE), '</div>',
    '</div>',
    '</div>',
    if (compact) '<p class="section-note"><a href="11_game_archive.html">Open the full archive page</a> for the full registry, review board, and workflow notes.</p>' else '',
    '</section>'
  )
}

render_game_archive_page <- function(bundle) {
  registry <- bundle$archive_watch_registry
  review <- bundle$archive_review_board
  summary <- bundle$archive_summary

  status_rows <- data.frame(
    label = c("Tracked fixtures", "Completed reviews", "Upcoming fixtures", "Local film saved"),
    value = c(
      archive_summary_value(summary, "matches_tracked", "0"),
      archive_summary_value(summary, "review_rows", "0"),
      archive_summary_value(summary, "upcoming_matches", "0"),
      archive_summary_value(summary, "local_recordings_found", "0")
    ),
    note = c(
      "All fixtures currently carried on the match board.",
      "Completed matches with model review fields attached.",
      "Future matches already in the watch registry.",
      "Private recordings detected in the local recordings folder."
    ),
    stringsAsFactors = FALSE
  )

  registry_table <- if (nrow(registry) > 0) {
    display_table(
      registry |>
        dplyr::select(date, match_phase, archive_status, match_label, venue_label, official_watch_platform, replay_status, recording_status, replay_lookup_hint),
      caption = "Official watch-source registry."
    )
  } else {
    display_table(empty_note("Watch-source registry will appear after the archive refresh."))
  }

  review_table <- if (nrow(review) > 0) {
    display_table(
      review |>
        dplyr::select(date, match_phase, match_label, review_outcome, actual_result_probability, total_goal_error, recording_status, score_error_band, upset_check),
      caption = "Completed match review board."
    )
  } else {
    display_table(empty_note("Completed-match review rows will appear after final scores are graded."))
  }

  paste0(
    metric_cards(status_rows),
    render_game_archive_section(bundle, compact = FALSE, limit = 8),
    '<section class="page-section archive-explainer">',
    '<div class="section-heading">',
    '<span class="section-kicker">Workflow</span>',
    '<h2>How To Use The Archive</h2>',
    '<p>Use the registry before kickoff to find the official provider listing. After the match, use the review board to see whether the model call held, where the score projection missed, and which matches deserve tuning attention.</p>',
    '</div>',
    '<div class="method-grid">',
    '<div><strong>Before kickoff</strong><span>Check the provider row, kickoff time, and replay lookup hint.</span></div>',
    '<div><strong>After final whistle</strong><span>Review the completed-match card for actual-result probability and score miss.</span></div>',
    '<div><strong>Model tuning</strong><span>Use upset checks and large score misses to decide what to recalibrate next.</span></div>',
    '</div>',
    '</section>',
    '<section class="page-section">',
    '<div class="section-heading"><span class="section-kicker">Registry</span><h2>Archive Tables</h2><p>These tables are reduced public summaries. Private notes and raw broadcast media are not stored on the public site.</p></div>',
    registry_table,
    review_table,
    '</section>'
  )
}

render_bracket <- function(root, preview = FALSE, section_id = NULL) {
  bracket_data <- build_projected_bracket(root)
  if (is.null(bracket_data)) {
    return('<div class="empty-state"><strong>The bracket is available after fixture predictions and squad group metadata are refreshed.</strong></div>')
  }
  bracket_json <- jsonlite::toJSON(bracket_data, auto_unbox = TRUE, na = "null", dataframe = "rows")
  bracket_json <- gsub("<", "\\\\u003c", bracket_json, fixed = TRUE)
  shell_class <- if (preview) "model-bracket-shell bracket-preview" else "model-bracket-shell"
  section_attr <- if (!is.null(section_id) && nzchar(section_id)) paste0(' id="', section_id, '"') else ""
  paste0(
    '<section class="', shell_class, '"', section_attr, '>',
    '<div class="model-bracket-header">',
    '<div>',
    '<div class="section-kicker">Bracket</div>',
    '<h2>Projected Tournament Bracket</h2>',
    '<p>Seeded from current group projections. Tap a team to advance it. Model picks, manual picks, and official results use separate labels, and completed knockout results lock automatically.</p>',
    '</div>',
    '<div class="model-bracket-controls">',
    '<button type="button" class="bracket-control" data-bracket-action="model" aria-controls="model-path-panel" aria-expanded="false">Show model path</button>',
    '<button type="button" class="bracket-control" data-bracket-action="reset">Reset picks</button>',
    '<button type="button" class="bracket-control" data-bracket-action="toggle-view" aria-controls="model-bracket-root" aria-pressed="false">Full bracket</button>',
    '</div>',
    '</div>',
    '<div class="bracket-tabs" role="tablist" aria-label="Bracket rounds"></div>',
    '<p class="bracket-instruction">Tap a team to advance it. Use the round tabs on small screens.</p>',
    '<div id="bracket-summary-strip" class="bracket-summary-strip" aria-live="polite"></div>',
    '<div id="bracket-mode-note" class="bracket-mode-note" aria-live="polite"></div>',
    '<div class="bracket-legend" aria-label="Bracket legend">',
    '<span class="bracket-legend-item"><i class="legend-swatch legend-model"></i>Model pick</span>',
    '<span class="bracket-legend-item"><i class="legend-swatch legend-user"></i>Your pick</span>',
    '<span class="bracket-legend-item"><i class="legend-swatch legend-official"></i>Official result</span>',
    '<span class="bracket-legend-item"><i class="legend-swatch legend-pending"></i>Pending side</span>',
    '</div>',
    '<div class="bracket-overview-grid">',
    '<div class="seed-watch-panel"><h3>Projected Group Seeds</h3><div id="group-seed-watch"></div></div>',
    '<div class="seed-watch-panel"><h3>Best Third Watch</h3><div id="third-place-watch"></div></div>',
    '</div>',
    '<section id="model-path-panel" class="model-path-panel" tabindex="-1" hidden>',
    '<div class="model-path-summary"></div>',
    '<div class="model-path-rounds" aria-label="Round-by-round model path"></div>',
    '</section>',
    '<div id="model-bracket-root" class="interactive-bracket-grid" data-view="full"></div>',
    '<div id="model-bracket-status" class="screen-reader-only" aria-live="polite"></div>',
    '<div id="model-bracket-champion" class="bracket-champion-card" aria-live="polite"></div>',
    '<script type="application/json" id="wc-bracket-data">', bracket_json, '</script>',
    '</section>'
  )
}
