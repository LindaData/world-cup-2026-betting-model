# Windows Setup Guide

This project can stay free or very cheap.

## What Is Already Installed

- Git: installed at `C:\Program Files\Git\cmd\git.exe`
- curl: installed at `C:\Windows\System32\curl.exe`

## Current Status

- Python base install works at `C:\Users\14154\AppData\Local\Programs\Python\Python310\python.exe`.
- Project `.venv` exists and works for project Python scripts.
- R 4.1.1 is installed at `C:\Program Files\R\R-4.1.1`.
- RStudio is installed at `C:\Program Files\RStudio\bin\rstudio.exe`.
- DuckDB is installed into the project-local `.r-lib/4.1.1`.
- Public raw data has been downloaded into `data/raw/`.
- DuckDB database has been created at `data/processed/world_cup.duckdb`.

## What Is Still Missing Or Weird

- Python: `python` on PATH is still shadowed by broken WindowsApps aliases. Use `.venv\Scripts\python.exe` or disable the aliases.
- R/Rscript: not on PATH from this shell. If RStudio works for you, this is not urgent.
- Quarto: optional, not currently on PATH.
- VS Code: optional, not currently on PATH.
- API keys: optional until we start authenticated data pulls.

## Step 1: Install Python

Cost: free.

1. Go to https://www.python.org/downloads/windows/
2. Download the latest stable **Windows installer (64-bit)** for Python 3.13.
3. Run the installer.
4. On the first installer screen, check **Add python.exe to PATH**.
5. Choose **Install Now**.
6. Close and reopen PowerShell.
7. Verify:

```powershell
python --version
python -m pip --version
```

If both commands print versions, Python is fixed.

## Step 2: Create A Virtual Environment

From the project folder:

```powershell
cd C:\Users\14154\Documents\Codex\2026-06-16\i-want-to-build-a-model
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

If PowerShell blocks activation, run this once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Then try:

```powershell
.\.venv\Scripts\Activate.ps1
```

## Step 3: Open The RStudio Project

Cost: free if you already have RStudio. R and RStudio are both free.

1. Open RStudio.
2. Choose **File > Open Project...**
3. Open:

```text
C:\Users\14154\Documents\Codex\2026-06-16\i-want-to-build-a-model\world-cup-betting-model.Rproj
```

4. In the RStudio Console, run:

```r
source("R/00_setup.R")
```

This installs free CRAN packages used by the R side of the project.
Packages are installed into the project-local `.r-lib/` folder, which keeps this project isolated from your global R setup.

## Step 4: Run The Free Public Data Check

No API keys needed:

```powershell
python scripts\check_connections.py
python scripts\fetch_raw_data.py --sources public
```

This should create a timestamped folder under `data\raw\`.

Then go back to RStudio and run:

```r
source("R/01_build_duckdb.R")
source("R/03_first_queries.R")
```

This creates the local SQL database at `data\processed\world_cup.duckdb`.

You can also trigger the free public Python pull from inside RStudio:

```r
source("R/04_fetch_public_data_from_rstudio.R")
```

On this machine, `reticulate` works with the base Python install. R can run the project `.venv` through `cmd.exe`, but direct `system2()` calls to `.venv\Scripts\python.exe` fail under R 4.1.1.

## Step 5: Create Free API Accounts

Add keys one at a time. Do not pay for anything yet.

### football-data.org

Cost: free tier available.

1. Go to https://www.football-data.org/client/register
2. Create a free account.
3. Copy the API token.
4. Copy `.env.example` to `.env`:

```powershell
Copy-Item .env.example .env
```

5. Open `.env` and set:

```text
FOOTBALL_DATA_TOKEN=your_token_here
```

6. Test:

```powershell
python scripts\check_connections.py
python scripts\fetch_raw_data.py --sources football-data
```

### The Odds API

Cost: free starter tier available. Use it carefully because odds calls consume credits.

1. Go to https://the-odds-api.com/
2. Create a free starter account.
3. Copy the API key.
4. In `.env`, set:

```text
THE_ODDS_API_KEY=your_key_here
```

5. First test only sport discovery:

```powershell
python scripts\check_connections.py
```

6. Pull odds only when you intentionally want to spend quota:

```powershell
python scripts\fetch_raw_data.py --sources odds --include-quota-odds
```

### API-Football

Cost: optional free tier available. Skip this until we know football-data.org and The Odds API are insufficient.

1. Go to https://www.api-football.com/pricing
2. Use the free plan only.
3. Add the key to `.env`:

```text
API_FOOTBALL_KEY=your_key_here
```

4. Test:

```powershell
python scripts\check_connections.py
```

## Step 6: Optional Editor

VS Code is optional, but useful and free.

1. Go to https://code.visualstudio.com/download
2. Download the Windows User Installer.
3. During install, choose **Add to PATH** if offered.
4. Reopen PowerShell.
5. Verify:

```powershell
code --version
```

## Budget Recommendation

Start with:

- Python: free
- Git: already installed
- VS Code: free, optional
- Openfootball and martj42 historical results: free public files
- Open-Meteo: free for non-commercial prototyping
- football-data.org: free tier
- The Odds API: free starter tier
- API-Football: free optional fallback

Do not buy paid plans until the free stack fails a specific modeling need.
