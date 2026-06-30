# Static-site readability overrides for the public World Cup pages.
# Source this file after R/matchday_components.R. It keeps the site static,
# avoids live browser API calls, and makes the public pages easier to scan.

status_slug <- function(x) {
  text <- tolower(as.character(x[[1]]))
  text <- gsub("[^a-z0-9]+", "-", text)
  text <- gsub("(^-+|-+$)", "", text)
  if (!nzchar(text)) "scheduled" else text
}

row_match_key <- function(rows) {
  if (nrow(rows) == 0) {
    return(character())
  }

  if ("source_match_id" %in% names(rows)) {
    ids <- as.character(rows$source_match_id)
    if (any(!is.na(ids) & nzchar(ids))) {
      return(ids)
    }
  }

  paste(
    as.character(rows$date),
    as.character(rows$home_team),
    as.character(rows$away_team),
    sep = "|"
  )
}

future_board_after_today <- function(board) {
  upcoming <- future_board(board)
  today <- today_board(board)

  if (nrow(upcoming) == 0 || nrow(today) == 0) {
    return(upcoming)
  }

  today_keys <- row_match_key(today)
  upcoming[!(row_match_key(upcoming) %in% today_keys), , drop = FALSE]
}

future_board_after_featured <- function(board) {
  upcoming <- future_board_after_today(board)
  if (nrow(upcoming) <= 1) {
    return(upcoming[0, , drop = FALSE])
  }
  upcoming |> dplyr::slice_tail(n = nrow(upcoming) - 1)
}

refresh_time_display <- function(row) {
  iso <- normalize_utc_iso(row$refresh_utc_iso)
  parsed <- parse_utc_time(iso)
  if (!is.na(iso) && !is.na(parsed)) {
    return(time_tag(row$refresh_utc_iso, "js-local-time forecast-refresh-time", "Forecast refresh time not posted"))
  }
  '<span class="time-unavailable">Site refresh timestamp shown above.</span>'
}

render_static_api_note <- function(summary, compact = FALSE) {
  updated <- summary_value(summary, "last_refreshed_local", "Not available yet")
  body <- if (compact) {
    "Forecasts refresh from the prepared model outputs and publish to this page for quick review."
  } else {
    "Forecasts refresh from the prepared model outputs and publish here as a fast, shareable board. The public page shows results and documentation while keeping private feeds out of the site."
  }

  paste0(
    '<section class="page-section static-note-section">',
    '<div class="freshness-note">',
    '<strong>Forecast freshness:</strong> ', escape_html(body),
    ' <span class="section-note">Last generated: ', escape_html(updated), '.</span>',
    '</div>',
    '</section>'
  )
}

model_fair_decimal <- function(probability) {
  value <- safe_number(probability)
  if (!is.finite(value) || value <= 0) {
    return("N/A")
  }
  fmt_number(1 / value, 2)
}

market_price_option <- function(label, probability, class_name, is_favorite = FALSE) {
  favorite_class <- if (is_favorite) " is-market-favorite" else ""
  paste0(
    '<div class="market-price ', escape_html(class_name), favorite_class, '">',
    '<span>', escape_html(label), '</span>',
    '<strong>', display_percent(probability, 1), '</strong>',
    '<small>Fair ', escape_html(model_fair_decimal(probability)), '</small>',
    '</div>'
  )
}

market_price_grid <- function(row) {
  home <- safe_text(row$home_team, "Home team")
  away <- safe_text(row$away_team, "Away team")
  knockout <- is_knockout_forecast(row)
  labels <- if (knockout) {
    c(home, "Level 90", away)
  } else {
    c(home, "Draw", away)
  }
  values <- if (knockout) {
    c(row$home_advance_prob, row$regulation_draw_prob, row$away_advance_prob)
  } else {
    c(row$ensemble_home_win_prob, row$ensemble_draw_prob, row$ensemble_away_win_prob)
  }
  classes <- c("market-home", "market-draw", "market-away")
  numeric_values <- vapply(values, safe_number, numeric(1))
  favorite <- if (any(is.finite(numeric_values))) which.max(numeric_values) else 0

  paste0(
    '<div class="market-price-grid" aria-label="Model probability market">',
    paste(vapply(seq_along(labels), function(i) {
      market_price_option(labels[[i]], values[[i]], classes[[i]], is_favorite = identical(i, favorite))
    }, character(1)), collapse = ""),
    '</div>'
  )
}

