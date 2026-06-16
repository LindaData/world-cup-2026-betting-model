CREATE OR REPLACE VIEW vw_news_query_signals AS
SELECT
  query,
  COUNT(*) AS articles,
  COUNT(DISTINCT domain) AS source_domains,
  COUNT(DISTINCT sourcecountry) AS source_countries,
  MIN(seendate) AS first_seen,
  MAX(seendate) AS last_seen,
  SUM(CASE
    WHEN lower(title) LIKE '%injur%' THEN 1
    WHEN lower(title) LIKE '%doubt%' THEN 1
    WHEN lower(title) LIKE '%suspend%' THEN 1
    WHEN lower(title) LIKE '%ban%' THEN 1
    WHEN lower(title) LIKE '%fitness%' THEN 1
    ELSE 0
  END) AS injury_or_availability_mentions,
  SUM(CASE
    WHEN lower(title) LIKE '%lineup%' THEN 1
    WHEN lower(title) LIKE '%starting xi%' THEN 1
    WHEN lower(title) LIKE '%squad%' THEN 1
    ELSE 0
  END) AS lineup_or_squad_mentions
FROM fact_news_articles_gdelt
GROUP BY query;

