# First Goals Linear Regression

This is the first deliberately simple modeling dataset.

## Target

```text
y_goals_for
```

Meaning: goals scored by the row's team in a historical international match.

## Unit Of Observation

One row per team per match.

Example: Brazil vs Morocco creates:

- Brazil row with `team = Brazil`, `opponent = Morocco`, `y_goals_for = Brazil goals`.
- Morocco row with `team = Morocco`, `opponent = Brazil`, `y_goals_for = Morocco goals`.

## Leak-Safe Features

The starting model uses only features known before kickoff:

- `pre_elo`
- `opponent_pre_elo`
- `pre_match_expected_result`
- `listed_home`
- `neutral`

The CSV still includes `elo_diff`, `is_world_cup`, and `is_friendly` for inspection. The first OLS formula excludes them because they are redundant with other terms:

- `elo_diff` is exactly `pre_elo - opponent_pre_elo`.
- `is_world_cup` and `is_friendly` are already represented by the `tournament` fixed effects.

The CSV also includes `match_year` and `tournament`, but the first saved OLS model does not use them. Sparse tournament/year fixed effects made the design matrix rank-deficient. We can add them back later using regularization or a more careful encoding.

The CSV includes `team` and `opponent`, but the first saved OLS model does not use them. Team/opponent fixed effects are a good next step, but the historical international data has sparse/rare teams that made plain `lm()` rank-deficient. We can handle that later with pooling, filtering, ridge regression, or Bayesian partial pooling.

It does not use:

- `goals_against`
- `actual_result`
- `post_elo`
- `elo_change`
- `goal_multiplier`

Those are all post-match or outcome-derived.

## Outputs

Generated under:

```text
data/processed/modeling
```

Files:

- `goals_linear_model_frame.csv`
- `goals_linear_model_sample_1000.csv`
- `goals_linear_model_metrics.csv`
- `goals_linear_model_coefficients.csv`
- `goals_linear_model_test_predictions.csv`
- `goals_linear_model_fit.rds`

## Caveat

Goals are count data, so OLS is only a first transparent baseline. A Poisson, negative-binomial, bivariate Poisson, or Skellam-style model is probably a better next step.
