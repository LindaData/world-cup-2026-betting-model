# Fit challenger models on the expanded historical feature population.
#
# These models test whether richer pre-match features improve held-out goal and
# result accuracy. They do not replace the production forecast automatically.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
population_path <- file.path(model_dir, "expanded_population_model_frame.csv")

if (!file.exists(population_path)) {
  stop("Run R/22_build_expanded_feature_population.R before fitting population expansion models.")
}

population <- readr::read_csv(population_path, show_col_types = FALSE)
population$date <- as.Date(population$date)
population$y_result_ordered <- factor(population$y_result_ordered, levels = c("loss", "draw", "win"))
full_sweep <- identical(Sys.getenv("WORLD_CUP_FULL_SWEEP"), "1")

logical_cols <- names(population)[vapply(population, is.logical, logical(1))]
for (col in logical_cols) {
  population[[col]] <- as.integer(ifelse(is.na(population[[col]]), FALSE, population[[col]]))
}

rich_feature_cols <- c(
  "match_year",
  "elo_diff",
  "expected_result",
  "k_factor",
  "goal_multiplier",
  "listed_home",
  "neutral",
  "is_world_cup",
  "is_world_cup_qualifier",
  "is_friendly",
  "is_qualifier",
  "is_nations_league",
  "is_major_tournament",
  "team_points_pg_l5",
  "opp_points_pg_l5",
  "form_points_diff_l5",
  "team_goal_diff_pg_l5",
  "opp_goal_diff_pg_l5",
  "form_goal_diff_l5",
  "attack_vs_defense_l5",
  "defense_vs_attack_l5",
  "team_points_pg_l10",
  "opp_points_pg_l10",
  "form_points_diff_l10",
  "attack_vs_defense_l10",
  "defense_vs_attack_l10",
  "h2h_points_pg_l5",
  "h2h_goal_diff_pg_l5",
  "team_days_since_match_capped",
  "opp_days_since_match_capped",
  "team_experience_log",
  "opp_experience_log",
  "experience_diff_log"
)

rich_feature_cols <- rich_feature_cols[rich_feature_cols %in% names(population)]
required_cols <- c("goals_for", "goals_against", "y_result_ordered", rich_feature_cols)
population <- population[stats::complete.cases(population[, c("goals_for", "goals_against", "y_result_ordered", "match_year")]), ]

fill_missing_from_train <- function(train, test, feature_cols) {
  for (col in feature_cols) {
    if (is.numeric(train[[col]]) || is.integer(train[[col]])) {
      replacement <- stats::median(train[[col]], na.rm = TRUE)
      if (!is.finite(replacement)) {
        replacement <- 0
      }
      train[[col]][is.na(train[[col]])] <- replacement
      test[[col]][is.na(test[[col]])] <- replacement
    } else {
      mode_value <- names(sort(table(train[[col]]), decreasing = TRUE))[1]
      if (is.na(mode_value) || !nzchar(mode_value)) {
        mode_value <- ""
      }
      train[[col]][is.na(train[[col]])] <- mode_value
      test[[col]][is.na(test[[col]])] <- mode_value
    }
  }
  list(train = train, test = test)
}

make_splits <- function(df) {
  set.seed(20260629)
  random_index <- stats::runif(nrow(df)) < 0.80
  split_list <- list(
    all_history_random_80_20 = list(
      train = df[random_index, ],
      test = df[!random_index, ]
    ),
    all_history_time_2019_plus = list(
      train = df[df$match_year <= 2018, ],
      test = df[df$match_year >= 2019, ]
    ),
    modern_1990_time_2019_plus = list(
      train = df[df$match_year >= 1990 & df$match_year <= 2018, ],
      test = df[df$match_year >= 2019, ]
    ),
    recent_2000_time_2019_plus = list(
      train = df[df$match_year >= 2000 & df$match_year <= 2018, ],
      test = df[df$match_year >= 2019, ]
    )
  )
  if (full_sweep) {
    return(split_list)
  }
  split_list[c("all_history_random_80_20", "recent_2000_time_2019_plus")]
}

