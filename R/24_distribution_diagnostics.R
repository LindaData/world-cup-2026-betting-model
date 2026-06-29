# Distribution diagnostics for the World Cup modeling workflow.
#
# This script maps common probability distributions to soccer modeling targets
# and writes compact diagnostics for the public methodology page.

source("R/00_setup.R")

model_dir <- file.path(here::here(), "data", "processed", "modeling")
population_path <- file.path(model_dir, "expanded_population_model_frame.csv")
goals_test_path <- file.path(model_dir, "goals_linear_model_test_predictions.csv")
result_test_path <- file.path(model_dir, "result_ordinal_model_test_predictions.csv")
fixture_path <- file.path(model_dir, "world_cup_2026_fixture_predictions.csv")

if (!file.exists(population_path)) {
  stop("Run R/22_build_expanded_feature_population.R before distribution diagnostics.")
}

population <- readr::read_csv(population_path, show_col_types = FALSE)
population$date <- as.Date(population$date)
population$goals_for <- as.numeric(population$goals_for)
population$goals_against <- as.numeric(population$goals_against)
population$goal_diff <- population$goals_for - population$goals_against
population$scored_any <- as.integer(population$goals_for > 0)
population$clean_sheet <- as.integer(population$goals_against == 0)
population$btts <- as.integer(population$goals_for > 0 & population$goals_against > 0)
population$win <- as.integer(population$goals_for > population$goals_against)
population$draw <- as.integer(population$goals_for == population$goals_against)
population$loss <- as.integer(population$goals_for < population$goals_against)
population$result <- ifelse(population$win == 1, "win", ifelse(population$draw == 1, "draw", "loss"))
population$is_world_cup <- as.logical(population$is_world_cup)
population$is_friendly <- as.logical(population$is_friendly)

safe_p <- function(x) {
  ifelse(is.na(x), NA, ifelse(x < 0.001, "<0.001", format(round(x, 3), nsmall = 3, trim = TRUE)))
}

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), NA, format(round(x, digits), nsmall = digits, big.mark = ",", trim = TRUE))
}

skewness <- function(x) {
  x <- x[is.finite(x)]
  s <- stats::sd(x)
  if (length(x) < 3 || !is.finite(s) || s == 0) return(NA_real_)
  mean(((x - mean(x)) / s)^3)
}

excess_kurtosis <- function(x) {
  x <- x[is.finite(x)]
  s <- stats::sd(x)
  if (length(x) < 4 || !is.finite(s) || s == 0) return(NA_real_)
  mean(((x - mean(x)) / s)^4) - 3
}

safe_chisq_p <- function(statistic, df) {
  if (!is.finite(statistic) || !is.finite(df) || df <= 0) return(NA_real_)
  stats::pchisq(statistic, df = df, lower.tail = FALSE)
}

jarque_bera <- function(x) {
  x <- x[is.finite(x)]
  sk <- skewness(x)
  ku <- excess_kurtosis(x)
  stat <- length(x) / 6 * (sk^2 + ku^2 / 4)
  c(statistic = stat, p_value = safe_chisq_p(stat, 2))
}

durbin_watson <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 2 || sum(x^2) == 0) return(NA_real_)
  sum(diff(x)^2) / sum(x^2)
}

lag_cor <- function(x, lag = 1) {
  x <- x[is.finite(x)]
  if (length(x) <= lag + 2) return(NA_real_)
  stats::cor(x[seq_len(length(x) - lag)], x[(lag + 1):length(x)], use = "complete.obs")
}

count_gof <- function(values, family) {
  values <- values[is.finite(values) & values >= 0]
  max_count <- max(values)
  breaks <- 0:min(max_count, 7)
  observed <- as.numeric(table(factor(pmin(values, max(breaks)), levels = breaks)))
  mean_value <- mean(values)
  var_value <- stats::var(values)

  if (family == "poisson") {
    expected_prob <- stats::dpois(breaks, lambda = mean_value)
    expected_prob[length(expected_prob)] <- stats::ppois(max(breaks) - 1, lambda = mean_value, lower.tail = FALSE)
    parameters <- 1
  } else {
    size <- ifelse(var_value > mean_value, mean_value^2 / (var_value - mean_value), 1e6)
    expected_prob <- stats::dnbinom(breaks, size = size, mu = mean_value)
    expected_prob[length(expected_prob)] <- stats::pnbinom(max(breaks) - 1, size = size, mu = mean_value, lower.tail = FALSE)
    parameters <- 2
  }

  expected <- expected_prob * length(values)
  keep <- expected >= 5
  if (sum(!keep) > 0 && sum(keep) > 0) {
    observed <- c(observed[keep], sum(observed[!keep]))
    expected <- c(expected[keep], sum(expected[!keep]))
  }
  statistic <- sum((observed - expected)^2 / pmax(expected, 1e-9))
  df <- length(observed) - 1 - parameters
  c(statistic = statistic, df = df, p_value = safe_chisq_p(statistic, df))
}

