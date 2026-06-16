# Data Sources

Checked on 2026-06-16.

## Core Truth Data

| Need | Source | Connection | Notes |
| --- | --- | --- | --- |
| 2026 groups, fixtures, venues | Openfootball World Cup repo | Public raw files | Good bootstrap source; keep as raw snapshot. |
| Historical men's international results | martj42 international_results | Public raw CSVs | Useful for Elo, recency-weighted team form, home/neutral effects, tournament effects. |
| 2026 squad players | Wikimedia API + official FIFA PDF | No key | Wikimedia is parsed into tables; FIFA PDF is archived raw for audit. |
| Live fixtures/results/standings | football-data.org | API key, `X-Auth-Token` header | Competition code `WC`; useful for official-ish current state. |
| Odds snapshots | The Odds API | API key query param | Use `h2h`, `spreads`, `totals`; store every pull with timestamp. |
| Fixtures/odds/player-match fallback | API-Football | API key header | Optional enrichment for squads, lineups, events, player statistics, and odds. |
| Weather | Open-Meteo | No key | Useful around kickoff for temperature, precipitation, humidity, wind. |

## Later Enrichment

These are not wired yet because source choice matters:

- Projected lineups.
- Injuries and suspensions.
- Player club minutes and transfer-market values.
- Referee assignments and card tendencies.
- Book-specific limits and liquidity.
- News sentiment, which should only be used if we can timestamp it cleanly.

## Modeling Implications

For a first model, historical results plus venue/rest/weather and market odds are enough to build a defensible baseline:

- Estimate latent team strength with an Elo or dynamic Poisson model.
- Convert expected goals to `1X2`, totals, and spread probabilities.
- Remove bookmaker vig from odds to derive market probabilities.
- Compare model probability to market probability.
- Track realized calibration and closing-line value separately.

Avoid training directly on closing odds as if they are labels; odds are market priors, not outcomes.
