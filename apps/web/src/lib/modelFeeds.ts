import type { LoadResult } from "@/lib/dataSources";

/** One match's model win probabilities. */
export interface ModelPrediction {
  home: number;
  draw: number;
  away: number;
}

/** Model win probabilities keyed by game_id / event_id. */
export type PredictionMap = Record<string, ModelPrediction>;

/** One team's chance of winning the tournament. */
export interface TitleChance {
  team: string;
  probability: number;
}

type Results = Record<string, LoadResult>;

/**
 * A feed is "preliminary" while the placeholder pipeline publishes it; the
 * production model drops the marker. Screens surface a PreliminaryChip next
 * to preliminary numbers so previews never pretend to be final.
 */
function isPreliminary(data: unknown): boolean {
  return (
    !!data &&
    typeof data === "object" &&
    (data as { provider?: unknown }).provider === "placeholder"
  );
}

/**
 * Pull the {game_id: {home, draw, away}} map out of the model_predictions
 * feed. Malformed entries are dropped rather than propagated to screens.
 */
export function getPredictions(results: Results): {
  map: PredictionMap;
  preliminary: boolean;
  version?: string;
} {
  const data = results["model_predictions"]?.data;
  const map: PredictionMap = {};
  if (!data || typeof data !== "object") {
    return { map, preliminary: false };
  }
  const feed = data as {
    predictions?: unknown;
    model_version?: unknown;
  };
  if (feed.predictions && typeof feed.predictions === "object") {
    for (const [id, v] of Object.entries(feed.predictions as Record<string, unknown>)) {
      if (!v || typeof v !== "object") continue;
      const p = v as Record<string, unknown>;
      if (
        typeof p.home === "number" &&
        typeof p.draw === "number" &&
        typeof p.away === "number"
      ) {
        map[id] = { home: p.home, draw: p.draw, away: p.away };
      }
    }
  }
  return {
    map,
    preliminary: isPreliminary(data),
    version: typeof feed.model_version === "string" ? feed.model_version : undefined,
  };
}

/**
 * Pull the champion list out of the model_champion feed, sorted by
 * probability (highest first).
 */
export function getTitleChances(results: Results): {
  list: TitleChance[];
  preliminary: boolean;
} {
  const data = results["model_champion"]?.data;
  const list: TitleChance[] = [];
  if (!data || typeof data !== "object") {
    return { list, preliminary: false };
  }
  const chances = (data as { title_chances?: unknown }).title_chances;
  if (Array.isArray(chances)) {
    for (const v of chances) {
      if (!v || typeof v !== "object") continue;
      const c = v as Record<string, unknown>;
      if (typeof c.team === "string" && typeof c.probability === "number") {
        list.push({ team: c.team, probability: c.probability });
      }
    }
    list.sort((a, b) => b.probability - a.probability);
  }
  return { list, preliminary: isPreliminary(data) };
}
