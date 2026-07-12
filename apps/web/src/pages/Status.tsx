import { useSyncExternalStore, useState } from "react";
import { RefreshCw, Copy } from "lucide-react";
import { useData } from "@/context/DataContext";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/StatusBadge";
import { SOURCES } from "@/lib/dataSources";
import { DATASETS, getAllStates, loadDataset, subscribe } from "@/lib/parquetData";

export default function Status() {
  const { results, loading, lastRefresh, refresh } = useData();

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold">Data Status</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Live view of every upstream source. Cached data is kept between refreshes.
          </p>
          {lastRefresh && (
            <p className="text-xs text-muted-foreground mt-1">
              Last refresh attempt: {new Date(lastRefresh).toLocaleString()}
            </p>
          )}
        </div>
        <Button onClick={() => refresh()} disabled={loading} className="gap-2">
          <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
          Refresh Data
        </Button>
      </div>

      <div className="space-y-2">
        {SOURCES.map((s) => {
          const r = results[s.key];
          return (
            <div key={s.key} className="surface-card p-4">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="min-w-0">
                  <div className="font-semibold text-card-foreground">{s.label}</div>
                  <a
                    href={r?.url ?? s.url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-[11px] text-primary break-all hover:underline"
                  >
                    {r?.url ?? s.url}
                  </a>
                </div>
                {r ? (
                  <StatusBadge origin={r.origin} />
                ) : (
                  <span className="chip bg-muted text-muted-foreground">Loading…</span>
                )}
              </div>
              <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                <Info label="Rows" value={r ? r.rows.toLocaleString() : "—"} />
                <Info label="Type" value={s.kind.toUpperCase()} />
                <Info
                  label="Fallback used"
                  value={r?.origin === "fallback" ? "Yes" : "No"}
                />
                <Info
                  label="Last success"
                  value={r ? new Date(r.fetchedAt).toLocaleString() : "—"}
                />
              </div>
              {r?.error && (
                <div className="mt-2 text-[11px] text-amber-400">Note: {r.error}</div>
              )}
            </div>
          );
        })}
      </div>

      <ParquetStatusSection />
    </div>
  );
}

function ParquetStatusSection() {
  const states = useSyncExternalStore(
    (cb) => subscribe(cb),
    () => getAllStates(),
    () => getAllStates(),
  );
  const [busy, setBusy] = useState(false);

  const retry = async () => {
    setBusy(true);
    try {
      await Promise.allSettled(DATASETS.map((d) => loadDataset(d.id, { bustCache: true })));
    } finally {
      setBusy(false);
    }
  };

  const diagnostics = () => {
    const payload = {
      generated_at: new Date().toISOString(),
      datasets: DATASETS.map((d) => {
        const s = states.find((x) => x.id === d.id);
        return {
          id: d.id,
          display_name: d.display_name,
          parquet_url: d.parquet_url,
          csv_fallback_url: d.csv_fallback_url,
          format_used: s?.format ?? null,
          status: s?.status ?? "idle",
          http_status: s?.httpStatus ?? null,
          parquet_http: s?.parquetHttp ?? null,
          csv_http: s?.csvHttp ?? null,
          rows: s?.rowCount ?? 0,
          file_size_bytes: s?.fileSizeBytes ?? null,
          generated_at_file: s?.generatedAt ?? null,
          loaded_at: s?.loadedAt ?? null,
          error: s?.error ?? null,
        };
      }),
    };
    navigator.clipboard?.writeText(JSON.stringify(payload, null, 2));
  };

  return (
    <section className="space-y-2">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold">Parquet datasets</h2>
          <p className="text-xs text-muted-foreground">
            Engine: DuckDB-WASM in the browser. Parquet is attempted first; CSV is used as fallback.
          </p>
        </div>
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={diagnostics} className="gap-2 min-h-[40px]">
            <Copy className="w-3 h-3" /> Copy diagnostics
          </Button>
          <Button size="sm" onClick={retry} disabled={busy} className="gap-2 min-h-[40px]">
            <RefreshCw className={`w-3 h-3 ${busy ? "animate-spin" : ""}`} />
            Retry failed
          </Button>
        </div>
      </div>
      {DATASETS.map((d) => {
        const s = states.find((x) => x.id === d.id);
        const ok = s && (s.status === "ready" || s.status === "csv_fallback");
        return (
          <div key={d.id} className="surface-card p-4">
            <div className="flex items-start justify-between gap-3 flex-wrap">
              <div className="min-w-0">
                <div className="font-semibold text-card-foreground">{d.display_name}</div>
                <a
                  href={d.parquet_url}
                  target="_blank"
                  rel="noreferrer"
                  className="text-[11px] text-primary break-all hover:underline block"
                >
                  Parquet: {d.parquet_url}
                </a>
                <a
                  href={d.csv_fallback_url}
                  target="_blank"
                  rel="noreferrer"
                  className="text-[11px] text-primary break-all hover:underline block"
                >
                  CSV fallback: {d.csv_fallback_url}
                </a>
              </div>
              <span
                className={`chip ${
                  s?.status === "ready"
                    ? "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30"
                    : s?.status === "csv_fallback"
                      ? "bg-amber-500/15 text-amber-300 border border-amber-500/30"
                      : s?.status === "loading"
                        ? "bg-sky-500/15 text-sky-300 border border-sky-500/30"
                        : s?.status === "unavailable"
                          ? "bg-red-500/15 text-red-300 border border-red-500/30"
                          : "bg-muted text-muted-foreground"
                }`}
              >
                {s?.status === "ready"
                  ? "Parquet"
                  : s?.status === "csv_fallback"
                    ? "CSV fallback"
                    : s?.status === "loading"
                      ? "Loading"
                      : s?.status === "unavailable"
                        ? "Unavailable"
                        : "Not loaded"}
              </span>
            </div>
            <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
              <Info label="Format used" value={s?.format ?? "—"} />
              <Info label="HTTP" value={s?.httpStatus ? String(s.httpStatus) : s?.parquetHttp ? `parquet ${s.parquetHttp}` : "—"} />
              <Info label="Rows" value={s?.rowCount ? s.rowCount.toLocaleString() : "—"} />
              <Info label="Size" value={s?.fileSizeBytes ? `${(s.fileSizeBytes / 1024).toFixed(1)} KB` : "—"} />
              <Info label="Generated" value={s?.generatedAt ? new Date(s.generatedAt).toLocaleString() : "—"} />
              <Info label="Loaded" value={s?.loadedAt ? new Date(s.loadedAt).toLocaleString() : "—"} />
              <Info label="Cache" value={s?.status === "cached" ? "Hit" : "—"} />
              <Info label="Health" value={ok ? "OK" : s?.status === "loading" ? "Loading" : "Action needed"} />
            </div>
            {s?.error && <div className="mt-2 text-[11px] text-amber-400">Note: {s.error}</div>}
            <div className="mt-2">
              <Button
                size="sm"
                variant="outline"
                className="min-h-[36px]"
                onClick={() => loadDataset(d.id, { bustCache: true })}
              >
                Retry
              </Button>
            </div>
          </div>
        );
      })}
    </section>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[11px] uppercase tracking-wider text-muted-foreground">{label}</div>
      <div className="text-card-foreground font-medium truncate">{value}</div>
    </div>
  );
}
