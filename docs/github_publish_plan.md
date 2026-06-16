# GitHub Publishing Plan

This project is being structured so it can become a clean GitHub repository.

## What To Include

Commit:

- `README.md`
- `R/`
- `scripts/`
- `src/`
- `sql/`
- `docs/`
- `reports/`
- `data/seed/`
- `data/samples/`
- `.env.example`
- `.gitignore`
- `pyproject.toml`
- `world-cup-betting-model.Rproj`

Do not commit:

- `.env`
- `.venv/`
- `.r-lib/`
- `data/raw/`
- `data/processed/`
- API keys
- full raw API responses
- paid data

## Suggested GitHub Repository Name

```text
world-cup-2026-betting-model
```

## First Commit Commands

From the project folder:

```powershell
git init
git add README.md .gitignore .env.example pyproject.toml world-cup-betting-model.Rproj
git add R scripts src sql docs reports data/seed data/samples
git commit -m "Initial World Cup data and modeling scaffold"
```

Before pushing, render the first report:

```r
source("R/12_render_reports.R")
```

Then create an empty GitHub repo and follow GitHub's instructions to add the remote:

```powershell
git remote add origin https://github.com/YOUR_USERNAME/world-cup-2026-betting-model.git
git branch -M main
git push -u origin main
```

The repository includes a GitHub Actions workflow:

```text
.github/workflows/pages.yml
```

It publishes the static website from `docs/` to GitHub Pages. If Pages does not appear automatically after the first push, go to:

```text
GitHub repo > Settings > Pages > Build and deployment > Source: GitHub Actions
```

Then rerun the `Publish GitHub Pages` workflow from the Actions tab.

## Suggested README Sections

- Project goal.
- Current data sources.
- Reproducible setup.
- Data pipeline.
- First model.
- Limitations.
- Roadmap.

## Presentation Principle

The public repo should show:

- Clear math.
- Small sample data.
- Reproducible scripts.
- Honest limitations.
- No secrets.
- No large or copyrighted raw-data dumps.
