CREATE OR REPLACE VIEW vw_recent_team_form AS
SELECT
  team,
  COUNT(*) AS matches,
  SUM(CASE WHEN result = 'W' THEN 1 ELSE 0 END) AS wins,
  SUM(CASE WHEN result = 'D' THEN 1 ELSE 0 END) AS draws,
  SUM(CASE WHEN result = 'L' THEN 1 ELSE 0 END) AS losses,
  AVG(goals_for) AS avg_goals_for,
  AVG(goals_against) AS avg_goals_against,
  AVG(goals_for - goals_against) AS avg_goal_diff
FROM vw_team_match_results
WHERE date >= DATE '2022-01-01'
GROUP BY team;

