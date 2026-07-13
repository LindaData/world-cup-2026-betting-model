import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Demo-mode regression guard: the bundled demo dataset must stay
 * route-compatible with the live feeds. Every game_id the demo prediction
 * feed publishes has to resolve to a demo fixture the same way the match
 * route does (string game_id lookup), or /match/:id dead-ends on the exact
 * links the app itself builds.
 */

interface DemoFixture {
  game_id: string;
  date_utc: string;
  home_team: string;
  away_team: string;
  status: string;
}

// Vitest runs with the app root (apps/web) as cwd, so resolve from there.
const readDemo = <T>(name: string): T =>
  JSON.parse(
    readFileSync(resolve(process.cwd(), "public/demo-data", name), "utf8"),
  ) as T;

const fixtures = readDemo<DemoFixture[]>("football_fixtures.json");
const predictionsFeed = readDemo<{
  provider?: string;
  predictions: Record<string, { home: number; draw: number; away: number }>;
}>("model_predictions.json");

/** Same shape gate the pages apply (asFixtures) before the game_id lookup. */
function resolvableFixtureIds(): Set<string> {
  return new Set(
    fixtures
      .filter(
        (row) =>
          !!row &&
          typeof row === "object" &&
          typeof row.game_id === "string" &&
          typeof row.date_utc === "string" &&
          typeof row.home_team === "string" &&
          typeof row.away_team === "string",
      )
      .map((row) => row.game_id),
  );
}

describe("demo data sync", () => {
  it("resolves every demo prediction game_id to a demo fixture", () => {
    const fixtureIds = resolvableFixtureIds();
    const unresolved = Object.keys(predictionsFeed.predictions).filter(
      (gameId) => !fixtureIds.has(gameId),
    );
    expect(unresolved).toEqual([]);
  });

  it("keeps the real semifinal/bracket game_ids in fixtures and predictions", () => {
    // The live ESPN ids for the semis, third-place match, and final: deep
    // links from real data must keep working in demo mode.
    const bracketIds = ["760514", "760515", "760516", "760517"];
    const fixtureIds = resolvableFixtureIds();
    for (const id of bracketIds) {
      expect(fixtureIds.has(id), `fixture ${id}`).toBe(true);
      expect(predictionsFeed.predictions[id], `prediction ${id}`).toBeDefined();
    }
  });

  it("keeps demo predictions honest: placeholder provider stays marked", () => {
    // The PreliminaryChip honesty rule keys off provider === "placeholder";
    // if the demo feed ever drops the marker it must be because the numbers
    // are real, not because the field was lost in a resync.
    expect(predictionsFeed.provider).toBe("placeholder");
  });
});
