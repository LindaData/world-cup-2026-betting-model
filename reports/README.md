# Reports

These reports are written for RStudio and can be rendered with `rmarkdown`.

## Available Reports

| Report | Purpose |
| --- | --- |
| `01_goals_linear_regression.Rmd` | First real-data modeling walkthrough using goals as the target. |

## Render From RStudio

```r
source("R/12_render_reports.R")
```

If rendering manually outside RStudio, set `RSTUDIO_PANDOC` first:

```r
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/bin/pandoc")
rmarkdown::render("reports/01_goals_linear_regression.Rmd")
```