sample_rows <- function(df, max_rows, seed_offset = 0) {
  if (nrow(df) <= max_rows) {
    return(df)
  }
  set.seed(20260629 + seed_offset)
  df[sample(seq_len(nrow(df)), max_rows), ]
}

rmse <- function(actual, predicted) {
  sqrt(mean((actual - predicted)^2, na.rm = TRUE))
}

mae <- function(actual, predicted) {
  mean(abs(actual - predicted), na.rm = TRUE)
}

poisson_deviance <- function(actual, predicted) {
  predicted <- pmax(predicted, 1e-10)
  ifelse(actual == 0, 2 * predicted, 2 * (actual * log(actual / predicted) - (actual - predicted)))
}

safe_model <- function(label, expr) {
  tryCatch(
    expr,
    error = function(e) {
      data.frame(
        model = label,
        status = "failed",
        note = conditionMessage(e),
        stringsAsFactors = FALSE
      )
    }
  )
}

goal_metric <- function(model, family, validation_type, train, test, predicted, note) {
  predicted <- pmax(0, as.numeric(predicted))
  data.frame(
    model = model,
    model_family = family,
    validation_type = validation_type,
    status = "fit",
    rows_train = nrow(train),
    rows_test = nrow(test),
    test_rmse = rmse(test$goals_for, predicted),
    test_mae = mae(test$goals_for, predicted),
    mean_prediction = mean(predicted, na.rm = TRUE),
    mean_poisson_deviance = mean(poisson_deviance(test$goals_for, predicted), na.rm = TRUE),
    note = note,
    stringsAsFactors = FALSE
  )
}

normalize_probabilities <- function(probabilities) {
  levels_out <- c("loss", "draw", "win")
  prob <- probabilities
  if (length(dim(prob)) == 3) {
    prob <- prob[, , dim(prob)[3]]
  }
  out <- as.data.frame(prob)
  if (ncol(out) == length(levels_out) && !all(levels_out %in% names(out))) {
    names(out) <- levels_out
  }
  for (level in levels_out) {
    if (!level %in% names(out)) {
      out[[level]] <- 0
    }
  }
  out <- out[, levels_out]
  out[] <- lapply(out, as.numeric)
  out[!is.finite(rowSums(out)), ] <- 1 / length(levels_out)
  out <- pmax(as.matrix(out), 1e-12)
  out / rowSums(out)
}

result_metric <- function(model, family, validation_type, train, test, probabilities, note) {
  levels_out <- c("loss", "draw", "win")
  prob <- normalize_probabilities(probabilities)
  actual <- as.character(test$y_result_ordered)
  pred_class <- levels_out[max.col(prob, ties.method = "first")]
  actual_index <- match(actual, levels_out)
  actual_prob <- pmax(prob[cbind(seq_len(nrow(prob)), actual_index)], 1e-12)
  one_hot <- matrix(0, nrow = nrow(prob), ncol = ncol(prob))
  one_hot[cbind(seq_len(nrow(one_hot)), actual_index)] <- 1
  data.frame(
    model = model,
    model_family = family,
    validation_type = validation_type,
    status = "fit",
    rows_train = nrow(train),
    rows_test = nrow(test),
    test_accuracy = mean(pred_class == actual, na.rm = TRUE),
    test_log_loss = -mean(log(actual_prob), na.rm = TRUE),
    test_multiclass_brier = mean(rowSums((prob - one_hot)^2), na.rm = TRUE),
    baseline_majority_accuracy = max(prop.table(table(train$y_result_ordered))),
    note = note,
    stringsAsFactors = FALSE
  )
}

