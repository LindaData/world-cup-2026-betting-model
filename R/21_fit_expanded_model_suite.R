# Expanded historical model suite.
#
# This script broadens model comparison without changing the production
# forecast. It trains candidate goal and result models on historical data,
# evaluates held-out splits, and writes compact model-selection artifacts for
# the Model Challengers report.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

goals_frame <- DBI::dbGetQuery(con, "
  SELECT
    source_match_id,
    date,
    match_year,
    tournament,
    neutral,
    team,
    opponent,
    listed_home,
    y_goals_for,
    pre_elo,
    opponent_pre_elo,
    elo_diff,
    pre_match_expected_result,
    k_factor,
    is_world_cup,
    is_friendly
  FROM vw_goals_linear_model_frame
")

result_frame <- DBI::dbGetQuery(con, "
  SELECT
    source_match_id,
    date,
    match_year,
    tournament,
    neutral,
    team,
    opponent,
    listed_home,
    goals_for,
    goals_against,
    y_result_ordered,
    pre_elo,
    opponent_pre_elo,
    elo_diff,
    pre_match_expected_result,
    k_factor,
    is_world_cup,
    is_friendly
  FROM vw_result_ordinal_model_frame
")

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

feature_cols <- c(
  "match_year",
  "pre_elo",
  "opponent_pre_elo",
  "elo_diff",
  "pre_match_expected_result",
  "k_factor",
  "listed_home",
  "neutral",
  "is_world_cup",
  "is_friendly"
)

prep_common <- function(df) {
  df$neutral <- as.logical(df$neutral)
  df$listed_home <- as.logical(df$listed_home)
  df$is_world_cup <- as.logical(df$is_world_cup)
  df$is_friendly <- as.logical(df$is_friendly)
  df$match_year <- as.numeric(df$match_year)
  df
}

goals_frame <- prep_common(goals_frame)
result_frame <- prep_common(result_frame)
result_frame$y_result_ordered <- factor(
  as.character(result_frame$y_result_ordered),
  levels = c("loss", "draw", "win")
)

goals_frame <- goals_frame[stats::complete.cases(goals_frame[, c("y_goals_for", feature_cols)]), ]
result_frame <- result_frame[stats::complete.cases(result_frame[, c("y_result_ordered", feature_cols)]), ]

make_splits <- function(df) {
  set.seed(20260629)
  df$random_split <- ifelse(stats::runif(nrow(df)) < 0.80, "train", "test")
  list(
    random_80_20 = list(
      train = df[df$random_split == "train", ],
      test = df[df$random_split == "test", ]
    ),
    train_through_2018_test_2019_plus = list(
      train = df[df$match_year <= 2018, ],
      test = df[df$match_year >= 2019, ]
    )
  )
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

goal_metric <- function(model, family, validation_type, status, train, test, predicted, note) {
  predicted <- pmax(0, as.numeric(predicted))
  data.frame(
    model = model,
    model_family = family,
    validation_type = validation_type,
    status = status,
    rows_train = nrow(train),
    rows_test = nrow(test),
    test_rmse = rmse(test$y_goals_for, predicted),
    test_mae = mae(test$y_goals_for, predicted),
    mean_prediction = mean(predicted, na.rm = TRUE),
    mean_poisson_deviance = mean(poisson_deviance(test$y_goals_for, predicted), na.rm = TRUE),
    note = note,
    stringsAsFactors = FALSE
  )
}

result_metric <- function(model, family, validation_type, status, train, test, probabilities, note) {
  levels_out <- c("loss", "draw", "win")
  prob <- as.matrix(probabilities[, levels_out, drop = FALSE])
  prob[!is.finite(prob)] <- 1 / length(levels_out)
  prob <- pmax(prob, 1e-12)
  prob <- prob / rowSums(prob)
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
    status = status,
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

normalize_probabilities <- function(probabilities) {
  levels_out <- c("loss", "draw", "win")
  out <- as.data.frame(probabilities)
  for (level in levels_out) {
    if (!level %in% names(out)) {
      out[[level]] <- 0
    }
  }
  out <- out[, levels_out]
  totals <- rowSums(out)
  out[!is.finite(totals) | totals <= 0, ] <- 1 / length(levels_out)
  totals <- rowSums(out)
  out / totals
}

goal_splits <- make_splits(goals_frame)
result_splits <- make_splits(result_frame)

goal_metrics <- list()
goal_status <- list()
result_metrics <- list()
result_status <- list()

goal_model_cols <- c(
  "match_year",
  "elo_diff",
  "pre_match_expected_result",
  "k_factor",
  "listed_home",
  "neutral",
  "is_world_cup",
  "is_friendly"
)
result_model_cols <- c(
  "elo_diff",
  "pre_match_expected_result",
  "listed_home",
  "neutral",
  "is_world_cup",
  "is_friendly"
)

sample_rows <- function(df, max_rows, seed_offset = 0) {
  if (nrow(df) <= max_rows) {
    return(df)
  }
  set.seed(20260629 + seed_offset)
  df[sample(seq_len(nrow(df)), max_rows), ]
}

goal_full_formula <- stats::as.formula(paste("y_goals_for ~", paste(goal_model_cols, collapse = " + ")))
goal_elo_formula <- y_goals_for ~ elo_diff + pre_match_expected_result + listed_home + neutral
goal_gam_formula <- stats::as.formula(
  paste(
    "y_goals_for ~",
    "s(elo_diff, k = 8) +",
    "s(pre_match_expected_result, k = 8) +",
    "s(match_year, k = 8) +",
    "listed_home + neutral + is_world_cup + is_friendly"
  )
)

for (split_name in names(goal_splits)) {
  split <- goal_splits[[split_name]]
  train <- split$train
  test <- split$test

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Elo OLS goals", {
    fit <- stats::lm(goal_elo_formula, data = train)
    pred <- stats::predict(fit, newdata = test)
    goal_metric(
      "Elo OLS goals",
      "Linear benchmark",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Small transparent baseline using team strength and home/neutral context."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Poisson GLM goals", {
    fit <- stats::glm(goal_full_formula, data = train, family = stats::poisson(link = "log"))
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric(
      "Poisson GLM goals",
      "Count model",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Standard count model for goals."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Quasi-Poisson goals", {
    fit <- stats::glm(goal_full_formula, data = train, family = stats::quasipoisson(link = "log"))
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric(
      "Quasi-Poisson goals",
      "Overdispersion-aware count model",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Uses the same mean structure as Poisson while allowing extra variance."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Negative binomial goals", {
    fit <- MASS::glm.nb(goal_full_formula, data = train)
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric(
      "Negative binomial goals",
      "Overdispersion-aware count model",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Count model designed for variance above the mean."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("GAM Poisson goals", {
    train_cap <- sample_rows(train, 50000, seed_offset = 10)
    fit <- mgcv::gam(goal_gam_formula, data = train_cap, family = stats::poisson(link = "log"), method = "REML")
    pred <- stats::predict(fit, newdata = test, type = "response")
    goal_metric(
      "GAM Poisson goals",
      "Smooth count model",
      split_name,
      "fit",
      train_cap,
      test,
      pred,
      "Allows curved relationships for Elo and expected result."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Two-stage zero-aware goals", {
    train_zero <- train
    train_zero$scored_any <- as.integer(train_zero$y_goals_for > 0)
    scored_formula <- stats::as.formula(paste("scored_any ~", paste(goal_model_cols, collapse = " + ")))
    fit_scored <- stats::glm(scored_formula, data = train_zero, family = stats::binomial(link = "logit"))
    fit_positive <- stats::glm(goal_full_formula, data = train_zero[train_zero$y_goals_for > 0, ], family = stats::poisson(link = "log"))
    pred_scored <- stats::predict(fit_scored, newdata = test, type = "response")
    pred_positive <- stats::predict(fit_positive, newdata = test, type = "response")
    pred <- pred_scored * pred_positive
    goal_metric(
      "Two-stage zero-aware goals",
      "Two-stage count model",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Separates the chance of scoring at all from expected goals after a team scores."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Regression tree goals", {
    fit <- rpart::rpart(goal_full_formula, data = train, method = "anova", control = rpart::rpart.control(cp = 0.001, minbucket = 80))
    pred <- stats::predict(fit, newdata = test)
    goal_metric(
      "Regression tree goals",
      "Single tree",
      split_name,
      "fit",
      train,
      test,
      pred,
      "Interpretable nonlinear tree benchmark."
    )
  })

  goal_metrics[[length(goal_metrics) + 1]] <- safe_model("Random forest goals", {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("The randomForest package is not installed.")
    }
    rf_train <- sample_rows(train, 25000, seed_offset = 20)
    set.seed(20260629)
    fit <- randomForest::randomForest(
      goal_full_formula,
      data = rf_train[, c("y_goals_for", goal_model_cols)],
      ntree = 120,
      mtry = min(4, length(goal_model_cols)),
      importance = FALSE,
      na.action = stats::na.omit
    )
    pred <- stats::predict(fit, newdata = test)
    goal_metric(
      "Random forest goals",
      "Tree ensemble",
      split_name,
      "fit",
      rf_train,
      test,
      pred,
      "Averaged decision trees that capture nonlinear interactions while reducing single-tree variance."
    )
  })
}

result_full_formula <- stats::as.formula(paste("y_result_ordered ~", paste(result_model_cols, collapse = " + ")))
result_elo_formula <- y_result_ordered ~ elo_diff + pre_match_expected_result + listed_home + neutral

for (split_name in names(result_splits)) {
  split <- result_splits[[split_name]]
  train <- split$train
  test <- split$test

  majority <- prop.table(table(train$y_result_ordered))
  majority_prob <- data.frame(
    loss = rep(unname(majority[["loss"]]), nrow(test)),
    draw = rep(unname(majority[["draw"]]), nrow(test)),
    win = rep(unname(majority[["win"]]), nrow(test))
  )
  result_metrics[[length(result_metrics) + 1]] <- result_metric(
    "Class-share baseline",
    "Naive probability baseline",
    split_name,
    "fit",
    train,
    test,
    majority_prob,
    "Always predicts the historical train-set class mix."
  )

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Elo ordinal result", {
    fit <- MASS::polr(result_elo_formula, data = train, method = "logistic", Hess = FALSE)
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "probs"))
    result_metric(
      "Elo ordinal result",
      "Ordinal logistic",
      split_name,
      "fit",
      train,
      test,
      prob,
      "Transparent ordered model using strength and site context."
    )
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Full ordinal result", {
    fit <- MASS::polr(result_full_formula, data = train, method = "logistic", Hess = FALSE)
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "probs"))
    result_metric(
      "Full ordinal result",
      "Ordinal logistic",
      split_name,
      "fit",
      train,
      test,
      prob,
      "Ordered win/draw/loss probability model with the expanded feature set."
    )
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Multinomial result", {
    fit <- nnet::multinom(result_full_formula, data = train, trace = FALSE, MaxNWts = 10000)
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "probs"))
    result_metric(
      "Multinomial result",
      "Multinomial logistic",
      split_name,
      "fit",
      train,
      test,
      prob,
      "Does not force loss, draw, and win into a proportional-odds structure."
    )
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Regularized multinomial result", {
    fit <- nnet::multinom(result_full_formula, data = train, trace = FALSE, decay = 0.001, MaxNWts = 10000)
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "probs"))
    result_metric(
      "Regularized multinomial result",
      "Regularized classifier",
      split_name,
      "fit",
      train,
      test,
      prob,
      "Adds a small penalty to reduce overfitting while estimating win, draw, and loss probabilities."
    )
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Classification tree result", {
    fit <- rpart::rpart(result_full_formula, data = train, method = "class", control = rpart::rpart.control(cp = 0.001, minbucket = 100))
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "prob"))
    result_metric(
      "Classification tree result",
      "Single tree",
      split_name,
      "fit",
      train,
      test,
      prob,
      "Interpretable nonlinear tree benchmark for win/draw/loss."
    )
  })

  result_metrics[[length(result_metrics) + 1]] <- safe_model("Random forest result", {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("The randomForest package is not installed.")
    }
    rf_train <- sample_rows(train, 25000, seed_offset = 30)
    set.seed(20260629)
    fit <- randomForest::randomForest(
      result_full_formula,
      data = rf_train[, c("y_result_ordered", result_model_cols)],
      ntree = 140,
      mtry = min(3, length(result_model_cols)),
      importance = FALSE,
      na.action = stats::na.omit
    )
    prob <- normalize_probabilities(stats::predict(fit, newdata = test, type = "prob"))
    result_metric(
      "Random forest result",
      "Tree ensemble classifier",
      split_name,
      "fit",
      rf_train,
      test,
      prob,
      "Averaged classification trees for nonlinear win, draw, and loss probability patterns."
    )
  })
}

