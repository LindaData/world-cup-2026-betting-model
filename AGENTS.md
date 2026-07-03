# LindaData Agent Routing — World Cup 2026 Forecasting Hub

This repo follows the LindaData organization. Treat all work as part of the LindaData HQ system.

## Owner

**ChefHands / Sergio Mora** is the final decision maker.

## Executive Routing

| Executive lane | Owns | Default work |
|---|---|---|
| Chief of Staff | Priorities and coordination | Convert owner feedback into ordered tasks; keep work aligned to LindaData HQ. |
| CDO | Data and modeling | Source refreshes, features, model training, validation, champion simulation, promotion rules. |
| CTO | Engineering and UI | Quarto, GitHub Pages, generated `docs/`, link health, mobile UX, repo structure. |
| COO | Operating process | Release readiness, refresh workflow, issue hygiene, handoffs, project cadence. |
| CSO / CIO | Security and information controls | Public-safe output, secrets, private data, repo exposure, credential handling. |
| CMO / PRO | External story | Clear public copy, responsible-use framing, social preview, project positioning. |
| CFO | Cost | Keep infrastructure free/static unless the owner approves paid services. |

## Non-Negotiables

- Keep the site public-safe.
- Do not commit raw data, credentials, `.env`, `.Renviron`, private provider exports, or private recordings.
- Keep the homepage mobile-first and easy to scan on iPhone.
- Forecasts first; technical diagnostics second.
- Do not make betting-profit or sportsbook-edge claims without complete validated market inputs and owner approval.
- When changing the homepage, update both source and live artifact:
  - `index.qmd`
  - `R/lindadata_project_ui.R` if helper structure changes
  - `assets/lindadata-ui.css` if styling changes
  - `docs/index.html` for GitHub Pages output
  - `docs/assets/lindadata-ui.css` if rendered CSS changes

## Current Site Architecture

- Quarto source: `index.qmd` and `reports/*.qmd`
- UI helpers: `R/matchday_components.R`, `R/static_readability_overrides.R`, `R/lindadata_project_ui.R`
- Main CSS: `styles.css`
- LindaData UI CSS: `assets/lindadata-ui.css`
- Live static output: `docs/`
- Public homepage artifact: `docs/index.html`

## Workflows By Agent Lane

### CDO / Data Pod

Use this lane for:

- Model input review
- Fixture/result refreshes
- Feature engineering
- Train/test validation
- Score-grid, result-model, and champion-simulation logic
- Challenger promotion decisions

Required standard:

- Separate current-tournament small-sample monitoring from historical validation.
- Preserve uncertainty language.
- Explain what changed in plain English.

### CTO / Engineering Pod

Use this lane for:

- Homepage and report UI
- Quarto rendering
- GitHub Pages structure
- Broken links
- Mobile UX
- Accessibility
- Static assets

Required standard:

- Preserve existing links unless intentionally changing navigation.
- Test link paths relative to GitHub Pages.
- Keep pages readable without JavaScript where possible.

### COO / Project Ops

Use this lane for:

- Release checklist
- Task sequencing
- Issue triage
- Branch/PR readiness
- Owner review package

Required standard:

- Summarize changes by user impact.
- State what is ready to review.
- Avoid long technical explanations unless requested.

### CSO / CIO

Use this lane for:

- Secrets review
- Public/private data split
- Security notes
- Repo hygiene
- Access/control concerns

Required standard:

- Block any commit that exposes credentials, private data, or raw restricted feeds.
- Prefer static public pages for this project.

### CMO / PRO

Use this lane for:

- Public project language
- SEO/social framing
- Responsible-use notes
- Short copy improvements

Required standard:

- Clear, concise, research-first language.
- No hype that overstates model certainty.

## Default Pull Request Checklist

Before merging:

- Homepage opens from `docs/index.html`.
- Primary links work:
  - Predictions
  - Bracket
  - Model Review
  - Coverage
  - Model Lab
  - GitHub
  - LindaData HQ
- Public copy does not expose private feeds or credentials.
- Mobile layout stacks cleanly.
- README and `AGENTS.md` stay aligned with the org.

## Owner Communication Style

- Be brief.
- Give links and exact status.
- Talk numbers and outcomes.
- Do the work when permissions are available.
- Ask only when a real decision is blocked.
