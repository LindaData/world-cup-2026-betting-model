# Regression diagnostics for local model outputs.
#
# This script keeps diagnostics on the laptop under data/processed/modeling.
# The website reads summarized CSVs and embeds rounded results in HTML.

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
    pre_match_expected_result
  FROM vw_goals_linear_model_frame
")

table_inventory <- DBI::dbGetQuery(con, "
  SELECT table_name, row_count
  FROM read_csv_auto('data/processed/metadata/table_inventory.csv')
")

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

goals_frame$neutral <- as.logical(goals_frame$neutral)
goals_frame$listed_home <- as.logical(goals_frame$listed_home)

formula_goals <- y_goals_for ~
  pre_elo +
  opponent_pre_elo +
  pre_match_expected_result +
  listed_home +
  neutral

feature_names <- c(
  "pre_elo",
  "opponent_pre_elo",
  "pre_match_expected_result",
  "listed_home",
  "neutral"
)

complete_rows <- stats::complete.cases(goals_frame[, c(feature_names, "y_goals_for", "date")])
goals_model_frame <- goals_frame[complete_rows, ]

design_matrix <- stats::model.matrix(formula_goals, data = goals_model_frame)
if ("(Intercept)" %in% colnames(design_matrix)) {
  design_matrix <- design_matrix[, colnames(design_matrix) != "(Intercept)", drop = FALSE]
}

vif_for_matrix <- function(x) {
  out <- data.frame(
    term = colnames(x),
    vif = NA_real_,
    stringsAsFactors = FALSE
  )

  if (ncol(x) <= 1) {
    return(out)
  }

  for (i in seq_len(ncol(x))) {
    y <- x[, i]
    others <- x[, -i, drop = FALSE]
    if (stats::var(y, na.rm = TRUE) == 0) {
      out$vif[[i]] <- NA_real_
      next
    }
    fit <- stats::lm(y ~ others)
    r_squared <- summary(fit)$r.squared
    out$vif[[i]] <- if (is.na(r_squared) || r_squared >= 1) Inf else 1 / (1 - r_squared)
  }

  out
}

vif_table <- vif_for_matrix(design_matrix)

numeric_features <- data.frame(
  pre_elo = goals_model_frame$pre_elo,
  opponent_pre_elo = goals_model_frame$opponent_pre_elo,
  pre_match_expected_result = goals_model_frame$pre_match_expected_result,
  listed_home = as.integer(goals_model_frame$listed_home),
  neutral = as.integer(goals_model_frame$neutral)
)

cor_matrix <- stats::cor(numeric_features, use = "pairwise.complete.obs")
cor_pairs <- as.data.frame(as.table(cor_matrix), stringsAsFactors = FALSE)
names(cor_pairs) <- c("feature_1", "feature_2", "correlation")
cor_pairs <- cor_pairs[as.character(cor_pairs$feature_1) < as.character(cor_pairs$feature_2), ]
cor_pairs$abs_correlation <- abs(cor_pairs$correlation)
cor_pairs <- cor_pairs[order(-cor_pairs$abs_correlation), ]

scaled_design <- scale(design_matrix)
scaled_design <- scaled_design[, apply(scaled_design, 2, function(x) all(is.finite(x))), drop = FALSE]
condition_number <- if (ncol(scaled_design) > 1) {
  kappa(scaled_design, exact = TRUE)
} else {
  NA_real_
}

ols_fit <- stats::lm(formula_goals, data = goals_model_frame)
ols_residuals <- stats::residuals(ols_fit)
ols_order <- order(goals_model_frame$date, goals_model_frame$source_match_id, goals_model_frame$team)
ols_residuals_ordered <- ols_residuals[ols_order]

durbin_watson <- function(residuals) {
  residuals <- residuals[is.finite(residuals)]
  if (length(residuals) < 2 || sum(residuals^2) == 0) {
    return(NA_real_)
  }
  sum(diff(residuals)^2) / sum(residuals^2)
}

lag1_cor <- function(residuals) {
  residuals <- residuals[is.finite(residuals)]
  if (length(residuals) < 3) {
    return(NA_real_)
  }
  stats::cor(residuals[-length(residuals)], residuals[-1], use = "complete.obs")
}

safe_chisq_upper <- function(statistic, df) {
  if (!is.finite(statistic) || !is.finite(df) || df <= 0) {
    return(NA_real_)
  }
  stats::pchisq(statistic, df = df, lower.tail = FALSE)
}

resid_sq_fit <- stats::lm(I(ols_residuals^2) ~ design_matrix)
bp_statistic <- length(ols_residuals) * summary(resid_sq_fit)$r.squared
bp_df <- ncol(design_matrix)
bp_p_value <- safe_chisq_upper(bp_statistic, bp_df)

centered_residuals <- ols_residuals - mean(ols_residuals, na.rm = TRUE)
residual_sd <- stats::sd(centered_residuals, na.rm = TRUE)
skewness <- if (is.finite(residual_sd) && residual_sd > 0) {
  mean((centered_residuals / residual_sd)^3, na.rm = TRUE)
} else {
  NA_real_
}
kurtosis_excess <- if (is.finite(residual_sd) && residual_sd > 0) {
  mean((centered_residuals / residual_sd)^4, na.rm = TRUE) - 3
} else {
  NA_real_
}
jarque_bera <- length(ols_residuals) / 6 * (skewness^2 + (kurtosis_excess^2 / 4))
jarque_bera_p_value <- safe_chisq_upper(jarque_bera, 2)

poisson_fit <- stats::glm(formula_goals, data = goals_model_frame, family = stats::poisson(link = "log"))
poisson_pearson <- stats::residuals(poisson_fit, type = "pearson")
poisson_pearson_ordered <- poisson_pearson[ols_order]
poisson_overdispersion_ratio <- sum(poisson_pearson^2, na.rm = TRUE) / stats::df.residual(poisson_fit)
poisson_deviance_ratio <- stats::deviance(poisson_fit) / stats::df.residual(poisson_fit)

target_mean <- mean(goals_model_frame$y_goals_for, na.rm = TRUE)
target_variance <- stats::var(goals_model_frame$y_goals_for, na.rm = TRUE)
target_variance_to_mean <- target_variance / target_mean

ols_diagnostics <- data.frame(
  diagnostic = c(
    "rows_used",
    "target_mean_goals",
    "target_variance_goals",
    "target_variance_to_mean",
    "max_vif",
    "condition_number",
    "durbin_watson",
    "lag1_residual_correlation",
    "breusch_pagan_statistic",
    "breusch_pagan_df",
    "breusch_pagan_p_value",
    "jarque_bera_statistic",
    "jarque_bera_p_value",
    "residual_standard_error"
  ),
  value = c(
    nrow(goals_model_frame),
    target_mean,
    target_variance,
    target_variance_to_mean,
    max(vif_table$vif, na.rm = TRUE),
    condition_number,
    durbin_watson(ols_residuals_ordered),
    lag1_cor(ols_residuals_ordered),
    bp_statistic,
    bp_df,
    bp_p_value,
    jarque_bera,
    jarque_bera_p_value,
    summary(ols_fit)$sigma
  ),
  stringsAsFactors = FALSE
)

poisson_diagnostics <- data.frame(
  diagnostic = c(
    "rows_used",
    "overdispersion_ratio",
    "deviance_ratio",
    "durbin_watson_pearson_residuals",
    "lag1_pearson_residual_correlation"
  ),
  value = c(
    nrow(goals_model_frame),
    poisson_overdispersion_ratio,
    poisson_deviance_ratio,
    durbin_watson(poisson_pearson_ordered),
    lag1_cor(poisson_pearson_ordered)
  ),
  stringsAsFactors = FALSE
)

status_from_threshold <- function(value, ok, caution, direction = "high_bad") {
  if (!is.finite(value)) {
    return("review")
  }
  if (direction == "high_bad") {
    if (value <= ok) return("ok")
    if (value <= caution) return("caution")
    return("high")
  }
  if (abs(value) <= ok) return("ok")
  if (abs(value) <= caution) return("caution")
  "high"
}

dw_value <- ols_diagnostics$value[ols_diagnostics$diagnostic == "durbin_watson"]
dw_status <- if (is.finite(dw_value) && dw_value >= 1.5 && dw_value <= 2.5) "ok" else "caution"

bp_status <- if (is.finite(bp_p_value) && bp_p_value >= 0.05) "ok" else "caution"
jb_status <- if (is.finite(jarque_bera_p_value) && jarque_bera_p_value >= 0.05) "ok" else "caution"

summary_table <- data.frame(
  check = c(
    "Collinearity",
    "Condition number",
    "OLS autocorrelation",
    "Heteroskedasticity",
    "Residual normality",
    "Poisson overdispersion",
    "Goal count variance",
    "Paired team-match rows"
  ),
  statistic = c(
    "Max VIF",
    "Condition number",
    "Durbin-Watson",
    "Breusch-Pagan p-value",
    "Jarque-Bera p-value",
    "Pearson dispersion ratio",
    "Variance / mean",
    "One match creates two rows"
  ),
  value = c(
    max(vif_table$vif, na.rm = TRUE),
    condition_number,
    dw_value,
    bp_p_value,
    jarque_bera_p_value,
    poisson_overdispersion_ratio,
    target_variance_to_mean,
    2
  ),
  status = c(
    status_from_threshold(max(vif_table$vif, na.rm = TRUE), ok = 5, caution = 10),
    status_from_threshold(condition_number, ok = 30, caution = 100),
    dw_status,
    bp_status,
    jb_status,
    status_from_threshold(poisson_overdispersion_ratio, ok = 1.5, caution = 2),
    status_from_threshold(target_variance_to_mean, ok = 1.5, caution = 2),
    "modeling note"
  ),
  public_interpretation = c(
    "Predictors are checked for overlap before interpreting coefficients.",
    "Large values suggest the design matrix is close to redundant.",
    "Values near 2 suggest less sequential residual pattern in the ordered rows.",
    "Small p-values suggest residual spread changes across predictor values.",
    "Small p-values mean OLS residuals are not bell-shaped; with this sample size that is expected.",
    "Values above 1 mean soccer goals vary more than a strict Poisson model assumes.",
    "A count target often has variance above its mean; this is why count models matter.",
    "Each match contributes two team perspectives, so future inference should consider match-level grouping."
  ),
  stringsAsFactors = FALSE
)

source_groups <- data.frame(
  source_group = c(
    "Historical team-match model rows",
    "2026 fixture shell",
    "Open-Meteo weather summaries",
    "GDELT news metadata",
    "Wikidata player enrichment",
    "API-Football league metadata",
    "API-Football detailed match/player tables"
  ),
  local_table = c(
    "vw_goals_linear_model_frame",
    "vw_2026_fixture_model_frame",
    "vw_fixture_weather_signals",
    "fact_news_articles_gdelt",
    "dim_player_wikidata",
    "api_football_world_cup_leagues",
    "api_football_world_cup_fixtures / teams / standings / players / injuries / odds"
  ),
  stringsAsFactors = FALSE
)

row_count_for <- function(pattern) {
  hits <- table_inventory[grepl(pattern, table_inventory$table_name), , drop = FALSE]
  if (nrow(hits) == 0) {
    return(0)
  }
  sum(hits$row_count, na.rm = TRUE)
}

source_groups$rows_available <- c(
  row_count_for("^vw_goals_linear_model_frame$"),
  row_count_for("^vw_2026_fixture_model_frame$"),
  row_count_for("^vw_fixture_weather_signals$"),
  row_count_for("^fact_news_articles_gdelt$"),
  row_count_for("^dim_player_wikidata$"),
  row_count_for("^api_football_world_cup_leagues$"),
  row_count_for("^api_football_world_cup_(fixtures|teams|standings|players|injuries|odds)$")
)

source_groups$current_model_role <- c(
  "Regression training data",
  "Fixture scoring frame",
  "Prediction context shown with scored fixtures",
  "Context layer for later feature engineering",
  "Player context for later feature engineering",
  "Coverage metadata",
  "Structured enrichment layer; no detailed rows in the current local snapshot"
)

readr::write_csv(summary_table, file.path(model_dir, "regression_diagnostics_summary.csv"))
readr::write_csv(vif_table, file.path(model_dir, "goals_model_vif.csv"))
readr::write_csv(cor_pairs, file.path(model_dir, "goals_model_predictor_correlations.csv"))
readr::write_csv(ols_diagnostics, file.path(model_dir, "goals_model_residual_diagnostics.csv"))
readr::write_csv(poisson_diagnostics, file.path(model_dir, "poisson_model_diagnostics.csv"))
readr::write_csv(source_groups, file.path(model_dir, "api_capture_model_usage.csv"))

cat("\nRegression diagnostics complete.\n")
cat("Summary: ", file.path(model_dir, "regression_diagnostics_summary.csv"), "\n", sep = "")
print(summary_table)
