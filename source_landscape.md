# World Cup Data Source Landscape

Checked on 2026-06-16.

This is a practical survey of sources worth considering for a serious 2026 World Cup prediction model.

## Already Pulled Or Wired

| Category | Source | Cost | Current status | Best use |
| --- | --- | --- | --- | --- |
| Historical international results | martj42 `international_results` | Free | Pulled | Team strength, scoring, home/neutral effects |
| 2026 fixture/stadium files | Openfootball | Free | Pulled | Fixture bootstrap and venue metadata |
| Squads/player metadata | Wikimedia + FIFA PDF | Free | Pulled | Player age, position, club, caps, goals |
| Historical player goals | martj42 `goalscorers` | Free | Pulled | Player scoring history |
| Team strength | Computed Elo from public results | Free | Built | Baseline team rating |
| Weather | Open-Meteo | Free for prototyping | Client wired | Temperature, precipitation, wind |
| News metadata | GDELT | Free | Client wired, live pull not yet tested here | Article volume, injury/suspension/lineup signals |
| Fixtures/teams/standings | football-data.org | Free tier; paid for deeper data | Client wired, key needed | Fixtures, scores, standings, some match details |
| Odds | The Odds API | Free starter; paid for useful volume/history | Client wired, key needed | Market probabilities and CLV |
| Lineups/events/player stats | API-Football | Free 100/day; cheap paid tiers | Client wired, key needed | Lineups, injuries, events, odds, statistics |

## Free / No-Key Data

### Public Match Results

Use this as the backbone of the model.

Data available:

- International results.
- Scores.
- Tournaments.
- Locations.
- Neutral-site flag.
- Goal events.
- Shootouts.

Limitations:

- No full player appearances/minutes.
- No xG, shots, cards, or lineups.
- Data quality should be spot-checked against official fixtures.

### Squads And Player Metadata

Sources:

- Wikimedia/Wikipedia squad pages.
- Official FIFA squad PDF.
- Wikidata SPARQL later if we want richer player identity links.

Data available:

- Player names.
- Position.
- Age/date of birth.
- Club.
- National-team caps and goals before tournament.
- Captain flags when present.

Limitations:

- Wikipedia/Wikimedia data is community-maintained.
- Good for features, but official FIFA PDF should be the audit reference.

### StatsBomb Open Data

Useful for training event-level concepts, not necessarily 2026 coverage.

Data available:

- Match event JSON.
- Lineups.
- Some StatsBomb 360 freeze-frame data for selected matches.

Best use:

- Learn event-feature engineering.
- Train/validate soccer xG-like ideas on historical competitions.
- Build tactical features if relevant competitions overlap.

Limitations:

- Open data covers only certain competitions/seasons.
- Not a complete 2026 World Cup live feed.

### Weather / Venue Context

Sources:

- Open-Meteo.
- Venue coordinates from seed data.

Data available:

- Temperature.
- Humidity.
- Precipitation.
- Wind speed.

Best use:

- Match-day context.
- Travel/rest/venue features.

### News Metadata

Source:

- GDELT.

Data available:

- Article title.
- URL.
- Source domain/country/language.
- Seen date.
- Query-level article volume.

Best use:

- Injury/availability attention.
- Lineup uncertainty.
- Team/player news spikes.
- Source diversity.

Avoid:

- Copying full article text into the repo.
- Blind sentiment features without validation.

## Free-Tier Or Cheap API Data

### API-Football

Likely highest value for the price.

Free tier:

- 100 requests/day.
- Includes fixtures, events, lineups, players/coaches, injuries, odds, statistics, predictions, and more.

Paid:

- Pro is listed at $19/month with 7,500 requests/day.
- Higher tiers increase daily requests.

Best use:

- 2026 player match history.
- Lineups and substitutions.
- Injuries/sidelined players.
- Fixture events.
- Player/fixture statistics.
- Cross-checking odds.

### The Odds API

Best for bookmaker market data.

Free:

- Starter plan with 500 credits/month.

Paid:

- Starts around $30/month for 20,000 credits/month.

Data available:

- H2H/moneyline.
- Spreads/handicaps.
- Totals.
- Futures/outrights.
- Player props for selected sports/markets where supported.

Best use:

- No-vig implied probabilities.
- Market baseline.
- Closing-line value.
- Feature for model comparison, not the training label.

### football-data.org

Good cheap structured football API.

Free:

- Fixtures, delayed scores/schedules, league tables, limited competitions, 10 calls/minute.

Paid:

- Deeper plans include lineups/subs, goal scorers, bookings/cards, squads.
- Odds and statistics are paid add-ons.

Best use:

- Structured fixture/standings backup.
- Lightweight official-ish match state.

### NewsAPI

Useful but not my first recommendation.

Free:

- Development/testing only.
- 100 requests/day.
- 24-hour article delay.
- Search up to one month old.

Paid:

- Business plan is expensive.

Best use:

- Development experiments only.

### Google Programmable Search

Not ideal for new projects.

Current docs say the Custom Search JSON API is closed to new customers and existing customers must transition by 2027.

Best use:

- Avoid unless you already have access.

## Expensive / Professional Data

These are likely out of budget unless this becomes a serious commercial product.

| Source type | Examples | Typical value |
| --- | --- | --- |
| Event data | StatsBomb paid, Opta/Stats Perform, Wyscout | xG, shots, passes, pressures, carries, possession events |
| Tracking data | SkillCorner, Second Spectrum/ChyronHego-style products | Player locations, spacing, runs, pressing |
| Sports data enterprise APIs | Sportradar, SportsDataIO enterprise tiers | Official feeds, live coverage, detailed stats |
| Betting market data | OddsJam, Betfair historical, Pinnacle/Sharp books | Historical lines, limits, market movement |
| Player valuation/injury intel | Transfermarkt-like datasets, paid scouting feeds | Club value, transfer history, injury history |

## Highest-Value Next Purchases, If Needed

1. API-Football Pro for one month around the tournament.
2. The Odds API low paid plan if free odds quota is insufficient.
3. football-data.org deep-data plan only if it has better World Cup coverage than API-Football.

Do not buy StatsBomb/Opta/Sportradar/Wyscout unless you already know the model needs event/tracking detail and you have a budget for it.

## Advanced Model Direction

Start with interpretable baselines and climb gradually:

1. Elo + recent form + squad strength.
2. Ordered outcome model for team perspective: loss/draw/win.
3. Bivariate Poisson or Skellam-style goal model for score distribution.
4. Market-calibrated model using no-vig odds as a benchmark.
5. News features: article volume, injury terms, player mentions, source diversity.
6. KNN/similarity model as an ensemble member: find historical matches with similar Elo gap, squad strength, rest/travel, weather, and market odds.
7. Calibration layer: isotonic/logistic calibration and Brier/log-loss tracking.

KNN can be useful as a sanity-check and local-pattern model, but I would not make it the main model. It struggles when feature scales, missingness, and sparse international data get messy. It can be a good ensemble feature.

