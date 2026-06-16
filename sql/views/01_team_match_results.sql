CREATE OR REPLACE VIEW vw_team_match_results AS
SELECT
  date,
  home_team AS team,
  away_team AS opponent,
  home_score AS goals_for,
  away_score AS goals_against,
  CASE
    WHEN home_score > away_score THEN 'W'
    WHEN home_score = away_score THEN 'D'
    ELSE 'L'
  END AS result,
  tournament,
  city,
  country,
  neutral,
  TRUE AS listed_home
FROM stg_international_results
UNION ALL
SELECT
  date,
  away_team AS team,
  home_team AS opponent,
  away_score AS goals_for,
  home_score AS goals_against,
  CASE
    WHEN away_score > home_score THEN 'W'
    WHEN away_score = home_score THEN 'D'
    ELSE 'L'
  END AS result,
  tournament,
  city,
  country,
  neutral,
  FALSE AS listed_home
FROM stg_international_results;

