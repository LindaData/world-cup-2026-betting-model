# Fit simple private models from film-study event and possession data.
#
# In RStudio:
# source("R/31_fit_film_study_models.R")
# fit_film_study_models()

find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "_quarto.yml"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root.")
    }
    current <- parent
  }
}

safe_read_csv <- function(path) {
  if (!file.exists(path)) {
    stop("Missing required file: ", path, call. = FALSE)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
}

coerce_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  tolower(as.character(x)) %in% c("true", "1", "t", "yes")
}

build_event_model_frame <- function(events) {
  events$is_shot <- coerce_logical(events$is_shot)
  events$is_goal <- coerce_logical(events$is_goal)
  events$is_card <- coerce_logical(events$is_card)

  frame <- subset(events, next_event_type != "END")
  frame$next_is_shot <- frame$next_event_type %in% c("shot", "goal")
  frame$x_zone <- factor(frame$x_zone)
  frame$y_lane <- factor(frame$y_lane)
  frame$event_group <- factor(frame$event_group)
  frame$team_inferred <- factor(frame$team_inferred)
  frame
}

build_possession_model_frame <- function(possessions) {
  frame <- possessions
  frame$possession_outcome <- ifelse(
    frame$goals > 0,
    "goal",
    ifelse(frame$shots > 0, "shot_no_goal", ifelse(frame$turnovers > 0, "turnover", "other"))
  )
  frame$first_x_zone <- factor(frame$first_x_zone)
  frame$last_x_zone <- factor(frame$last_x_zone)
  frame$first_y_lane <- factor(frame$first_y_lane)
  frame$last_y_lane <- factor(frame$last_y_lane)
  frame$team_inferred <- factor(frame$team_inferred)
  frame
}

fit_event_model <- function(frame) {
  positive_count <- sum(frame$next_is_shot, na.rm = TRUE)
  negative_count <- sum(!frame$next_is_shot, na.rm = TRUE)
  can_fit <- nrow(frame) >= 20 && positive_count >= 5 && negative_count >= 5

  if (!can_fit) {
    return(list(
      fitted = FALSE,
      reason = "Need at least 20 event rows with at least 5 positive and 5 negative next-shot outcomes.",
      model = NULL
    ))
  }

  model <- stats::glm(
    next_is_shot ~ event_group + x_zone + y_lane + seconds_since_prev_event,
    data = frame,
    family = stats::binomial()
  )

  predictions <- frame
  predictions$pred_next_shot_prob <- stats::predict(model, newdata = frame, type = "response")

  coefficients <- data.frame(
    term = rownames(summary(model)$coefficients),
    summary(model)$coefficients,
    row.names = NULL,
    check.names = FALSE
  )

  list(
    fitted = TRUE,
    reason = "",
    model = model,
    predictions = predictions,
    coefficients = coefficients,
    metrics = data.frame(
      rows = nrow(frame),
      positive_outcomes = positive_count,
      negative_outcomes = negative_count,
      brier_score = mean((predictions$pred_next_shot_prob - as.numeric(predictions$next_is_shot))^2)
    )
  )
}

fit_possession_model <- function(frame) {
  outcome_counts <- table(frame$possession_outcome)
  usable_classes <- names(outcome_counts[outcome_counts >= 3])
  reduced <- subset(frame, possession_outcome %in% usable_classes)
  reduced$possession_outcome <- droplevels(factor(reduced$possession_outcome))
  can_fit <- length(usable_classes) >= 2 && nrow(reduced) >= 30

  if (!can_fit) {
    return(list(
      fitted = FALSE,
      reason = "Need at least 30 possessions with at least 2 outcome classes having 3 or more rows each.",
      model = NULL
    ))
  }

  model <- nnet::multinom(
    possession_outcome ~ team_inferred + first_x_zone + last_x_zone + possession_duration_seconds + possession_events,
    data = reduced,
    trace = FALSE
  )

  probs <- predict(model, newdata = reduced, type = "probs")
  probs <- as.data.frame(probs)
  predictions <- cbind(reduced, probs)
  predictions$predicted_outcome <- colnames(probs)[max.col(probs, ties.method = "first")]

  coefficients <- as.data.frame(summary(model)$coefficients)
  coefficients$outcome_level <- rownames(coefficients)
  rownames(coefficients) <- NULL

  accuracy <- mean(predictions$predicted_outcome == as.character(predictions$possession_outcome))

  list(
    fitted = TRUE,
    reason = "",
    model = model,
    predictions = predictions,
    coefficients = coefficients,
    metrics = data.frame(
      rows = nrow(reduced),
      modeled_classes = length(usable_classes),
      accuracy = accuracy
    )
  )
}

fit_film_study_models <- function() {
  root <- find_project_root()
  processed_dir <- file.path(root, "data", "processed", "film_study")
  dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

  events <- safe_read_csv(file.path(processed_dir, "film_study_events_enriched.csv"))
  possessions <- safe_read_csv(file.path(processed_dir, "film_study_possessions.csv"))

  event_frame <- build_event_model_frame(events)
  possession_frame <- build_possession_model_frame(possessions)

  utils::write.csv(event_frame, file.path(processed_dir, "film_study_event_model_frame.csv"), row.names = FALSE)
  utils::write.csv(possession_frame, file.path(processed_dir, "film_study_possession_model_frame.csv"), row.names = FALSE)

  event_fit <- fit_event_model(event_frame)
  possession_fit <- fit_possession_model(possession_frame)

  if (isTRUE(event_fit$fitted)) {
    utils::write.csv(event_fit$predictions, file.path(processed_dir, "film_study_event_model_predictions.csv"), row.names = FALSE)
    utils::write.csv(event_fit$coefficients, file.path(processed_dir, "film_study_event_model_coefficients.csv"), row.names = FALSE)
    utils::write.csv(event_fit$metrics, file.path(processed_dir, "film_study_event_model_metrics.csv"), row.names = FALSE)
  }

  if (isTRUE(possession_fit$fitted)) {
    utils::write.csv(possession_fit$predictions, file.path(processed_dir, "film_study_possession_model_predictions.csv"), row.names = FALSE)
    utils::write.csv(possession_fit$coefficients, file.path(processed_dir, "film_study_possession_model_coefficients.csv"), row.names = FALSE)
    utils::write.csv(possession_fit$metrics, file.path(processed_dir, "film_study_possession_model_metrics.csv"), row.names = FALSE)
  }

  summary_list <- list(
    created_at_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    event_rows = nrow(event_frame),
    possession_rows = nrow(possession_frame),
    event_model = list(
      fitted = isTRUE(event_fit$fitted),
      reason = event_fit$reason
    ),
    possession_model = list(
      fitted = isTRUE(possession_fit$fitted),
      reason = possession_fit$reason
    )
  )

  jsonlite::write_json(
    summary_list,
    file.path(processed_dir, "film_study_model_summary.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )

  invisible(summary_list)
}