empirical_bayes_goal_pred <- function(train, test, prior_n = 12) {
  global <- mean(train$goals_for, na.rm = TRUE)
  home_multiplier <- mean(train$goals_for[train$listed_home == 1 & train$neutral == 0], na.rm = TRUE) / global
  if (!is.finite(home_multiplier)) {
    home_multiplier <- 1
  }
  attack <- stats::aggregate(goals_for ~ team, data = train, FUN = function(x) {
    (sum(x, na.rm = TRUE) + prior_n * global) / (length(x) + prior_n)
  })
  names(attack)[2] <- "attack_rate"
  defense <- stats::aggregate(goals_against ~ team, data = train, FUN = function(x) {
    (sum(x, na.rm = TRUE) + prior_n * global) / (length(x) + prior_n)
  })
  names(defense) <- c("opponent", "opp_defense_rate")
  scored <- dplyr::left_join(test[, c("team", "opponent", "listed_home", "neutral")], attack, by = "team")
  scored <- dplyr::left_join(scored, defense, by = "opponent")
  scored$attack_rate[is.na(scored$attack_rate)] <- global
  scored$opp_defense_rate[is.na(scored$opp_defense_rate)] <- global
  site_adjustment <- ifelse(scored$listed_home == 1 & scored$neutral == 0, home_multiplier, 1)
  pmax(0, sqrt(scored$attack_rate * scored$opp_defense_rate) * site_adjustment)
}

goal_formula <- stats::as.formula(paste("goals_for ~", paste(rich_feature_cols, collapse = " + ")))
result_formula <- stats::as.formula(paste("y_result_ordered ~", paste(rich_feature_cols, collapse = " + ")))
gam_formula <- stats::as.formula(
  paste(
    "goals_for ~ s(elo_diff, k = 8) + s(expected_result, k = 8) +",
    "s(form_points_diff_l10, k = 8) + s(attack_vs_defense_l10, k = 8) +",
    "listed_home + neutral + is_world_cup + is_world_cup_qualifier + is_friendly + is_major_tournament"
  )
)

splits <- make_splits(population)
goal_metrics <- list()
result_metrics <- list()

