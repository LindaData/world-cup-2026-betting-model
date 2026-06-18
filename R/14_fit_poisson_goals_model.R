# Poisson goals model.
#
# Goals are non-negative counts. Poisson regression is a natural next model
# after OLS because it predicts an expected count without allowing negative
# expected goals.

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

model_frame$neutral <- as.logical(model_frame$neutral)
model_frame$listed_home <- as.logical(model_frame$listed_home)
model_frame$is_world_cup <- as.logical(model_frame$is_world_cup)
model_frame$is_friendly <- as.logical(model_frame$is_friendly)

feature_names <- c(
  "pre_elo",
  "opponent_pre_elo",
  "pre_match_expected_result",
  "listed_home",
  "neutral"
)

complete_rows <- stats::complete.cases(model_frame[, c(feature_names, "y_goals_for", "match_year")])
model_frame <- model_frame[complete_rows, ]
model_frame <- model_frame[model_frame$y_goals_for >= 0, ]

formula_poisson <- y_goals_for ~
  pre_elo +
  opponent_pre_elo +
  pre_match_expected_result +
  listed_home +
  neutral

poisson_deviance <- function(actual, predicted) {
  predicted <- pmax(predicted, 1e-12)
  term <- ifelse(actual == 0, 0, actual * log(actual / predicted))
  2 * (term - (actual - predicted))
}

fit_and_score <- function(train, test, validation_type) {
  fit <- stats::glm(formula_poisson, data = train, family = stats::poisson(link = "log"))
  pred <- as.numeric(stats::predict(fit, newdata = test, type = "response"))
  residual <- test$y_goals_for - pred

  metrics <- data.frame(
    validation_type = validation_type,
    rows_total = nrow(model_frame),
    rows_train = nrow(train),
    rows_test = nrow(test),
    predictors_after_encoding = length(stats::coef(fit)) - 1,
    test_rmse = sqrt(mean(residual^2, na.rm = TRUE)),
    test_mae = mean(abs(residual), na.rm = TRUE),
    mean_y_test = mean(test$y_goals_for, na.rm = TRUE),
    mean_poisson_deviance = mean(poisson_deviance(test$y_goals_for, pred), na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  predictions <- test[
    ,
    c(
      "source_match_id",
      "date",
      "team",
      "opponent",
      "tournament",
      "y_goals_for"
    )
  ]
  predictions$validation_type <- validation_type
  predictions$pred_goals_for_poisson <- pred
  predictions$residual <- residual

  list(fit = fit, metrics = metrics, predictions = predictions)
}

set.seed(20260618)
random_split <- ifelse(stats::runif(nrow(model_frame)) < 0.80, "train", "test")
random_train <- model_frame[random_split == "train", ]
random_test <- model_frame[random_split == "test", ]

time_train <- model_frame[model_frame$match_year <= 2018, ]
time_test <- model_frame[model_frame$match_year >= 2019, ]

random_result <- fit_and_score(random_train, random_test, "random_80_20")
time_result <- fit_and_score(time_train, time_test, "train_through_2018_test_2019_plus")

metrics <- rbind(random_result$metrics, time_result$metrics)

coef_table <- as.data.frame(summary(random_result$fit)$coefficients)
coef_table$term <- rownames(coef_table)
rownames(coef_table) <- NULL
coef_table <- coef_table[, c("term", "Estimate", "Std. Error", "z value", "Pr(>|z|)")]
names(coef_table) <- c("term", "estimate", "std_error", "z_value", "p_value")
coef_table$rate_ratio <- exp(coef_table$estimate)

test_predictions <- rbind(random_result$predictions, time_result$predictions)

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

readr::write_csv(model_frame, file.path(model_dir, "goals_poisson_model_frame.csv"))
readr::write_csv(sample_rows, file.path(model_dir, "goals_poisson_model_sample_1000.csv"))
readr::write_csv(metrics, file.path(model_dir, "goals_poisson_model_metrics.csv"))
readr::write_csv(coef_table, file.path(model_dir, "goals_poisson_model_coefficients.csv"))
readr::write_csv(test_predictions, file.path(model_dir, "goals_poisson_model_test_predictions.csv"))

saveRDS(random_result$fit, file.path(model_dir, "goals_poisson_model_fit_random.rds"))
saveRDS(time_result$fit, file.path(model_dir, "goals_poisson_model_fit_time_forward.rds"))

cat("\nPoisson goals model complete.\n")
cat("Model frame: ", file.path(model_dir, "goals_poisson_model_frame.csv"), "\n", sep = "")
cat("Metrics: ", file.path(model_dir, "goals_poisson_model_metrics.csv"), "\n", sep = "")
cat("Coefficients: ", file.path(model_dir, "goals_poisson_model_coefficients.csv"), "\n", sep = "")
print(metrics)
