# Local Update Workflow

This project can be refreshed locally before we push anything to GitHub.

The updater does four jobs:

1. Pulls fresh source data when requested.
2. Rebuilds processed CSVs and DuckDB tables.
3. Re-runs metadata exports and the baseline goals model.
4. Re-runs the ordinal win/draw/loss result model.
5. Copies shareable outputs into `docs/` for the eventual website.

## Safest First Run

Use this when you want to verify the pipeline without hitting the internet:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile local-rebuild
```

From RStudio:

```r
source("R/20_refresh_all.R")
refresh_world_cup_data(profile = "local-rebuild")
```

## Refresh Free Sources

Use this to pull free/no-key sources again:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh
```

From RStudio:

```r
source("R/20_refresh_all.R")
refresh_world_cup_data(profile = "free-refresh")
```

This refreshes:

- Public international match results and goalscorers.
- Openfootball World Cup files.
- Wikimedia/FIFA public World Cup pages and squad data.
- Wikidata player enrichment.
- Open-Meteo venue weather where available.
- GDELT news metadata.

PowerShell wrapper:

```powershell
.\scripts\run_update.ps1 -Profile free-refresh
```

## Add Keyed APIs Later

After you add keys to `.env`, run:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh --include-keyed-apis
```

This will call the keyed providers that are configured. It still avoids quota-consuming odds pulls.

To intentionally pull odds:

```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile free-refresh --include-keyed-apis --include-odds-quota
```

PowerShell wrapper:

```powershell
.\scripts\run_update.ps1 -Profile free-refresh -IncludeKeyedApis
.\scripts\run_update.ps1 -Profile free-refresh -IncludeKeyedApis -IncludeOddsQuota
```

## Run Logs

Each refresh creates a timestamped folder:

```text
data/processed/update_runs/
```

The latest run summary is also written to:

```text
data/processed/update_runs/latest.json
```

The public-facing status page is refreshed here:

```text
docs/current_data_status.md
```

## Scheduling Later

Once API keys are in place, we can schedule the same command with Windows Task Scheduler.
For now, manual refresh is better because it keeps quota and cloud costs under control.

The eventual scheduled command will look like this:

```text
powershell.exe -ExecutionPolicy Bypass -File scripts\run_update.ps1 -Profile free-refresh
```
