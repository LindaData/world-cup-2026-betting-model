// Lazy-loaded DuckDB-WASM singleton. The worker is created from a JSDelivr-hosted
// bundle so we don't need to add wasm assets to the Vite bundle.
//
// Public surface: getDuck() returns an AsyncDuckDB instance, initialising on first call.

import type { AsyncDuckDB } from "@duckdb/duckdb-wasm";

let dbPromise: Promise<AsyncDuckDB> | null = null;

export type InitProgress = {
  stage: "idle" | "bundle" | "worker" | "instantiate" | "ready" | "error";
  message?: string;
};

const listeners = new Set<(p: InitProgress) => void>();
let lastProgress: InitProgress = { stage: "idle" };

export function onInitProgress(cb: (p: InitProgress) => void) {
  listeners.add(cb);
  cb(lastProgress);
  return () => {
    listeners.delete(cb);
  };
}

function setProgress(p: InitProgress) {
  lastProgress = p;
  listeners.forEach((l) => l(p));
}

export async function getDuck(): Promise<AsyncDuckDB> {
  if (dbPromise) return dbPromise;
  dbPromise = (async () => {
    try {
      setProgress({ stage: "bundle", message: "Selecting DuckDB-WASM bundle…" });
      const duckdb = await import("@duckdb/duckdb-wasm");
      const bundles = duckdb.getJsDelivrBundles();
      const bundle = await duckdb.selectBundle(bundles);

      setProgress({ stage: "worker", message: "Starting query worker…" });
      const workerUrl = URL.createObjectURL(
        new Blob([`importScripts("${bundle.mainWorker}");`], { type: "text/javascript" }),
      );
      const worker = new Worker(workerUrl);

      setProgress({ stage: "instantiate", message: "Loading query engine…" });
      const logger = new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING);
      const db = new duckdb.AsyncDuckDB(logger, worker);
      await db.instantiate(bundle.mainModule, bundle.pthreadWorker);
      URL.revokeObjectURL(workerUrl);

      setProgress({ stage: "ready" });
      return db;
    } catch (e) {
      setProgress({ stage: "error", message: (e as Error).message });
      dbPromise = null;
      throw e;
    }
  })();
  return dbPromise;
}

/** Run a SQL query and return an array of row objects (JS-safe). */
export async function runSql<T = Record<string, unknown>>(sql: string): Promise<T[]> {
  const db = await getDuck();
  const conn = await db.connect();
  try {
    const result = await conn.query(sql);
    // Convert Arrow records to plain JS objects with serialisable values.
    const out: T[] = [];
    for (const row of result.toArray()) {
      const obj: Record<string, unknown> = {};
      for (const key of Object.keys(row)) {
        const v = row[key];
        obj[key] = normalise(v);
      }
      out.push(obj as T);
    }
    return out;
  } finally {
    await conn.close();
  }
}

function normalise(v: unknown): unknown {
  if (v == null) return null;
  if (typeof v === "bigint") return Number(v);
  if (v instanceof Date) return v.toISOString();
  if (typeof v === "object" && v && "toJSON" in v && typeof (v as { toJSON: unknown }).toJSON === "function") {
    try {
      return (v as { toJSON: () => unknown }).toJSON();
    } catch {
      return String(v);
    }
  }
  return v;
}

/** Run a COPY (...) TO 'name.csv' and read the resulting buffer back. */
export async function exportCsv(sql: string, virtualName = "export.csv"): Promise<Uint8Array> {
  const db = await getDuck();
  const conn = await db.connect();
  try {
    await conn.query(`COPY (${sql}) TO '${virtualName}' WITH (HEADER, FORMAT 'csv')`);
    const buf = await db.copyFileToBuffer(virtualName);
    try {
      await db.dropFile(virtualName);
    } catch {
      /* ignore */
    }
    return buf;
  } finally {
    await conn.close();
  }
}

/** Register a remote URL as a virtual file inside DuckDB. */
export async function registerRemote(name: string, url: string): Promise<void> {
  const db = await getDuck();
  const duckdb = await import("@duckdb/duckdb-wasm");
  await db.registerFileURL(name, url, duckdb.DuckDBDataProtocol.HTTP, false);
}

export async function dropFileSafe(name: string) {
  try {
    const db = await getDuck();
    await db.dropFile(name);
  } catch {
    /* ignore */
  }
}
