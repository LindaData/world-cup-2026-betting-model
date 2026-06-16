CREATE OR REPLACE VIEW vw_goals_linear_model_frame AS
SELECT
  source_match_id,
  date,
  EXTRACT(year FROM date) AS match_year,
  tournament,
  city,
  country,
  neutral,
  team,
  opponent,
  listed_home,
  goals_for AS y_goals_for,
  pre_elo,
  opponent_pre_elo,
  pre_elo - opponent_pre_elo AS elo_diff,
  expected_result AS pre_match_expected_result,
  k_factor,
  CASE WHEN tournament = 'FIFA World Cup' THEN TRUE ELSE FALSE END AS is_world_cup,
  CASE WHEN tournament = 'Friendly' THEN TRUE ELSE FALSE END AS is_friendly
FROM fact_team_elo_match_history
WHERE
  date < DATE '2026-06-11'
  AND goals_for IS NOT NULL
  AND pre_elo IS NOT NULL
  AND opponent_pre_elo IS NOT NULL;

