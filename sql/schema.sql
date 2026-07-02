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

CREATE TABLE IF NOT EXISTS fact_2026_world_cup_fixture_times (
  source_match_id BIGINT,
  date DATE,
  local_time VARCHAR,
  utc_offset VARCHAR,
  kickoff_local_iso VARCHAR,
  kickoff_utc_iso VARCHAR,
  refresh_utc_iso VARCHAR,
  home_team VARCHAR,
  away_team VARCHAR,
  home_team_key VARCHAR,
  away_team_key VARCHAR,
  venue_label VARCHAR
);

CREATE TABLE IF NOT EXISTS film_study_tags (
  recorded_at_utc VARCHAR,
  match_key VARCHAR,
  home_team VARCHAR,
  away_team VARCHAR,
  video_file VARCHAR,
  event_type VARCHAR,
  team VARCHAR,
  player VARCHAR,
  outcome VARCHAR,
  time_seconds DOUBLE,
  clock VARCHAR,
  frame_index BIGINT,
  x_pct DOUBLE,
  y_pct DOUBLE,
  notes VARCHAR,
  source_file VARCHAR
);

CREATE TABLE IF NOT EXISTS film_study_events_enriched (
  recorded_at_utc VARCHAR,
  match_key VARCHAR,
  home_team VARCHAR,
  away_team VARCHAR,
  video_file VARCHAR,
  event_type VARCHAR,
  team VARCHAR,
  player VARCHAR,
  outcome VARCHAR,
  time_seconds DOUBLE,
  clock VARCHAR,
  frame_index BIGINT,
  x_pct DOUBLE,
  y_pct DOUBLE,
  notes VARCHAR,
  source_file VARCHAR,
  event_index BIGINT,
  seconds_since_prev_event DOUBLE,
  event_group VARCHAR,
  x_zone VARCHAR,
  y_lane VARCHAR,
  is_shot BOOLEAN,
  is_goal BOOLEAN,
  is_card BOOLEAN,
  is_attacking_event BOOLEAN,
  is_terminal_event BOOLEAN,
  is_on_target BOOLEAN,
  team_clean VARCHAR,
  possession_id BIGINT,
  team_inferred VARCHAR,
  next_event_type VARCHAR,
  next_team_inferred VARCHAR
);

CREATE TABLE IF NOT EXISTS film_study_possessions (
  match_key VARCHAR,
  possession_id BIGINT,
  home_team VARCHAR,
  away_team VARCHAR,
  team_inferred VARCHAR,
  possession_start_seconds DOUBLE,
  possession_end_seconds DOUBLE,
  possession_events BIGINT,
  shots BIGINT,
  goals BIGINT,
  passes BIGINT,
  attack_entries BIGINT,
  turnovers BIGINT,
  fouls BIGINT,
  cards BIGINT,
  notes_logged BIGINT,
  first_x_zone VARCHAR,
  last_x_zone VARCHAR,
  first_y_lane VARCHAR,
  last_y_lane VARCHAR,
  possession_duration_seconds DOUBLE,
  shot_rate_per_event DOUBLE
);

CREATE TABLE IF NOT EXISTS film_study_match_features (
  match_key VARCHAR,
  home_team VARCHAR,
  away_team VARCHAR,
  tagged_events BIGINT,
  unique_players_tagged BIGINT,
  unique_teams_tagged BIGINT,
  tagged_shots BIGINT,
  tagged_goals BIGINT,
  shots_on_target BIGINT,
  tagged_cards BIGINT,
  tagged_fouls BIGINT,
  tagged_turnovers BIGINT,
  tagged_notes BIGINT,
  avg_seconds_between_events DOUBLE,
  median_seconds_between_events DOUBLE,
  tagged_possessions BIGINT,
  avg_possession_seconds DOUBLE,
  median_possession_seconds DOUBLE,
  max_possession_seconds DOUBLE,
  avg_events_per_possession DOUBLE,
  max_events_in_possession BIGINT
);

