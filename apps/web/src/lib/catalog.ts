// Catalog loader. Reads /data-source.json, then tries the R2 catalog URL it
// points to. If that fails (or fallback_mode is true), it builds a catalog from
// the existing public LindaData GitHub repository so the app keeps working.

import { DATASETS as FALLBACK_DATASETS, type DatasetDef } from "./parquetData";

const BASE_GH =
  "https://raw.githubusercontent.com/LindaData/world-cup-2026-betting-model/main/docs/sports-data/data";

export type AvailabilityStatus = "available" | "degraded" | "missing";

export interface CatalogEntry {
  dataset_id: string;
  display_name: string;
  description: string;
  sport: "NBA" | "MLB" | "Meta" | string;
  source_api: string;
  source_endpoint: string;
  entity: string;
  granularity: "per_game" | "per_team" | "per_player" | "snapshot" | "manifest" | string;
  league_id: string | number | null;
  league_name: string | null;
  season: string | null;
  row_count: number | null;
  column_count: number | null;
  file_size_bytes: number | null;
  generated_at_utc: string | null;
  earliest_date: string | null;
  latest_date: string | null;
  parquet_url: string | null;
  sample_csv_url: string | null;
  raw_json_url: string | null;
  raw_json_prefix: string | null;
  schema_url: string | null;
  profile_url: string | null;
  quality_url: string | null;
  primary_key: string | null;
  partition_columns: string[];
  schema_version: string;
  availability_status: AvailabilityStatus;
}

export interface Catalog {
  generated_at_utc: string;
  source: "r2" | "fallback";
  entries: CatalogEntry[];
}

interface DataSourceConfig {
  catalog_url: string;
  fallback_mode: boolean;
  notice?: string;
}

const ENTITY_BY_TYPE: Record<string, CatalogEntry["entity"]> = {
  games: "games",
  standings: "standings",
  live: "scores",
  manifest: "operational_metadata",
};

function fallbackFromDatasets(): CatalogEntry[] {
  return FALLBACK_DATASETS.map((d: DatasetDef) => ({
    dataset_id: d.id,
    display_name: d.display_name,
    description: d.description,
    sport: d.sport,
    source_api: d.sport === "Meta" ? "linda-data-meta" : "api-sports",
    source_endpoint: d.source_url,
    entity: ENTITY_BY_TYPE[d.dataset_type] ?? "operational_metadata",
    granularity:
      d.dataset_type === "games"
        ? "per_game"
        : d.dataset_type === "standings"
        ? "per_team"
        : d.dataset_type === "live"
        ? "snapshot"
        : "manifest",
    league_id: null,
    league_name: d.sport === "NBA" ? "NBA" : d.sport === "MLB" ? "MLB" : null,
    season: d.season ?? null,
    row_count: null,
    column_count: null,
    file_size_bytes: null,
    generated_at_utc: null,
    earliest_date: null,
    latest_date: null,
    parquet_url: d.parquet_url,
    sample_csv_url: d.csv_fallback_url,
    raw_json_url: d.csv_fallback_url.endsWith(".json") ? d.csv_fallback_url : null,
    raw_json_prefix: null,
    schema_url: null,
    profile_url: null,
    quality_url: null,
    primary_key: d.primary_key ?? null,
    partition_columns: [],
    schema_version: "v0-fallback",
    availability_status: "available" as AvailabilityStatus,
  }));
}

const SAMPLE_DATASETS: Pick<
  CatalogEntry,
  "dataset_id" | "display_name" | "description" | "sport" | "entity" | "granularity" | "league_name" | "season" | "sample_csv_url" | "raw_json_url" | "source_endpoint" | "source_api"
>[] = [
  // Extra fallback entities that map to existing files
  {
    dataset_id: "nba_snapshot",
    display_name: "NBA Daily Snapshot",
    description: "Combined NBA daily snapshot JSON (games + standings).",
    sport: "NBA",
    entity: "operational_metadata",
    granularity: "snapshot",
    league_name: "NBA",
    season: null,
    sample_csv_url: null,
    raw_json_url: `${BASE_GH}/basketball_snapshot.json`,
    source_endpoint: `${BASE_GH}/basketball_snapshot.json`,
    source_api: "linda-data-meta",
  },
  {
    dataset_id: "mlb_snapshot",
    display_name: "MLB Daily Snapshot",
    description: "Combined MLB daily snapshot JSON (games + standings).",
    sport: "MLB",
    entity: "operational_metadata",
    granularity: "snapshot",
    league_name: "MLB",
    season: null,
    sample_csv_url: null,
    raw_json_url: `${BASE_GH}/baseball_snapshot.json`,
    source_endpoint: `${BASE_GH}/baseball_snapshot.json`,
    source_api: "linda-data-meta",
  },
];

function withSnapshots(entries: CatalogEntry[]): CatalogEntry[] {
  const base = [...entries];
  for (const s of SAMPLE_DATASETS) {
    if (base.some((e) => e.dataset_id === s.dataset_id)) continue;
    base.push({
      ...s,
      league_id: null,
      row_count: null,
      column_count: null,
      file_size_bytes: null,
      generated_at_utc: null,
      earliest_date: null,
      latest_date: null,
      parquet_url: null,
      schema_url: null,
      profile_url: null,
      quality_url: null,
      primary_key: null,
      partition_columns: [],
      raw_json_prefix: null,
      schema_version: "v0-fallback",
      availability_status: "available",
    });
  }
  return base;
}

let cached: Catalog | null = null;

export async function loadCatalog(forceRefresh = false): Promise<Catalog> {
  if (cached && !forceRefresh) return cached;
  const base = (import.meta.env.BASE_URL || "/").replace(/\/$/, "");
  const configUrl = `${base}/data-source.json?t=${Date.now()}`;
  let config: DataSourceConfig | null = null;
  try {
    const res = await fetch(configUrl, { cache: "no-store" });
    if (res.ok) config = (await res.json()) as DataSourceConfig;
  } catch {
    /* ignore */
  }

  const wantR2 =
    !!config &&
    !!config.catalog_url &&
    !config.catalog_url.includes("REPLACE_WITH_R2_PUBLIC_DOMAIN");

  if (wantR2) {
    try {
      const res = await fetch(`${config!.catalog_url}?t=${Date.now()}`, { cache: "no-store" });
      if (res.ok) {
        const data = (await res.json()) as { entries: CatalogEntry[]; generated_at_utc?: string };
        if (Array.isArray(data.entries) && data.entries.length) {
          cached = {
            generated_at_utc: data.generated_at_utc ?? new Date().toISOString(),
            source: "r2",
            entries: data.entries,
          };
          try {
            localStorage.setItem("gsp:catalog", JSON.stringify(cached));
          } catch {
            /* ignore */
          }
          return cached;
        }
      }
    } catch {
      /* fall through to fallback */
    }
  }

  // Try cached previous catalog
  if (!cached) {
    try {
      const raw = localStorage.getItem("gsp:catalog");
      if (raw) cached = JSON.parse(raw) as Catalog;
    } catch {
      /* ignore */
    }
  }

  // Always merge a fresh fallback so newly added repo files appear
  cached = {
    generated_at_utc: new Date().toISOString(),
    source: "fallback",
    entries: withSnapshots(fallbackFromDatasets()),
  };
  return cached;
}

export function getCachedCatalog(): Catalog | null {
  return cached;
}
