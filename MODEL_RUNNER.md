# LindaData World Cup Model Runner

## What This Adds

The repo can run the World Cup model pipeline without Codex by using GitHub Actions as the execution layer.

Workflow:

```text
.github/workflows/lindadata-run-world-cup-models.yml
```

Public-safe cache:

```text
data/public/
```

Output publisher:

```text
scripts/publish_public_model_outputs.py
```

## Operating Model

| LindaData owner | Responsibility |
|---|---|
| CDO | Model quality, backtesting, calibration, and model promotion gates. |
| CTO | GitHub Actions runner, Python/R dependencies, Quarto render, and Pages output. |
| COO | Schedule, manual runs, morning review flow, and stale-data triage. |
| CIO / CSO | Secrets, private/public boundary, and prevention of raw/private data commits. |

## Data Strategy

### Stored in GitHub

`data/public/` stores only public-safe model outputs copied from allowlisted processed folders:

- `data/processed/modeling/*.csv`
- `data/processed/modeling/*.json`
- `data/processed/metadata/*.csv`
- `data/processed/metadata/*.json`
- `docs/current_data_status.md`

The cache intentionally excludes raw snapshots, credentials, local/private files, DuckDB databases, model binaries, RDS files, UBJ files, pickle files, and private film-study outputs.

### Stored in GitHub Secrets

Provider keys belong in GitHub repository secrets, not committed files:

- `FOOTBALL_DATA_TOKEN`
- `THE_ODDS_API_KEY`
- `API_FOOTBALL_KEY`
- optional: `API_SPORTS_KEY`

Non-secret provider settings can be stored as GitHub repository variables:

- `API_FOOTBALL_HOST`
- `API_FOOTBALL_WORLD_CUP_LEAGUE_ID`
- `API_FOOTBALL_SEASON`
- `FOOTBALL_DATA_WORLD_CUP_COMPETITION`
- `FOOTBALL_DATA_SEASON`
- `ODDS_API_SPORT_KEY`
- `ODDS_REGIONS`
- `ODDS_MARKETS`
- `ODDS_ODDS_FORMAT`

## How To Run Without Codex

1. Open the GitHub repo.
2. Go to **Actions**.
3. Select **LindaData Run World Cup Models**.
4. Click **Run workflow**.
5. Keep the default `free-refresh` profile for no-key/public data refresh.
6. Turn on `include_keyed_apis` only after the provider secrets are configured.
7. Leave `include_odds_quota` off unless you intentionally want to spend Odds API quota.
8. Keep `commit_outputs` on when the run should publish `docs/` and `data/public/` back to `main`.

## Runner Behavior

The workflow:

1. checks out the repo;
2. installs Python, R, Quarto, and required packages;
3. runs `scripts/update_pipeline.py`;
4. runs `scripts/publish_public_model_outputs.py`;
5. uploads diagnostics as a 14-day artifact;
6. commits rendered `docs/` and public-safe `data/public/` outputs when the model run succeeds.

## Safety Rules

Do not commit:

- `.env` or `.Renviron`;
- API tokens or provider credentials;
- `data/raw/` snapshots;
- `data/private/` files;
- full DuckDB databases;
- paid API raw payloads;
- local film-study recordings, tags, or clips.

The public website should stay a summary and review surface, not a raw data warehouse.