CREATE TABLE IF NOT EXISTS film_study_zone_summary (
  match_key VARCHAR,
  team_inferred VARCHAR,
  x_zone VARCHAR,
  y_lane VARCHAR,
  events BIGINT,
  shots BIGINT,
  goals BIGINT
);

CREATE TABLE IF NOT EXISTS film_study_event_transitions (
  match_key VARCHAR,
  team_inferred VARCHAR,
  event_type VARCHAR,
  next_event_type VARCHAR,
  transition_count BIGINT,
  transition_rate DOUBLE
);

CREATE TABLE IF NOT EXISTS film_study_clips (
  match_key VARCHAR,
  event_index BIGINT,
  event_type VARCHAR,
  team_inferred VARCHAR,
  player VARCHAR,
  time_seconds DOUBLE,
  video_file VARCHAR,
  clip_file VARCHAR,
  seconds_before DOUBLE,
  seconds_after DOUBLE,
  fps DOUBLE,
  width BIGINT,
  height BIGINT,
  clip_start_seconds DOUBLE,
  clip_end_seconds DOUBLE,
  frames_written BIGINT
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

CREATE TABLE IF NOT EXISTS api_football_world_cup_leagues (
  api_league_id BIGINT,
  league_name VARCHAR,
  league_type VARCHAR,
  country_name VARCHAR,
  season BIGINT,
  season_start DATE,
  season_end DATE,
  season_current BOOLEAN,
  coverage_events BOOLEAN,
  coverage_lineups BOOLEAN,
  coverage_fixture_statistics BOOLEAN,
  coverage_player_statistics BOOLEAN,
  coverage_standings BOOLEAN,
  coverage_players BOOLEAN,
  coverage_injuries BOOLEAN,
  coverage_predictions BOOLEAN,
  coverage_odds BOOLEAN
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_fixtures (
  api_fixture_id BIGINT,
  referee VARCHAR,
  timezone VARCHAR,
  fixture_date TIMESTAMP,
  timestamp BIGINT,
  venue_id BIGINT,
  venue_name VARCHAR,
  venue_city VARCHAR,
  status_long VARCHAR,
  status_short VARCHAR,
  elapsed BIGINT,
  league_id BIGINT,
  league_name VARCHAR,
  season BIGINT,
  round VARCHAR,
  home_team_id BIGINT,
  home_team VARCHAR,
  home_winner BOOLEAN,
  away_team_id BIGINT,
  away_team VARCHAR,
  away_winner BOOLEAN,
  home_goals INTEGER,
  away_goals INTEGER,
  halftime_home INTEGER,
  halftime_away INTEGER,
  fulltime_home INTEGER,
  fulltime_away INTEGER,
  extratime_home INTEGER,
  extratime_away INTEGER,
  penalty_home INTEGER,
  penalty_away INTEGER
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_team_match_frame (
  api_fixture_id BIGINT,
  fixture_date TIMESTAMP,
  league_id BIGINT,
  season BIGINT,
  round VARCHAR,
  venue_id BIGINT,
  venue_name VARCHAR,
  venue_city VARCHAR,
  status_short VARCHAR,
  team_id BIGINT,
  team VARCHAR,
  opponent_id BIGINT,
  opponent VARCHAR,
  listed_home BOOLEAN,
  goals_for INTEGER,
  goals_against INTEGER,
  goal_diff INTEGER,
  result VARCHAR
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_teams (
  team_id BIGINT,
  team_name VARCHAR,
  team_code VARCHAR,
  country VARCHAR,
  founded BIGINT,
  national BOOLEAN,
  venue_id BIGINT,
  venue_name VARCHAR,
  venue_city VARCHAR,
  venue_capacity BIGINT,
  venue_surface VARCHAR
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_standings (
  league_id BIGINT,
  league_name VARCHAR,
  season BIGINT,
  rank BIGINT,
  team_id BIGINT,
  team_name VARCHAR,
  points BIGINT,
  goals_diff BIGINT,
  group_name VARCHAR,
  form VARCHAR,
  status VARCHAR,
  description VARCHAR,
  all_played BIGINT,
  all_win BIGINT,
  all_draw BIGINT,
  all_lose BIGINT,
  all_goals_for BIGINT,
  all_goals_against BIGINT
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_injuries (
  player_id BIGINT,
  player_name VARCHAR,
  player_type VARCHAR,
  player_reason VARCHAR,
  team_id BIGINT,
  team_name VARCHAR,
  fixture_id BIGINT,
  fixture_timezone VARCHAR,
  fixture_date TIMESTAMP,
  league_id BIGINT,
  league_name VARCHAR,
  season BIGINT
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_odds (
  fixture_id BIGINT,
  fixture_timezone VARCHAR,
  fixture_date TIMESTAMP,
  league_id BIGINT,
  league_name VARCHAR,
  season BIGINT,
  bookmaker_id BIGINT,
  bookmaker_name VARCHAR,
  bet_id BIGINT,
  bet_name VARCHAR,
  outcome_value VARCHAR,
  outcome_odd DOUBLE
);

CREATE TABLE IF NOT EXISTS api_football_world_cup_players (
  player_id BIGINT,
  player_name VARCHAR,
  player_firstname VARCHAR,
  player_lastname VARCHAR,
  age BIGINT,
  birth_date DATE,
  birth_place VARCHAR,
  birth_country VARCHAR,
  nationality VARCHAR,
  height VARCHAR,
  weight VARCHAR,
  injured BOOLEAN,
  team_id BIGINT,
  team_name VARCHAR,
  league_id BIGINT,
  league_name VARCHAR,
  season BIGINT,
  appearances BIGINT,
  lineups BIGINT,
  minutes BIGINT,
  position VARCHAR,
  rating DOUBLE,
  captain BOOLEAN,
  goals_total BIGINT,
  goals_conceded BIGINT,
  assists BIGINT,
  shots_total BIGINT,
  shots_on BIGINT,
  passes_total BIGINT,
  passes_key BIGINT,
  tackles_total BIGINT,
  duels_total BIGINT,
  duels_won BIGINT,
  dribbles_attempts BIGINT,
  dribbles_success BIGINT,
  fouls_drawn BIGINT,
  fouls_committed BIGINT,
  yellow_cards BIGINT,
  red_cards BIGINT,
  penalties_scored BIGINT,
  penalties_missed BIGINT,
  penalties_saved BIGINT
);

CREATE TABLE IF NOT EXISTS api_football_fixture_lineups (
  api_fixture_id BIGINT,
  team_id BIGINT,
  team_name VARCHAR,
  formation VARCHAR,
  coach_id BIGINT,
  coach_name VARCHAR,
  lineup_role VARCHAR,
  player_id BIGINT,
  player_name VARCHAR,
  player_number BIGINT,
  player_position VARCHAR,
  player_grid VARCHAR
);

CREATE TABLE IF NOT EXISTS api_football_fixture_events (
  api_fixture_id BIGINT,
  elapsed BIGINT,
  extra BIGINT,
  team_id BIGINT,
  team_name VARCHAR,
  player_id BIGINT,
  player_name VARCHAR,
  assist_id BIGINT,
  assist_name VARCHAR,
  event_type VARCHAR,
  event_detail VARCHAR,
  comments VARCHAR
);

CREATE TABLE IF NOT EXISTS api_football_fixture_predictions (
  api_fixture_id BIGINT,
  winner_id BIGINT,
  winner_name VARCHAR,
  winner_comment VARCHAR,
  win_or_draw BOOLEAN,
  under_over VARCHAR,
  goals_home VARCHAR,
  goals_away VARCHAR,
  advice VARCHAR,
  home_percent VARCHAR,
  draw_percent VARCHAR,
  away_percent VARCHAR,
  home_team_id BIGINT,
  home_team VARCHAR,
  away_team_id BIGINT,
  away_team VARCHAR
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
