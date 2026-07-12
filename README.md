# LindaData World Cup 2026 Forecasting Hub

A LindaData project for World Cup 2026 forecasting, model review, and public-safe research presentation.

[Open live project](https://lindadata.github.io/world-cup-2026-betting-model/) · [Open repository](https://github.com/LindaData/world-cup-2026-betting-model)

![World Cup 2026 Forecasting Model preview](assets/social-preview.svg)

## Repository Layout

This repo is the consolidated home of the LindaData sports portfolio (see `MIGRATION.md` for the full map):

- **Repo root** — the World Cup 2026 forecasting engine: R models, Python data pipelines, DuckDB, and the Quarto site published to GitHub Pages from `docs/`.
- **`apps/web/`** — the consolidated React app (formerly `game-stat-pulse`, absorbing `lindadata-sports-hub`): World Cup fixtures/standings/live scores, NBA/MLB data, dataset review tooling, and a private betting desk gated behind `VITE_ENABLE_BETTING_DESK`. Deploys to Vercel.

## Project Role

This repo is part of the LindaData HQ portfolio. It should be treated as a product/research project, not as an isolated notebook.

Primary goal: one clean public hub for match probabilities, projected scores, bracket paths, champion outlook, post-match model review, and model documentation.

Current operating mode:

- Static GitHub Pages site served from `docs/`.
- Quarto source pages rendered from R helper components.
- Public-safe outputs only; raw datasets, credentials, private feeds, `.env`, and `.Renviron` stay out of the repo.
- Forecasting language stays educational/research-focused. Do not claim betting profit, sportsbook edge, or financial advice unless complete validated market inputs are added and approved.

## LindaData Org Routing

ChefHands / Sergio Mora is the project owner and final decision maker.

Executive routing:

- **Chief of Staff:** priority routing, morning review flow, task sequencing.
- **CDO:** data sources, features, model outputs, validation, and model promotion rules.
- **CTO:** Quarto site, GitHub Pages, repo hygiene, links, mobile UX, and automation.
- **COO:** operating workflow, refresh cadence, issue flow, release readiness.
- **CSO / CIO:** public-safety controls, credentials, source exposure, and access hygiene.
- **CMO / PRO:** public explanation, concise copy, project positioning, and responsible-use framing.
- **CFO:** cost control. Prefer free/static infrastructure unless the owner approves paid services.

See `AGENTS.md` for detailed agent routing.

## Main User Paths

The homepage is now organized as a command center:

1. **Predictions** — current match cards, probabilities, projected score, and pick.
2. **Bracket** — tournament path and champion outlook.
3. **Model Review** — completed-match grading and calibration watch areas.
4. **Coverage** — public-safe data-source summary.
5. **Model Lab** — challenger model comparison before promotion.
6. **GitHub** — source, docs, pull requests, and project governance.

## Key Outputs

- Match forecasts with win/draw/loss or advance probabilities.
- Projected scores and expected goals.
- Tournament bracket projection.
- Champion simulation summary.
- Post-match model accuracy and failure-mode review.
- Challenger model bench and diagnostics.
- Public-safe data coverage notes.

## Technology Stack

- **R / Quarto:** modeling reports, UI helpers, and static site rendering.
- **Python:** source refreshes, orchestration, and pipeline tasks.
- **SQL / DuckDB:** local analytical storage and model-ready joins.
- **GitHub Pages:** public static deployment from `docs/`.

## Reproduction

Open `world-cup-betting-model.Rproj` in RStudio.

Install or refresh local R dependencies:

```r
source("R/00_setup.R")
```

Rebuild local data/model outputs from existing processed files:

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

## UI/UX Rules

- Mobile-first.
- Forecasts first, diagnostics second.
- Use short labels and clear calls to action.
- Keep the LindaData HQ link visible.
- Use the public command-center pattern from `R/lindadata_project_ui.R` and `assets/lindadata-ui.css`.
- Keep generated `docs/index.html` aligned with `index.qmd` when changing the homepage.

## Security

The public site is static and does not have login, user accounts, or application-level SSO.

Security controls for this repo should be handled through GitHub:

- Enable two-factor authentication on the GitHub account or organization.
- Store API keys only in GitHub Actions secrets or local private env files.
- Never commit raw provider exports, credentials, `.env`, `.Renviron`, or private recordings.
- Keep Pages deployment scoped to generated public files.
- Use Dependabot or manual review for dependency updates.

See [SECURITY.md](SECURITY.md) for the repository security policy.

## Local Film Study

Local film-study tools are for private review of video files the owner has the right to analyze. Captures should stay local under private data paths and should not be committed.

## Current Priority

Maintain this as a clean LindaData project hub while keeping the HVAC project as the broader current company priority unless the owner explicitly changes priority.
