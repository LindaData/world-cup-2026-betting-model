# World Cup 2026 Forecasting Model

A reproducible forecasting system that produces match probabilities, projected scores, champion probabilities, tournament paths, and post-match model evaluation.

[View live forecasts](https://lindadata.github.io/world-cup-2026-betting-model/)

![World Cup 2026 Forecasting Model preview](assets/social-preview.svg)

## Current Status

The public site is a static Quarto website built from local model outputs. The prediction board refreshes from the existing data pipeline and publishes summarized results to GitHub Pages. Raw data, API keys, credentials, and private files are intentionally excluded from the public site.

## Key Outputs

- Today's match forecasts with win, draw, and loss probabilities.
- Next-match forecast with projected score and expected goals.
- Upcoming match cards with accessible one-tap details.
- Interactive tournament bracket seeded from current projections.
- Champion outlook from tournament-path simulations.
- Post-match model accuracy table.
- Technical model reports for methodology review.

## Technology Stack

- **R / RStudio:** modeling, reporting, Quarto rendering, Shiny prototype work.
- **Python:** API clients, source refreshes, data snapshots, orchestration.
- **SQL / DuckDB:** local analytical storage, joins, model-ready tables.
- **Quarto:** static website generation for GitHub Pages.
- **GitHub Actions:** scheduled refresh and site publication.

## Model Overview

The public forecast currently combines:

- **Win / draw / loss model:** an ordinal logistic model for three-outcome match probabilities.
- **Goals forecast:** a Poisson goals model used to estimate expected goals and scoreline probabilities.
- **OLS benchmark:** a simple linear goals model kept as an interpretable baseline.
- **Similar match model:** a KNN-style challenger that compares fixtures with similar historical team-match rows.
- **Champion simulation:** a tournament-path layer that reuses current fixture probabilities and strength signals to estimate title odds. It defaults to 50,000 simulations and reports Monte Carlo uncertainty.
- **Expanded challenger suite:** Poisson, quasi-Poisson, negative binomial, zero-aware, GAM, tree, random forest, ordinal, multinomial, and regularized classifier comparisons are fit on historical train/test splits before any promotion into the public forecast.
- **Expanded feature population:** local R scripts build rolling form, opponent form, head-to-head, rest, team-experience, and tournament-context features across the historical team-match population.
- **Distribution diagnostics:** Bernoulli, binomial, Poisson, geometric, uniform, normal, exponential, gamma, beta, t, chi-squared, and F checks are mapped to soccer modeling targets with fit diagnostics and autocorrelation tests.

The match models are trained on historical data and evaluated on held-out test splits. The champion simulation is downstream of those match forecasts: more simulations reduce simulation noise, while train/test validation measures predictive quality. The site presents consumer-facing predictions first. Technical diagnostics remain available under Methodology.

## Data Sources

The workflow uses model-ready summaries from:

- Historical international match results and goalscorer records.
- Derived team-strength and recent-form features.
- 2026 fixture, venue, and kickoff-time references.
- Weather context from open weather sources.
- News metadata where available.
- API-Football enrichment layers when the account and endpoint coverage permit.

The public site does not publish raw datasets, `.env`, `.Renviron`, API keys, credentials, or private files.

## Reproduction

Open `world-cup-betting-model.Rproj` in RStudio.

Install or refresh the local project dependencies:

```r
source("R/00_setup.R")
```

Rebuild the local database and reports from existing processed files:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile local-rebuild
```

Refresh public/free data sources, rebuild models, and render the site:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh --continue-on-error
```

Render only the Quarto website:

```r
source("R/12_render_reports.R")
```

The rendered static site is written to `docs/`.

## Production Features

- Prediction-first homepage.
- Mobile-friendly Predictions page.
- Browser-local kickoff times with UTC fallback.
- Accessible match details using native disclosure controls.
- Interactive bracket with mobile round tabs.
- Champion probability section.
- Post-match model review.
- SEO metadata, sitemap, robots file, structured data, and social preview assets.
- GitHub Pages publication from `docs/`.

## SEO And Sharing

The public site includes:

- Canonical URLs generated from the configured GitHub Pages URL.
- Page descriptions, Open Graph tags, Twitter card metadata, and a PNG social preview.
- `robots.txt` and `sitemap.xml` for crawler discovery.
- JSON-LD structured data describing the website, source repository, and public summary dataset.
- A web manifest and theme color for consistent browser presentation.

The public pages intentionally avoid exposing raw datasets, credentials, private API responses, or internal pricing notes.

## Security And SSO

The forecast site is a static GitHub Pages website and does not have a login surface, user accounts, or application-level SSO.

Security controls for this repo should be handled through GitHub:

- Enable two-factor authentication on the GitHub account or organization.
- Require SAML/SSO only if the repo moves under a GitHub Enterprise organization that supports it.
- Store API keys only in GitHub Actions secrets.
- Keep Pages deployment scoped to the `github-pages` environment.
- Use Dependabot to track GitHub Actions updates.

See [SECURITY.md](SECURITY.md) for the repository security policy.

## Prototype Features

- Live lineup and card projections depend on provider coverage.
- API odds and market-comparison scaffolding exist, but market edge is not presented as operational unless complete odds inputs are available.
- Multi-sport expansion is documented as a roadmap, not part of the primary World Cup navigation.
- Local film-study tagging is available for user-supplied video files and exports private CSV tags for downstream modeling.

## Local Film Study

Use the local Python tagger for private match review on video files you already have the right to analyze:

If you want to capture a local screen region directly into the workflow, install the film-study extras first:

```powershell
py -m pip install -e .[filmstudy]
```

Then start a private local capture from RStudio or PowerShell. The capture stays on your laptop, writes into `data/private/recordings/`, and then registers the saved file for tagging and downstream analysis.

To inspect the available monitors first:

```r
source("R/28_film_study_workflow.R")
list_capture_monitors()
```

To save a reusable capture profile:

```r
source("R/28_film_study_workflow.R")

create_capture_profile(
  profile_name = "peacock-main-window",
  select_region = TRUE
)
```

After that, you can reuse the same region without drawing it again:

```r
source("R/38_capture_and_process_film_study_session.R")

capture_and_process_film_study_session(
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden",
  profile_name = "peacock-main-window",
  select_region = FALSE,
  quality_profile = "archive"
)
```

From PowerShell:

```powershell
.\.venv\Scripts\python.exe scripts\capture_film_study_screen.py --match-key wc2026-49483 --home-team France --away-team Sweden --select-region --quality-profile archive
```

From RStudio:

```r
source("R/28_film_study_workflow.R")

capture_film_study_screen(
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden",
  select_region = TRUE,
  quality_profile = "archive"
)
```

That opens a region selector, records the selected area until you press `q`, saves the file, and immediately registers it into the film-study catalog. `archive` uses MJPG AVI for higher quality. `compact` uses MP4 for smaller files.

If you want to test the same capture-registration path without live screen capture, you can import a local sample video through the recorder:

```r
source("R/28_film_study_workflow.R")

capture_film_study_screen(
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden",
  mock_video = "C:/path/to/local-sample.mp4"
)
```

That writes the sample into `data/private/recordings/`, creates a capture manifest, and registers it exactly like a recorded session. It is useful for validating the workflow when desktop capture is unavailable.

To generate a local tagger preset template before review:

```r
source("R/28_film_study_workflow.R")

create_tagger_preset_template(
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden"
)
```

That writes a JSON template in `data/private/tagger_presets/`. The tagger will use it automatically when the file name matches the `match_key`. During tagging, `h` and `a` can be used in the Team prompt for home and away, and blank values fall back to the most recent tagged values.

If you want one end-to-end session from capture through tagging and model-ready outputs:

```r
source("R/38_capture_and_process_film_study_session.R")

capture_and_process_film_study_session(
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden",
  select_region = TRUE,
  quality_profile = "archive"
)
```

That workflow:

1. lets you select the screen region
2. records the local video
3. creates a local tagger preset template for the match
4. opens the tagger when recording stops
5. rebuilds the film-study datasets after tagging
6. refreshes clips, DuckDB, private reports, state-engine outputs, and a per-match export bundle

Session exports now carry explicit readiness states:

- `captured_ready_for_review`: video metadata and quality audit exist
- `ready_for_annotation`: capture manifest and tagger preset are in place
- `analysis_ready`: tags have been created and the private analysis outputs can be rebuilt from them

If you want a quick non-interactive smoke test from RStudio before a real session:

```r
source("R/38_capture_and_process_film_study_session.R")

capture_and_process_film_study_session(
  match_key = "smoke-test-001",
  home_team = "Home",
  away_team = "Away",
  region = c(0, 0, 320, 180),
  select_region = FALSE,
  max_seconds = 2,
  no_preview = TRUE,
  launch_tagger = FALSE,
  skip_previews = TRUE,
  quality_profile = "compact"
)
```

That is useful for proving the local desktop capture path works before you run a longer real review session.

To validate that the local setup is ready on this laptop:

```r
source("R/39_validate_film_study_setup.R")
validate_local_film_study_setup()
```

Or from PowerShell:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File scripts\run_project_python.ps1 scripts\validate_film_study_setup.py
```

To validate setup and launch the private Shiny workbench in one step:

```powershell
.\scripts\start_film_study_workbench.ps1
```

To start a real capture session from PowerShell without opening RStudio first:

```powershell
.\scripts\start_film_study_capture_session.ps1 -MatchKey "wc2026-49483" -HomeTeam "France" -AwayTeam "Sweden"
```

Or reuse a saved profile:

```powershell
.\scripts\start_film_study_capture_session.ps1 -MatchKey "wc2026-49483" -HomeTeam "France" -AwayTeam "Sweden" -ProfileName "peacock-main-window"
```

First register the local video and extract its metadata:

```powershell
.\.venv\Scripts\python.exe scripts\prepare_film_study_session.py --video "C:\path\to\match.mp4" --match-key wc2026-49483 --home-team France --away-team Sweden
```

That writes private video metadata to `data/private/video_library/` and generates preview stills plus a contact sheet for quick review.

To register the file and open the tagger immediately:

```powershell
.\.venv\Scripts\python.exe scripts\prepare_film_study_session.py --video "C:\path\to\match.mp4" --match-key wc2026-49483 --home-team France --away-team Sweden --launch-tagger
```

Or launch the tagger directly:

```powershell
.\.venv\Scripts\python.exe scripts\video_tagger.py --video "C:\path\to\match.mp4" --match-key wc2026-49483 --home-team France --away-team Sweden
```

That writes private tag files to `data/private/film_tags/`.

If your local recorder saves files into one folder, you can point the workflow at that folder and let it grab the newest file:

```powershell
.\.venv\Scripts\python.exe scripts\ingest_latest_local_video.py --source-dir "C:\path\to\video-folder" --match-key wc2026-49483 --home-team France --away-team Sweden --launch-tagger
```

If you want the project to wait for the next saved local video and register it as soon as it appears:

```powershell
.\.venv\Scripts\python.exe scripts\watch_for_next_video.py --source-dir "C:\path\to\video-folder" --match-key wc2026-49483 --home-team France --away-team Sweden --launch-tagger
```

To combine all local tag files into one model-ready table:

```powershell
.\.venv\Scripts\python.exe scripts\build_film_study_dataset.py
```

To generate analysis-ready outputs from those tags:

```powershell
.\.venv\Scripts\python.exe scripts\build_film_study_features.py
```

That creates:

- `data/processed/film_study/film_study_events_enriched.csv`
- `data/processed/film_study/film_study_possessions.csv`
- `data/processed/film_study/film_study_match_features.csv`
- `data/processed/film_study/film_study_zone_summary.csv`
- `data/processed/film_study/film_study_event_transitions.csv`
- `data/processed/film_study/film_study_feature_metadata.json`

To extract short clips around tagged events from your local video file:

```powershell
.\.venv\Scripts\python.exe scripts\extract_film_study_clips.py --seconds-before 3 --seconds-after 4
```

To load the local film-study outputs into DuckDB for SQL and R analysis:

```powershell
.\.venv\Scripts\python.exe scripts\build_film_study_duckdb.py
```

You can run the same workflow from RStudio:

```r
source("R/28_film_study_workflow.R")

prepare_film_session(
  video = "C:/path/to/match.mp4",
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden",
  launch_tagger = TRUE
)

ingest_latest_local_video(
  source_dir = "C:/path/to/video-folder",
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden"
)

refresh_film_study_analysis()

extract_film_study_clips(event_types = c("shot", "goal"))

build_film_study_duckdb()
```

The feature layer uses explicit heuristics, not full tracking data. Possessions are split when the tagged team changes, a long gap occurs, or a terminal event ends the sequence. Screen click coordinates are kept as tagged percentages and should only be interpreted as spatial football zones if you tag consistently.

Render the private HTML review report from RStudio:

```r
source("R/29_render_film_study_review.R")
render_film_study_review()
```

Launch the local Shiny control surface from RStudio:

```r
source("R/30_launch_film_study_app.R")
launch_film_study_app()
```

Fit the private film-study models and render the modeling report:

```r
source("R/31_fit_film_study_models.R")
fit_film_study_models()

source("R/32_render_film_study_modeling_report.R")
render_film_study_modeling_report()
```

Run the full local film-study pipeline in one command:

```r
source("R/34_process_film_study_session.R")

process_film_study_session(
  source_dir = "C:/path/to/video-folder",
  match_key = "wc2026-49483",
  home_team = "France",
  away_team = "Sweden"
)
```

## Planned Features

- Stronger calibration reporting as the tournament sample grows.
- Automated stale-data warning thresholds.
- More complete lineups, injuries, cards, and odds ingestion where paid API coverage justifies the cost.
- Optional Shiny or Streamlit app for interactive private analysis.

## Limitations

Forecasts are probabilistic. Completed 2026 match samples are small early in the tournament, so current-tournament accuracy should be treated as monitoring evidence, not proof. Some enrichment layers are unavailable until API providers publish the records or the account tier supports the endpoint.

## Responsible Use

This project is for statistical modeling, education, and research. It does not guarantee match outcomes or betting profit. Do not treat the site as financial advice, and always verify official match information before acting on a forecast.
