# Environment Status

Checked from Codex shell on 2026-06-16.

## Working

- Python base install: `C:\Users\14154\AppData\Local\Programs\Python\Python310\python.exe`
- Python version: 3.10.1
- Project virtual environment: `.venv/`
- Public data connection script: works with network permission.
- Public raw snapshot saved at: `data/raw/20260616T153114Z`
- R install: `C:\Program Files\R\R-4.1.1`
- R version: 4.1.1
- RStudio install: `C:\Program Files\RStudio\bin\rstudio.exe`
- RStudio project file: `world-cup-betting-model.Rproj`
- Project-local R library: `.r-lib/4.1.1`
- DuckDB database: `data/processed/world_cup.duckdb`
- R scripts tested:
  - `R/00_setup.R`
  - `R/01_build_duckdb.R`
  - `R/02_check_python_bridge.R`
  - `R/03_first_queries.R`

## Known Quirks

- `python` on PATH is still shadowed by WindowsApps aliases, so direct `python --version` fails from this shell.
- Use `.venv\Scripts\python.exe` for project scripts, or disable Windows Python app execution aliases in Windows Settings.
- `R` and `Rscript` are installed but not on PATH. RStudio should still find R.
- R 4.1.1 is old. Current project packages work, but package warnings say they were built under R 4.1.3.
- R 4.1.1 cannot call `.venv\Scripts\python.exe` directly via `system2()`, but it can call it through `cmd.exe`.
- `reticulate` works with the base Python install, not the project venv.

## Still Missing

- API keys:
  - `FOOTBALL_DATA_TOKEN`
  - `THE_ODDS_API_KEY`
  - optional `API_FOOTBALL_KEY`
- Optional Quarto install if you want `.qmd` notebooks rendered from RStudio.

## Recommended Next Step

Open `world-cup-betting-model.Rproj` in RStudio and run:

```r
source("R/03_first_queries.R")
```

Then get the free API keys one at a time, starting with football-data.org.

