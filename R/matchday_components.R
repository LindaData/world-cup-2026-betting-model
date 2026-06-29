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
    data_sources = read_csv_if_exists(file.path(model_dir, "matchday_prediction_data_sources.csv"))
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

probability_edge <- function(row) {
  probs <- c(
    safe_number(row$ensemble_home_win_prob),
    safe_number(row$ensemble_draw_prob),
    safe_number(row$ensemble_away_win_prob)
  )
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
    '<span>Model pick</span>',
    '<strong>', escape_html(pick), '</strong>',
    '<small>Prediction strength: ', escape_html(strength), '. ', escape_html(model_agreement(row)), ' agree.</small>',
    '</div>',
    '<div class="forecast-probabilities" aria-label="Win draw loss probabilities">',
    probability_row(paste(home, "win"), row$ensemble_home_win_prob, "home-prob"),
    probability_row("Draw", row$ensemble_draw_prob, "draw-prob"),
    probability_row(paste(away, "win"), row$ensemble_away_win_prob, "away-prob"),
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
    '<dt>Over 2.5 goals</dt><dd>', display_percent(row$over_2_5_prob, 1), '<small>Chance the match has at least 3 total goals.</small></dd>',
    '<dt>Both teams to score</dt><dd>', display_percent(row$both_teams_to_score_prob, 1), '<small>Chance both teams score at least once.</small></dd>',
    '<dt>Yellow cards</dt><dd>', escape_html(yellow_card_text(row)), '</dd>',
    '<dt>Lineups</dt><dd>', escape_html(lineup_text(row)), '</dd>',
    '<dt>Model votes</dt><dd>OLS: ', escape_html(safe_text(row$ols_predicted_winner, "Not available yet")),
    '; Poisson: ', escape_html(safe_text(row$poisson_predicted_winner, "Not available yet")),
    '; Win/draw/loss: ', escape_html(safe_text(row$ordinal_predicted_winner, "Not available yet")), '</dd>',
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

render_today_section <- function(board, summary, heading = "Today's Forecasts") {
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
    '<p>Each card shows readable win, draw, and loss probabilities. Open details for totals, cards, lineups, and model votes.</p>',
    '</div>',
    render_forecast_list(upcoming, "No upcoming matches are available in the current fixture table.", limit = limit, card_variant = "upcoming"),
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
    '<p>The site combines historical international results, team-strength features, recent form, venue context, weather, and live football feeds where available. The public forecast is an ensemble of a win/draw/loss model and a score-grid model.</p>',
    '</div>',
    '<div class="method-grid">',
    '<div><strong>Win / draw / loss</strong><span>Estimates match outcome probabilities from team strength and context.</span></div>',
    '<div><strong>Score forecast</strong><span>Uses a Poisson goals model to project expected goals and likely scorelines.</span></div>',
    '<div><strong>Similarity check</strong><span>Compares fixtures with similar historical matches as a challenger model.</span></div>',
    '</div>',
    '<p class="responsible-note">This is a forecasting and research project. It does not guarantee accuracy, and it should not be treated as financial advice.</p>',
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
      home_win = fmt_percent(ensemble_home_win_prob, 1),
      draw = fmt_percent(ensemble_draw_prob, 1),
      away_win = fmt_percent(ensemble_away_win_prob, 1),
      expected_goals = paste0(fmt_number(pred_home_goals_poisson, 2), " - ", fmt_number(pred_away_goals_poisson, 2)),
      over_2_5 = fmt_percent(over_2_5_prob, 1),
      both_score = fmt_percent(both_teams_to_score_prob, 1)
    ) |>
    dplyr::select(
      date,
      kickoff_utc,
      match_timing,
      match_label,
      predicted_winner,
      home_win,
      draw,
      away_win,
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
    list(
      match = as.integer(row$match_id),
      slotA = as.character(row$slot_a),
      slotB = as.character(row$slot_b),
      teamA = resolve_slot(as.character(row$slot_a)),
      teamB = resolve_slot(as.character(row$slot_b))
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
      knockout = "Knockout advancement uses the current Elo-style strength signal until knockout match-specific data exists."
    )
  )
}

render_bracket <- function(root, preview = FALSE) {
  bracket_data <- build_projected_bracket(root)
  if (is.null(bracket_data)) {
    return('<div class="empty-state"><strong>The bracket is available after fixture predictions and squad group metadata are refreshed.</strong></div>')
  }
  bracket_json <- jsonlite::toJSON(bracket_data, auto_unbox = TRUE, na = "null", dataframe = "rows")
  bracket_json <- gsub("<", "\\\\u003c", bracket_json, fixed = TRUE)
  shell_class <- if (preview) "model-bracket-shell bracket-preview" else "model-bracket-shell"
  paste0(
    '<section class="', shell_class, '">',
    '<div class="model-bracket-header">',
    '<div>',
    '<div class="section-kicker">Bracket</div>',
    '<h2>Projected Tournament Bracket</h2>',
    '<p>Seeded from current group projections. Tap a team to advance it. Model picks, manual picks, and official results use separate labels.</p>',
    '</div>',
    '<div class="model-bracket-controls">',
    '<button type="button" class="bracket-control" data-bracket-action="model">Model path</button>',
    '<button type="button" class="bracket-control" data-bracket-action="reset">Reset picks</button>',
    '<button type="button" class="bracket-control" data-bracket-action="toggle-view">Full bracket</button>',
    '</div>',
    '</div>',
    '<div class="bracket-tabs" role="tablist" aria-label="Bracket rounds"></div>',
    '<p class="bracket-instruction">Tap a team to advance it. Use the round tabs on small screens.</p>',
    '<div class="bracket-overview-grid">',
    '<div class="seed-watch-panel"><h3>Projected Group Seeds</h3><div id="group-seed-watch"></div></div>',
    '<div class="seed-watch-panel"><h3>Best Third Watch</h3><div id="third-place-watch"></div></div>',
    '</div>',
    '<div id="model-bracket-root" class="interactive-bracket-grid" data-view="full"></div>',
    '<div id="model-bracket-status" class="screen-reader-only" aria-live="polite"></div>',
    '<div id="model-bracket-champion" class="bracket-champion-card" aria-live="polite"></div>',
    '<script type="application/json" id="wc-bracket-data">', bracket_json, '</script>',
    '</section>'
  )
}
