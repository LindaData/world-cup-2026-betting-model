# First large linear regression for team goals.
#
# Target:
#   y_goals_for = goals scored by this team in a historical match.
#
# Important:
#   This is a starter OLS model, not the final soccer model. Goals are counts, so
#   Poisson/negative-binomial models will probably be better later. We start here
#   because linear regression is transparent and easy to inspect.

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
    city,
    country,
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

model_frame$team <- factor(model_frame$team)
model_frame$opponent <- factor(model_frame$opponent)
model_frame$tournament <- factor(model_frame$tournament)
model_frame$neutral <- as.logical(model_frame$neutral)
model_frame$listed_home <- as.logical(model_frame$listed_home)
model_frame$is_world_cup <- as.logical(model_frame$is_world_cup)
model_frame$is_friendly <- as.logical(model_frame$is_friendly)

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

formula_large_lm <- y_goals_for ~
  pre_elo +
  opponent_pre_elo +
  pre_match_expected_result +
  listed_home +
  neutral

fit <- stats::lm(formula_large_lm, data = train)

pred <- stats::predict(fit, newdata = test)
test$pred_goals_for_lm <- as.numeric(pred)
test$residual <- test$y_goals_for - test$pred_goals_for_lm

metrics <- data.frame(
  rows_total = nrow(model_frame),
  rows_train = nrow(train),
  rows_test = nrow(test),
  predictors_after_encoding = length(stats::coef(fit)) - 1,
  train_r_squared = summary(fit)$r.squared,
  train_adj_r_squared = summary(fit)$adj.r.squared,
  test_rmse = sqrt(mean(test$residual^2, na.rm = TRUE)),
  test_mae = mean(abs(test$residual), na.rm = TRUE),
  mean_y_test = mean(test$y_goals_for, na.rm = TRUE),
  stringsAsFactors = FALSE
)

coef_table <- as.data.frame(summary(fit)$coefficients)
coef_table$term <- rownames(coef_table)
rownames(coef_table) <- NULL
coef_table <- coef_table[, c("term", "Estimate", "Std. Error", "t value", "Pr(>|t|)")]
names(coef_table) <- c("term", "estimate", "std_error", "t_value", "p_value")

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
    "y_goals_for",
    "pre_elo",
    "opponent_pre_elo",
    "elo_diff",
    "pre_match_expected_result"
  )
]
sample_rows <- head(sample_rows, 1000)

readr::write_csv(model_frame, file.path(model_dir, "goals_linear_model_frame.csv"))
readr::write_csv(sample_rows, file.path(model_dir, "goals_linear_model_sample_1000.csv"))
readr::write_csv(metrics, file.path(model_dir, "goals_linear_model_metrics.csv"))
readr::write_csv(coef_table, file.path(model_dir, "goals_linear_model_coefficients.csv"))
readr::write_csv(
  test[
    ,
    c(
      "source_match_id",
      "date",
      "team",
      "opponent",
      "tournament",
      "y_goals_for",
      "pred_goals_for_lm",
      "residual"
    )
  ],
  file.path(model_dir, "goals_linear_model_test_predictions.csv")
)

saveRDS(fit, file.path(model_dir, "goals_linear_model_fit.rds"))

cat("\nLinear goals model complete.\n")
cat("Model frame: ", file.path(model_dir, "goals_linear_model_frame.csv"), "\n", sep = "")
cat("Sample rows: ", file.path(model_dir, "goals_linear_model_sample_1000.csv"), "\n", sep = "")
cat("Metrics: ", file.path(model_dir, "goals_linear_model_metrics.csv"), "\n", sep = "")
cat("Coefficients: ", file.path(model_dir, "goals_linear_model_coefficients.csv"), "\n", sep = "")
cat("Saved fit: ", file.path(model_dir, "goals_linear_model_fit.rds"), "\n", sep = "")

print(metrics)
cat("\nTop interpretable non-fixed-effect coefficients:\n")
print(coef_table[coef_table$term %in% c(
  "(Intercept)",
  "pre_elo",
  "opponent_pre_elo",
  "elo_diff",
  "pre_match_expected_result",
  "listed_homeTRUE",
  "neutralTRUE",
  "is_world_cupTRUE",
  "is_friendlyTRUE"
), ])
