CREATE TABLE IF NOT EXISTS raw_snapshot_files (
  snapshot_id VARCHAR,
  file_name VARCHAR,
  file_path VARCHAR,
  file_ext VARCHAR,
  bytes BIGINT,
  modified_at VARCHAR
);

CREATE TABLE IF NOT EXISTS raw_manifests (
  snapshot_id VARCHAR,
  manifest_json VARCHAR
);

CREATE TABLE IF NOT EXISTS seed_venues (
  venue_id VARCHAR,
  region VARCHAR,
  country VARCHAR,
  city VARCHAR,
  venue_name VARCHAR,
  timezone VARCHAR,
  latitude DOUBLE,
  longitude DOUBLE,
  capacity BIGINT
);

CREATE TABLE IF NOT EXISTS stg_international_results (
  date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  home_score INTEGER,
  away_score INTEGER,
  tournament VARCHAR,
  city VARCHAR,
  country VARCHAR,
  neutral BOOLEAN
);

CREATE TABLE IF NOT EXISTS stg_international_goalscorers (
  date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  team VARCHAR,
  scorer VARCHAR,
  minute INTEGER,
  own_goal BOOLEAN,
  penalty BOOLEAN
);

CREATE TABLE IF NOT EXISTS stg_international_shootouts (
  date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  winner VARCHAR,
  first_shooter VARCHAR
);

CREATE TABLE IF NOT EXISTS odds_snapshots (
  snapshot_id VARCHAR,
  pulled_at_utc TIMESTAMP,
  provider VARCHAR,
  sport_key VARCHAR,
  event_id VARCHAR,
  commence_time TIMESTAMP,
  home_team VARCHAR,
  away_team VARCHAR,
  bookmaker_key VARCHAR,
  bookmaker_title VARCHAR,
  market_key VARCHAR,
  outcome_name VARCHAR,
  outcome_price DOUBLE,
  outcome_point DOUBLE,
  raw_json VARCHAR
);

CREATE TABLE IF NOT EXISTS football_data_matches (
  snapshot_id VARCHAR,
  pulled_at_utc TIMESTAMP,
  match_id VARCHAR,
  utc_date TIMESTAMP,
  status VARCHAR,
  stage VARCHAR,
  group_name VARCHAR,
  home_team VARCHAR,
  away_team VARCHAR,
  home_score INTEGER,
  away_score INTEGER,
  raw_json VARCHAR
);

CREATE TABLE IF NOT EXISTS weather_hourly (
  venue_id VARCHAR,
  weather_time TIMESTAMP,
  temperature_2m DOUBLE,
  relative_humidity_2m DOUBLE,
  precipitation DOUBLE,
  wind_speed_10m DOUBLE,
  raw_json VARCHAR
);

CREATE TABLE IF NOT EXISTS fact_international_matches_team_long (
  source_match_id BIGINT,
  date DATE,
  tournament VARCHAR,
  city VARCHAR,
  country VARCHAR,
  neutral BOOLEAN,
  team VARCHAR,
  opponent VARCHAR,
  listed_home BOOLEAN,
  goals_for INTEGER,
  goals_against INTEGER,
  goal_diff INTEGER,
  result VARCHAR
);

CREATE TABLE IF NOT EXISTS agg_team_history (
  team VARCHAR,
  matches BIGINT,
  wins BIGINT,
  draws BIGINT,
  losses BIGINT,
  goals_for BIGINT,
  goals_against BIGINT,
  first_match_date DATE,
  last_match_date DATE,
  avg_goals_for DOUBLE,
  avg_goals_against DOUBLE,
  avg_goal_diff DOUBLE,
  win_pct DOUBLE
);

CREATE TABLE IF NOT EXISTS agg_team_recent_form (
  team VARCHAR,
  matches BIGINT,
  wins BIGINT,
  draws BIGINT,
  losses BIGINT,
  goals_for BIGINT,
  goals_against BIGINT,
  first_match_date DATE,
  last_match_date DATE,
  avg_goals_for DOUBLE,
  avg_goals_against DOUBLE,
  avg_goal_diff DOUBLE,
  win_pct DOUBLE,
  since_date DATE
);

