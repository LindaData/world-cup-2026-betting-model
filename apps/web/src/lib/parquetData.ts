// Parquet-first dataset registry + loader for Raw Data Lab.
//
// For each logical dataset we attempt to register a Parquet URL with DuckDB.
// If the Parquet file 404s (HEAD check), we fall back to the CSV file and
// register that instead. Either way the dataset becomes queryable through
// DuckDB-WASM as a virtual table name.

import { dropFileSafe, registerRemote, runSql } from "./duck";

const BASE =
  "https://raw.githubusercontent.com/LindaData/world-cup-2026-betting-model/main/docs/sports-data/data";

export type DatasetFormat = "parquet" | "csv";
export type LoadStatus =
  | "idle"
  | "loading"
  | "ready"
  | "csv_fallback"
  | "cached"
  | "partial"
  | "unavailable";

export type Sport = "NBA" | "MLB" | "Meta";
export type DatasetType = "games" | "standings" | "live" | "manifest";

export interface DatasetDef {
  id: string;
  display_name: string;
  sport: Sport;
  dataset_type: DatasetType;
  parquet_url: string;
  csv_fallback_url: string;
  source_url: string;
  filename_base: string;
  season?: string;
  primary_key?: string;
  description: string;
}

export const DATASETS: DatasetDef[] = [
  {
    id: "nba_games",
    display_name: "NBA Games",
    sport: "NBA",
    dataset_type: "games",
    parquet_url: `${BASE}/basketball_games_full.parquet`,
    csv_fallback_url: `${BASE}/basketball_games_full.csv`,
    source_url: `${BASE}/basketball_games_full.csv`,
    filename_base: "nba_games",
    season: "2024-2025",
    primary_key: "game_id",
    description: "Per-game NBA results, scores, and status.",
  },
  {
    id: "nba_standings",
    display_name: "NBA Standings",
    sport: "NBA",
    dataset_type: "standings",
    parquet_url: `${BASE}/basketball_standings.parquet`,
    csv_fallback_url: `${BASE}/basketball_standings.csv`,
    source_url: `${BASE}/basketball_standings.csv`,
    filename_base: "nba_standings",
    season: "2024-2025",
    primary_key: "team_id",
    description: "NBA team standings by group.",
  },
  {
    id: "nba_live",
    display_name: "NBA Live",
    sport: "NBA",
    dataset_type: "live",
    parquet_url: `${BASE}/nba_live.parquet`,
    csv_fallback_url: `${BASE}/nba_live.json`,
    source_url: `${BASE}/nba_live.json`,
    filename_base: "nba_live",
    description: "Today's NBA scoreboard.",
  },
  {
    id: "mlb_games",
    display_name: "MLB Games",
    sport: "MLB",
    dataset_type: "games",
    parquet_url: `${BASE}/baseball_games_full.parquet`,
    csv_fallback_url: `${BASE}/baseball_games_full.csv`,
    source_url: `${BASE}/baseball_games_full.csv`,
    filename_base: "mlb_games",
    season: "2024",
    primary_key: "game_id",
    description: "Per-game MLB results, scores, and status.",
  },
  {
    id: "mlb_standings",
    display_name: "MLB Standings",
    sport: "MLB",
    dataset_type: "standings",
    parquet_url: `${BASE}/baseball_standings.parquet`,
    csv_fallback_url: `${BASE}/baseball_standings.csv`,
    source_url: `${BASE}/baseball_standings.csv`,
    filename_base: "mlb_standings",
    season: "2024",
    primary_key: "team_id",
    description: "MLB team standings by division.",
  },
  {
    id: "mlb_live",
    display_name: "MLB Live",
    sport: "MLB",
    dataset_type: "live",
    parquet_url: `${BASE}/mlb_live.parquet`,
    csv_fallback_url: `${BASE}/mlb_live.json`,
    source_url: `${BASE}/mlb_live.json`,
    filename_base: "mlb_live",
    description: "Today's MLB scoreboard.",
  },
];

export interface DatasetState {
  id: string;
  status: LoadStatus;
  format: DatasetFormat | "json" | null;
  table: string | null; // SQL table name once registered
  rowCount: number;
  columnCount: number;
  columns: { name: string; type: string }[];
  fileSizeBytes: number | null;
  earliestDate: string | null;
  latestDate: string | null;
  generatedAt: string | null;
  loadedAt: string | null;
  httpStatus: number | null;
  parquetHttp: number | null;
  csvHttp: number | null;
  error: string | null;
}

function emptyState(id: string): DatasetState {
  return {
    id,
    status: "idle",
    format: null,
    table: null,
    rowCount: 0,
    columnCount: 0,
    columns: [],
    fileSizeBytes: null,
    earliestDate: null,
    latestDate: null,
    generatedAt: null,
    loadedAt: null,
    httpStatus: null,
    parquetHttp: null,
    csvHttp: null,
    error: null,
  };
}

const STATE: Map<string, DatasetState> = new Map(DATASETS.map((d) => [d.id, emptyState(d.id)]));
const listeners = new Set<() => void>();

let snapshot: DatasetState[] = DATASETS.map((d) => getState(d.id));
export function getState(id: string): DatasetState {
  return STATE.get(id) ?? emptyState(id);
}
export function getAllStates(): DatasetState[] {
  return snapshot;
}
export function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}
function update(id: string, patch: Partial<DatasetState>) {
  const cur = STATE.get(id) ?? emptyState(id);
  STATE.set(id, { ...cur, ...patch });
  snapshot = DATASETS.map((d) => STATE.get(d.id) ?? emptyState(d.id));
  listeners.forEach((l) => l());
}

