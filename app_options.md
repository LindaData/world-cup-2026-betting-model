# App Options: Shiny vs Streamlit

## Current Readiness

Shiny is the smoother first app path on this computer.

Installed R pieces:

- `shiny`
- `bslib`
- `DT`
- `plotly`
- `ggplot2`
- `dplyr`
- `DBI`
- `duckdb`

Missing optional R pieces:

- `rsconnect`, only needed for deploying Shiny to shinyapps.io or Posit Connect.
- `ordinal` or `VGAM`, useful for ordinal logistic regression alternatives.
- `tidymodels`, useful later but not required for a first model.

Streamlit is not ready yet because the project Python virtual environment is intentionally minimal.

Missing Python app packages:

- `streamlit`
- `duckdb`
- `pandas`
- `plotly`
- `altair`
- `scikit-learn`

## Recommended Path

Start with Shiny because you already work mostly in R/RStudio and the required packages are mostly installed.

Use DuckDB as the shared backend:

```text
data/processed/world_cup.duckdb
```

That lets us build a Shiny app first and still build a Streamlit app later without changing the data layer.

## App Roadmap

1. Build a Shiny dashboard that reads from DuckDB.
2. Add tabs for fixtures, team form, odds snapshots, and model probabilities.
3. Start with a simple ordinal/logistic baseline.
4. Add probability calibration and betting-market comparison.
5. Only then decide whether Streamlit adds anything useful.

## Commands

Check app readiness from RStudio:

```r
source("R/05_check_app_readiness.R")
```

Install optional Shiny deployment package:

```r
install.packages("rsconnect", repos = "https://cloud.r-project.org")
```

Install Python packages for Streamlit later:

```powershell
.\.venv\Scripts\python.exe -m pip install streamlit duckdb pandas plotly altair scikit-learn
```