model_market_rows <- function(board, limit = 8) {
  rows <- dplyr::bind_rows(today_board(board), future_board(board))
  if (nrow(rows) == 0) {
    return(rows)
  }
  rows <- rows[!duplicated(row_match_key(rows)), , drop = FALSE]
  rows |> dplyr::slice_head(n = limit)
}

render_model_market_row <- function(row) {
  home <- safe_text(row$home_team, "Home team")
  away <- safe_text(row$away_team, "Away team")
  pick <- safe_text(row$predicted_winner, "Pending")
  status <- safe_text(row$match_timing, "Scheduled")
  expected_goals <- paste0(
    display_number(row$pred_home_goals_poisson, 2),
    " - ",
    display_number(row$pred_away_goals_poisson, 2)
  )
  venue <- paste(safe_text(row$city, "Venue"), safe_text(row$country, "location"), sep = ", ")
  knockout_note <- if (is_knockout_forecast(row)) {
    '<span class="market-tag">Advance market</span>'
  } else {
    '<span class="market-tag">Result market</span>'
  }

  paste0(
    '<article class="model-market-row">',
    '<div class="market-match-cell">',
    '<div class="market-row-meta">',
    '<span class="status-pill status-', escape_html(status_slug(status)), '">', escape_html(status), '</span>',
    knockout_note,
    '</div>',
    '<h3>', escape_html(home), ' <span>vs</span> ', escape_html(away), '</h3>',
    '<p>', match_time_display(row), '</p>',
    '<small>', escape_html(venue), '</small>',
    '</div>',
    market_price_grid(row),
    '<div class="market-pick-cell">',
    '<span>Model pick</span>',
    '<strong>', escape_html(pick), '</strong>',
    '<small>', escape_html(prediction_strength(row)), ' strength</small>',
    '</div>',
    '<div class="market-score-cell">',
    '<span>Score</span>',
    '<strong>', escape_html(safe_text(row$most_likely_score, "Pending")), '</strong>',
    '<small>Expected ', escape_html(expected_goals), '</small>',
    '</div>',
    '<details class="market-row-details">',
    '<summary>More</summary>',
    '<div class="market-detail-grid">',
    '<div><span>Probability edge</span><strong>', escape_html(probability_edge(row)), '</strong></div>',
    '<div><span>Over 2.5</span><strong>', display_percent(row$over_2_5_prob, 1), '</strong></div>',
    '<div><span>Both teams score</span><strong>', display_percent(row$both_teams_to_score_prob, 1), '</strong></div>',
    '<div><span>Cards</span><strong>', escape_html(yellow_card_text(row)), '</strong></div>',
    '<div><span>Lineups</span><strong>', escape_html(lineup_text(row)), '</strong></div>',
    '<div><span>Refresh</span><strong>', refresh_time_display(row), '</strong></div>',
    '</div>',
    '</details>',
    '</article>'
  )
}

render_model_market_board <- function(board, title = "Model Board", subtitle = NULL, limit = 8, section_id = "model-board") {
  rows <- model_market_rows(board, limit = limit)
  if (is.null(subtitle)) {
    subtitle <- "Sportsbook-style scan of model probabilities, fair decimal prices, expected score, and pick."
  }
  if (nrow(rows) == 0) {
    body <- '<div class="empty-state"><strong>No model board rows are available yet.</strong></div>'
  } else {
    body <- paste0(
      '<div class="model-market-board">',
      '<div class="model-market-head" aria-hidden="true">',
      '<span>Match</span><span>Model market</span><span>Pick</span><span>Score</span><span>Details</span>',
      '</div>',
      paste(vapply(seq_len(nrow(rows)), function(i) render_model_market_row(rows[i, ]), character(1)), collapse = ""),
      '</div>'
    )
  }

  paste0(
    '<section id="', escape_html(section_id), '" class="page-section model-market-section">',
    '<div class="market-board-title">',
    '<div>',
    '<span class="section-kicker">Forecast board</span>',
    '<h2>', escape_html(title), '</h2>',
    '<p>', escape_html(subtitle), '</p>',
    '</div>',
    '<p class="market-board-note">Fair decimal is calculated from the model probability. These are not sportsbook odds.</p>',
    '</div>',
    body,
    '</section>'
  )
}

