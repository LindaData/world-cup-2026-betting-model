# Ordinal logistic regression for team match result.
#
# Target:
#   y_result_ordered = loss < draw < win for one team in one historical match.
#
# This is a proportional-odds model. It is useful as a transparent baseline,
# but we will still compare it later against multinomial, paired-goal, and
# calibrated market-aware probability models.

source("R/00_setup.R")

if (!requireNamespace("MASS", quietly = TRUE)) {
  install.packages("MASS", repos = "https://cloud.r-project.org")
}

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
    city,
    country,
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

model_frame$team <- factor(model_frame$team)
model_frame$opponent <- factor(model_frame$opponent)
model_frame$tournament <- factor(model_frame$tournament)
model_frame$neutral <- as.logical(model_frame$neutral)
model_frame$listed_home <- as.logical(model_frame$listed_home)
model_frame$is_world_cup <- as.logical(model_frame$is_world_cup)
model_frame$is_friendly <- as.logical(model_frame$is_friendly)
model_frame$y_result_ordered <- ordered(
  model_frame$y_result_ordered,
  levels = c("loss", "draw", "win")
)

set.seed(20260616)
model_frame$split <- ifelse(stats::runif(nrow(model_frame)) < 0.80, "train", "test")

train <- model_frame[model_frame$split == "train", ]
test <- model_frame[model_frame$split == "test", ]

known_test_levels <-
  as.character(test$team) %in% as.character(unique(train$team)) &
  as.character(test$opponent) %in% as.character(unique(train$opponent)) &
  as.character(test$tournament) %in% as.character(unique(train$tournament)) &
  as.character(test$match_year) %in% as.character(unique(train$match_year))

if (any(!known_test_levels)) {
  train <- rbind(train, test[!known_test_levels, ])
  test <- test[known_test_levels, ]
}

train <- droplevels(train)
test$team <- factor(test$team, levels = levels(train$team))
test$opponent <- factor(test$opponent, levels = levels(train$opponent))
test$tournament <- factor(test$tournament, levels = levels(train$tournament))
test$y_result_ordered <- ordered(
  as.character(test$y_result_ordered),
  levels = levels(train$y_result_ordered)
)

formula_ordinal <- y_result_ordered ~
  pre_elo +
  opponent_pre_elo +
  pre_match_expected_result +
  listed_home +
  neutral

fit <- MASS::polr(formula_ordinal, data = train, method = "logistic", Hess = TRUE)

probabilities <- as.data.frame(stats::predict(fit, newdata = test, type = "probs"))
names(probabilities) <- paste0("pred_prob_", names(probabilities))

pred_class <- sub("^pred_prob_", "", names(probabilities)[max.col(probabilities, ties.method = "first")])

test_predictions <- cbind(
  test[
    ,
    c(
      "source_match_id",
      "date",
      "team",
      "opponent",
      "tournament",
      "goals_for",
      "goals_against",
      "y_result_ordered",
      "pre_elo",
      "opponent_pre_elo",
      "elo_diff",
      "pre_match_expected_result"
    )
  ],
  predicted_result = pred_class,
  probabilities
)

actual_index <- match(as.character(test$y_result_ordered), c("loss", "draw", "win"))
prob_matrix <- as.matrix(probabilities[, paste0("pred_prob_", c("loss", "draw", "win"))])
actual_prob <- prob_matrix[cbind(seq_len(nrow(prob_matrix)), actual_index)]
actual_prob <- pmax(actual_prob, 1e-15)

one_hot <- matrix(0, nrow = nrow(prob_matrix), ncol = ncol(prob_matrix))
one_hot[cbind(seq_len(nrow(one_hot)), actual_index)] <- 1

class_counts <- as.data.frame(table(model_frame$y_result_ordered), stringsAsFactors = FALSE)
names(class_counts) <- c("result", "rows")
class_counts$share <- class_counts$rows / sum(class_counts$rows)

confusion <- as.data.frame(
  table(
    actual_result = as.character(test$y_result_ordered),
    predicted_result = pred_class
  ),
  stringsAsFactors = FALSE
)
names(confusion) <- c("actual_result", "predicted_result", "rows")

metrics <- data.frame(
  rows_total = nrow(model_frame),
  rows_train = nrow(train),
  rows_test = nrow(test),
  predictors_after_encoding = length(stats::coef(fit)),
  test_accuracy = mean(pred_class == as.character(test$y_result_ordered)),
  test_log_loss = -mean(log(actual_prob)),
  test_multiclass_brier = mean(rowSums((prob_matrix - one_hot)^2)),
  baseline_majority_accuracy = max(prop.table(table(train$y_result_ordered))),
  stringsAsFactors = FALSE
)

coef_table <- as.data.frame(coef(summary(fit)))
coef_table$term <- rownames(coef_table)
rownames(coef_table) <- NULL
names(coef_table) <- c("estimate", "std_error", "t_value", "term")
coef_table$component <- ifelse(grepl("\\|", coef_table$term), "threshold", "slope")
coef_table$p_value_approx <- 2 * stats::pnorm(abs(coef_table$t_value), lower.tail = FALSE)
coef_table <- coef_table[, c("component", "term", "estimate", "std_error", "t_value", "p_value_approx")]

sample_rows <- model_frame[
  order(model_frame$date, model_frame$source_match_id),
  c(
    "source_match_id",
    "date",
    "team",
    "opponent",
    "tournament",
    "listed_home",
    "neutral",
    "goals_for",
    "goals_against",
    "y_result_ordered",
    "pre_elo",
    "opponent_pre_elo",
    "elo_diff",
    "pre_match_expected_result"
  )
]
sample_rows <- head(sample_rows, 1000)

readr::write_csv(model_frame, file.path(model_dir, "result_ordinal_model_frame.csv"))
readr::write_csv(sample_rows, file.path(model_dir, "result_ordinal_model_sample_1000.csv"))
readr::write_csv(metrics, file.path(model_dir, "result_ordinal_model_metrics.csv"))
readr::write_csv(coef_table, file.path(model_dir, "result_ordinal_model_coefficients.csv"))
readr::write_csv(test_predictions, file.path(model_dir, "result_ordinal_model_test_predictions.csv"))
readr::write_csv(class_counts, file.path(model_dir, "result_ordinal_model_class_distribution.csv"))
readr::write_csv(confusion, file.path(model_dir, "result_ordinal_model_confusion_matrix.csv"))

saveRDS(fit, file.path(model_dir, "result_ordinal_model_fit.rds"))

cat("\nOrdinal result model complete.\n")
cat("Model frame: ", file.path(model_dir, "result_ordinal_model_frame.csv"), "\n", sep = "")
cat("Sample rows: ", file.path(model_dir, "result_ordinal_model_sample_1000.csv"), "\n", sep = "")
cat("Metrics: ", file.path(model_dir, "result_ordinal_model_metrics.csv"), "\n", sep = "")
cat("Coefficients: ", file.path(model_dir, "result_ordinal_model_coefficients.csv"), "\n", sep = "")
cat("Saved fit: ", file.path(model_dir, "result_ordinal_model_fit.rds"), "\n", sep = "")

print(metrics)
cat("\nClass distribution:\n")
print(class_counts)
