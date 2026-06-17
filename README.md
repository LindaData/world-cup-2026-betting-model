# 2026 World Cup Betting Model

This project is a reproducible data and modeling scaffold for the 2026 FIFA World Cup. It is designed to be worked on from RStudio while using Python for data acquisition and SQL/DuckDB for storage.

The current model estimates team goals and win/draw/loss probabilities using historical international match data, with market comparison, roster strength, player availability, and news signals organized in the project workflow.

The intended workflow is three-language:

- **Python**: API clients, raw data pulls, repeatable snapshots.
- **SQL**: storage tables, joins, views, auditable transformations.
- **R/RStudio**: exploration, statistical modeling, plots, reports.

DuckDB is the default SQL engine because it is free, embedded, works from R and Python, and does not require running a database server.

## Presentable Outputs

- Quarto website source: `_quarto.yml`, `index.qmd`, and `reports/*.qmd`
- Rendered GitHub Pages site: `docs/`
- Goals model walkthrough: `reports/01_goals_linear_regression.qmd`
- Ordinal result model report: `reports/02_ordinal_result_model.qmd`
- Local Shiny prototype: `apps/shiny_world_cup/app.R`

Render the Quarto site from RStudio:

```r
source("R/12_render_reports.R")
```

## Step 1: Data Sources

For a serious soccer betting model, start with these data families:

1. Fixtures, venues, kickoff times, results, and tournament stage.
2. Historical international results for team-strength estimation.
3. Team ratings and rankings, such as FIFA ranking points or our own Elo.
4. Betting odds snapshots from multiple books, ideally with open and close prices.
5. Context features: rest, travel distance, home/host effects, weather, injuries, roster strength, suspensions, and referee tendencies.

The first API/source connections are scaffolded in `src/wc_model/providers/`:

- `openfootball`: public 2026 World Cup schedule and stadium files.
- `international_results`: public historical men's international results, goalscorers, and shootouts.
- `football_data`: fixtures, teams, standings, and results from football-data.org.
- `the_odds_api`: bookmaker odds and market discovery from The Odds API.
- `api_football`: optional API-Football fallback/enrichment provider.
- `open_meteo`: weather context by venue/date.

## Setup

Copy `.env.example` to `.env` and add API keys as you sign up for providers.

```powershell
Copy-Item .env.example .env
```

Connection scripts use only the Python standard library. Later analysis notebooks can add pandas, statsmodels, PyMC, scikit-learn, or Stan.

```powershell
python scripts/check_connections.py
python scripts/fetch_raw_data.py --sources public
```

On this machine, the project uses the local `.venv` for Python and the Quarto copy bundled with RStudio.

## RStudio Workflow

Open `world-cup-betting-model.Rproj` in RStudio, then run:

```r
source("R/00_setup.R")
source("R/01_build_duckdb.R")
source("R/02_check_python_bridge.R")
```

After Python is installed and `.env` is configured, Python pulls raw data:

```powershell
python scripts\fetch_raw_data.py --sources public
```

Then R builds/updates the DuckDB database:

```r
source("R/01_build_duckdb.R")
```

The database is written to `data/processed/world_cup.duckdb`.

For app readiness checks:

```r
source("R/05_check_app_readiness.R")
```

The first interactive app is Shiny because this machine already has the R app stack installed and the existing coursework examples use Shiny patterns.

Run the local app from RStudio:

```r
shiny::runApp("apps/shiny_world_cup")
```

Streamlit can use the same DuckDB/model outputs if a Python-first app becomes useful.

## Current Data Build

The easiest local update path is now the refresh orchestrator:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile local-rebuild
```

From RStudio:

```r
source("R/20_refresh_all.R")
refresh_world_cup_data(profile = "local-rebuild")
```

To pull the free/no-key sources again:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh
```

After API keys are added to `.env`, keyed providers can be included with:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh --include-keyed-apis
```

Odds pulls that consume quota require the extra `--include-odds-quota` flag.

To refresh the free public data:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_raw_data.py --sources public wikimedia official-fifa
.\.venv\Scripts\python.exe scripts\build_public_processed_csv.py
```

Then load it into DuckDB from R/RStudio:

```r
source("R/01_build_duckdb.R")
source("R/06_data_inventory.R")
```

Use the rendered Quarto site for the current public data inventory and model summaries.

To pull free GDELT news metadata:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_news_gdelt.py --include-team-queries
```

Then reload DuckDB:

```r
source("R/01_build_duckdb.R")
```

## Data Storage

Raw pulls go under `data/raw/<timestamp>/`. Do not edit raw files. Feature tables and modeling datasets should go under `data/processed/` once we build them.

## Betting Note

This project is for statistical modeling and research. It will not guarantee profit. Use legal books only, track bankroll separately, and evaluate bets by expected value and calibration rather than vibes.
