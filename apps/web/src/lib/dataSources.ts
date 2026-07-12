import Papa from "papaparse";

const BASE =
  "https://raw.githubusercontent.com/LindaData/world-cup-2026-betting-model/main/docs/sports-data/data";

export type SourceKind = "csv" | "json";

export interface SourceDef {
  key: string;
  label: string;
  kind: SourceKind;
  url: string;
  fallbackUrl?: string;
}

export const SOURCES: SourceDef[] = [
  { key: "manifest", label: "Manifest", kind: "json", url: `${BASE}/manifest.json` },
  { key: "live_manifest", label: "Live Manifest", kind: "json", url: `${BASE}/live_manifest.json` },
  { key: "football_manifest", label: "Football Manifest", kind: "json", url: `${BASE}/football_manifest.json` },
  { key: "football_live", label: "Football Live", kind: "json", url: `${BASE}/football_live.json` },
  { key: "football_fixtures", label: "Football Fixtures", kind: "json", url: `${BASE}/football_fixtures.json` },
  { key: "football_standings", label: "Football Standings", kind: "json", url: `${BASE}/football_standings.json` },
  { key: "nba_live", label: "NBA Live", kind: "json", url: `${BASE}/nba_live.json` },
  { key: "mlb_live", label: "MLB Live", kind: "json", url: `${BASE}/mlb_live.json` },
  { key: "basketball_snapshot", label: "NBA Snapshot", kind: "json", url: `${BASE}/basketball_snapshot.json` },
  { key: "baseball_snapshot", label: "MLB Snapshot", kind: "json", url: `${BASE}/baseball_snapshot.json` },
  {
    key: "basketball_games",
    label: "NBA Games (season)",
    kind: "csv",
    url: `${BASE}/basketball_games_full.csv`,
    fallbackUrl: `${BASE}/basketball_games.csv`,
  },
  {
    key: "basketball_standings",
    label: "NBA Standings",
    kind: "csv",
    url: `${BASE}/basketball_standings.csv`,
  },
  {
    key: "baseball_games",
    label: "MLB Games (season)",
    kind: "csv",
    url: `${BASE}/baseball_games_full.csv`,
    fallbackUrl: `${BASE}/baseball_games.csv`,
  },
  {
    key: "baseball_standings",
    label: "MLB Standings",
    kind: "csv",
    url: `${BASE}/baseball_standings.csv`,
  },
];

export type LoadOrigin = "network" | "fallback" | "cache" | "empty";

export interface LoadResult<T = unknown> {
  key: string;
  data: T | null;
  rows: number;
  origin: LoadOrigin;
  error?: string;
  fetchedAt: string;
  url: string;
}

const LS_PREFIX = "lindadata:";
const TS_KEY = (k: string) => `${LS_PREFIX}${k}:ts`;
const DATA_KEY = (k: string) => `${LS_PREFIX}${k}:data`;
const META_KEY = (k: string) => `${LS_PREFIX}${k}:meta`;

interface CachedMeta {
  rows: number;
  url: string;
  fetchedAt: string;
}

function readCache<T>(key: string): { data: T; meta: CachedMeta } | null {
  try {
    const raw = localStorage.getItem(DATA_KEY(key));
    const meta = localStorage.getItem(META_KEY(key));
    if (!raw || !meta) return null;
    return { data: JSON.parse(raw) as T, meta: JSON.parse(meta) as CachedMeta };
  } catch {
    return null;
  }
}

function writeCache<T>(key: string, data: T, meta: CachedMeta) {
  try {
    localStorage.setItem(DATA_KEY(key), JSON.stringify(data));
    localStorage.setItem(META_KEY(key), JSON.stringify(meta));
    localStorage.setItem(TS_KEY(key), meta.fetchedAt);
  } catch {
    /* quota - ignore */
  }
}

async function fetchText(url: string): Promise<string> {
  const sep = url.includes("?") ? "&" : "?";
  const res = await fetch(`${url}${sep}t=${Date.now()}`, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.text();
}

function parseCsv<T = Record<string, string>>(text: string): T[] {
  const out = Papa.parse<T>(text, {
    header: true,
    skipEmptyLines: true,
    dynamicTyping: false,
  });
  return (out.data || []).filter(
    (r) => r && Object.keys(r as object).length > 0,
  );
}

function rowCount(kind: SourceKind, data: unknown): number {
  if (data == null) return 0;
  if (kind === "csv") return Array.isArray(data) ? data.length : 0;
  if (Array.isArray(data)) return data.length;
  if (typeof data === "object") {
    const d = data as Record<string, unknown>;
    if (Array.isArray(d.events)) return (d.events as unknown[]).length;
    return 1;
  }
  return 0;
}

async function fetchOne(url: string, kind: SourceKind): Promise<{ data: unknown; rows: number }> {
  const text = await fetchText(url);
  if (kind === "csv") {
    const rows = parseCsv(text);
    if (rows.length === 0) throw new Error("Empty CSV");
    return { data: rows, rows: rows.length };
  }
  const data = JSON.parse(text);
  return { data, rows: rowCount(kind, data) };
}

export async function loadSource(src: SourceDef): Promise<LoadResult> {
  const cached = readCache(src.key);
  const now = new Date().toISOString();

  // Try primary
  try {
    const { data, rows } = await fetchOne(src.url, src.kind);
    if (rows > 0) {
      const meta: CachedMeta = { rows, url: src.url, fetchedAt: now };
      writeCache(src.key, data, meta);
      return { key: src.key, data, rows, origin: "network", fetchedAt: now, url: src.url };
    }
    // empty - for JSON live feeds this is valid (no games today)
    if (src.kind === "json") {
      const meta: CachedMeta = { rows, url: src.url, fetchedAt: now };
      writeCache(src.key, data, meta);
      return { key: src.key, data, rows, origin: "network", fetchedAt: now, url: src.url };
    }
    throw new Error("Empty response");
  } catch (primaryErr) {
    // Try fallback
    if (src.fallbackUrl) {
      try {
        const { data, rows } = await fetchOne(src.fallbackUrl, src.kind);
        if (rows > 0) {
          const meta: CachedMeta = { rows, url: src.fallbackUrl, fetchedAt: now };
          writeCache(src.key, data, meta);
          return {
            key: src.key,
            data,
            rows,
            origin: "fallback",
            fetchedAt: now,
            url: src.fallbackUrl,
          };
        }
      } catch {
        /* fall through to cache */
      }
    }
    // Cache
    if (cached) {
      return {
        key: src.key,
        data: cached.data,
        rows: cached.meta.rows,
        origin: "cache",
        fetchedAt: cached.meta.fetchedAt,
        url: cached.meta.url,
        error: (primaryErr as Error).message,
      };
    }
    return {
      key: src.key,
      data: null,
      rows: 0,
      origin: "empty",
      fetchedAt: now,
      url: src.url,
      error: (primaryErr as Error).message,
    };
  }
}

export async function loadAll(): Promise<Record<string, LoadResult>> {
  const settled = await Promise.allSettled(SOURCES.map(loadSource));
  const map: Record<string, LoadResult> = {};
  settled.forEach((s, i) => {
    const src = SOURCES[i];
    if (s.status === "fulfilled") {
      map[s.value.key] = s.value;
    } else {
      map[src.key] = {
        key: src.key,
        data: null,
        rows: 0,
        origin: "empty",
        fetchedAt: new Date().toISOString(),
        url: src.url,
        error: String(s.reason),
      };
    }
  });
  return map;
}