async function headInfo(url: string, bust: boolean): Promise<{ ok: boolean; status: number; size: number | null; lastModified: string | null }> {
  const u = bust ? `${url}${url.includes("?") ? "&" : "?"}t=${Date.now()}` : url;
  try {
    const res = await fetch(u, { method: "HEAD", cache: "default" });
    const size = res.headers.get("content-length");
    return {
      ok: res.ok,
      status: res.status,
      size: size ? Number(size) : null,
      lastModified: res.headers.get("last-modified"),
    };
  } catch {
    return { ok: false, status: 0, size: null, lastModified: null };
  }
}

function tableName(id: string) {
  return `ds_${id}`;
}
function virtName(id: string, ext: string) {
  return `${id}.${ext}`;
}

/**
 * Load a dataset into DuckDB.
 * Strategy: try Parquet (HEAD check), else CSV fallback. Live JSON datasets
 * use read_json_auto.
 */
export async function loadDataset(id: string, opts: { bustCache?: boolean } = {}): Promise<DatasetState> {
  const def = DATASETS.find((d) => d.id === id);
  if (!def) throw new Error(`Unknown dataset ${id}`);
  update(id, { status: "loading", error: null });

  try {
    const tbl = tableName(id);
    // Try parquet first
    const parquetHead = await headInfo(def.parquet_url, !!opts.bustCache);
    let format: DatasetState["format"] = null;
    let httpStatus: number | null = null;
    let fileSize: number | null = null;
    let registeredName: string | null = null;

    if (parquetHead.ok) {
      registeredName = virtName(id, "parquet");
      await dropFileSafe(registeredName);
      await registerRemote(registeredName, def.parquet_url);
      await runSql(`CREATE OR REPLACE VIEW ${tbl} AS SELECT * FROM read_parquet('${registeredName}')`);
      format = "parquet";
      httpStatus = parquetHead.status;
      fileSize = parquetHead.size;
    } else {
      // Fallback
      const csvHead = await headInfo(def.csv_fallback_url, !!opts.bustCache);
      if (!csvHead.ok) {
        update(id, {
          status: "unavailable",
          parquetHttp: parquetHead.status,
          csvHttp: csvHead.status,
          error: `Parquet HTTP ${parquetHead.status}, CSV HTTP ${csvHead.status}`,
        });
        return getState(id);
      }
      const ext = def.csv_fallback_url.endsWith(".json") ? "json" : "csv";
      registeredName = virtName(id, ext);
      await dropFileSafe(registeredName);
      await registerRemote(registeredName, def.csv_fallback_url);
      if (ext === "csv") {
        await runSql(
          `CREATE OR REPLACE VIEW ${tbl} AS SELECT * FROM read_csv_auto('${registeredName}', HEADER=TRUE, ALL_VARCHAR=TRUE)`,
        );
        format = "csv";
      } else {
        // Live JSON: try to extract .events array if present, else top-level array
        try {
          await runSql(
            `CREATE OR REPLACE VIEW ${tbl} AS SELECT * FROM read_json_auto('${registeredName}', maximum_object_size=67108864)`,
          );
        } catch {
          await runSql(`CREATE OR REPLACE VIEW ${tbl} AS SELECT unnest(events) AS event FROM read_json_auto('${registeredName}')`);
        }
        format = "json";
      }
      httpStatus = csvHead.status;
      fileSize = csvHead.size;
    }

    // Stats
    const countRow = await runSql<{ n: number }>(`SELECT COUNT(*)::INT AS n FROM ${tbl}`);
    const rowCount = Number(countRow[0]?.n ?? 0);
    const cols = await runSql<{ column_name: string; column_type: string }>(`DESCRIBE ${tbl}`);
    const columns = cols.map((c) => ({ name: String(c.column_name), type: String(c.column_type) }));

    // date range if a date_utc column exists
    let earliestDate: string | null = null;
    let latestDate: string | null = null;
    const dateCol = columns.find((c) => /date|timestamp/i.test(c.name))?.name;
    if (dateCol) {
      try {
        const r = await runSql<{ mn: string; mx: string }>(
          `SELECT MIN(${quoteIdent(dateCol)})::VARCHAR AS mn, MAX(${quoteIdent(dateCol)})::VARCHAR AS mx FROM ${tbl}`,
        );
        earliestDate = r[0]?.mn ?? null;
        latestDate = r[0]?.mx ?? null;
      } catch {
        /* ignore */
      }
    }

    update(id, {
      status: format === "parquet" ? "ready" : format === "csv" || format === "json" ? "csv_fallback" : "ready",
      format,
      table: tbl,
      rowCount,
      columnCount: columns.length,
      columns,
      fileSizeBytes: fileSize,
      earliestDate,
      latestDate,
      loadedAt: new Date().toISOString(),
      generatedAt: parquetHead.lastModified,
      httpStatus,
      parquetHttp: parquetHead.status,
      csvHttp: format === "parquet" ? null : httpStatus,
      error: null,
    });
    saveSetting(`ds:${id}:lastLoad`, new Date().toISOString());
    return getState(id);
  } catch (e) {
    update(id, { status: "unavailable", error: (e as Error).message });
    return getState(id);
  }
}

export function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}
export function sqlString(v: string): string {
  return `'${v.replace(/'/g, "''")}'`;
}

/* ---------------- Small settings cache ---------------- */
const LS = "lindadata:rdl:";
export function saveSetting(key: string, value: unknown) {
  try {
    localStorage.setItem(LS + key, JSON.stringify(value));
  } catch {
    /* ignore */
  }
}
export function loadSetting<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(LS + key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}
