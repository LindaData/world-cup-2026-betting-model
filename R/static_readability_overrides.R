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
    '<summary>View details</summary>',
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

review_bool <- function(x) {
  if (length(x) == 0 || is.null(x)) {
    return(FALSE)
  }
  value <- x[[1]]
  if (is.logical(value)) {
    isTRUE(value)
  } else {
    tolower(as.character(value)) %in% c("true", "t", "1", "yes", "right", "hit")
  }
}

review_col_number <- function(data, column) {
  if (nrow(data) == 0 || !column %in% names(data)) {
    return(rep(NA_real_, nrow(data)))
  }
  suppressWarnings(as.numeric(data[[column]]))
}

review_col_logical <- function(data, column) {
  if (nrow(data) == 0 || !column %in% names(data)) {
    return(rep(FALSE, nrow(data)))
  }
  vapply(seq_len(nrow(data)), function(i) review_bool(data[[column]][i]), logical(1))
}

review_grade_class <- function(correct) {
  if (isTRUE(correct)) "review-hit" else "review-miss"
}

review_grade_label <- function(correct) {
  if (isTRUE(correct)) "Hit" else "Miss"
}

review_error_label <- function(value) {
  if (!is.finite(value)) {
    return("Pending")
  }
  if (value <= 1) {
    return("Tight")
  }
  if (value <= 2) {
    return("Watch")
  }
  "Wide"
}

review_error_class <- function(value) {
  if (!is.finite(value)) {
    return("review-neutral")
  }
  if (value <= 1) {
    return("review-good")
  }
  if (value <= 2) {
    return("review-watch")
  }
  "review-bad"
}

review_issue_key <- function(row) {
  actual_draw <- if ("actual_draw_flag" %in% names(row)) {
    isTRUE(row$actual_draw_flag[[1]])
  } else {
    grepl("draw", tolower(safe_text(row$actual_result, "")))
  }
  phase <- safe_text(row$phase, "Group")
  penalty_score <- safe_text(row$penalty_score, "")
  extra_time_score <- safe_text(row$extra_time_score, "")
  goal_bias <- safe_number(row$total_goal_bias_value)
  confidence <- safe_number(row$prediction_confidence_value)

  if (actual_draw) {
    return("draw_underweight")
  }
  if (identical(phase, "Knockout") && (nzchar(penalty_score) || nzchar(extra_time_score))) {
    return("knockout_path")
  }
  if (is.finite(goal_bias) && goal_bias >= 0.75) {
    return("score_too_open")
  }
  if (is.finite(goal_bias) && goal_bias <= -0.75) {
    return("score_too_low")
  }
  if (is.finite(confidence) && confidence >= 0.65) {
    return("favorite_too_strong")
  }
  "team_strength_miss"
}

review_issue_label <- function(key) {
  switch(
    key,
    draw_underweight = "Draw underweight",
    knockout_path = "Knockout path swing",
    score_too_open = "Score too open",
    score_too_low = "Score too low",
    favorite_too_strong = "Favorite too strong",
    team_strength_miss = "Team-strength miss",
    "Review needed"
  )
}

review_issue_state <- function(key) {
  switch(
    key,
    draw_underweight = "alert",
    knockout_path = "watch",
    score_too_open = "watch",
    score_too_low = "watch",
    favorite_too_strong = "alert",
    team_strength_miss = "neutral",
    "neutral"
  )
}

review_issue_action <- function(key) {
  switch(
    key,
    draw_underweight = "Lift draw probability and compress winner edges in balanced matches.",
    knockout_path = "Review 90-minute draw handling before the tiebreak layer takes over.",
    score_too_open = "Compress goal totals in slower matches and stronger-defence spots.",
    score_too_low = "Allow more attacking upside where the model is keeping totals too low.",
    favorite_too_strong = "Check team-strength, venue, and form weights before backing a heavy lean.",
    team_strength_miss = "Recheck team-strength inputs, venue context, and stale form signals.",
    "Review the contributing team-strength and score assumptions."
  )
}

review_issue_note <- function(row, key = NULL) {
  issue_key <- if (!is.null(key) && nzchar(key)) key else review_issue_key(row)
  goal_bias <- safe_number(row$total_goal_bias_value)

  switch(
    issue_key,
    draw_underweight = "Missed a match that finished level. The draw layer needs more weight.",
    knockout_path = "The match stayed alive after regulation, so the advancement path needs a better tiebreak read.",
    score_too_open = if (is.finite(goal_bias)) {
      paste0("Expected total ran ", fmt_number(goal_bias, 2), " goals above reality.")
    } else {
      "Projected scoring ran too hot for what actually happened."
    },
    score_too_low = if (is.finite(goal_bias)) {
      paste0("Expected total ran ", fmt_number(abs(goal_bias), 2), " goals below reality.")
    } else {
      "Projected scoring was too conservative for what actually happened."
    },
    favorite_too_strong = "A high-confidence side still missed. The edge was wider than the result justified.",
    team_strength_miss = "The match moved against the side the ensemble preferred. Recheck strength and venue context.",
    "Review the miss against the current weighting and score assumptions."
  )
}

review_issue_summary_note <- function(key) {
  switch(
    key,
    draw_underweight = "Most misses still come from matches that finished level.",
    knockout_path = "The miss came from regulation staying level before the bracket path changed.",
    score_too_open = "Projected totals are running hotter than the final scores in this bucket.",
    score_too_low = "Projected totals are coming in below the final scores in this bucket.",
    favorite_too_strong = "The model created a stronger edge than the result justified.",
    team_strength_miss = "The ensemble side was wrong without a strong draw or score-bias signal.",
    "Review the miss against the current weighting and score assumptions."
  )
}

review_row_note <- function(row) {
  correct <- review_bool(row$ensemble_correct)
  goal_error <- safe_number(row$poisson_total_goal_error)
  probability_actual <- safe_number(row$ensemble_probability_actual)
  actual_result <- tolower(safe_text(row$actual_result, ""))
  penalty_score <- safe_text(row$penalty_score, "")
  extra_time_score <- safe_text(row$extra_time_score, "")

  if (correct && is.finite(goal_error) && goal_error <= 1) {
    return("Pick landed and the score forecast was close.")
  }
  if (correct) {
    return("Pick landed; review the score total before promotion.")
  }
  if ("issue_note" %in% names(row)) {
    issue_note <- safe_text(row$issue_note, "")
    if (nzchar(issue_note)) {
      return(issue_note)
    }
  }
  if (grepl("draw", actual_result)) {
    return("Missed the level result. Draw probability needs review.")
  }
  if (nzchar(penalty_score) || nzchar(extra_time_score)) {
    return("Knockout path changed after regulation.")
  }
  if (is.finite(probability_actual) && probability_actual < 0.35) {
    return("Low-probability result. Treat as an upset check.")
  }
  "Pick missed. Review team strength, form, and venue features."
}

