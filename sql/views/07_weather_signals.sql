CREATE OR REPLACE VIEW vw_fixture_weather_signals AS
SELECT
  source_match_id,
  fixture_date,
  home_team,
  away_team,
  venue_id,
  venue_name,
  city,
  country,
  AVG(temperature_2m) AS avg_temperature_2m,
  MAX(temperature_2m) AS max_temperature_2m,
  AVG(relative_humidity_2m) AS avg_relative_humidity_2m,
  SUM(precipitation) AS total_precipitation,
  AVG(wind_speed_10m) AS avg_wind_speed_10m,
  MAX(wind_speed_10m) AS max_wind_speed_10m
FROM fact_fixture_weather_hourly_open_meteo
GROUP BY
  source_match_id,
  fixture_date,
  home_team,
  away_team,
  venue_id,
  venue_name,
  city,
  country;

