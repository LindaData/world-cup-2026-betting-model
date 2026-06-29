# Codex Prompt: World Cup Static Site Render + Validation

Repo: `LindaData/world-cup-2026-betting-model`
Issue: `#8`
Priority: secondary. HVAC project remains higher priority.

## Mission
Validate and finish the static World Cup site readability cleanup that was merged in PR #7. Keep this project as a static Quarto/GitHub Pages report. Do not convert it into Shiny, Next.js, Streamlit, or a live API app.

## Hard constraints
- Public output must remain static GitHub Pages from `docs/`.
- No live browser API calls.
- No paid API keys in front-end code.
- Do not commit `.env`, `.Renviron`, credentials, private files, raw API feeds, or local caches.
- Use a small PR for fixes.
- Keep changes focused on render correctness, readability, and validation.

## First commands
Run from repo root.

```bash
git checkout main
git pull --ff-only
```

Inspect the recent static readability work:

```bash
git log --oneline -5
ls -la
ls -la R reports docs .github || true
```

## Environment setup
Prefer the existing project setup. Try these in order and adapt only as needed.

### R dependencies
```r
source("R/00_setup.R")
```

If package setup fails, install only missing packages required for render. Do not rewrite the dependency system unless necessary.

### Python environment
If the local `.venv` exists, use it. Otherwise create one.

Linux/macOS:
```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
```

Windows PowerShell:
```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
if (Test-Path requirements.txt) { pip install -r requirements.txt }
```

## Required validation before render
Check the override file parses.

```r
source("R/report_helpers.R")
source("R/matchday_components.R")
source("R/static_readability_overrides.R")
status_slug("Today")
status_slug("Upcoming")
status_slug("Pending score")
```

Expected:
- `today`
- `upcoming`
- `pending-score`

Check the Quarto source references the overrides:

```bash
grep -R "static_readability_overrides" -n index.qmd reports/08_matchday_predictions.qmd
```

## Render task
Render the site using the project’s preferred path.

Try:

```r
source("R/12_render_reports.R")
```

If that fails because the pipeline artifacts are stale/missing, run the local rebuild from the README, then render again.

Linux/macOS:
```bash
.venv/bin/python scripts/update_pipeline.py --profile local-rebuild --continue-on-error
```

Windows PowerShell:
```powershell
.\.venv\Scripts\python.exe scripts\update_pipeline.py --profile local-rebuild --continue-on-error
```

Then render again:

```r
source("R/12_render_reports.R")
```

## Required checks after render
Inspect generated files:

```bash
ls -lah docs/index.html docs/reports/08_matchday_predictions.html
```

Check for encoding bugs:

```bash
grep -R "â€™\|â€“\|â€œ\|â€\|Ã" -n docs/index.html docs/reports/08_matchday_predictions.html docs/reports/*.html || true
```

Expected: no matches.

Check bad status slug regression:

```bash
grep -R "status--" -n docs/index.html docs/reports/08_matchday_predictions.html || true
```

Expected: no matches.

Check static explanation exists:

```bash
grep -R "static" -n docs/index.html docs/reports/08_matchday_predictions.html | head -20
```

Expected: homepage and predictions page both explain the static/offline API setup.

Check no secrets are staged:

```bash
git status --short
git diff --stat
git diff -- . ':(exclude)data/raw/**' ':(exclude).env' ':(exclude).Renviron'
```

Also inspect for accidental secret-looking content:

```bash
grep -R "API_KEY\|SECRET\|TOKEN\|PASSWORD\|RAPIDAPI\|X-RapidAPI" -n docs R reports scripts config .github || true
```

If matches are only labels/documentation and not actual secrets, note that in the PR.

## Functional review
Open locally if possible:

```bash
python -m http.server 8000 -d docs
```

Review:
- `http://localhost:8000/`
- `http://localhost:8000/reports/08_matchday_predictions.html`
- `http://localhost:8000/reports/00_data_overview.html`

Confirm:
- Homepage is readable in under 30 seconds.
- Nav is simple: Home, Predictions, Bracket, Data, Methodology, GitHub.
- Today / Next Match / Upcoming do not show the same fixture unnecessarily.
- Forecast cards use `Forecast generated` instead of confusing refresh text.
- Bracket still loads.
- Data page still loads.
- Site remains usable on mobile width.

## Fix guidance
If render fails because of `R/static_readability_overrides.R`, fix that file first.

Likely things to check:
- Pipe operator availability.
- Function order after sourcing.
- Apostrophes in single-quoted HTML strings.
- Data frames with zero rows.
- Missing columns in older pipeline artifacts.

Keep fixes defensive and small.

## Commit and PR
Create a branch:

```bash
git checkout -b codex/worldcup-static-render-validation
```

After fixes and render:

```bash
git status --short
git add _quarto.yml index.qmd reports/08_matchday_predictions.qmd R/static_readability_overrides.R docs
# Add only files actually changed and safe to publish.
git commit -m "Validate World Cup static site render"
git push -u origin codex/worldcup-static-render-validation
```

Open a PR:

Title:
`Validate World Cup static site render`

PR body:
```md
Closes #8.

## Summary
- Ran the static World Cup Quarto render.
- Validated readability overrides and regenerated public docs.
- Confirmed no live API calls or secrets were added.

## Validation
- [ ] R setup completed
- [ ] Override file parsed
- [ ] Quarto render completed
- [ ] No mojibake found
- [ ] No bad `status--` classes found
- [ ] Homepage reviewed
- [ ] Predictions page reviewed
- [ ] No secrets/raw data committed

## Notes
HVAC remains the higher-priority project. This PR only validates the World Cup static report.
```

## Stop conditions
Stop and report instead of guessing if:
- Required source files are missing.
- The local data pipeline needs paid/private credentials not present in the environment.
- Render requires raw data that is intentionally excluded from the repo.
- You detect actual secrets staged for commit.

If blocked, leave a comment on issue #8 with the exact command, error, and smallest next step.