render_review_recent_row <- function(row) {
  correct <- review_bool(row$ensemble_correct)
  goal_error <- safe_number(row$poisson_total_goal_error)
  probability_actual <- safe_number(row$ensemble_probability_actual)
  grade_label <- review_grade_label(correct)
  grade_class <- review_grade_class(correct)
  error_label <- review_error_label(goal_error)
  error_class <- review_error_class(goal_error)
  actual <- paste0(
    safe_text(row$actual_winner, "Result pending"),
    " ",
    safe_text(row$actual_score, "")
  )
  probability_text <- if (is.finite(probability_actual)) {
    display_percent(probability_actual, 1)
  } else {
    "Not posted"
  }
  goal_error_text <- if (is.finite(goal_error)) {
    paste0(display_number(goal_error, 2), " goals")
  } else {
    "Pending"
  }
  issue_label <- if (correct) {
    "Stable call"
  } else {
    safe_text(row$issue_label, "Review needed")
  }

  paste0(
    '<article class="review-board-row ', escape_html(grade_class), '">',
    '<div class="review-match-cell">',
    '<strong>', escape_html(safe_text(row$match_label, "Match")), '</strong>',
    '<small>', escape_html(safe_text(row$date, "Date pending")), '</small>',
    '</div>',
    '<div class="review-result-cell">',
    '<span>Actual</span>',
    '<strong>', escape_html(actual), '</strong>',
    '<small>', escape_html(safe_text(row$actual_public_outcome, safe_text(row$actual_result, "Result pending"))), '</small>',
    '</div>',
    '<div class="review-result-cell">',
    '<span>Model pick</span>',
    '<strong>', escape_html(safe_text(row$ensemble_pick, "Pick pending")), '</strong>',
    '<small>Actual result probability ', probability_text, '</small>',
    '</div>',
    '<div class="review-grade-cell">',
    '<span class="review-badge ', escape_html(grade_class), '">', escape_html(grade_label), '</span>',
    '<small>', escape_html(review_row_note(row)), '</small>',
    '</div>',
    '<div class="review-error-cell">',
    '<span class="review-error-chip ', escape_html(error_class), '">', escape_html(error_label), '</span>',
    '<strong>', escape_html(goal_error_text), '</strong>',
    '<small>', escape_html(issue_label), '</small>',
    '</div>',
    '</article>'
  )
}

render_review_pattern_card <- function(row) {
  count_label <- paste0(fmt_integer(row$matches[[1]]), ifelse(row$matches[[1]] == 1, " miss", " misses"))
  confidence_text <- display_percent(row$avg_confidence[[1]], 1)
  goal_text <- if (is.finite(row$avg_goal_error[[1]])) {
    paste0(fmt_number(row$avg_goal_error[[1]], 2), " goals")
  } else {
    "Pending"
  }

  paste0(
    '<article class="review-pattern-card review-pattern-', escape_html(row$state[[1]]), '">',
    '<div class="review-pattern-head">',
    '<span>', escape_html(row$label[[1]]), '</span>',
    '<strong>', escape_html(count_label), '</strong>',
    '</div>',
    '<div class="review-pattern-metrics">',
    '<div><small>Avg confidence</small><b>', confidence_text, '</b></div>',
    '<div><small>Avg score miss</small><b>', escape_html(goal_text), '</b></div>',
    '</div>',
    '<p>', escape_html(row$note[[1]]), '</p>',
    '<small>', escape_html(row$action[[1]]), '</small>',
    '</article>'
  )
}

