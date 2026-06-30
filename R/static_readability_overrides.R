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
    '</div>',
    '</article>'
  )
}

render_model_review_section <- function(bundle, compact = FALSE, limit = 8) {
  detail <- bundle$accuracy_detail
  accuracy <- bundle$accuracy

  if (is.null(detail) || nrow(detail) == 0) {
    return(
      paste0(
        '<section id="model-review" class="page-section model-review-section">',
        '<div class="empty-state"><strong>Post-match model review will appear after completed matches are scored.</strong></div>',
        '</section>'
      )
    )
  }

  correct <- review_col_logical(detail, "ensemble_correct")
  completed <- length(correct)
  hits <- sum(correct, na.rm = TRUE)
  misses <- completed - hits
  hit_rate <- if (completed > 0) hits / completed else NA_real_
  goal_error <- review_col_number(detail, "poisson_total_goal_error")
  team_goal_error <- review_col_number(detail, "poisson_team_goal_mae")
  actual_probability <- review_col_number(detail, "ensemble_probability_actual")
  tight_scores <- sum(is.finite(goal_error) & goal_error <= 1, na.rm = TRUE)
  draw_misses <- if ("actual_result" %in% names(detail)) {
    sum(!correct & grepl("draw", tolower(as.character(detail$actual_result))), na.rm = TRUE)
  } else {
    0
  }
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

  recent <- detail |>
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
      c("source_match_id", "is_knockout_match", "confidence_band", "prediction_confidence"),
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

  review |>
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
      ensemble_probability_actual_value = suppressWarnings(as.numeric(.data$ensemble_probability_actual))
    )
}

make_tuning_segment <- function(data, segment, note) {
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
    stringsAsFactors = FALSE
  )
}

render_tuning_segment_row <- function(row) {
  paste0(
    '<article class="tuning-segment-row">',
    '<div class="tuning-segment-main">',
    '<strong>', escape_html(row$segment[[1]]), '</strong>',
    '<small>', escape_html(row$note[[1]]), '</small>',
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
    '</div>',
    '<h3>', escape_html(row$match_label[[1]]), '</h3>',
    '<div class="tuning-miss-grid">',
    '<div><span>Model pick</span><strong>', escape_html(safe_text(row$ensemble_pick, "Pick pending")), '</strong></div>',
    '<div><span>Actual</span><strong>', escape_html(actual_label), '</strong></div>',
    '<div><span>Top probability</span><strong>', display_percent(row$prediction_confidence_value[[1]], 1), '</strong></div>',
    '<div><span>Score miss</span><strong>', ifelse(is.finite(row$poisson_total_goal_error_value[[1]]), paste0(fmt_number(row$poisson_total_goal_error_value[[1]], 2), " goals"), "Pending"), '</strong></div>',
    '</div>',
    '<p>', escape_html(miss_note), '</p>',
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
    make_tuning_segment(review[review$phase == "Group", , drop = FALSE], "Group-stage matches", "Where the current grading sample is deepest."),
    make_tuning_segment(review[review$phase == "Knockout", , drop = FALSE], "Knockout matches", "Sample is still small; treat this as directional."),
    make_tuning_segment(review[review$confidence_band_label == "Strong", , drop = FALSE], "Strong picks", "High-probability spots from the public ensemble."),
    make_tuning_segment(review[review$confidence_band_label == "Medium", , drop = FALSE], "Medium picks", "Competitive matches with some separation."),
    make_tuning_segment(review[review$confidence_band_label == "Lean", , drop = FALSE], "Lean picks", "Closest matches and lowest public conviction."),
    make_tuning_segment(review[review$actual_draw_flag, , drop = FALSE], "Actual draws / level finals", "The current blind spot in the graded sample.")
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
    '<div class="decision-card">', accuracy_html, '<a href="', escape_html(href("model-review")), '">Review record</a></div>',
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
