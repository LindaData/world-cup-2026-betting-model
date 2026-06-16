# API Key Setup

You do not need keys for the data already pulled into this project.

Keys are needed for live/enriched data, especially odds, lineups, player minutes, and fixture-level player statistics.

## No-Key Sources Already Wired

| Source | What it gives us | Status |
| --- | --- | --- |
| Openfootball World Cup files | 2026 fixture/stadium bootstrap files | Pulled |
| martj42 international_results | Historical international results, goal events, shootouts | Pulled |
| Wikimedia API | 2026 World Cup pages, squads, officials wikitext | Pulled |
| FIFA squad PDF | Official squad PDF raw archive | Pulled |
| Open-Meteo | Weather by venue/date | Client wired, not bulk-pulled yet |

## football-data.org

Use for fixtures, teams, standings, scorers, and match details where your plan allows.

1. Go to https://www.football-data.org/client/register
2. Create a free account.
3. Copy the API token.
4. In `.env`, set:

```text
FOOTBALL_DATA_TOKEN=your_token_here
```

5. Test:

```powershell
.\.venv\Scripts\python.exe scripts\check_connections.py
.\.venv\Scripts\python.exe scripts\fetch_raw_data.py --sources football-data
```

Notes:

- Header used by the client: `X-Auth-Token`.
- World Cup competition code is configured as `WC`.
- Some player/squad/lineup depth may depend on football-data.org plan coverage.

## The Odds API

Use for bookmaker odds snapshots.

1. Go to https://the-odds-api.com/
2. Create a free starter account.
3. Copy the API key.
4. In `.env`, set:

```text
THE_ODDS_API_KEY=your_key_here
```

5. Test sport discovery:

```powershell
.\.venv\Scripts\python.exe scripts\check_connections.py
```

6. Pull odds only when you intend to spend free quota:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_raw_data.py --sources odds --include-quota-odds
```

Notes:

- Odds calls consume quota.
- We store odds snapshots raw first; model-implied probabilities and no-vig market probabilities come later.

## API-Football / API-SPORTS

Use for richer fixture data, squads, lineups, fixture events, player statistics, and possibly odds if coverage is useful.

1. Go to https://www.api-football.com/pricing
2. Start with the free plan only.
3. Copy your API key.
4. In `.env`, set:

```text
API_FOOTBALL_KEY=your_key_here
```

5. Search for the World Cup league id:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_raw_data.py --sources api-football
```

6. After we identify the correct league id, set:

```text
API_FOOTBALL_WORLD_CUP_LEAGUE_ID=the_id_here
```

Then rerun:

```powershell
.\.venv\Scripts\python.exe scripts\fetch_raw_data.py --sources api-football
```

Notes:

- This is the most likely cheap source for lineups/player-match statistics.
- Free quota is limited; we should pull strategically, not repeatedly.

## Kaggle

Optional. Kaggle is free but requires an account and API token.

Only add this if we find a specific dataset we trust and need.

1. Create/login to Kaggle.
2. Go to Account settings.
3. Create a new API token.
4. Save `kaggle.json` outside the repo or add it only to a local ignored config path.

Do not commit Kaggle credentials.

