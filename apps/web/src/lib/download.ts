// Browser-side download helpers. Used by dataset cards, record inspector, and
// review basket. CSV escaping handles commas, quotes, newlines, nulls, unicode.

import Papa from "papaparse";

export function triggerDownload(filename: string, blob: Blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function rowsToCsv(rows: Record<string, unknown>[], headers?: string[]): string {
  if (rows.length === 0 && (!headers || headers.length === 0)) return "";
  const cols = headers ?? Array.from(new Set(rows.flatMap((r) => Object.keys(r))));
  const data = rows.map((r) => {
    const out: Record<string, unknown> = {};
    for (const c of cols) {
      const v = r[c];
      out[c] = v == null ? "" : typeof v === "object" ? JSON.stringify(v) : v;
    }
    return out;
  });
  return Papa.unparse({ fields: cols, data: data.map((d) => cols.map((c) => d[c])) }, {
    quotes: true,
    newline: "\n",
  });
}

export function downloadCsv(filename: string, rows: Record<string, unknown>[], headers?: string[]) {
  const csv = rowsToCsv(rows, headers);
  // BOM for Excel UTF-8 compatibility
  triggerDownload(filename, new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8" }));
}

export function downloadJson(filename: string, data: unknown) {
  triggerDownload(filename, new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
}

/**
 * Stream the first N rows from a public CSV URL using Papa Parse, without
 * loading the entire file into memory. Used to deliver a 100-row sample CSV
 * before DuckDB-WASM initialises.
 */
export async function streamCsvSample(
  url: string,
  limit = 100,
): Promise<{ headers: string[]; rows: Record<string, string>[] }> {
  const res = await fetch(`${url}${url.includes("?") ? "&" : "?"}t=${Date.now()}`, {
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const text = await res.text();
  // Use Papa with a small preview; preview cuts off after N rows
  const parsed = Papa.parse<Record<string, string>>(text, {
    header: true,
    skipEmptyLines: true,
    preview: limit,
  });
  return {
    headers: parsed.meta.fields ?? [],
    rows: parsed.data,
  };
}

export async function downloadSampleCsv(
  sourceUrl: string,
  filename: string,
  limit = 100,
): Promise<{ rowCount: number }> {
  const { headers, rows } = await streamCsvSample(sourceUrl, limit);
  downloadCsv(filename, rows as unknown as Record<string, unknown>[], headers);
  return { rowCount: rows.length };
}

export async function downloadRawJson(sourceUrl: string, filename: string) {
  const res = await fetch(`${sourceUrl}${sourceUrl.includes("?") ? "&" : "?"}t=${Date.now()}`, {
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const blob = await res.blob();
  triggerDownload(filename, blob);
}

export function sanitizeFilename(name: string): string {
  return name.replace(/[^a-z0-9._-]+/gi, "_").toLowerCase();
}
