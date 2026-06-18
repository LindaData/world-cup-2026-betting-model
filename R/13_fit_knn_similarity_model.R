# KNN similarity model for goals and win/draw/loss.
#
# This model uses nearby historical team-match rows as analogs. It is included
# as a comparison model because it is intuitive: find similar past matchups and
# average what happened in those games.

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
    tournament,
    team,
    opponent,
    listed_home,
    neutral,
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

model_frame$listed_home <- as.logical(model_frame$listed_home)
model_frame$neutral <- as.logical(model_frame$neutral)
model_frame$is_world_cup <- as.logical(model_frame$is_world_cup)
model_frame$is_friendly <- as.logical(model_frame$is_friendly)
model_frame$y_result_ordered <- factor(
  model_frame$y_result_ordered,
  levels = c("loss", "draw", "win")
)

feature_names <- c(
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

model_frame$listed_home <- as.integer(model_frame$listed_home)
model_frame$neutral <- as.integer(model_frame$neutral)
model_frame$is_world_cup <- as.integer(model_frame$is_world_cup)
model_frame$is_friendly <- as.integer(model_frame$is_friendly)

complete_rows <- stats::complete.cases(model_frame[, c(feature_names, "goals_for", "y_result_ordered")])
model_frame <- model_frame[complete_rows, ]

set.seed(20260617)
model_frame$split <- ifelse(stats::runif(nrow(model_frame)) < 0.80, "train", "test")

train <- model_frame[model_frame$split == "train", ]
test <- model_frame[model_frame$split == "test", ]

train_cap <- min(nrow(train), 12000)
test_cap <- min(nrow(test), 4000)
train_eval <- train[sample(seq_len(nrow(train)), train_cap), ]
test_eval <- test[sample(seq_len(nrow(test)), test_cap), ]

train_x_raw <- as.matrix(train_eval[, feature_names])
test_x_raw <- as.matrix(test_eval[, feature_names])

center <- colMeans(train_x_raw, na.rm = TRUE)
scale_values <- apply(train_x_raw, 2, stats::sd, na.rm = TRUE)
scale_values[is.na(scale_values) | scale_values == 0] <- 1

scale_with_train <- function(x) {
  sweep(sweep(x, 2, center, "-"), 2, scale_values, "/")
}

train_x <- scale_with_train(train_x_raw)
test_x <- scale_with_train(test_x_raw)

k <- 25
result_levels <- c("loss", "draw", "win")

predictions <- vector("list", nrow(test_x))

for (i in seq_len(nrow(test_x))) {
  distances <- rowSums((sweep(train_x, 2, test_x[i, ], "-"))^2)
  neighbor_ids <- order(distances)[seq_len(min(k, length(distances)))]
  neighbor_results <- as.character(train_eval$y_result_ordered[neighbor_ids])
  neighbor_goals <- train_eval$goals_for[neighbor_ids]
  result_counts <- table(factor(neighbor_results, levels = result_levels))
  result_probabilities <- as.numeric(result_counts) / sum(result_counts)
  names(result_probabilities) <- result_levels

  predictions[[i]] <- data.frame(
    source_match_id = test_eval$source_match_id[[i]],
    date = test_eval$date[[i]],
    team = test_eval$team[[i]],
    opponent = test_eval$opponent[[i]],
    tournament = test_eval$tournament[[i]],
    goals_for = test_eval$goals_for[[i]],
    goals_against = test_eval$goals_against[[i]],
    actual_result = as.character(test_eval$y_result_ordered[[i]]),
    pred_goals_for_knn = mean(neighbor_goals, na.rm = TRUE),
    predicted_result = names(result_probabilities)[which.max(result_probabilities)],
    pred_prob_loss = result_probabilities[["loss"]],
    pred_prob_draw = result_probabilities[["draw"]],
    pred_prob_win = result_probabilities[["win"]],
    neighbors_used = length(neighbor_ids),
    stringsAsFactors = FALSE
  )
}

test_predictions <- do.call(rbind, predictions)

prob_matrix <- as.matrix(test_predictions[, c("pred_prob_loss", "pred_prob_draw", "pred_prob_win")])
actual_index <- match(test_predictions$actual_result, result_levels)
actual_prob <- prob_matrix[cbind(seq_len(nrow(prob_matrix)), actual_index)]
actual_prob <- pmax(actual_prob, 1e-15)

one_hot <- matrix(0, nrow = nrow(prob_matrix), ncol = ncol(prob_matrix))
one_hot[cbind(seq_len(nrow(one_hot)), actual_index)] <- 1

goals_residual <- test_predictions$goals_for - test_predictions$pred_goals_for_knn

metrics <- data.frame(
  rows_total = nrow(model_frame),
  rows_train_pool = nrow(train),
  rows_test_pool = nrow(test),
  rows_train_evaluated = nrow(train_eval),
  rows_test_evaluated = nrow(test_eval),
  k_neighbors = k,
  goals_rmse = sqrt(mean(goals_residual^2, na.rm = TRUE)),
  goals_mae = mean(abs(goals_residual), na.rm = TRUE),
  result_accuracy = mean(test_predictions$predicted_result == test_predictions$actual_result),
  result_log_loss = -mean(log(actual_prob)),
  result_multiclass_brier = mean(rowSums((prob_matrix - one_hot)^2)),
  reference_accuracy = max(prop.table(table(train_eval$y_result_ordered))),
  stringsAsFactors = FALSE
)

feature_table <- data.frame(
  feature = feature_names,
  role = c(
    "Team strength",
    "Opponent strength",
    "Strength gap",
    "Pre-match expected result",
    "Match importance",
    "Home listing flag",
    "Neutral-site flag",
    "World Cup flag",
    "Friendly match flag"
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(model_frame, file.path(model_dir, "knn_similarity_model_frame.csv"))
readr::write_csv(metrics, file.path(model_dir, "knn_similarity_model_metrics.csv"))
readr::write_csv(feature_table, file.path(model_dir, "knn_similarity_model_features.csv"))
readr::write_csv(
  head(test_predictions[order(test_predictions$date, test_predictions$source_match_id), ], 1000),
  file.path(model_dir, "knn_similarity_model_sample_predictions.csv")
)

cat("\nKNN similarity model complete.\n")
cat("Model frame: ", file.path(model_dir, "knn_similarity_model_frame.csv"), "\n", sep = "")
cat("Metrics: ", file.path(model_dir, "knn_similarity_model_metrics.csv"), "\n", sep = "")
cat("Features: ", file.path(model_dir, "knn_similarity_model_features.csv"), "\n", sep = "")
print(metrics)
