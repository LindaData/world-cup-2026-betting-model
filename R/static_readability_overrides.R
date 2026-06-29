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
    "This is a static page. APIs are pulled offline, converted into model-ready files, and rendered into this public report."
  } else {
    "This is a static forecasting report. APIs are pulled offline, cleaned into model files, and rendered into GitHub Pages. The public browser does not call paid APIs or expose keys."
  }

  paste0(
    '<section class="page-section static-note-section">',
    '<div class="performance-note">',
    '<strong>Static-site setup:</strong> ', escape_html(body),
    ' <span class="section-note">Last generated: ', escape_html(updated), '.</span>',
    '</div>',
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
    '<small>Strength: ', escape_html(strength), '. ', escape_html(model_agreement(row)), ' agree.</small>',
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
    '<summary>View details</summary>',
    '<dl>',
    regulation_detail,
    '<dt>Over 2.5 goals</dt><dd>', display_percent(row$over_2_5_prob, 1), '<small>Chance the match has at least 3 total goals.</small></dd>',
    '<dt>Both teams to score</dt><dd>', display_percent(row$both_teams_to_score_prob, 1), '<small>Chance both teams score at least once.</small></dd>',
    '<dt>Yellow cards</dt><dd>', escape_html(yellow_card_text(row)), '</dd>',
    '<dt>Lineups</dt><dd>', escape_html(lineup_text(row)), '</dd>',
    '<dt>Model votes</dt><dd>OLS: ', escape_html(safe_text(row$ols_predicted_winner, "Not available yet")),
    '; Poisson: ', escape_html(safe_text(row$poisson_predicted_winner, "Not available yet")),
    '; Result model: ', escape_html(safe_text(row$ordinal_predicted_winner, "Not available yet")), '</dd>',
    '<dt>Venue</dt><dd>', escape_html(venue), '</dd>',
    '</dl>',
    '</details>',
    '</article>'
  )
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
    '<p>Readable static forecasts: match probabilities, likely scores, bracket path, and model reliability notes.</p>',
    '<p class="hero-context">Built as a static Quarto report from offline model outputs. No paid API keys or raw feeds are exposed on the public page.</p>',
    '<div class="hero-actions product-actions">',
    '<a class="button-primary" href="reports/08_matchday_predictions.html">View predictions</a>',
    '<a class="button-secondary" href="reports/08_matchday_predictions.html#bracket">Open bracket</a>',
    '<a class="button-secondary" href="reports/00_data_overview.html">Check data</a>',
    '</div>',
    '<p class="timezone-note">Times show in your local timezone when available. UTC is the fallback.</p>',
    '</div>',
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
    '<p>The next match after today\'s slate is expanded by default so the pick and details are visible without hunting.</p>',
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
    '<p>Additional static forecast cards after today and the featured next match.</p>',
    '</div>',
    render_forecast_list(upcoming, "No additional upcoming matches are available in the current fixture table.", limit = limit, card_variant = "upcoming"),
    '</section>'
  )
}
