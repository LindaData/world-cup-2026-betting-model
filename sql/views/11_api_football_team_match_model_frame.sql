CREATE OR REPLACE VIEW vw_api_football_team_match_model_frame AS
SELECT
  api.api_fixture_id,
  api.fixture_date,
  api.league_id,
  api.season,
  api.round,
  api.venue_id,
  api.venue_name,
  api.venue_city,
  api.status_short,
  api.team_id,
  api.team,
  api.opponent_id,
  api.opponent,
  api.listed_home,
  api.goals_for,
  api.goals_against,
  api.goal_diff,
  api.result,
  team_features.squad_caps_before_tournament,
  team_features.squad_goals_before_tournament,
  team_features.win_pct_since_2022,
  team_features.avg_goals_for_since_2022,
  team_features.avg_goals_against_since_2022,
  team_features.latest_elo,
  opponent_features.latest_elo AS opponent_latest_elo,
  team_features.latest_elo - opponent_features.latest_elo AS elo_diff_team_minus_opponent,
  team_features.avg_goals_for_since_2022
    - opponent_features.avg_goals_against_since_2022 AS recent_attack_vs_opponent_defense
FROM api_football_world_cup_team_match_frame AS api
LEFT JOIN vw_2026_team_model_features AS team_features
  ON api.team = team_features.team
LEFT JOIN vw_2026_team_model_features AS opponent_features
  ON api.opponent = opponent_features.team;