for (split_name in names(splits)) {
  cat("\nPopulation expansion split: ", split_name, "\n", sep = "")
  split <- fill_missing_from_train(splits[[split_name]]$train, splits[[split_name]]$test, rich_feature_cols)
  train <- split$train
  test <- split$test
  if (nrow(train) == 0 || nrow(test) == 0) {
    next
  }
  glm_train <- sample_rows(train, ifelse(full_sweep, nrow(train), 35000), seed_offset = 6)
  class_train <- sample_rows(train, ifelse(full_sweep, nrow(train), 30000), seed_offset = 7)

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Rich empirical Bayes goals", {
    pred <- empirical_bayes_goal_pred(train, test)
    goal_metric(
      "Rich empirical Bayes goals",
      "Shrinkage baseline",
      split_name,
      train,
      test,
      pred,
      "Shrinks team attack and opponent defense toward the global scoring rate."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Rich Poisson goals", {
    fit <- stats::glm(goal_formula, data = glm_train, family = stats::poisson(link = "log"))
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric("Rich Poisson goals", "Count model", split_name, glm_train, test, pred, "Poisson model using expanded rolling-form features.")
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Rich negative binomial goals", {
    fit <- MASS::glm.nb(goal_formula, data = glm_train, control = stats::glm.control(maxit = 35))
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric("Rich negative binomial goals", "Overdispersion-aware count model", split_name, glm_train, test, pred, "Count model allowing goal variance above the mean.")
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Rich GAM Poisson goals", {
    gam_train <- sample_rows(train, ifelse(full_sweep, 45000, 16000), seed_offset = 40)
    fit <- mgcv::gam(gam_formula, data = gam_train, family = stats::poisson(link = "log"), method = "REML")
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric("Rich GAM Poisson goals", "Smooth count model", split_name, gam_train, test, pred, "Smooth count model using Elo, expected result, and recent-form curves.")
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("GBM Poisson goals", {
    if (!requireNamespace("gbm", quietly = TRUE)) {
      stop("The gbm package is not installed.")
    }
    gbm_train <- sample_rows(train, ifelse(full_sweep, 30000, 9000), seed_offset = 50)
    fit <- gbm::gbm(
      goal_formula,
      data = gbm_train[, c("goals_for", rich_feature_cols)],
      distribution = "poisson",
      n.trees = ifelse(full_sweep, 550, 180),
      interaction.depth = 3,
      shrinkage = 0.03,
      bag.fraction = 0.75,
      train.fraction = 1,
      verbose = FALSE
    )
    pred <- stats::predict(fit, newdata = test, n.trees = ifelse(full_sweep, 550, 180), type = "response")
    goal_metric("GBM Poisson goals", "Gradient boosting", split_name, gbm_train, test, pred, "Boosted tree count model on the richer feature population.")
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Rich random forest goals", {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("The randomForest package is not installed.")
    }
    rf_train <- sample_rows(train, ifelse(full_sweep, 22000, 7000), seed_offset = 60)
    set.seed(20260629)
    fit <- randomForest::randomForest(
      goal_formula,
      data = rf_train[, c("goals_for", rich_feature_cols)],
      ntree = ifelse(full_sweep, 100, 45),
      mtry = min(6, length(rich_feature_cols)),
      importance = FALSE,
      na.action = stats::na.omit
    )
    pred <- stats::predict(fit, newdata = test)
    goal_metric("Rich random forest goals", "Tree ensemble", split_name, rf_train, test, pred, "Random forest on expanded rolling-form and tournament features.")
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Linear SVR goals", {
    if (!requireNamespace("e1071", quietly = TRUE)) {
      stop("The e1071 package is not installed.")
    }
    svm_train <- sample_rows(train, ifelse(full_sweep, 9000, 2200), seed_offset = 70)
    x_train <- stats::model.matrix(goal_formula, data = svm_train)[, -1, drop = FALSE]
    x_test <- stats::model.matrix(goal_formula, data = test)[, -1, drop = FALSE]
    fit <- e1071::svm(x = x_train, y = svm_train$goals_for, kernel = "linear", cost = 1, scale = TRUE)
    pred <- stats::predict(fit, newdata = x_test)
    goal_metric("Linear SVR goals", "Support vector regression", split_name, svm_train, test, pred, "Linear support-vector regression on a capped training sample.")
  })

  majority <- prop.table(table(train$y_result_ordered))
  majority_prob <- data.frame(
    loss = rep(unname(majority[["loss"]]), nrow(test)),
    draw = rep(unname(majority[["draw"]]), nrow(test)),
    win = rep(unname(majority[["win"]]), nrow(test))
  )
  result_metrics[[length(result_metrics) + 1]] <- result_metric(
    "Population class-share baseline",
    "Naive probability baseline",
    split_name,
    train,
    test,
    majority_prob,
    "Always predicts the train-set loss/draw/win class mix."
  )

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Rich ordinal result", {
    fit <- MASS::polr(result_formula, data = class_train, method = "logistic", Hess = FALSE)
    prob <- stats::predict(fit, newdata = test, type = "probs")
    result_metric("Rich ordinal result", "Ordinal logistic", split_name, class_train, test, prob, "Ordered win/draw/loss model using expanded features.")
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Rich multinomial result", {
    fit <- nnet::multinom(result_formula, data = class_train, trace = FALSE, MaxNWts = 50000)
    prob <- stats::predict(fit, newdata = test, type = "probs")
    result_metric("Rich multinomial result", "Multinomial logistic", split_name, class_train, test, prob, "Unordered win/draw/loss classifier using expanded features.")
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Rich regularized multinomial result", {
    fit <- nnet::multinom(result_formula, data = class_train, trace = FALSE, decay = 0.002, MaxNWts = 50000)
    prob <- stats::predict(fit, newdata = test, type = "probs")
    result_metric("Rich regularized multinomial result", "Regularized classifier", split_name, class_train, test, prob, "Small weight decay to reduce overfitting in the expanded classifier.")
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("GBM multinomial result", {
    if (!requireNamespace("gbm", quietly = TRUE)) {
      stop("The gbm package is not installed.")
    }
    gbm_train <- sample_rows(train, ifelse(full_sweep, 30000, 9000), seed_offset = 80)
    fit <- gbm::gbm(
      result_formula,
      data = gbm_train[, c("y_result_ordered", rich_feature_cols)],
      distribution = "multinomial",
      n.trees = ifelse(full_sweep, 450, 160),
      interaction.depth = 3,
      shrinkage = 0.03,
      bag.fraction = 0.75,
      train.fraction = 1,
      verbose = FALSE
    )
    prob <- stats::predict(fit, newdata = test, n.trees = ifelse(full_sweep, 450, 160), type = "response")
    result_metric("GBM multinomial result", "Gradient boosting classifier", split_name, gbm_train, test, prob, "Boosted tree classifier for win, draw, and loss probabilities.")
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Rich random forest result", {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("The randomForest package is not installed.")
    }
    rf_train <- sample_rows(train, ifelse(full_sweep, 22000, 7000), seed_offset = 90)
    set.seed(20260629)
    fit <- randomForest::randomForest(
      result_formula,
      data = rf_train[, c("y_result_ordered", rich_feature_cols)],
      ntree = ifelse(full_sweep, 120, 55),
      mtry = min(6, length(rich_feature_cols)),
      importance = FALSE,
      na.action = stats::na.omit
    )
    prob <- stats::predict(fit, newdata = test, type = "prob")
    result_metric("Rich random forest result", "Tree ensemble classifier", split_name, rf_train, test, prob, "Random forest classifier on richer rolling-form features.")
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Linear SVM result", {
    if (!requireNamespace("e1071", quietly = TRUE)) {
      stop("The e1071 package is not installed.")
    }
    svm_train <- sample_rows(train, ifelse(full_sweep, 9000, 2200), seed_offset = 100)
    x_train <- stats::model.matrix(result_formula, data = svm_train)[, -1, drop = FALSE]
    x_test <- stats::model.matrix(result_formula, data = test)[, -1, drop = FALSE]
    fit <- e1071::svm(
      x = x_train,
      y = svm_train$y_result_ordered,
      kernel = "linear",
      cost = 1,
      scale = TRUE,
      probability = TRUE
    )
    pred <- stats::predict(fit, newdata = x_test, probability = TRUE)
    prob <- attr(pred, "probabilities")
    result_metric("Linear SVM result", "Support vector classifier", split_name, svm_train, test, prob, "Linear support-vector classifier on a capped training sample.")
  })
}

