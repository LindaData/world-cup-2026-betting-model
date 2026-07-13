# Roadmap & Decision Record

Owner: Sergio Mora. Last updated: 2026-07-12 (all decisions confirmed by owner).

## The product

Public face: a credible forecasting hub (probabilities, bracket, calibration,
post-match review — no betting claims). Private face: an authenticated desk
that closes the loop the repos never had:

model probabilities → market odds → no-vig comparison → edge board →
sized stakes → tracked results → CLV feedback → model calibration.

## Decisions (locked)

| Area | Decision |
|---|---|
| Monorepo home | `world-cup-2026-betting-model`; rename to `lindadata-sports` after the final (GitHub redirects old URLs) |
| Modeling language | R stays, runs in Actions; Python port only if ever justified |
| Betting tools | Private: gated by `VITE_ENABLE_BETTING_DESK` + Supabase Auth (allowlisted email) |
| Hosting | React app on Vercel; Quarto reports stay on GitHub Pages |
| Odds source | The Odds API **free tier** (500 credits/mo), quota-aware pipeline |
| Markets | h2h/1X2, totals, spreads, outrights |
| Books | Best price across US + EU books; Pinnacle as no-vig CLV benchmark |
| Cadence | Daily snapshot + closing capture ~75 min before kickoff |
| Edge model input | Matchday prediction board ensemble probabilities |
| Public market views | None — all model-vs-market stays in the private desk |
| Persistence | Supabase (free tier), single-owner RLS |
| Budget | $0/month; surface costs before anything paid |
| Post-WC targets | Club football first (same pipeline), then NBA (October), then MLB |
| Alerts | None for now; owner checks the desk |

Known tension: 3 sports x 4 markets x 3 regions does not fit 500 free
credits/month. Sequencing (one competition at a time) + the credit counter in
`odds_manifest.json` decide when a paid tier is justified.

## Phases

- **Phase 0 — done in PR #16:** monorepo, consolidated app, football feed
  fixed (ESPN), Vercel-ready.
- **Phase 1 — the loop (in progress):**
  1. ✅ Odds ingestion: `scripts/fetch_odds_snapshots.py` + hourly
     `odds-snapshots.yml` (credit-gated: daily + closing capture).
  2. ✅ Supabase schema (`supabase/schema.sql`) + setup guide.
  3. ☐ Publish matchday-board probabilities as `model_predictions.json`
     (public-safe) from the model run.
  4. ☐ Edge board page in the desk: auto-join predictions x odds_latest,
     EV/Kelly via `edgeMath`, write-through to `edge_snapshots`.
  5. ☐ Supabase-backed ledger (replace localStorage; CSV import for old
     records); auto-fill closing odds + CLV from `odds/closing/`.
- **Phase 2 — prove it:** CLV/calibration report vs Pinnacle no-vig closing
  lines; World Cup retrospective. No stake scaling before this exists.
- **Phase 3 — multi-sport one-stop shop (pivot):** keyless ESPN feeds for
  NFL/NBA/MLB/NHL/CFB (this PR): `scripts/publish_multisport_espn.py` +
  `publish-multisport.yml` publish per-sport schedules and standings into
  `docs/sports-data/data/`, and live scoreboards now cover all five leagues.
  Per-sport models next (MLB in season now, NFL Sept, NBA/NHL Oct); odds
  ingestion extends per sport once `THE_ODDS_API_KEY` exists. Rename repo.
  Archive the three sibling repos.

## Owner to-do (blocking Phase 1 completion)

1. Merge PR #16 (also stops the daily "Run failed" emails).
2. Sign up at the-odds-api.com (free) → add `THE_ODDS_API_KEY` to this
   repo's Actions secrets.
3. Create the Supabase project per `supabase/README.md` → add the two
   `VITE_SUPABASE_*` vars to Vercel.
4. Create the Vercel project: import this repo, Root Directory `apps/web`.