ks_sample <- function(x, max_n = 5000, seed = 20260629) {
  x <- x[is.finite(x)]
  if (length(x) > max_n) {
    set.seed(seed)
    x <- sample(x, max_n)
  }
  x
}

fit_beta_moments <- function(x) {
  x <- x[is.finite(x)]
  x <- pmin(pmax(x, 1e-6), 1 - 1e-6)
  m <- mean(x)
  v <- stats::var(x)
  common <- m * (1 - m) / v - 1
  alpha <- m * common
  beta <- (1 - m) * common
  c(alpha = alpha, beta = beta)
}

distribution_map <- data.frame(
  distribution = c(
    "Bernoulli",
    "Binomial",
    "Poisson",
    "Geometric",
    "Uniform",
    "Normal",
    "Exponential",
    "Gamma",
    "Beta",
    "t",
    "Chi-squared",
    "F"
  ),
  soccer_target = c(
    "Single yes/no event: win, scored at least once, clean sheet, both teams scored.",
    "Number of successes across a fixed set of matches, such as wins in a team window.",
    "Team goals, cards, injuries, news mentions, and other event counts.",
    "Number of matches until the next scoring success or clean sheet.",
    "Random simulation draws and randomized train/test assignment.",
    "Large-sample residual checks for linear models and continuous context features.",
    "Time until the next match or next event when the event rate is roughly constant.",
    "Positive waiting times and skewed continuous context, such as rest days.",
    "Model probabilities and calibration uncertainty for win/draw/loss forecasts.",
    "Heavy-tailed residuals when normal errors understate outliers.",
    "Goodness-of-fit, independence tests, and residual variance checks.",
    "Variance comparisons across competitions, eras, or model residual groups."
  ),
  current_model_use = c(
    "Active for binary side targets and feature engineering.",
    "Used for window summaries and team-form checks.",
    "Active for goals and event-count challengers.",
    "Diagnostic candidate for scoring droughts.",
    "Active in simulation and validation sampling, not as an observed match model.",
    "Diagnostic baseline; not assumed for raw goals.",
    "Diagnostic candidate for rest-time spacing.",
    "Diagnostic candidate for rest-time spacing and skewed measurements.",
    "Active for probability calibration summaries.",
    "Candidate residual model when tails are heavier than normal.",
    "Active in diagnostics.",
    "Active in diagnostics."
  ),
  stringsAsFactors = FALSE
)

goals <- population$goals_for
goal_mean <- mean(goals, na.rm = TRUE)
goal_var <- stats::var(goals, na.rm = TRUE)
poisson_gof <- count_gof(goals, "poisson")
nb_gof <- count_gof(goals, "negative_binomial")

bernoulli_targets <- c("win", "draw", "scored_any", "clean_sheet", "btts")
bernoulli_summary <- dplyr::bind_rows(lapply(bernoulli_targets, function(target) {
  x <- population[[target]]
  p <- mean(x, na.rm = TRUE)
  n <- sum(!is.na(x))
  data.frame(
    distribution = "Bernoulli",
    target = target,
    rows = n,
    estimate = p,
    statistic = p * (1 - p),
    p_value = NA_real_,
    interpretation = "Estimated probability and Bernoulli variance for a single yes/no event.",
    stringsAsFactors = FALSE
  )
}))

team_win_counts <- stats::aggregate(win ~ team, data = population[population$match_year >= 2000, ], FUN = function(x) c(successes = sum(x), trials = length(x)))
binom_success <- team_win_counts$win[, "successes"]
binom_trials <- team_win_counts$win[, "trials"]
binom_p <- sum(binom_success) / sum(binom_trials)
binom_expected <- binom_trials * binom_p
binom_var <- binom_trials * binom_p * (1 - binom_p)
binom_stat <- sum((binom_success - binom_expected)^2 / pmax(binom_var, 1e-9))
binom_df <- length(binom_success) - 1