CREATE TABLE IF NOT EXISTS fact_player_goals (
  date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  team VARCHAR,
  scorer VARCHAR,
  minute INTEGER,
  own_goal BOOLEAN,
  penalty BOOLEAN
);

CREATE TABLE IF NOT EXISTS agg_player_international_goals (
  team VARCHAR,
  player_name VARCHAR,
  international_goals_in_dataset BIGINT,
  penalty_goals BIGINT,
  own_goals BIGINT,
  first_goal_date DATE,
  last_goal_date DATE,
  tournaments_scored_in VARCHAR
);

CREATE TABLE IF NOT EXISTS fact_2026_world_cup_fixtures (
  source_match_id BIGINT,
  date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  home_score INTEGER,
  away_score INTEGER,
  status VARCHAR,
  city VARCHAR,
  country VARCHAR,
  neutral BOOLEAN
);

CREATE TABLE IF NOT EXISTS dim_locations_from_results (
  city VARCHAR,
  country VARCHAR,
  matches_in_results_dataset BIGINT
);

CREATE TABLE IF NOT EXISTS dim_2026_world_cup_squad_players (
  group_name VARCHAR,
  team VARCHAR,
  shirt_number INTEGER,
  position VARCHAR,
  player_name VARCHAR,
  player_wiki_title VARCHAR,
  sort_name VARCHAR,
  birth_date DATE,
  age_years_as_of_2026_06_11 INTEGER,
  caps_before_tournament INTEGER,
  goals_before_tournament INTEGER,
  club VARCHAR,
  club_wiki_title VARCHAR,
  club_country_code VARCHAR,
  notes VARCHAR,
  is_captain BOOLEAN
);

CREATE TABLE IF NOT EXISTS fact_team_elo_match_history (
  source_match_id BIGINT,
  date DATE,
  tournament VARCHAR,
  city VARCHAR,
  country VARCHAR,
  neutral BOOLEAN,
  k_factor INTEGER,
  goal_multiplier DOUBLE,
  team VARCHAR,
  opponent VARCHAR,
  listed_home BOOLEAN,
  goals_for INTEGER,
  goals_against INTEGER,
  pre_elo DOUBLE,
  opponent_pre_elo DOUBLE,
  expected_result DOUBLE,
  actual_result DOUBLE,
  elo_change DOUBLE,
  post_elo DOUBLE
);

CREATE TABLE IF NOT EXISTS agg_team_elo_latest (
  team VARCHAR,
  latest_elo DOUBLE,
  rated_matches BIGINT
);

CREATE TABLE IF NOT EXISTS fact_news_articles_gdelt (
  pulled_at_utc TIMESTAMP,
  query VARCHAR,
  url VARCHAR,
  title VARCHAR,
  seendate VARCHAR,
  domain VARCHAR,
  language VARCHAR,
  sourcecountry VARCHAR,
  socialimage VARCHAR
);

CREATE TABLE IF NOT EXISTS agg_news_query_counts_gdelt (
  query VARCHAR,
  articles BIGINT
);

CREATE TABLE IF NOT EXISTS dim_player_wikidata (
  team VARCHAR,
  player_name VARCHAR,
  player_wiki_title VARCHAR,
  wikidata_qid VARCHAR,
  wikidata_label VARCHAR,
  date_of_birth VARCHAR,
  height_m DOUBLE,
  image VARCHAR,
  country_of_citizenship_qids VARCHAR,
  position_played_qids VARCHAR,
  club_or_team_qids VARCHAR,
  raw_entity_available BOOLEAN
);

CREATE TABLE IF NOT EXISTS fact_fixture_weather_hourly_open_meteo (
  source_match_id BIGINT,
  fixture_date DATE,
  home_team VARCHAR,
  away_team VARCHAR,
  venue_id VARCHAR,
  venue_name VARCHAR,
  city VARCHAR,
  country VARCHAR,
  weather_time TIMESTAMP,
  temperature_2m DOUBLE,
  relative_humidity_2m DOUBLE,
  precipitation DOUBLE,
  wind_speed_10m DOUBLE
);
