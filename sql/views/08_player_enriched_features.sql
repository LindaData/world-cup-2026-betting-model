CREATE OR REPLACE VIEW vw_2026_squad_player_enriched AS
SELECT
  squad.*,
  wd.wikidata_qid,
  wd.wikidata_label,
  wd.height_m,
  wd.image,
  wd.country_of_citizenship_qids,
  wd.position_played_qids,
  wd.club_or_team_qids,
  wd.raw_entity_available
FROM dim_2026_world_cup_squad_players AS squad
LEFT JOIN dim_player_wikidata AS wd
  ON squad.team = wd.team
  AND squad.player_name = wd.player_name;