streak_lengths <- unlist(lapply(split(population[order(population$date), ], population$team), function(df) {
  streak <- 0
  out <- numeric()
  for (scored in df$scored_any) {
    if (is.na(scored)) next
    if (scored == 1) {
      out <- c(out, streak)
      streak <- 0
    } else {
      streak <- streak + 1
    }
  }
  out
}))
geo_p <- 1 / (mean(streak_lengths, na.rm = TRUE) + 1)
geo_gof <- count_gof(streak_lengths, "poisson")

days_between <- population$team_days_since_match_capped
days_between <- days_between[is.finite(days_between) & days_between > 0]
days_sample <- ks_sample(days_between)
exp_rate <- 1 / mean(days_sample)
exp_ks <- suppressWarnings(stats::ks.test(days_sample, "pexp", rate = exp_rate))
gamma_shape <- mean(days_sample)^2 / stats::var(days_sample)
gamma_rate <- mean(days_sample) / stats::var(days_sample)
gamma_ks <- suppressWarnings(stats::ks.test(days_sample, "pgamma", shape = gamma_shape, rate = gamma_rate))

linear_preds <- if (file.exists(goals_test_path)) readr::read_csv(goals_test_path, show_col_types = FALSE) else data.frame()
residuals <- if (nrow(linear_preds) > 0 && "residual" %in% names(linear_preds)) linear_preds$residual else numeric()
jb <- jarque_bera(residuals)
resid_kurtosis <- excess_kurtosis(residuals)
t_df_estimate <- ifelse(is.finite(resid_kurtosis) && resid_kurtosis > 0, 6 / resid_kurtosis + 4, NA_real_)

result_preds <- if (file.exists(result_test_path)) readr::read_csv(result_test_path, show_col_types = FALSE) else data.frame()
prob_values <- c()
if (nrow(result_preds) > 0) {
  prob_cols <- intersect(c("pred_prob_loss", "pred_prob_draw", "pred_prob_win"), names(result_preds))
  prob_values <- c(prob_values, unlist(result_preds[, prob_cols], use.names = FALSE))
}
if (file.exists(fixture_path)) {
  fixture_preds <- readr::read_csv(fixture_path, show_col_types = FALSE)
  prob_cols <- intersect(c("pred_home_win_prob", "pred_draw_prob", "pred_away_win_prob", "home_advance_prob", "away_advance_prob"), names(fixture_preds))
  prob_values <- c(prob_values, unlist(fixture_preds[, prob_cols], use.names = FALSE))
}
prob_values <- prob_values[is.finite(prob_values) & prob_values > 0 & prob_values < 1]
prob_sample <- ks_sample(prob_values)
beta_params <- fit_beta_moments(prob_sample)
beta_ks <- suppressWarnings(stats::ks.test(prob_sample, "pbeta", shape1 = beta_params[["alpha"]], shape2 = beta_params[["beta"]]))

chi_table <- table(population$result, ifelse(population$is_world_cup, "world_cup", "other"))
chi_test <- suppressWarnings(stats::chisq.test(chi_table))
f_test <- suppressWarnings(stats::var.test(
  population$goals_for[population$is_world_cup],
  population$goals_for[population$is_friendly]
))

uniform_draws <- stats::runif(10000)
uniform_ks <- suppressWarnings(stats::ks.test(uniform_draws, "punif"))

