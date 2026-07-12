# Game Stat Pulse

Game Stat Pulse is a mobile-first sports-data approval portal. Its current job is to let a domain reviewer inspect the collected data structure before any predictive model is built.

## Current review workflow

1. Pushes to `main` deploy only the browser app to GitHub Pages.
2. The dedicated data-lake workflow reads `API_FOOTBALL_KEY` from repository secrets when it is manually dispatched or run by schedule.
3. `scripts/fetch_api_football.py` calls the configured API-Football endpoints.
4. Every discovered field is retained in the normalized schema.
5. The generated build is uploaded as the `modeling-data-lake-build` Actions artifact, with optional R2 publishing when R2 secrets are configured.
6. The public app loads an R2 catalog when `public/data-source.json` points at one; otherwise it uses the browser fallback catalog.
7. A reviewer can approve the dataset, request changes, add notes, and export the decision log as CSV.
8. Models remain intentionally locked until the data is approved.

The API key is never sent to the browser or committed to the repository.

## Architecture

- **Frontend:** React 18, Vite, Tailwind, and shadcn/ui.
- **Review page:** Dynamic catalog queue with search, filters, all-column tables, schema inspection, notes, and approval decisions.
- **API ingestion:** Python requests executed only inside GitHub Actions.
- **Storage:** Bronze JSON, normalized Parquet, limited CSV samples, schemas, profiles, quality reports, and a central catalog.
- **Pages deployment:** GitHub Pages serves the app only and does not run secret-backed API pulls.
- **Optional full lake:** Cloudflare R2 can receive the full generated build through the manual or scheduled publishing workflow.
- **Modeling data plan:** `config/pro_sports_modeling_sources.yml` tracks the source domains needed for professional sports betting research across football, basketball, baseball, hockey, and American football.

## GitHub secret for API-Football samples

API-Football review samples use a repository Actions secret. Open **Settings -> Secrets and variables -> Actions** and confirm:

| Secret | Purpose |
| --- | --- |
| `API_FOOTBALL_KEY` | API-Football v3 key used by GitHub Actions only. The key stays server-side and is never sent to the browser. |

Optional R2 secrets:

| Secret | Purpose |
| --- | --- |
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 access key |
| `R2_SECRET_ACCESS_KEY` | R2 secret key |
| `R2_BUCKET_NAME` | R2 bucket name |
| `R2_PUBLIC_BASE_URL` | Public data-lake base URL without a trailing slash |

## API-Football endpoint registry

`config/api_football_endpoints.yml` controls the approval sample. It includes the core review and betting-market entities:

- Countries
- Leagues
- Teams
- Team statistics
- Venues
- Standings
- Fixtures
- Head-to-head fixtures
- Players
- Injuries, lineups, transfers, coaches, trophies, and sidelined history
- Pre-match odds, live odds, bookmakers, bet markets, and odds mapping

The registry is configuration-driven, so additional endpoints can be added without changing the frontend. Endpoint failures or plan restrictions do not stop the full workflow; affected catalog entries are marked degraded or missing.

The API-Football pull is paced from `request_delay_seconds` in `config/api_football_endpoints.yml` so GitHub Actions stays under provider rate limits while using the server-side `API_FOOTBALL_KEY`.

The default API-Football review season is pinned to `2024` because the current API plan reports that some football endpoints are only available for 2022-2024. This can be moved forward when the key has current-season access.

## Pages

| Route | Purpose |
| --- | --- |
| `/` or `/approval` | Primary data approval queue |
| `/datasets` | Dataset catalog and downloads |
| `/explore` | DuckDB-WASM data explorer |
| `/coverage` | Coverage matrix |
| `/dictionary` | Field dictionary |
| `/quality` | Data-quality results |
| `/basket` | Flagged record basket |
| `/status` | Source and cache status |

## Review behavior

- All discovered sample columns are visible in a horizontally scrollable table.
- Public row count is deliberately limited during approval.
- Schema metadata is shown separately from the sample values.
- Decisions and notes are stored in the reviewer's browser and can be exported as `game_stat_pulse_data_approvals.csv`.
- Central multi-reviewer persistence is a later phase and will require authentication plus a backend.

## Local development

```bash
bun install
bun run dev
bun run test
bun run build
```

Build the local data catalog:

```bash
pip install duckdb pandas pyarrow requests pyyaml
python scripts/build_data_lake.py
API_FOOTBALL_KEY=your_key python scripts/fetch_api_football.py
python scripts/profile_datasets.py
python scripts/validate_datasets.py
```

Never place the real key in `.env` files that are committed, source code, frontend variables, logs, or browser requests.

## Deployment

- Pushes to `main` run `.github/workflows/deploy.yml`.
- The workflow deploys the app to GitHub Pages and does not call API-Football or expose repository secrets.
- `.github/workflows/publish-data-lake.yml` runs on manual dispatch and on the daily schedule only, so app deploys do not spend API quota.
- The data-lake workflow uses `API_FOOTBALL_KEY` from Actions secrets, uploads a `modeling-data-lake-build` artifact for model work, and can also publish the complete generated lake to R2 when the optional secrets are configured.
- Provider quota note: the June 30, 2026 setup run hit the API-Football daily request limit. Wait for the daily reset or upgrade the plan before manually dispatching another fresh data pull.