goal_metric_table <- dplyr::bind_rows(goal_metrics)
result_metric_table <- dplyr::bind_rows(result_metrics)

status_table <- data.frame(
  component = c("expanded_population", "MASS", "mgcv", "nnet", "gbm", "randomForest", "e1071"),
  status = c(
    "available",
    ifelse(requireNamespace("MASS", quietly = TRUE), "available", "missing"),
    ifelse(requireNamespace("mgcv", quietly = TRUE), "available", "missing"),
    ifelse(requireNamespace("nnet", quietly = TRUE), "available", "missing"),
    ifelse(requireNamespace("gbm", quietly = TRUE), "available", "missing"),
    ifelse(requireNamespace("randomForest", quietly = TRUE), "available", "missing"),
    ifelse(requireNamespace("e1071", quietly = TRUE), "available", "missing")
  ),
  note = c(
    paste0("Using ", nrow(population), " team-match rows and ", length(rich_feature_cols), " challenger features."),
    "Fits negative-binomial and ordinal logistic models.",
    "Fits smooth Poisson goal models.",
    "Fits multinomial result models.",
    "Fits gradient-boosted goal and result challengers.",
    "Fits random-forest goal and result challengers.",
    "Fits support-vector goal and result challengers."
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(goal_metric_table, file.path(model_dir, "population_expansion_goal_metrics.csv"))
readr::write_csv(result_metric_table, file.path(model_dir, "population_expansion_result_metrics.csv"))
readr::write_csv(status_table, file.path(model_dir, "population_expansion_status.csv"))

cat("\nPopulation expansion model suite complete.\n")
cat("Goal metrics: ", file.path(model_dir, "population_expansion_goal_metrics.csv"), "\n", sep = "")
cat("Result metrics: ", file.path(model_dir, "population_expansion_result_metrics.csv"), "\n", sep = "")
print(goal_metric_table[order(goal_metric_table$validation_type, goal_metric_table$test_rmse), ])
print(result_metric_table[order(result_metric_table$validation_type, result_metric_table$test_multiclass_brier), ])
