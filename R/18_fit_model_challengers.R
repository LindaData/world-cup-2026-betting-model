# Stepwise and tree-based challenger models for team goals.
#
# These models are evaluated beside the current OLS/Poisson/KNN stack. They are
# not promoted into the public forecast until backtesting supports that move.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

model_frame <- DBI::dbGetQuery(con, "
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

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

model_frame$neutral <- as.logical(model_frame$neutral)
model_frame$listed_home <- as.logical(model_frame$listed_home)
model_frame$is_world_cup <- as.logical(model_frame$is_world_cup)
model_frame$is_friendly <- as.logical(model_frame$is_friendly)
model_frame$match_year <- as.numeric(model_frame$match_year)

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

complete_rows <- stats::complete.cases(model_frame[, c("y_goals_for", feature_cols)])
model_frame <- model_frame[complete_rows, ]

set.seed(20260629)
if (nrow(model_frame) > 40000) {
  model_frame <- model_frame[sample(seq_len(nrow(model_frame)), 40000), ]
}
model_frame$split <- ifelse(stats::runif(nrow(model_frame)) < 0.80, "train", "test")

train <- model_frame[model_frame$split == "train", ]
test <- model_frame[model_frame$split == "test", ]

rmse <- function(actual, predicted) {
  sqrt(mean((actual - predicted)^2, na.rm = TRUE))
}

mae <- function(actual, predicted) {
  mean(abs(actual - predicted), na.rm = TRUE)
}

metric_row <- function(model, family, status, rows_train, rows_test, actual, predicted, note = "") {
  data.frame(
    model = model,
    model_family = family,
    status = status,
    rows_train = rows_train,
    rows_test = rows_test,
    test_rmse = rmse(actual, predicted),
    test_mae = mae(actual, predicted),
    mean_prediction = mean(predicted, na.rm = TRUE),
    note = note,
    stringsAsFactors = FALSE
  )
}

metrics <- list()
importance <- list()
prediction_samples <- list()
status_rows <- list()

candidate_formula <- stats::as.formula(paste("y_goals_for ~", paste(feature_cols, collapse = " + ")))
null_formula <- y_goals_for ~ 1

full_lm <- stats::lm(candidate_formula, data = train)
null_lm <- stats::lm(null_formula, data = train)
stepwise_fit <- stats::step(
  null_lm,
  scope = list(lower = null_formula, upper = candidate_formula),
  direction = "both",
  trace = 0
)

stepwise_pred <- pmax(0, as.numeric(stats::predict(stepwise_fit, newdata = test)))
metrics[[length(metrics) + 1]] <- metric_row(
  "Stepwise OLS",
  "Interpretable regression",
  "fit",
  nrow(train),
  nrow(test),
  test$y_goals_for,
  stepwise_pred,
  "AIC-selected regression terms; kept as a transparent challenger."
)

step_coef <- as.data.frame(summary(stepwise_fit)$coefficients)
step_coef$feature <- rownames(step_coef)
rownames(step_coef) <- NULL
step_coef$model <- "Stepwise OLS"
step_coef$importance <- abs(step_coef$Estimate)
importance[[length(importance) + 1]] <- step_coef[, c("model", "feature", "importance")]

prediction_samples[[length(prediction_samples) + 1]] <- data.frame(
  model = "Stepwise OLS",
  source_match_id = test$source_match_id,
  date = test$date,
  team = test$team,
  opponent = test$opponent,
  actual_goals = test$y_goals_for,
  predicted_goals = stepwise_pred,
  residual = test$y_goals_for - stepwise_pred,
  stringsAsFactors = FALSE
)

saveRDS(stepwise_fit, file.path(model_dir, "goals_stepwise_model_fit.rds"))

tree_train_limit <- min(nrow(train), 12000)
tree_test_limit <- min(nrow(test), 4000)
set.seed(20260629)
tree_train <- train[sample(seq_len(nrow(train)), tree_train_limit), ]
tree_test <- test[sample(seq_len(nrow(test)), tree_test_limit), ]

if (requireNamespace("xgboost", quietly = TRUE)) {
  x_train <- stats::model.matrix(candidate_formula, data = tree_train)[, -1, drop = FALSE]
  x_test <- stats::model.matrix(candidate_formula, data = tree_test)[, -1, drop = FALSE]
  dtrain <- xgboost::xgb.DMatrix(data = x_train, label = tree_train$y_goals_for)
  dtest <- xgboost::xgb.DMatrix(data = x_test, label = tree_test$y_goals_for)

  xgb_fit <- xgboost::xgb.train(
    params = list(
      objective = "count:poisson",
      eval_metric = "rmse",
      max_depth = 4,
      eta = 0.06,
      subsample = 0.85,
      colsample_bytree = 0.85,
      min_child_weight = 8
    ),
    data = dtrain,
    nrounds = 180,
    evals = list(train = dtrain, test = dtest),
    verbose = 0
  )
  xgb_pred <- pmax(0, as.numeric(stats::predict(xgb_fit, dtest)))
  metrics[[length(metrics) + 1]] <- metric_row(
    "XGBoost goals",
    "Gradient-boosted trees",
    "fit",
    nrow(tree_train),
    nrow(tree_test),
    tree_test$y_goals_for,
    xgb_pred,
    "Uses the xgboost package when installed locally."
  )
  xgb_importance <- xgboost::xgb.importance(model = xgb_fit)
  if (nrow(xgb_importance) > 0) {
    importance[[length(importance) + 1]] <- data.frame(
      model = "XGBoost goals",
      feature = xgb_importance$Feature,
      importance = xgb_importance$Gain,
      stringsAsFactors = FALSE
    )
  }
  prediction_samples[[length(prediction_samples) + 1]] <- data.frame(
    model = "XGBoost goals",
    source_match_id = tree_test$source_match_id,
    date = tree_test$date,
    team = tree_test$team,
    opponent = tree_test$opponent,
    actual_goals = tree_test$y_goals_for,
    predicted_goals = xgb_pred,
    residual = tree_test$y_goals_for - xgb_pred,
    stringsAsFactors = FALSE
  )
  xgboost::xgb.save(xgb_fit, file.path(model_dir, "goals_xgboost_model_fit.ubj"))
  status_rows[[length(status_rows) + 1]] <- data.frame(
    component = "xgboost",
    status = "available",
    note = "XGBoost challenger was fit.",
    stringsAsFactors = FALSE
  )
} else {
  status_rows[[length(status_rows) + 1]] <- data.frame(
    component = "xgboost",
    status = "not_installed",
    note = "Install the R xgboost package to fit the gradient-boosted challenger.",
    stringsAsFactors = FALSE
  )
}

if (requireNamespace("randomForest", quietly = TRUE)) {
  set.seed(20260629)
  rf_fit <- randomForest::randomForest(
    candidate_formula,
    data = tree_train[, c("y_goals_for", feature_cols)],
    ntree = 90,
    mtry = 4,
    importance = TRUE,
    na.action = stats::na.omit
  )
  rf_pred <- pmax(0, as.numeric(stats::predict(rf_fit, newdata = tree_test)))
  metrics[[length(metrics) + 1]] <- metric_row(
    "Random forest goals",
    "Tree ensemble fallback",
    "fit",
    nrow(tree_train),
    nrow(tree_test),
    tree_test$y_goals_for,
    rf_pred,
    "Additional free local tree-ensemble benchmark."
  )
  rf_importance <- randomForest::importance(rf_fit)
  if (nrow(rf_importance) > 0) {
    importance[[length(importance) + 1]] <- data.frame(
      model = "Random forest goals",
      feature = rownames(rf_importance),
      importance = rf_importance[, ncol(rf_importance)],
      stringsAsFactors = FALSE
    )
  }
  prediction_samples[[length(prediction_samples) + 1]] <- data.frame(
    model = "Random forest goals",
    source_match_id = tree_test$source_match_id,
    date = tree_test$date,
    team = tree_test$team,
    opponent = tree_test$opponent,
    actual_goals = tree_test$y_goals_for,
    predicted_goals = rf_pred,
    residual = tree_test$y_goals_for - rf_pred,
    stringsAsFactors = FALSE
  )
  saveRDS(rf_fit, file.path(model_dir, "goals_random_forest_model_fit.rds"))
  status_rows[[length(status_rows) + 1]] <- data.frame(
    component = "randomForest",
    status = "available",
    note = "Random forest challenger was fit.",
    stringsAsFactors = FALSE
  )
} else {
  status_rows[[length(status_rows) + 1]] <- data.frame(
    component = "randomForest",
    status = "not_installed",
    note = "Install the R randomForest package to fit the local tree fallback.",
    stringsAsFactors = FALSE
  )
}

metric_table <- dplyr::bind_rows(metrics)
importance_table <- dplyr::bind_rows(importance) |>
  dplyr::group_by(model) |>
  dplyr::mutate(importance_scaled = importance / max(importance, na.rm = TRUE)) |>
  dplyr::ungroup() |>
  dplyr::arrange(model, dplyr::desc(importance_scaled))
prediction_table <- dplyr::bind_rows(prediction_samples) |>
  dplyr::group_by(model) |>
  dplyr::slice_head(n = 1000) |>
  dplyr::ungroup()
status_table <- dplyr::bind_rows(status_rows)

readr::write_csv(metric_table, file.path(model_dir, "model_challenger_metrics.csv"))
readr::write_csv(importance_table, file.path(model_dir, "model_challenger_feature_importance.csv"))
readr::write_csv(prediction_table, file.path(model_dir, "model_challenger_prediction_sample.csv"))
readr::write_csv(status_table, file.path(model_dir, "model_challenger_status.csv"))

cat("\nModel challenger run complete.\n")
cat("Metrics: ", file.path(model_dir, "model_challenger_metrics.csv"), "\n", sep = "")
cat("Feature importance: ", file.path(model_dir, "model_challenger_feature_importance.csv"), "\n", sep = "")
print(metric_table)
print(status_table)