render_model_review_section <- function(bundle, compact = FALSE, limit = 8) {
  detail <- bundle$accuracy_detail
  accuracy <- bundle$accuracy
  review <- review_analysis_frame(bundle)

  if (is.null(detail) || nrow(detail) == 0 || nrow(review) == 0) {
    return(
      paste0(
        '<section id="model-review" class="page-section model-review-section">',
        '<div class="empty-state"><strong>Post-match model review will appear after completed matches are scored.</strong></div>',
        '</section>'
      )
    )
  }

  correct <- review$ensemble_correct_flag
  completed <- length(correct)
  hits <- sum(correct, na.rm = TRUE)
  misses <- completed - hits
  hit_rate <- if (completed > 0) hits / completed else NA_real_
  goal_error <- review$poisson_total_goal_error_value
  team_goal_error <- suppressWarnings(as.numeric(review$poisson_team_goal_mae))
  actual_probability <- review$ensemble_probability_actual_value
  tight_scores <- sum(is.finite(goal_error) & goal_error <= 1, na.rm = TRUE)
  draw_misses <- sum(!correct & review$actual_draw_flag, na.rm = TRUE)
  upset_checks <- sum(!correct & is.finite(actual_probability) & actual_probability < 0.35, na.rm = TRUE)
  avg_goal_error <- if (any(is.finite(goal_error))) mean(goal_error, na.rm = TRUE) else NA_real_
  avg_team_goal_error <- if (any(is.finite(team_goal_error))) mean(team_goal_error, na.rm = TRUE) else NA_real_
  average_actual_probability <- if (any(is.finite(actual_probability))) mean(actual_probability, na.rm = TRUE) else NA_real_

  score_cards <- paste0(
    '<div class="review-score-card review-score-card-primary">',
    '<span>Model record</span>',
    '<strong>', escape_html(fmt_integer(hits)), '-', escape_html(fmt_integer(misses)), '</strong>',
    '<small>', display_percent(hit_rate, 1), ' hit rate across ', escape_html(fmt_integer(completed)), ' graded matches.</small>',
    '</div>',
    '<div class="review-score-card">',
    '<span>Avg score miss</span>',
    '<strong>', ifelse(is.finite(avg_goal_error), paste0(fmt_number(avg_goal_error, 2), " goals"), "Pending"), '</strong>',
    '<small>Total-goal distance from the final score.</small>',
    '</div>',
    '<div class="review-score-card">',
    '<span>Avg team-goal miss</span>',
    '<strong>', ifelse(is.finite(avg_team_goal_error), paste0(fmt_number(avg_team_goal_error, 2), " goals"), "Pending"), '</strong>',
    '<small>Average absolute miss per team.</small>',
    '</div>',
    '<div class="review-score-card">',
    '<span>Actual result probability</span>',
    '<strong>', display_percent(average_actual_probability, 1), '</strong>',
    '<small>Average probability assigned to what happened.</small>',
    '</div>'
  )

  learning_cards <- paste0(
    '<div><strong>', escape_html(fmt_integer(tight_scores)), '</strong><span>close score reads</span><small>Final score within one total goal.</small></div>',
    '<div><strong>', escape_html(fmt_integer(draw_misses)), '</strong><span>draw or level misses</span><small>Signals where tie probability needs attention.</small></div>',
    '<div><strong>', escape_html(fmt_integer(upset_checks)), '</strong><span>upset checks</span><small>Actual outcome had less than 35% model probability.</small></div>'
  )

  miss_patterns <- review |>
    dplyr::filter(!.data$ensemble_correct_flag) |>
    dplyr::group_by(issue_key, issue_label, issue_state, issue_action) |>
    dplyr::summarise(
      matches = dplyr::n(),
      avg_confidence = mean(.data$prediction_confidence_value, na.rm = TRUE),
      avg_goal_error = mean(.data$poisson_total_goal_error_value, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(.data$matches), dplyr::desc(.data$avg_confidence)) |>
    dplyr::mutate(note = vapply(.data$issue_key, review_issue_summary_note, character(1))) |>
    dplyr::rename(
      label = issue_label,
      state = issue_state,
      action = issue_action
    ) |>
    dplyr::slice_head(n = 4)
  pattern_html <- if (nrow(miss_patterns) > 0) {
    paste(vapply(seq_len(nrow(miss_patterns)), function(i) render_review_pattern_card(miss_patterns[i, , drop = FALSE]), character(1)), collapse = "")
  } else {
    ""
  }

  recent <- review |>
    dplyr::arrange(dplyr::desc(as.Date(.data$date)), dplyr::desc(.data$source_match_id)) |>
    dplyr::slice_head(n = limit)
  recent_html <- paste(vapply(seq_len(nrow(recent)), function(i) render_review_recent_row(recent[i, ]), character(1)), collapse = "")

  accuracy_note <- if (!is.null(accuracy) && nrow(accuracy) > 0) {
    models <- accuracy |>
      dplyr::mutate(
        label = paste0(.data$model, ": ", fmt_percent(.data$outcome_accuracy, 1))
      ) |>
      dplyr::pull(.data$label)
    paste0('<p class="review-model-note"><strong>Model bench:</strong> ', escape_html(paste(models, collapse = " | ")), '.</p>')
  } else {
    ""
  }

  compact_class <- if (compact) " model-review-compact" else ""

  paste0(
    '<section id="model-review" class="page-section model-review-section', compact_class, '">',
    '<div class="section-heading">',
    '<span class="section-kicker">Model review</span>',
    '<h2>Where The Model Is Winning And Missing</h2>',
    '<p>A post-match grading board that shows hits, misses, score error, and the next places to tune the model. These results are calculated from scored matches only.</p>',
    '</div>',
    '<div class="review-scoreboard">', score_cards, '</div>',
    '<div class="review-learning-strip" aria-label="Model tuning signals">', learning_cards, '</div>',
    if (nzchar(pattern_html)) paste0(
      '<div class="review-pattern-section">',
      '<div class="review-pattern-title"><h3>Main miss types</h3><p>These are the patterns doing the most damage in the graded sample right now.</p></div>',
      '<div class="review-pattern-grid">', pattern_html, '</div>',
      '</div>'
    ) else "",
    '<div class="review-board" aria-label="Recent model grading board">',
    '<div class="review-board-head" aria-hidden="true"><span>Match</span><span>Actual</span><span>Model pick</span><span>Grade</span><span>Score miss</span></div>',
    recent_html,
    '</div>',
    accuracy_note,
    '<p class="section-note">Reading this board: Hit/Miss grades the model pick. Score miss grades the projected score. A missed pick with a low actual-result probability is useful model feedback, not a failure of the site.</p>',
    '</section>'
  )
}

review_analysis_frame <- function(bundle) {
  detail <- bundle$accuracy_detail
  board <- bundle$board

  if (is.null(detail) || nrow(detail) == 0) {
    return(data.frame())
  }

  review <- detail
  if (!is.null(board) && nrow(board) > 0 && "source_match_id" %in% names(detail) && "source_match_id" %in% names(board)) {
    board_fields <- intersect(
      c("source_match_id", "is_knockout_match", "confidence_band", "prediction_confidence", "expected_total_goals"),
      names(board)
    )
    board_lookup <- board |>
      dplyr::select(dplyr::any_of(board_fields)) |>
      dplyr::distinct(.data$source_match_id, .keep_all = TRUE)
    review <- review |>
      dplyr::left_join(board_lookup, by = "source_match_id")
  }

  if (!"is_knockout_match" %in% names(review)) {
    review$is_knockout_match <- NA
  }
  if (!"confidence_band" %in% names(review)) {
    review$confidence_band <- NA_character_
  }
  if (!"prediction_confidence" %in% names(review)) {
    review$prediction_confidence <- NA_real_
  }

  review <- review |>
    dplyr::mutate(
      ensemble_correct_flag = tolower(as.character(.data$ensemble_correct)) %in% c("true", "t", "1", "yes"),
      actual_result_lower = tolower(as.character(.data$actual_result)),
      ensemble_result_lower = tolower(as.character(.data$ensemble_result)),
      is_knockout_flag = tolower(as.character(.data$is_knockout_match)) %in% c("true", "t", "1", "yes"),
      phase = dplyr::if_else(.data$is_knockout_flag, "Knockout", "Group"),
      actual_draw_flag = .data$actual_result_lower == "draw",
      predicted_draw_flag = .data$ensemble_result_lower == "draw",
      confidence_band_label = dplyr::coalesce(as.character(.data$confidence_band), "Not labeled"),
      prediction_confidence_value = suppressWarnings(as.numeric(.data$prediction_confidence)),
      poisson_total_goal_error_value = suppressWarnings(as.numeric(.data$poisson_total_goal_error)),
      ensemble_probability_actual_value = suppressWarnings(as.numeric(.data$ensemble_probability_actual)),
      expected_total_goals_value = suppressWarnings(as.numeric(.data$expected_total_goals)),
      actual_total_goals_value = vapply(.data$actual_score, parse_score_total, numeric(1)),
      total_goal_bias_value = .data$expected_total_goals_value - .data$actual_total_goals_value
    )

  if (nrow(review) > 0) {
    review$issue_key <- vapply(seq_len(nrow(review)), function(i) review_issue_key(review[i, , drop = FALSE]), character(1))
    review$issue_label <- vapply(review$issue_key, review_issue_label, character(1))
    review$issue_state <- vapply(review$issue_key, review_issue_state, character(1))
    review$issue_action <- vapply(review$issue_key, review_issue_action, character(1))
    review$issue_note <- vapply(seq_len(nrow(review)), function(i) review_issue_note(review[i, , drop = FALSE], review$issue_key[[i]]), character(1))
  }

  review
}

make_tuning_segment <- function(data, segment, note, action) {
  if (nrow(data) == 0) {
    return(NULL)
  }

  matches <- nrow(data)
  accuracy <- mean(data$ensemble_correct_flag, na.rm = TRUE)
  goal_error <- if (any(is.finite(data$poisson_total_goal_error_value))) {
    mean(data$poisson_total_goal_error_value, na.rm = TRUE)
  } else {
    NA_real_
  }

  data.frame(
    segment = segment,
    matches = matches,
    accuracy = accuracy,
    goal_error = goal_error,
    note = note,
    action = action,
    stringsAsFactors = FALSE
  )
}

render_tuning_segment_row <- function(row) {
  paste0(
    '<article class="tuning-segment-row">',
    '<div class="tuning-segment-main">',
    '<strong>', escape_html(row$segment[[1]]), '</strong>',
    '<small>', escape_html(row$note[[1]]), '</small>',
    '<small class="tuning-segment-action"><span>Tune first:</span> ', escape_html(row$action[[1]]), '</small>',
    '</div>',
    '<div class="tuning-segment-metric"><span>Matches</span><strong>', escape_html(fmt_integer(row$matches[[1]])), '</strong></div>',
    '<div class="tuning-segment-metric"><span>Hit rate</span><strong>', display_percent(row$accuracy[[1]], 1), '</strong></div>',
    '<div class="tuning-segment-metric"><span>Score miss</span><strong>', ifelse(is.finite(row$goal_error[[1]]), paste0(fmt_number(row$goal_error[[1]], 2), " goals"), "Pending"), '</strong></div>',
    '</article>'
  )
}

render_tuning_miss_card <- function(row) {
  actual_label <- paste0(
    safe_text(row$actual_winner, "Result pending"),
    " ",
    safe_text(row$actual_score, "")
  )
  miss_note <- if (row$actual_draw_flag[[1]]) {
    "Actual result finished level."
  } else if (row$phase[[1]] == "Knockout") {
    "Knockout path missed."
  } else {
    "Winner call missed."
  }

  paste0(
    '<article class="tuning-miss-card">',
    '<div class="tuning-miss-head">',
    '<span class="review-badge review-miss">Miss</span>',
    '<span class="tuning-phase-tag">', escape_html(row$phase[[1]]), '</span>',
    '<span class="tuning-phase-tag">', escape_html(row$confidence_band_label[[1]]), '</span>',
    '<span class="tuning-phase-tag">', escape_html(safe_text(row$issue_label, "Review needed")), '</span>',
    '</div>',
    '<h3>', escape_html(row$match_label[[1]]), '</h3>',
    '<div class="tuning-miss-grid">',
    '<div><span>Model pick</span><strong>', escape_html(safe_text(row$ensemble_pick, "Pick pending")), '</strong></div>',
    '<div><span>Actual</span><strong>', escape_html(actual_label), '</strong></div>',
    '<div><span>Top probability</span><strong>', display_percent(row$prediction_confidence_value[[1]], 1), '</strong></div>',
    '<div><span>Score miss</span><strong>', ifelse(is.finite(row$poisson_total_goal_error_value[[1]]), paste0(fmt_number(row$poisson_total_goal_error_value[[1]], 2), " goals"), "Pending"), '</strong></div>',
    '</div>',
    '<p>', escape_html(miss_note), '</p>',
    '<p class="tuning-miss-next"><strong>Next check:</strong> ', escape_html(safe_text(row$issue_action, "Review the contributing weights and score assumptions.")), '</p>',
    '</article>'
  )
}

make_confidence_check <- function(data, label, note) {
  if (nrow(data) == 0) {
    return(NULL)
  }

  avg_conf <- mean(data$prediction_confidence_value, na.rm = TRUE)
  hit_rate <- mean(data$ensemble_correct_flag, na.rm = TRUE)
  gap <- hit_rate - avg_conf

  data.frame(
    band = label,
    matches = nrow(data),
    avg_confidence = avg_conf,
    hit_rate = hit_rate,
    gap = gap,
    note = note,
    stringsAsFactors = FALSE
  )
}

confidence_check_state <- function(gap) {
  if (!is.finite(gap)) {
    return("neutral")
  }
  if (gap <= -0.07) {
    return("high")
  }
  if (gap >= 0.07) {
    return("low")
  }
  "balanced"
}

confidence_check_copy <- function(gap) {
  if (!is.finite(gap)) {
    return("Not enough completed matches yet.")
  }
  points <- abs(100 * gap)
  if (gap <= -0.07) {
    return(paste0("Actual hit rate is ", fmt_number(points, 1), " points lower than the stated confidence."))
  }
  if (gap >= 0.07) {
    return(paste0("Actual hit rate is ", fmt_number(points, 1), " points higher than the stated confidence."))
  }
  paste0("Actual hit rate is within ", fmt_number(points, 1), " points of the stated confidence.")
}

render_confidence_check_card <- function(row) {
  state <- confidence_check_state(row$gap[[1]])

  paste0(
    '<article class="confidence-check-card confidence-check-', escape_html(state), '">',
    '<div class="confidence-check-head">',
    '<span>', escape_html(row$band[[1]]), '</span>',
    '<strong>', escape_html(fmt_integer(row$matches[[1]])), ' graded matches</strong>',
    '</div>',
    '<div class="confidence-check-metrics">',
    '<div><small>Model usually said</small><b>', display_percent(row$avg_confidence[[1]], 1), '</b></div>',
    '<div><small>Actually landed</small><b>', display_percent(row$hit_rate[[1]], 1), '</b></div>',
    '</div>',
    '<p>', escape_html(confidence_check_copy(row$gap[[1]])), '</p>',
    '<small>', escape_html(row$note[[1]]), '</small>',
    '</article>'
  )
}

render_tuning_watch_section <- function(bundle, compact = FALSE, limit = 6) {
  review <- review_analysis_frame(bundle)

  if (nrow(review) == 0) {
    return(
      paste0(
        '<section id="tuning-watch" class="page-section tuning-watch-section">',
        '<div class="empty-state"><strong>Tuning watch will appear after completed matches are graded.</strong></div>',
        '</section>'
      )
    )
  }

  segments <- dplyr::bind_rows(
    make_tuning_segment(review[review$phase == "Group", , drop = FALSE], "Group-stage matches", "Where the current grading sample is deepest.", "Use this as the primary recalibration sample before reacting to small knockout noise."),
    make_tuning_segment(review[review$phase == "Knockout", , drop = FALSE], "Knockout matches", "Sample is still small; treat this as directional.", "Review the regulation-to-advancement handoff, but wait for more matches before retuning heavily."),
    make_tuning_segment(review[review$confidence_band_label == "Strong", , drop = FALSE], "Strong picks", "High-probability spots from the public ensemble.", "Keep the decisive-result backbone steady and focus on tied outcomes that slipped through."),
    make_tuning_segment(review[review$confidence_band_label == "Medium", , drop = FALSE], "Medium picks", "Competitive matches with some separation.", "Check whether draw probability and venue effects need a lift in balanced matches."),
    make_tuning_segment(review[review$confidence_band_label == "Lean", , drop = FALSE], "Lean picks", "Closest matches and lowest public conviction.", "Reduce confidence spread in close matches before making lean picks more aggressive."),
    make_tuning_segment(review[review$actual_draw_flag, , drop = FALSE], "Actual draws / level finals", "The current blind spot in the graded sample.", "Raise draw share and compress goal totals in the balanced-match layer first.")
  )

  draw_matches <- sum(review$actual_draw_flag, na.rm = TRUE)
  predicted_draws <- sum(review$predicted_draw_flag, na.rm = TRUE)
  strong_rows <- review[review$confidence_band_label == "Strong", , drop = FALSE]
  strong_misses <- sum(!strong_rows$ensemble_correct_flag, na.rm = TRUE)
  strong_draw_misses <- sum(!strong_rows$ensemble_correct_flag & strong_rows$actual_draw_flag, na.rm = TRUE)
  lean_rows <- review[review$confidence_band_label == "Lean", , drop = FALSE]
  lean_accuracy <- if (nrow(lean_rows) > 0) mean(lean_rows$ensemble_correct_flag, na.rm = TRUE) else NA_real_
  knockout_rows <- review[review$phase == "Knockout", , drop = FALSE]
  knockout_matches <- nrow(knockout_rows)
  knockout_accuracy <- if (knockout_matches > 0) mean(knockout_rows$ensemble_correct_flag, na.rm = TRUE) else NA_real_

  priority_cards <- paste0(
    '<div class="tuning-priority-card tuning-priority-card-primary">',
    '<span>Draw calibration</span>',
    '<strong>', escape_html(fmt_integer(draw_matches)), ' actual draws / level finals</strong>',
    '<small>', escape_html(fmt_integer(predicted_draws)), ' top-pick draws so far. This is the clearest gap in the current sample.</small>',
    '</div>',
    '<div class="tuning-priority-card">',
    '<span>Lean-confidence spots</span>',
    '<strong>', display_percent(lean_accuracy, 1), ' hit rate</strong>',
    '<small>', escape_html(fmt_integer(nrow(lean_rows))), ' graded matches. Treat lean picks as the noisiest segment.</small>',
    '</div>',
    '<div class="tuning-priority-card">',
    '<span>Strong-pick misses</span>',
    '<strong>', escape_html(fmt_integer(strong_misses)), ' misses</strong>',
    '<small>', escape_html(fmt_integer(strong_draw_misses)), ' of those misses were actual draws. The model still leans too hard toward a winner.</small>',
    '</div>',
    '<div class="tuning-priority-card">',
    '<span>Knockout evidence</span>',
    '<strong>', escape_html(fmt_integer(knockout_matches)), ' graded match', ifelse(knockout_matches == 1, "", "es"), '</strong>',
    '<small>', ifelse(knockout_matches < 5, "Too early to retune the knockout layer from public results alone.", paste0(display_percent(knockout_accuracy, 1), " accuracy so far.")), '</small>',
    '</div>'
  )

  confidence_checks <- dplyr::bind_rows(
    make_confidence_check(
      review[is.finite(review$prediction_confidence_value) & review$prediction_confidence_value < 0.55, , drop = FALSE],
      "Under 55%",
      "Closest matches with the least separation."
    ),
    make_confidence_check(
      review[is.finite(review$prediction_confidence_value) & review$prediction_confidence_value >= 0.55 & review$prediction_confidence_value < 0.65, , drop = FALSE],
      "55% to 65%",
      "Competitive matches with a small edge."
    ),
    make_confidence_check(
      review[is.finite(review$prediction_confidence_value) & review$prediction_confidence_value >= 0.65 & review$prediction_confidence_value < 0.75, , drop = FALSE],
      "65% to 75%",
      "Solid lean spots where the model sees a clearer favorite."
    ),
    make_confidence_check(
      review[is.finite(review$prediction_confidence_value) & review$prediction_confidence_value >= 0.75, , drop = FALSE],
      "75%+",
      "The strongest public calls on the board."
    )
  )

  confidence_html <- if (nrow(confidence_checks) > 0) {
    paste(vapply(seq_len(nrow(confidence_checks)), function(i) {
      render_confidence_check_card(confidence_checks[i, , drop = FALSE])
    }, character(1)), collapse = "")
  } else {
    '<div class="empty-state"><strong>Confidence checks will appear after completed matches are graded.</strong></div>'
  }

  segment_rows <- paste(vapply(seq_len(nrow(segments)), function(i) render_tuning_segment_row(segments[i, , drop = FALSE]), character(1)), collapse = "")

  misses <- review |>
    dplyr::filter(!.data$ensemble_correct_flag) |>
    dplyr::arrange(dplyr::desc(.data$prediction_confidence_value), dplyr::desc(.data$date)) |>
    dplyr::slice_head(n = limit)
  miss_cards <- if (nrow(misses) > 0) {
    paste(vapply(seq_len(nrow(misses)), function(i) render_tuning_miss_card(misses[i, , drop = FALSE]), character(1)), collapse = "")
  } else {
    '<div class="empty-state"><strong>No missed predictions are available yet.</strong></div>'
  }

  compact_class <- if (compact) " tuning-watch-compact" else ""

  paste0(
    '<section id="tuning-watch" class="page-section tuning-watch-section', compact_class, '">',
    '<div class="section-heading">',
    '<span class="section-kicker">Tuning watch</span>',
    '<h2>Where To Fine-Tune Next</h2>',
    '<p>This section groups graded results into the segments that matter most for improving the model. It is meant to guide the next round of feature work and recalibration.</p>',
    '</div>',
    '<div class="tuning-priority-grid">', priority_cards, '</div>',
    '<div class="confidence-check-section">',
    '<div class="confidence-check-title">',
    '<h3>Confidence Reality Check</h3>',
    '<p>Each band compares what the public probability said before kickoff with what actually happened in completed matches.</p>',
    '</div>',
    '<div class="confidence-check-grid">', confidence_html, '</div>',
    '</div>',
    '<div class="tuning-segment-board">',
    '<div class="tuning-segment-head" aria-hidden="true"><span>Segment</span><span>Matches</span><span>Hit rate</span><span>Score miss</span></div>',
    segment_rows,
    '</div>',
    '<div class="tuning-miss-section">',
    '<div class="tuning-miss-title">',
    '<h3>High-Confidence Misses</h3>',
    '<p>These are the misses worth reviewing first because the model was willing to make a strong public call.</p>',
    '</div>',
    '<div class="tuning-miss-grid">', miss_cards, '</div>',
    '</div>',
    '<p class="section-note">Current read: the ensemble behaves like a winner-seeking model. Draws are the biggest blind spot in the graded sample, while strong favorite spots are generally solid outside of tied matches.</p>',
    '</section>'
  )
}

parse_score_total <- function(score) {
  value <- trimws(as.character(score))
  if (length(value) == 0 || is.na(value) || !grepl("^[0-9]+-[0-9]+$", value)) {
    return(NA_real_)
  }
  home <- suppressWarnings(as.numeric(sub("-.*$", "", value)))
  away <- suppressWarnings(as.numeric(sub("^.*-", "", value)))
  home + away
}

adjustment_board_frame <- function(bundle) {
  review <- review_analysis_frame(bundle)
  board <- bundle$board

  if (nrow(review) == 0) {
    return(data.frame())
  }

  analysis <- review

  if (!"expected_total_goals_value" %in% names(analysis)) {
    analysis$expected_total_goals_value <- NA_real_
  }
  if (!"actual_total_goals_value" %in% names(analysis)) {
    analysis$actual_total_goals_value <- vapply(analysis$actual_score, parse_score_total, numeric(1))
  }
  if (!"total_goal_bias_value" %in% names(analysis)) {
    analysis$total_goal_bias_value <- analysis$expected_total_goals_value - analysis$actual_total_goals_value
  }
  if (all(!is.finite(analysis$expected_total_goals_value)) && !is.null(board) && nrow(board) > 0 && "source_match_id" %in% names(board)) {
    expected_lookup <- board |>
      dplyr::select("source_match_id", dplyr::any_of("expected_total_goals")) |>
      dplyr::distinct(.data$source_match_id, .keep_all = TRUE)
    analysis <- analysis |>
      dplyr::left_join(expected_lookup, by = "source_match_id") |>
      dplyr::mutate(
        expected_total_goals_value = dplyr::coalesce(.data$expected_total_goals_value, suppressWarnings(as.numeric(.data$expected_total_goals))),
        total_goal_bias_value = dplyr::coalesce(.data$total_goal_bias_value, .data$expected_total_goals_value - .data$actual_total_goals_value)
      )
  }

  draw_rows <- analysis[analysis$actual_draw_flag, , drop = FALSE]
  low_rows <- analysis[is.finite(analysis$prediction_confidence_value) & analysis$prediction_confidence_value < 0.55, , drop = FALSE]
  miss_rows <- analysis[!analysis$ensemble_correct_flag, , drop = FALSE]
  decisive_rows <- analysis[!analysis$actual_draw_flag, , drop = FALSE]

  draw_note <- if (nrow(draw_rows) > 0) {
    paste0(
      display_percent(mean(draw_rows$ensemble_probability_actual_value, na.rm = TRUE), 1),
      " average probability on the outcome that actually happened."
    )
  } else {
    "Completed level results are not available yet."
  }

  low_gap <- if (nrow(low_rows) > 0) {
    mean(low_rows$ensemble_correct_flag, na.rm = TRUE) - mean(low_rows$prediction_confidence_value, na.rm = TRUE)
  } else {
    NA_real_
  }

  bias_note <- if (nrow(miss_rows) > 0 && any(is.finite(miss_rows$total_goal_bias_value))) {
    draw_bias <- mean(draw_rows$total_goal_bias_value, na.rm = TRUE)
    if (is.finite(draw_bias)) {
      paste0("Level results ran ", fmt_number(draw_bias, 2), " goals above reality on average.")
    } else {
      "Use this to decide whether the score layer should be compressed."
    }
  } else {
    "Use this to decide whether the score layer should be compressed."
  }

  cards <- data.frame(
    state = c("alert", "warning", "warning", "positive"),
    label = c(
      "Draw weight needs a lift",
      "Closest matches are still too aggressive",
      "Missed matches are running too open",
      "Decisive winners are holding up"
    ),
    value = c(
      if (nrow(draw_rows) > 0) paste0(display_percent(mean(draw_rows$ensemble_correct_flag, na.rm = TRUE), 1), " hit rate on ", fmt_integer(nrow(draw_rows)), " level results") else "Pending",
      if (nrow(low_rows) > 0) paste0(display_percent(mean(low_rows$ensemble_correct_flag, na.rm = TRUE), 1), " landed vs ", display_percent(mean(low_rows$prediction_confidence_value, na.rm = TRUE), 1), " stated") else "Pending",
      if (nrow(miss_rows) > 0 && any(is.finite(miss_rows$total_goal_bias_value))) paste0(fmt_number(mean(miss_rows$total_goal_bias_value, na.rm = TRUE), 2), " goals above reality on misses") else "Pending",
      if (nrow(decisive_rows) > 0) paste0(display_percent(mean(decisive_rows$ensemble_correct_flag, na.rm = TRUE), 1), " hit rate when the match does not finish level") else "Pending"
    ),
    note = c(
      draw_note,
      if (is.finite(low_gap)) paste0("The under-55% band missed by ", fmt_number(abs(100 * low_gap), 1), " percentage points.") else "Low-confidence calibration will appear after more completed matches.",
      bias_note,
      "Keep this backbone steady while the draw and score layers are tuned."
    ),
    stringsAsFactors = FALSE
  )

  challenger_note <- NULL
  challengers <- bundle$challenger_metrics
  if (!is.null(challengers) && nrow(challengers) > 0) {
    leader <- challengers |>
      dplyr::filter(.data$status == "fit") |>
      dplyr::arrange(.data$test_rmse) |>
      dplyr::slice_head(n = 1)
    if (nrow(leader) > 0) {
      challenger_note <- paste0(
        safe_text(leader$model[[1]], "Best local challenger"),
        " leads the current local challenger board at ",
        fmt_number(leader$test_rmse[[1]], 3),
        " RMSE."
      )
    }
  }

  list(cards = cards, challenger_note = challenger_note)
}

render_adjustment_board_section <- function(bundle, compact = FALSE) {
  board_data <- adjustment_board_frame(bundle)

  if (!is.list(board_data) || nrow(board_data$cards) == 0) {
    return(
      paste0(
        '<section id="adjustments" class="page-section adjustment-board-section">',
        '<div class="empty-state"><strong>Adjustment board will appear after completed matches are graded.</strong></div>',
        '</section>'
      )
    )
  }

  cards <- board_data$cards
  card_html <- paste(vapply(seq_len(nrow(cards)), function(i) {
    row <- cards[i, , drop = FALSE]
    paste0(
      '<article class="adjustment-card adjustment-card-', escape_html(row$state[[1]]), '">',
      '<span>', escape_html(row$label[[1]]), '</span>',
      '<strong>', escape_html(row$value[[1]]), '</strong>',
      '<p>', escape_html(row$note[[1]]), '</p>',
      '</article>'
    )
  }, character(1)), collapse = "")

  challenger_html <- if (!is.null(board_data$challenger_note) && nzchar(board_data$challenger_note)) {
    paste0(
      '<div class="adjustment-promo-note">',
      '<strong>Promotion watch:</strong> ',
      escape_html(board_data$challenger_note),
      ' Keep backtesting and calibration checks ahead of any public promotion.',
      '</div>'
    )
  } else {
    ""
  }

  paste0(
    '<section id="adjustments" class="page-section adjustment-board-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Adjustment board</span>',
    '<h2>What To Adjust Next</h2>',
    '<p>This board turns the graded-match sample into concrete tuning directions so you can decide where to change weights, calibration, or score assumptions next.</p>',
    '</div>',
    '<div class="adjustment-grid">', card_html, '</div>',
    challenger_html,
    '<p class="section-note">Current read: keep the decisive-result backbone, but retune draw probability and score compression before making the public pick more aggressive.</p>',
    '</section>'
  )
}

model_signal_frame <- function(bundle) {
  detail <- bundle$accuracy_detail
  accuracy <- bundle$accuracy

  if (is.null(detail) || nrow(detail) == 0) {
    return(data.frame())
  }

  model_rows <- data.frame(
    model = c("Ensemble", "OLS goals", "Poisson score grid", "Ordinal result"),
    result_col = c("ensemble_result", "ols_result", "poisson_result", "ordinal_result"),
    correct_col = c("ensemble_correct", "ols_correct", "poisson_correct", "ordinal_correct"),
    prob_col = c("ensemble_probability_actual", "ensemble_probability_actual", "poisson_probability_actual", "ordinal_probability_actual"),
    goal_error_col = c(NA_character_, "ols_total_goal_error", "poisson_total_goal_error", NA_character_),
    role = c(
      "Public pick shown on the site.",
      "Expected-goal benchmark translated into a result call.",
      "Score-grid baseline for goals and scoreline context.",
      "Direct win / draw / loss probability baseline."
    ),
    stringsAsFactors = FALSE
  )

  if (!is.null(accuracy) && nrow(accuracy) > 0) {
    accuracy_lookup <- accuracy |>
      dplyr::select(.data$model, .data$plain_english)
    model_rows <- model_rows |>
      dplyr::left_join(accuracy_lookup, by = "model")
  } else {
    model_rows$plain_english <- NA_character_
  }

  out <- lapply(seq_len(nrow(model_rows)), function(i) {
    row <- model_rows[i, , drop = FALSE]
    result_values <- as.character(detail[[row$result_col[[1]]]])
    correct_values <- tolower(as.character(detail[[row$correct_col[[1]]]])) %in% c("true", "t", "1", "yes")
    prob_values <- suppressWarnings(as.numeric(detail[[row$prob_col[[1]]]]))
    goal_values <- if (is.na(row$goal_error_col[[1]])) rep(NA_real_, nrow(detail)) else suppressWarnings(as.numeric(detail[[row$goal_error_col[[1]]]]))

    data.frame(
      model = row$model[[1]],
      role = row$role[[1]],
      plain_english = safe_text(row$plain_english, row$role[[1]]),
      matches = nrow(detail),
      accuracy = mean(correct_values, na.rm = TRUE),
      actual_prob_mean = mean(prob_values, na.rm = TRUE),
      draw_actual_prob = mean(prob_values[detail$actual_result == "draw"], na.rm = TRUE),
      decisive_actual_prob = mean(prob_values[detail$actual_result != "draw"], na.rm = TRUE),
      top_pick_draws = sum(result_values == "draw", na.rm = TRUE),
      top_pick_draw_hits = sum(result_values == "draw" & detail$actual_result == "draw", na.rm = TRUE),
      goal_error = mean(goal_values, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })

  dplyr::bind_rows(out)
}

render_model_signal_card <- function(row, draw_best, score_best) {
  draw_badge <- if (identical(row$model[[1]], draw_best)) {
    '<span class="model-signal-chip model-signal-chip-highlight">Best draw coverage</span>'
  } else {
    ""
  }
  score_badge <- if (identical(row$model[[1]], score_best)) {
    '<span class="model-signal-chip">Tightest score miss</span>'
  } else {
    ""
  }
  score_text <- if (is.finite(row$goal_error[[1]])) {
    paste0(fmt_number(row$goal_error[[1]], 2), " goals")
  } else {
    "Result-only"
  }
  draw_pick_text <- paste0(
    fmt_integer(row$top_pick_draws[[1]]),
    " draw calls / ",
    fmt_integer(row$top_pick_draw_hits[[1]]),
    " correct"
  )

  paste0(
    '<article class="model-signal-card">',
    '<div class="model-signal-head">',
    '<h3>', escape_html(row$model[[1]]), '</h3>',
    '<div class="model-signal-chip-row">', draw_badge, score_badge, '</div>',
    '</div>',
    '<p>', escape_html(row$plain_english[[1]]), '</p>',
    '<div class="model-signal-metrics">',
    '<div><span>Hit rate</span><strong>', display_percent(row$accuracy[[1]], 1), '</strong></div>',
    '<div><span>Actual draw probability</span><strong>', display_percent(row$draw_actual_prob[[1]], 1), '</strong></div>',
    '<div><span>Actual decisive-result probability</span><strong>', display_percent(row$decisive_actual_prob[[1]], 1), '</strong></div>',
    '<div><span>Score miss</span><strong>', escape_html(score_text), '</strong></div>',
    '<div><span>Top-pick draw behavior</span><strong>', escape_html(draw_pick_text), '</strong></div>',
    '</div>',
    '</article>'
  )
}

render_model_disagreement_row <- function(row) {
  paste0(
    '<article class="model-disagreement-row">',
    '<div class="model-disagreement-match">',
    '<strong>', escape_html(row$match_label[[1]]), '</strong>',
    '<small>', escape_html(safe_text(row$actual_result, "Result pending")), ' / ', escape_html(safe_text(row$actual_score, "")), '</small>',
    '</div>',
    '<div class="model-disagreement-picks">',
    '<span>Ensemble</span><strong>', escape_html(safe_text(row$ensemble_result, "Pending")), '</strong>',
    '<span>OLS</span><strong>', escape_html(safe_text(row$ols_result, "Pending")), '</strong>',
    '<span>Poisson</span><strong>', escape_html(safe_text(row$poisson_result, "Pending")), '</strong>',
    '<span>Ordinal</span><strong>', escape_html(safe_text(row$ordinal_result, "Pending")), '</strong>',
    '</div>',
    '</article>'
  )
}

render_model_signal_section <- function(bundle, compact = FALSE) {
  detail <- bundle$accuracy_detail
  signals <- model_signal_frame(bundle)

  if (nrow(signals) == 0 || is.null(detail) || nrow(detail) == 0) {
    return(
      paste0(
        '<section id="model-signals" class="page-section model-signal-section">',
        '<div class="empty-state"><strong>Model signal board will appear after completed matches are graded.</strong></div>',
        '</section>'
      )
    )
  }

  draw_best <- signals$model[[which.max(signals$draw_actual_prob)]]
  score_candidates <- signals[is.finite(signals$goal_error), , drop = FALSE]
  score_best <- if (nrow(score_candidates) > 0) score_candidates$model[[which.min(score_candidates$goal_error)]] else ""

  disagreement_rows <- detail |>
    dplyr::filter(
      .data$ensemble_result != .data$ols_result |
        .data$ensemble_result != .data$poisson_result |
        .data$ensemble_result != .data$ordinal_result
    )
  disagreement_count <- nrow(disagreement_rows)
  cards <- paste(vapply(seq_len(nrow(signals)), function(i) render_model_signal_card(signals[i, , drop = FALSE], draw_best, score_best), character(1)), collapse = "")

  disagreement_html <- if (disagreement_count > 0) {
    paste(vapply(seq_len(nrow(disagreement_rows)), function(i) render_model_disagreement_row(disagreement_rows[i, , drop = FALSE]), character(1)), collapse = "")
  } else {
    '<div class="empty-state"><strong>The baseline models are fully aligned on the current graded sample.</strong></div>'
  }

  takeaway <- paste0(
    'Current read: all four baseline models land on the same headline hit rate in the graded sample. ',
    'The bigger issue is shared calibration, especially on matches that finish level. ',
    'Baseline disagreement is rare (', fmt_integer(disagreement_count), ' graded matches), so the public ensemble does not yet gain much diversity from mixing these four signals.'
  )

  paste0(
    '<section id="model-signals" class="page-section model-signal-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Model signals</span>',
    '<h2>Which Model Is Helping Where?</h2>',
    '<p>This board shows what each baseline model contributes to the public forecast. The goal is to make tuning decisions without flooding the page with technical diagnostics.</p>',
    '</div>',
    '<div class="model-signal-grid">', cards, '</div>',
    '<div class="model-disagreement-board">',
    '<div class="model-disagreement-title">',
    '<h3>Where The Baselines Split</h3>',
    '<p>These are the few graded matches where the baseline models did not all point to the same outcome.</p>',
    '</div>',
    disagreement_html,
    '</div>',
    '<p class="section-note">', escape_html(takeaway), '</p>',
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
      '<small>', escape_html(prediction_strength(row)), ' strength / ', escape_html(probability_edge(row)), ' edge</small>',
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
      '<span>Model review</span>',
      '<strong>', display_percent(ensemble$outcome_accuracy[[1]], 1), '</strong>',
      '<small>Correct winner/result picks over ', escape_html(ensemble$completed_matches[[1]]), ' completed matches.</small>'
    )
  } else {
    '<span>Model review</span><strong>Pending results</strong><small>Accuracy appears after completed matches are scored.</small>'
  }

  adjustment_html <- if (!is.null(bundle$accuracy_detail) && nrow(bundle$accuracy_detail) > 0) {
    review <- review_analysis_frame(bundle)
    draw_rows <- review[review$actual_draw_flag, , drop = FALSE]
    low_rows <- review[is.finite(review$prediction_confidence_value) & review$prediction_confidence_value < 0.55, , drop = FALSE]
    if (nrow(draw_rows) > 0) {
      paste0(
        '<span>Tuning priority</span>',
        '<strong>', display_percent(mean(draw_rows$ensemble_correct_flag, na.rm = TRUE), 1), ' draw hit rate</strong>',
        '<small>', escape_html(fmt_integer(nrow(draw_rows))), ' level results graded; the draw layer is still the clearest gap.</small>'
      )
    } else if (nrow(low_rows) > 0) {
      paste0(
        '<span>Tuning priority</span>',
        '<strong>', display_percent(mean(low_rows$ensemble_correct_flag, na.rm = TRUE), 1), ' landed below 55%</strong>',
        '<small>Use the adjustment board to review the current low-confidence gap.</small>'
      )
    } else {
      accuracy_html
    }
  } else {
    accuracy_html
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
    '<div class="decision-card">', adjustment_html, '<a href="', escape_html(href("adjustments")), '">Open adjustment board</a></div>',
    '</section>'
  )
}

render_next_match_section <- function(board) {
  upcoming <- future_board_after_today(board)
  if (nrow(upcoming) == 0) {
    return(
      '<section id="next-match" class="page-section"><div class="empty-state"><strong>No additional future matches are available after the current slate.</strong></div></section>'
    )
  }

  paste0(
    '<section id="next-match" class="page-section forecast-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Next match</span>',
    '<h2>Next Match Forecast</h2>',
    '<p>The next match after the current slate is expanded by default so the pick, probabilities, and details are immediately visible.</p>',
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

render_forecast_dictionary_section <- function() {
  dictionary <- data.frame(
    term = c(
      "Win probability",
      "Advance probability",
      "Level after regulation",
      "Expected goals",
      "Most likely score",
      "Prediction strength",
      "Model agreement",
      "Brier score",
      "RMSE",
      "MAE",
      "Calibration"
    ),
    definition = c(
      "The model-estimated chance that a team wins the match when a regulation result can stand on its own.",
      "The chance that a team moves on in a knockout match after regulation, extra time, or penalties.",
      "For knockout matches, the chance the score is tied after 90 minutes. It is not treated as a final draw.",
      "The average score the model expects, not the exact score it promises.",
      "The single scoreline with the highest probability in the score grid.",
      "A plain-language label that groups the top outcome probability into lean, medium, or strong.",
      "How many of the baseline models point to the same winner, draw, or advancing team.",
      "A probability-quality score. Lower is better because it means the forecast probabilities stayed closer to reality.",
      "Root mean squared error. It punishes larger misses more than smaller ones. Lower is better.",
      "Mean absolute error. It is the average size of the miss with no extra penalty for large errors. Lower is better.",
      "How closely the published probabilities match long-run results after enough matches have been graded."
    ),
    stringsAsFactors = FALSE
  )

  cards <- paste(vapply(seq_len(nrow(dictionary)), function(i) {
    paste0(
      '<article class="dictionary-card">',
      '<h3>', escape_html(dictionary$term[[i]]), '</h3>',
      '<p>', escape_html(dictionary$definition[[i]]), '</p>',
      '</article>'
    )
  }, character(1)), collapse = "")

  paste0(
    '<section id="dictionary" class="page-section dictionary-section">',
    '<div class="section-heading">',
    '<span class="section-kicker">Guide</span>',
    '<h2>Forecast Dictionary</h2>',
    '<p>Short definitions for the terms that appear most often on the public forecast board and review pages.</p>',
    '</div>',
    '<div class="dictionary-grid">', cards, '</div>',
    '</section>'
  )
}
