# Repo Consolidation — Migration Map

This repository is becoming the single home for the four LindaData sports
repos. The R/Python/Quarto forecasting engine at the repo root is unchanged;
the React frontends are consolidated into `apps/web/`.

## Where everything went

| Old repo | Role | Destination |
|---|---|---|
| `world-cup-2026-betting-model` | Forecasting engine, data pipelines, Quarto site | This repo, unchanged (root: `R/`, `scripts/`, `src/wc_model/`, `sql/`, `reports/`, `docs/`) |
| `game-stat-pulse` | Data-approval portal, DuckDB explorer, quant libs (edge/Kelly, model audit, bankroll ledger), Python data-lake pipeline | `apps/web/` (full app), workflows preserved read-only in `apps/web/.github-reference/` |
| `lindadata-sports-hub` | Mobile viewer for Football/NBA/MLB | Football page + football data contract ported into `apps/web/` (`src/pages/Football.tsx`, `src/lib/football.ts`); the rest was duplicate scaffold |
| `game-stat-lab` | Mock-data research-console UI concept | Design reference only; nothing ported (all data was static samples) |

## What changed in the consolidated app (`apps/web/`)

- **Football is the landing page** (`/`): World Cup 2026 fixtures, group
  standings (P/W/D/L/GD/Pts columns), and a live-scores slot. NBA/MLB pages
  unchanged at `/nba` and `/mlb`.
- **Betting desk is private**: `/desk`, `/edge`, `/portfolio`, `/bankroll`
  only exist when `VITE_ENABLE_BETTING_DESK=true` (always on in local dev).
  Public builds ship predictions and data tooling only. Model audit (`/model`)
  stays public — it is validation, not staking.
- **Deploys to Vercel** from the domain root (`vercel.json`; set the Vercel
  project Root Directory to `apps/web`). GitHub Pages continues to serve the
  Quarto reports site from `docs/` unchanged. Set `VITE_BASE` for subpath
  hosting.
- Branding updated from "Game Stat Pulse" to LindaData Sports.

## Football feed fix (was broken)

`publish-api-football.yml` had failed on every run since it was added:
API-Football's free plan does not cover season 2026, so
`football_fixtures.json` / `football_standings.json` / `football_manifest.json`
were never published, and the sports-hub Football page always rendered empty.

The workflow now runs `scripts/publish_football_espn.py` — the same keyless
ESPN API the NBA/MLB live scoreboards already use — as the primary source,
with API-Football as an optional enrichment step when a working key is
present. `fetch_live_scoreboards.py` also now publishes `football_live.json`
(World Cup live scores) every 30 minutes.

## Cutover plan (do not rush before the final)

The World Cup final is 2026-07-19. All live crons run from `main` and are
untouched by this branch until merge.

1. Merge this PR → football feed starts publishing, `apps/web` exists in the
   monorepo. Nothing else changes; old repos keep working.
2. Create the Vercel project (Root Directory `apps/web`, Bun install/build,
   optional `VITE_ENABLE_BETTING_DESK=true` on a separate private/preview
   deployment).
3. After the final: archive `game-stat-pulse`, `game-stat-lab`, and
   `lindadata-sports-hub` (read-only), leaving pointer notices in each.
4. Optionally rename this repo (GitHub redirects old URLs automatically,
   including the raw.githubusercontent.com data URLs the app fetches).

## Not migrated (deliberately)

- `game-stat-pulse` browser localStorage records (approvals, ledger entries)
  — they live in the browser, not the repo; export to CSV from the old
  deployment if worth keeping.
- The film-study subsystem stays at the repo root as-is; splitting or
  dropping it is a separate decision.
- Old GitHub Pages frontend deployments stay live until the repos are
  archived.
