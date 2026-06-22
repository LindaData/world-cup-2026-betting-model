# Current Data Status

Last site render completed locally on 2026-06-22.

## Modeling Coverage

| Area | Current count |
| --- | ---: |
| 2026 fixtures scored | 72 |
| Fixtures with final scores | 40 |
| Fixtures with weather context | 44 |
| Team-fixture rows scored | 144 |

## Latest Accuracy Snapshot

| Model | Completed matches | Result accuracy | Average total-goal miss |
| --- | ---: | ---: | ---: |
| Ensemble | 40 | 60.0% | 1.52 goals |
| OLS goals | 40 | 60.0% | 1.60 goals |
| Poisson score grid | 40 | 60.0% | 1.52 goals |
| Ordinal result | 40 | 60.0% | Not a goal model |

## Published Site Output

The rendered website is in `docs/`. It includes the matchday prediction board,
the completed-match accuracy table, model summaries, diagnostics, and source
coverage notes. Private local files and raw source snapshots are intentionally
kept outside the published output.
