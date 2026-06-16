CREATE OR REPLACE VIEW vw_2026_fixture_model_frame AS
SELECT
  fixtures.source_match_id,
  fixtures.date,
  fixtures.home_team,
  fixtures.away_team,
  fixtures.home_score,
  fixtures.away_score,
  fixtures.status,
  fixtures.city,
  fixtures.country,
  fixtures.neutral,
  home_features.squad_caps_before_tournament AS home_squad_caps_before_tournament,
  away_features.squad_caps_before_tournament AS away_squad_caps_before_tournament,
  home_features.squad_goals_before_tournament AS home_squad_goals_before_tournament,
  away_features.squad_goals_before_tournament AS away_squad_goals_before_tournament,
  home_features.win_pct_since_2022 AS home_win_pct_since_2022,
  away_features.win_pct_since_2022 AS away_win_pct_since_2022,
  home_features.avg_goals_for_since_2022 AS home_avg_goals_for_since_2022,
  away_features.avg_goals_for_since_2022 AS away_avg_goals_for_since_2022,
  home_features.avg_goals_against_since_2022 AS home_avg_goals_against_since_2022,
  away_features.avg_goals_against_since_2022 AS away_avg_goals_against_since_2022,
  home_features.latest_elo AS home_latest_elo,
  away_features.latest_elo AS away_latest_elo,
  home_features.latest_elo - away_features.latest_elo AS elo_diff_home_minus_away,
  CASE
    WHEN fixtures.home_score IS NULL OR fixtures.away_score IS NULL THEN NULL
    WHEN fixtures.home_score > fixtures.away_score THEN 'home_win'
    WHEN fixtures.home_score = fixtures.away_score THEN 'draw'
    ELSE 'away_win'
  END AS match_result_ordinal
FROM fact_2026_world_cup_fixtures AS fixtures
LEFT JOIN vw_2026_team_model_features AS home_features
  ON fixtures.home_team = home_features.team
LEFT JOIN vw_2026_team_model_features AS away_features
  ON fixtures.away_team = away_features.team;
