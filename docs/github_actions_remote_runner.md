# GitHub Actions Remote Data Runner

This workflow uses a GitHub-hosted Linux machine to pull API-Sports data without requiring the local Codex/RStudio computer to be online.

## One-time setup

1. Open the repository on GitHub.
2. Go to **Settings → Secrets and variables → Actions**.
3. Select **New repository secret**.
4. Name it `API_SPORTS_KEY` and paste the API-Sports key.
5. Do not add the key to `.env.example`, workflow YAML, issues, logs, or commits.

## Test the connection

1. Open **Actions → API-Sports cloud pull → Run workflow**.
2. Select `basketball` or `baseball`.
3. Set endpoint to `status`.
4. Set parameters to `{}`.
5. Set maximum pages to `1`.
6. Run the workflow.

The workflow summary shows the response count and any quota headers returned by API-Sports.

## Pull data

Run the same workflow with an API-Sports endpoint and its query parameters. Parameters must be a JSON object.

Safe initial discovery pulls:

| Sport | Endpoint | Parameters | Max pages |
| --- | --- | --- | ---: |
| Basketball | `leagues` | `{}` | 1 |
| Baseball | `leagues` | `{}` | 1 |
| Football | `leagues` | `{"search":"World Cup"}` | 1 |

For large endpoints such as games or players, provide the league, season, team, date, or other required filters from the provider documentation. Keep `max_pages` low on the first run, review the result and quota headers, and then increase it.

## Retrieve the data

Each run uploads a compressed workflow artifact named like:

```text
api-sports-basketball-123456789
```

Open the completed workflow run and download the artifact. It contains raw JSON pages and a `manifest.json` file. Artifacts are retained for seven days to minimize storage use.

## Architecture

- **GitHub Actions:** remote Linux compute and manual scheduling.
- **GitHub Secrets:** encrypted API-key storage.
- **Workflow artifacts:** short-term raw snapshot storage.
- **GitHub Pages:** existing public model reports and dashboards.
- **Codespaces:** optional browser-based interactive development when a full remote editor is needed.

The first version is deliberately manual. Scheduled bulk jobs should only be added after the exact leagues, seasons, endpoints, and API quota are confirmed.
