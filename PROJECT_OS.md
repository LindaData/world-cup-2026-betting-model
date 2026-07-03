# LindaData World Cup Project OS

## Purpose

This repo is the LindaData World Cup 2026 forecasting project. It should stay public-safe, static-first, and easy to review from the LindaData HQ. The public site shows forecasts, bracket paths, model review, and data coverage without exposing private feeds, credentials, raw paid API responses, or internal pricing notes.

## Operating Priority

- Project state: active research / public forecasting site.
- Portfolio priority: secondary to HVAC Copilot and the universal review layer unless ChefHands explicitly reprioritizes it.
- Delivery standard: mobile-first, prediction-first, concise, and understandable without reading the technical reports.

## Executive Routing

| Area | Executive owner | What they control |
|---|---|---|
| Forecast quality | CDO | Modeling approach, backtesting, calibration, champion simulations, model promotion gates. |
| Site and pipeline | CTO | Quarto site, data refresh jobs, GitHub Pages deployment, repo hygiene, technical reliability. |
| Publishing flow | COO | Morning review sequence, release checklist, issue triage, stale-data follow-up. |
| Public messaging | CMO / CCO | Clear labels, responsible-use language, public-facing copy, no unsupported betting or profit claims. |
| Risk and security | CIO / CSO | Secret handling, public/private boundaries, dependency and deployment controls. |
| Executive summary | Chief of Staff | ChefHands-facing summary, priorities, blockers, and next actions. |

## Page UX Rules

1. The first screen should explain what the project is, what to do first, and where to click next.
2. Forecasts come before methodology.
3. Model review must remain visible because accuracy and calibration are part of the product.
4. Data coverage must be easy to find so stale or missing inputs are not hidden.
5. Betting-style language must be careful: fair probabilities are model outputs, not sportsbook recommendations.
6. Mobile review matters more than desktop decoration.

## Morning Review Flow

1. Open the HQ/homepage.
2. Check the current model board and next-match card.
3. Review model health: hit rate, score miss, draw misses, and upset checks.
4. Open bracket/champion outlook for tournament-level storylines.
5. Check data coverage when lineups, cards, weather, or provider feeds are missing.
6. Escalate issues through the executive owner above.

## Model Promotion Gate

A model or feature should not become the public default simply because it looks stronger on one slate. Promotion requires:

- backtest evidence;
- calibration check;
- leakage review;
- comparison against current production ensemble;
- clear public explanation if behavior changes;
- rollback path.

## Public-Safety Boundary

Allowed on the public site:

- summarized forecasts;
- model diagnostics;
- static charts and tables;
- data freshness notes;
- responsible-use disclaimers;
- links to GitHub and LindaData HQ.

Not allowed on the public site:

- API keys or tokens;
- `.env`, `.Renviron`, private config, or paid API payloads;
- raw proprietary feeds;
- private film-study videos or tags;
- claims of guaranteed outcomes, betting profit, or financial advice.

## Current UX Refresh

The homepage has been reorganized around a LindaData command-center flow:

- project status and executive routing at the top;
- quick shortcuts for current slate, next match, model review, bracket, and champion outlook;
- morning-review cards before the dense forecast board;
- clearer navbar grouping: HQ, Board, Predictions, Bracket, Archive, Model Lab, and Data/Ops.
