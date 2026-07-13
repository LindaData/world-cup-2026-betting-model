import { describe, expect, it } from "vitest";
import type { LoadResult } from "./dataSources";
import { getPredictions, getTitleChances } from "./modelFeeds";

function result(key: string, data: unknown): Record<string, LoadResult> {
  return {
    [key]: {
      key,
      data,
      rows: 1,
      origin: "network",
      fetchedAt: "2026-07-13T00:00:00Z",
      url: `https://example.test/${key}.json`,
    },
  };
}

describe("getPredictions", () => {
  it("extracts the map, preliminary flag, and version", () => {
    const { map, preliminary, version } = getPredictions(
      result("model_predictions", {
        provider: "placeholder",
        model_version: "preview-0",
        predictions: {
          "760514": { home: 0.42, draw: 0.27, away: 0.31 },
          malformed: { home: "high", draw: 0.2 },
        },
      }),
    );
    expect(map).toEqual({ "760514": { home: 0.42, draw: 0.27, away: 0.31 } });
    expect(preliminary).toBe(true);
    expect(version).toBe("preview-0");
  });

  it("is not preliminary once a real provider publishes", () => {
    const { preliminary } = getPredictions(
      result("model_predictions", {
        provider: "wc26-model",
        predictions: { "760514": { home: 0.5, draw: 0.3, away: 0.2 } },
      }),
    );
    expect(preliminary).toBe(false);
  });

  it("returns an empty non-preliminary map when the feed is missing", () => {
    expect(getPredictions({})).toEqual({ map: {}, preliminary: false, version: undefined });
  });
});

describe("getTitleChances", () => {
  it("extracts and sorts chances, highest first", () => {
    const { list, preliminary } = getTitleChances(
      result("model_champion", {
        provider: "placeholder",
        title_chances: [
          { team: "England", probability: 0.2 },
          { team: "France", probability: 0.31 },
          { team: "Broken" },
        ],
      }),
    );
    expect(list).toEqual([
      { team: "France", probability: 0.31 },
      { team: "England", probability: 0.2 },
    ]);
    expect(preliminary).toBe(true);
  });

  it("returns an empty non-preliminary list when the feed is missing", () => {
    expect(getTitleChances({})).toEqual({ list: [], preliminary: false });
  });
});
