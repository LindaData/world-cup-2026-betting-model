CREATE OR REPLACE VIEW vw_2026_team_model_features AS
SELECT
  squad.team,
  COUNT(*) AS squad_players,
  SUM(CASE WHEN squad.position = 'GK' THEN 1 ELSE 0 END) AS goalkeepers,
  SUM(CASE WHEN squad.position = 'DF' THEN 1 ELSE 0 END) AS defenders,
  SUM(CASE WHEN squad.position = 'MF' THEN 1 ELSE 0 END) AS midfielders,
  SUM(CASE WHEN squad.position = 'FW' THEN 1 ELSE 0 END) AS forwards,
  AVG(squad.age_years_as_of_2026_06_11) AS avg_squad_age,
  SUM(squad.caps_before_tournament) AS squad_caps_before_tournament,
  SUM(squad.goals_before_tournament) AS squad_goals_before_tournament,
  AVG(squad.caps_before_tournament) AS avg_caps_before_tournament,
  AVG(squad.goals_before_tournament) AS avg_goals_before_tournament,
  recent.matches AS matches_since_2022,
  recent.win_pct AS win_pct_since_2022,
  recent.avg_goals_for AS avg_goals_for_since_2022,
  recent.avg_goals_against AS avg_goals_against_since_2022,
  recent.avg_goal_diff AS avg_goal_diff_since_2022,
  history.matches AS all_time_matches_in_public_results,
  history.win_pct AS all_time_win_pct_public_results,
  elo.latest_elo,
  elo.rated_matches AS elo_rated_matches
FROM dim_2026_world_cup_squad_players AS squad
LEFT JOIN agg_team_recent_form AS recent
  ON squad.team = recent.team
LEFT JOIN agg_team_history AS history
  ON squad.team = history.team
LEFT JOIN agg_team_elo_latest AS elo
  ON squad.team = elo.team
GROUP BY
  squad.team,
  recent.matches,
  recent.win_pct,
  recent.avg_goals_for,
  recent.avg_goals_against,
  recent.avg_goal_diff,
  history.matches,
  history.win_pct,
  elo.latest_elo,
  elo.rated_matches;
