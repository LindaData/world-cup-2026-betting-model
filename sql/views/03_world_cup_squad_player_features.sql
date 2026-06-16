CREATE OR REPLACE VIEW vw_2026_squad_player_features AS
SELECT
  squad.group_name,
  squad.team,
  squad.shirt_number,
  squad.position,
  squad.player_name,
  squad.birth_date,
  squad.age_years_as_of_2026_06_11,
  squad.caps_before_tournament,
  squad.goals_before_tournament,
  squad.club,
  squad.club_country_code,
  squad.is_captain,
  COALESCE(player_goals.international_goals_in_dataset, 0) AS goals_in_public_goal_events_dataset,
  player_goals.first_goal_date,
  player_goals.last_goal_date,
  team_recent.matches AS team_matches_since_2022,
  team_recent.win_pct AS team_win_pct_since_2022,
  team_recent.avg_goals_for AS team_avg_goals_for_since_2022,
  team_recent.avg_goals_against AS team_avg_goals_against_since_2022,
  team_recent.avg_goal_diff AS team_avg_goal_diff_since_2022
FROM dim_2026_world_cup_squad_players AS squad
LEFT JOIN agg_player_international_goals AS player_goals
  ON squad.team = player_goals.team
  AND squad.player_name = player_goals.player_name
LEFT JOIN agg_team_recent_form AS team_recent
  ON squad.team = team_recent.team;

