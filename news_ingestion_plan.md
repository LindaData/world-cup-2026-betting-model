# News Ingestion Plan

The model should use news as timestamped context, not as copied article content.

## Recommended First Source: GDELT

GDELT is free and monitors global web, print, and broadcast news in many languages. It is a strong first pass for:

- Injury and suspension chatter.
- Lineup uncertainty.
- Manager comments.
- Squad changes.
- Travel/weather disruptions.
- Sentiment and media-volume shifts around teams or players.

The first script stores article metadata only:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_news_gdelt.py --include-team-queries
```

Outputs:

- Raw JSON: `data/raw/news/<timestamp>/`
- Article metadata table: `data/processed/public_csv/fact_news_articles_gdelt.csv`
- Query count table: `data/processed/public_csv/agg_news_query_counts_gdelt.csv`

After running it, load into DuckDB:

```r
source("R/01_build_duckdb.R")
```

## Modeling Features To Derive Later

- Article count by team/player over last 1, 3, 7, and 14 days.
- Negative/injury keyword counts.
- Source diversity count.
- Sudden spike flags relative to team baseline.
- Player-specific mention counts near kickoff.
- Team travel/weather disruption terms.

## Why Not Full Article Scraping First

Full article scraping can create copyright and terms-of-service problems. Metadata, URLs, titles, timestamps, source domains, and derived counts are safer and often enough for model signals.

If we need richer article text later, use explicit APIs with allowed usage terms, or store only derived features from fetched text.