diagnostics <- dplyr::bind_rows(
  bernoulli_summary,
  data.frame(
    distribution = "Binomial",
    target = "Team wins since 2000",
    rows = length(binom_success),
    estimate = binom_p,
    statistic = binom_stat / binom_df,
    p_value = safe_chisq_p(binom_stat, binom_df),
    interpretation = "Overdispersion ratio above 1 means team win counts vary more than a simple common-p binomial.",
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = c("Poisson", "Negative binomial"),
    target = c("Team goals", "Team goals"),
    rows = length(goals),
    estimate = c(goal_mean, goal_mean),
    statistic = c(poisson_gof[["statistic"]], nb_gof[["statistic"]]),
    p_value = c(poisson_gof[["p_value"]], nb_gof[["p_value"]]),
    interpretation = c(
      paste0("Goal variance/mean is ", fmt(goal_var / goal_mean), "; values above 1 suggest overdispersion."),
      "Negative binomial is checked because soccer goals have more variance than a strict Poisson often allows."
    ),
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = "Geometric",
    target = "Matches until team scores",
    rows = length(streak_lengths),
    estimate = geo_p,
    statistic = mean(streak_lengths, na.rm = TRUE),
    p_value = NA_real_,
    interpretation = "Useful for scoring-drought features; the estimate is the implied scoring-success probability.",
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = "Uniform",
    target = "Monte Carlo simulation draws",
    rows = length(uniform_draws),
    estimate = mean(uniform_draws),
    statistic = unname(uniform_ks$statistic),
    p_value = uniform_ks$p.value,
    interpretation = "Uniform draws are used for simulation and train/test sampling, not as an observed soccer outcome.",
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = c("Normal", "t"),
    target = c("OLS goal residuals", "OLS goal residuals"),
    rows = length(residuals),
    estimate = c(stats::sd(residuals, na.rm = TRUE), t_df_estimate),
    statistic = c(jb[["statistic"]], resid_kurtosis),
    p_value = c(jb[["p_value"]], NA_real_),
    interpretation = c(
      "Jarque-Bera tests whether linear-model residuals look normal; large samples often reject normality.",
      "Positive excess kurtosis supports checking heavier-tailed residual models."
    ),
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = c("Exponential", "Gamma"),
    target = c("Days between team matches", "Days between team matches"),
    rows = length(days_sample),
    estimate = c(exp_rate, gamma_shape),
    statistic = c(unname(exp_ks$statistic), unname(gamma_ks$statistic)),
    p_value = c(exp_ks$p.value, gamma_ks$p.value),
    interpretation = c(
      "Exponential checks a constant-rate waiting-time assumption.",
      "Gamma allows waiting times to have a hump and more flexible spread."
    ),
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = "Beta",
    target = "Predicted probabilities",
    rows = length(prob_sample),
    estimate = beta_params[["alpha"]] / sum(beta_params),
    statistic = unname(beta_ks$statistic),
    p_value = beta_ks$p.value,
    interpretation = "Beta summarizes uncertainty and shape for probabilities between 0 and 1.",
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = "Chi-squared",
    target = "Result mix by World Cup versus other matches",
    rows = sum(chi_table),
    estimate = NA_real_,
    statistic = unname(chi_test$statistic),
    p_value = chi_test$p.value,
    interpretation = "Tests whether win/draw/loss mix differs between World Cup and non-World Cup rows.",
    stringsAsFactors = FALSE
  ),
  data.frame(
    distribution = "F",
    target = "Goal variance: World Cup versus friendlies",
    rows = sum(population$is_world_cup, na.rm = TRUE) + sum(population$is_friendly, na.rm = TRUE),
    estimate = unname(f_test$estimate[1] / f_test$estimate[2]),
    statistic = unname(f_test$statistic),
    p_value = f_test$p.value,
    interpretation = "Compares goal variance across competitions; variance shifts can affect model error.",
    stringsAsFactors = FALSE
  )
)

diagnostics$decision <- dplyr::case_when(
  diagnostics$distribution %in% c("Poisson", "Negative binomial") ~ "Use in goal-count challenger models.",
  diagnostics$distribution %in% c("Bernoulli", "Binomial", "Beta") ~ "Use for binary outcomes, form summaries, and probability calibration.",
  diagnostics$distribution %in% c("Normal", "t", "Chi-squared", "F") ~ "Use in diagnostics and residual testing.",
  diagnostics$distribution %in% c("Exponential", "Gamma", "Geometric") ~ "Use as candidate feature models for rest, drought, and event timing.",
  diagnostics$distribution == "Uniform" ~ "Use for simulation and randomized validation.",
  TRUE ~ "Review."
)

autocorrelation <- data.frame(
  series = c("OLS residuals", "OLS residuals", "OLS residuals"),
  lag = c(1, 5, 10),
  autocorrelation = c(lag_cor(residuals, 1), lag_cor(residuals, 5), lag_cor(residuals, 10)),
  durbin_watson = c(durbin_watson(residuals), NA_real_, NA_real_),
  interpretation = c(
    "Lag-1 residual correlation should be near zero after ordering by match date.",
    "Lag-5 check looks for short residual runs across nearby matches.",
    "Lag-10 check looks for broader residual persistence."
  ),
  stringsAsFactors = FALSE
)

readr::write_csv(distribution_map, file.path(model_dir, "distribution_candidate_map.csv"))
readr::write_csv(diagnostics, file.path(model_dir, "distribution_diagnostics_summary.csv"))
readr::write_csv(autocorrelation, file.path(model_dir, "distribution_autocorrelation_tests.csv"))

cat("\nDistribution diagnostics complete.\n")
cat("Summary: ", file.path(model_dir, "distribution_diagnostics_summary.csv"), "\n", sep = "")
print(diagnostics[, c("distribution", "target", "rows", "estimate", "statistic", "p_value", "decision")])