render_forecast_card <- function(row, variant = "standard", initially_open = FALSE) {
  home <- safe_text(row$home_team, "Home team")
  away <- safe_text(row$away_team, "Away team")
  pick <- safe_text(row$predicted_winner, "No model pick yet")
  status <- safe_text(row$match_timing, "Scheduled")
  knockout <- is_knockout_forecast(row)
  pick_label <- if (knockout) "Projected to advance" else "Model pick"
  probability_label <- if (knockout) "Advancement and regulation-level probabilities" else "Win / draw / loss probabilities"
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
    '<span class="status-pill status-', escape_html(status_slug(status)), '">', escape_html(status), '</span>',
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
    '<div><span>Forecast generated</span><strong>', refresh, '</strong></div>',
    '</div>',
    '<details class="forecast-details"', open_attr, '>',
    '<summary>View match details</summary>',
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

render_home_hero <- function(summary, board) {
  next_match <- future_board(board)
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

  hero_panel <- if (nrow(next_match) > 0) {
    row <- next_match[1, ]
    knockout <- is_knockout_forecast(row)
    home <- safe_text(row$home_team, "Home team")
    away <- safe_text(row$away_team, "Away team")
    pick_label <- if (knockout) "Projected to advance" else "Model pick"
    home_label <- if (knockout) paste(home, "advance") else paste(home, "win")
    away_label <- if (knockout) paste(away, "advance") else paste(away, "win")
    middle_label <- if (knockout) safe_text(row$draw_probability_label, "Level after regulation") else "Draw"
    home_prob <- if (knockout) row$home_advance_prob else row$ensemble_home_win_prob
    away_prob <- if (knockout) row$away_advance_prob else row$ensemble_away_win_prob
    middle_prob <- if (knockout) row$regulation_draw_prob else row$ensemble_draw_prob
    paste0(
      '<aside class="hero-forecast-panel" aria-label="Featured next forecast">',
      '<span class="section-kicker">Next forecast</span>',
      '<h2>', escape_html(home), ' <span>vs</span> ', escape_html(away), '</h2>',
      '<p class="hero-kickoff">', match_time_display(row), '</p>',
      '<div class="hero-pick">',
      '<span>', escape_html(pick_label), '</span>',
      '<strong>', escape_html(safe_text(row$predicted_winner, "No model pick yet")), '</strong>',
      '<small>', escape_html(prediction_strength(row)), ' strength &middot; ', escape_html(probability_edge(row)), ' edge</small>',
      '</div>',
      '<div class="hero-prob-list">',
      '<div><span>', escape_html(home_label), '</span><strong>', display_percent(home_prob, 1), '</strong></div>',
      '<div><span>', escape_html(middle_label), '</span><strong>', display_percent(middle_prob, 1), '</strong></div>',
      '<div><span>', escape_html(away_label), '</span><strong>', display_percent(away_prob, 1), '</strong></div>',
      '</div>',
      '<a class="button-secondary hero-panel-link" href="reports/08_matchday_predictions.html#next-match">Open forecast</a>',
      '</aside>'
    )
  } else {
    paste0(
      '<aside class="hero-forecast-panel" aria-label="Featured forecast status">',
      '<span class="section-kicker">Forecast status</span>',
      '<h2>No upcoming match is available</h2>',
      '<p>The board will update after the next fixture refresh.</p>',
      '<a class="button-secondary hero-panel-link" href="reports/08_matchday_predictions.html">Open prediction board</a>',
      '</aside>'
    )
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
    '<p>Match probabilities, projected scores, bracket path, and model reliability notes for the 2026 World Cup.</p>',
    '<p class="hero-context">Forecasts come first. Data coverage, methodology, and diagnostics stay available when you want to inspect the work behind the numbers.</p>',
    '<div class="hero-actions product-actions">',
    '<a class="button-primary" href="reports/08_matchday_predictions.html">View today&apos;s predictions</a>',
    '<a class="button-secondary" href="reports/08_matchday_predictions.html#bracket">Open bracket</a>',
    '</div>',
    '<p class="timezone-note">Times are shown in your local timezone when available. UTC is the fallback.</p>',
    '</div>',
    hero_panel,
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
    note = c("fixture board", "current slate", "future forecasts", "graded results"),
    stringsAsFactors = FALSE
  )

  card_html <- apply(cards, 1, function(row) {
    paste0(
      '<div class="quick-read-card">',
      '<span>', escape_html(row[["label"]]), '</span>',
      '<strong>', escape_html(row[["value"]]), '</strong>',
      '<small>', escape_html(row[["note"]]), '</small>',
      '</div>'
    )
  })

  paste0(
    '<section class="quick-read-section" aria-label="Forecast board summary">',
    paste(card_html, collapse = ""),
    '</section>'
  )
}

render_forecast_command_center <- function(bundle, board, compact = FALSE, base_path = "") {
  champion <- bundle$champion_summary
  accuracy <- bundle$accuracy
  today <- today_board(board)
  upcoming <- future_board(board)

  next_match_html <- if (nrow(upcoming) > 0) {
    row <- upcoming[1, ]
    paste0(
      '<span>Next match</span>',
      '<strong>', escape_html(safe_text(row$home_team, "Home team")), ' vs ', escape_html(safe_text(row$away_team, "Away team")), '</strong>',
      '<small>', escape_html(safe_text(row$predicted_winner, "No model pick yet")), ' is the current pick.</small>'
    )
  } else {
    '<span>Next match</span><strong>No future match posted</strong><small>The board updates after the next refresh.</small>'
  }

  champion_html <- if (!is.null(champion) && nrow(champion) > 0) {
    top <- champion |>
      dplyr::arrange(dplyr::desc(.data$champion_probability)) |>
      dplyr::slice_head(n = 1)
    paste0(
      '<span>Tournament favorite</span>',
      '<strong>', escape_html(top$team[[1]]), '</strong>',
      '<small>', display_percent(top$champion_probability[[1]], 1), ' champion probability across ',
      escape_html(summary_value(bundle$champion_metadata, "simulations", "simulations")), ' simulations.</small>'
    )
  } else {
    '<span>Tournament favorite</span><strong>Pending simulation</strong><small>Champion projections appear after simulation output is available.</small>'
  }

  accuracy_html <- if (!is.null(accuracy) && nrow(accuracy) > 0) {
    ensemble <- accuracy |>
      dplyr::filter(.data$model == "Ensemble") |>
      dplyr::slice_head(n = 1)
    if (nrow(ensemble) == 0) {
      ensemble <- accuracy |> dplyr::slice_head(n = 1)
    }
    paste0(
      '<span>Model reliability</span>',
      '<strong>', display_percent(ensemble$outcome_accuracy[[1]], 1), '</strong>',
      '<small>Correct winner/result picks over ', escape_html(ensemble$completed_matches[[1]]), ' completed matches.</small>'
    )
  } else {
    '<span>Model reliability</span><strong>Pending results</strong><small>Accuracy appears after completed matches are scored.</small>'
  }

  today_label <- if (nrow(today) > 0) {
    paste0(nrow(today), " match", if (nrow(today) == 1) "" else "es", " today")
  } else {
    "No matches today"
  }

  section_class <- if (compact) "decision-panel decision-panel-compact" else "decision-panel"
  href <- function(anchor) {
    paste0(base_path, "#", anchor)
  }
  paste0(
    '<section class="', section_class, '" aria-label="Forecast command center">',
    '<div class="decision-card decision-card-primary">',
    '<span>Start here</span>',
    '<strong>', escape_html(today_label), '</strong>',
    '<small>Jump straight to the current board, then use the bracket to test paths.</small>',
    '<a href="', escape_html(href("today")), '">Review today</a>',
    '</div>',
    '<div class="decision-card">', next_match_html, '<a href="', escape_html(href("next-match")), '">Open next forecast</a></div>',
    '<div class="decision-card">', champion_html, '<a href="', escape_html(href("champion-outlook")), '">See champion outlook</a></div>',
    '<div class="decision-card">', accuracy_html, '<a href="', escape_html(href("model-performance")), '">Check accuracy</a></div>',
    '</section>'
  )
}

render_next_match_section <- function(board) {
  upcoming <- future_board_after_today(board)
  if (nrow(upcoming) == 0) {
    return(
      '<section id="next-match" class="page-section"><div class="empty-state"><strong>No additional future matches are available after today\'s slate.</strong></div></section>'
    )
  }

  paste0(
    '<section id="next-match" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Next match</span>',
    '<h2>Next Match Forecast</h2>',
    '<p>The next match after today\'s slate is expanded by default so the pick, probabilities, and details are immediately visible.</p>',
    '</div>',
    render_forecast_list(upcoming |> dplyr::slice_head(n = 1), "No next match is available.", card_variant = "next"),
    '</section>'
  )
}

render_upcoming_section <- function(board, limit = 8) {
  upcoming <- future_board_after_featured(board)
  paste0(
    '<section id="upcoming" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Upcoming</span>',
    '<h2>Upcoming Matches</h2>',
    '<p>Additional forecast cards after today and the featured next match.</p>',
    '</div>',
    render_forecast_list(upcoming, "No additional upcoming matches are available in the current fixture table.", limit = limit, card_variant = "upcoming"),
    '</section>'
  )
}