goal_metric_table <- dplyr::bind_rows(goal_metrics)
result_metric_table <- dplyr::bind_rows(result_metrics)

status_table <- dplyr::bind_rows(
  data.frame(
    component = c("MASS", "nnet", "mgcv", "rpart", "randomForest", "xgboost"),
    status = c(
      ifelse(requireNamespace("MASS", quietly = TRUE), "available", "missing"),
      ifelse(requireNamespace("nnet", quietly = TRUE), "available", "missing"),
      ifelse(requireNamespace("mgcv", quietly = TRUE), "available", "missing"),
      ifelse(requireNamespace("rpart", quietly = TRUE), "available", "missing"),
      ifelse(requireNamespace("randomForest", quietly = TRUE), "available", "missing"),
      ifelse(requireNamespace("xgboost", quietly = TRUE), "available", "missing")
    ),
    note = c(
      "Fits negative-binomial and ordinal logistic models.",
      "Fits multinomial logistic result models.",
      "Fits smooth Poisson goal models.",
      "Fits single-tree goal and result benchmarks.",
      "Fits random-forest goal and result challengers.",
      "Not required for this suite; used by the separate tree challenger script when installed."
    ),
    stringsAsFactors = FALSE
  )
)

readr::write_csv(goal_metric_table, file.path(model_dir, "expanded_goal_model_metrics.csv"))
readr::write_csv(result_metric_table, file.path(model_dir, "expanded_result_model_metrics.csv"))
readr::write_csv(status_table, file.path(model_dir, "expanded_model_suite_status.csv"))

cat("\nExpanded model suite complete.\n")
cat("Goal metrics: ", file.path(model_dir, "expanded_goal_model_metrics.csv"), "\n", sep = "")
cat("Result metrics: ", file.path(model_dir, "expanded_result_model_metrics.csv"), "\n", sep = "")
print(goal_metric_table[order(goal_metric_table$validation_type, goal_metric_table$test_rmse), ])
print(result_metric_table[order(result_metric_table$validation_type, result_metric_table$test_multiclass_brier), ])
