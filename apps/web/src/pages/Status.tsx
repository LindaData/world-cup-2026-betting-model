import { useSyncExternalStore, useState } from "react";
import { RefreshCw, Copy, Check } from "lucide-react";
import { useData } from "@/context/DataContext";
import { Button } from "@/components/ui/button";
import { StatusBadge, StatusChip, type StatusTone } from "@/components/StatusBadge";
import { SOURCES } from "@/lib/dataSources";
import { DATASETS, getAllStates, loadDataset, subscribe } from "@/lib/parquetData";

/**
 * One-line, ellipsized feed URL: shows the tail path segments in the mono
 * label style with a tap-to-copy affordance for the full URL. Keeps the
 * mobile page scannable instead of a wall of wrapped URLs.
 */
function FeedUrl({ url, prefix }: { url: string; prefix?: string }) {
  const [copied, setCopied] = useState(false);
  const tail = url.split("/").slice(-2).join("/");
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard unavailable */
    }
  };
  return (
    <div className="flex min-w-0 items-center gap-1">
      <a
        href={url}
        target="_blank"
        rel="noreferrer"
        title={url}
        className="min-w-0 truncate font-mono text-[11px] text-muted-foreground hover:text-foreground hover:underline"
      >
        {prefix ? `${prefix}: ` : ""}
        {tail}
      </a>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy URL ${url}`}
        title="Copy full URL"
        className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
      >
        {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
      </button>
    </div>
  );
}

export default function Status() {
  const { results, loading, lastRefresh, refresh } = useData();

  // One page-level summary instead of eleven equally loud amber badges: the
  // count lives up here, the per-card offline chips render dimmed below.
  const offlineCount = SOURCES.filter((s) => {
    const r = results[s.key];
    return r ? r.origin === "empty" : !loading;
  }).length;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <p className="label-mono">Feeds</p>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <h1 className="text-2xl md:text-3xl font-bold">Feed status</h1>
            {offlineCount > 0 && (
              <StatusChip
                tone="warn"
                label={`${offlineCount} of ${SOURCES.length} feeds offline`}
              />
            )}
          </div>
          <p className="text-sm text-muted-foreground mt-1">
            Where each number on this site comes from, and whether it is live
            right now. Cached data is kept between refreshes.
          </p>
          {lastRefresh && (
            <p className="text-xs text-muted-foreground mt-1 tabular-nums">
              Last checked {new Date(lastRefresh).toLocaleString()}
            </p>
          )}
        </div>
        {/* Outline: "Retry failed" below is this screen's one green primary. */}
        <Button
          variant="outline"
          onClick={() => refresh()}
          disabled={loading}
          className="gap-2 min-h-[44px]"
        >
          <RefreshCw
            className={`w-4 h-4 ${loading ? "animate-spin motion-reduce:animate-none" : ""}`}
          />
          Refresh
        </Button>
      </div>

      <div className="grid gap-3 lg:grid-cols-2">
        {SOURCES.map((s) => {
          const r = results[s.key];
          return (
            <div key={s.key} className="surface-card p-4">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-card-foreground">{s.label}</div>
                  <FeedUrl url={r?.url ?? s.url} />
                </div>
                {/* "Loading" is never a terminal state: once the request
                    settles the chip flips to Live / Cached / Demo / Unavailable.
                    Per-card offline chips are dimmed (muted with an amber dot):
                    the loud amber lives only in the page-level summary above. */}
                {r && r.origin !== "empty" ? (
                  <StatusBadge origin={r.origin} />
                ) : !r && loading ? (
                  <StatusChip tone="muted" label="Checking…" />
                ) : (
                  <StatusChip tone="muted" label="Offline" className="[&>span]:bg-warn" />
                )}
              </div>
              <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                <Info label="Rows" value={r ? r.rows.toLocaleString() : "—"} />
                <Info label="Type" value={s.kind.toUpperCase()} />
                {/* Demo data serving the page IS a fallback: never claim "No"
                    while demo rows are rendering elsewhere. */}
                <Info
                  label="Fallback"
                  value={
                    r?.origin === "fallback" ? "Yes" : r?.origin === "demo" ? "Demo" : "No"
                  }
                />
                <Info
                  label="Last success"
                  value={r ? formatStamp(r.fetchedAt) : "—"}
                  title={r ? new Date(r.fetchedAt).toLocaleString() : undefined}
                />
              </div>
              {r?.error && (
                <div className="mt-2 text-[11px] text-muted-foreground">
                  Unreachable at{" "}
                  {new Date(r.fetchedAt).toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}{" "}
                  ({r.error}) — retries on the next refresh.
                </div>
              )}
            </div>
          );
        })}
      </div>

      <ParquetStatusSection />
    </div>
  );
}

/* One status vocabulary page-wide: a broken feed and a broken dataset are the
   same condition, so both say "Offline" through the same chip family. */
const PARQUET_CHIP: Record<string, { label: string; tone: StatusTone }> = {
  ready: { label: "OK", tone: "live" },
  csv_fallback: { label: "OK · CSV", tone: "live" },
  cached: { label: "Cached", tone: "info" },
  loading: { label: "Loading", tone: "muted" },
  unavailable: { label: "Offline", tone: "warn" },
};

const PARQUET_CHIP_IDLE: { label: string; tone: StatusTone } = {
  label: "Not loaded",
  tone: "muted",
};

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
    <section className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <p className="label-mono">Datasets</p>
          <h2 className="text-lg font-semibold mt-0.5">Analysis tables</h2>
          <p className="text-xs text-muted-foreground">
            Loaded in your browser. The compact format is tried first, with a
            plain CSV copy as backup.
          </p>
        </div>
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={diagnostics} className="gap-2 min-h-[44px]">
            <Copy className="w-3 h-3" /> Copy diagnostics
          </Button>
          <Button size="sm" onClick={retry} disabled={busy} className="gap-2 min-h-[44px]">
            <RefreshCw
              className={`w-3 h-3 ${busy ? "animate-spin motion-reduce:animate-none" : ""}`}
            />
            Retry failed feeds
          </Button>
        </div>
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        {DATASETS.map((d) => {
          const s = states.find((x) => x.id === d.id);
          const chip = (s && PARQUET_CHIP[s.status]) || PARQUET_CHIP_IDLE;
          return (
            <div key={d.id} className="surface-card p-4">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-card-foreground">{d.display_name}</div>
                  <FeedUrl url={d.parquet_url} prefix="Parquet" />
                  <FeedUrl url={d.csv_fallback_url} prefix="CSV backup" />
                </div>
                {/* Same dimming rule as the feed cards: offline reads muted
                    with an amber dot, never another loud amber badge. */}
                {chip.tone === "warn" ? (
                  <StatusChip tone="muted" label={chip.label} className="[&>span]:bg-warn" />
                ) : (
                  <StatusChip tone={chip.tone} label={chip.label} />
                )}
              </div>
              <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                <Info label="Format" value={s?.format ?? "—"} />
                <Info
                  label="HTTP"
                  value={
                    s?.httpStatus
                      ? String(s.httpStatus)
                      : s?.parquetHttp
                        ? `parquet ${s.parquetHttp}`
                        : "—"
                  }
                />
                <Info label="Rows" value={s?.rowCount ? s.rowCount.toLocaleString() : "—"} />
                <Info
                  label="Size"
                  value={s?.fileSizeBytes ? `${(s.fileSizeBytes / 1024).toFixed(1)} KB` : "—"}
                />
                <Info
                  label="Generated"
                  value={s?.generatedAt ? formatStamp(s.generatedAt) : "—"}
                  title={s?.generatedAt ? new Date(s.generatedAt).toLocaleString() : undefined}
                />
                <Info
                  label="Loaded"
                  value={s?.loadedAt ? formatStamp(s.loadedAt) : "—"}
                  title={s?.loadedAt ? new Date(s.loadedAt).toLocaleString() : undefined}
                />
                <Info label="Cache" value={s?.status === "cached" ? "Hit" : "—"} />
                {/* No separate "Health" cell: the status chip above already
                    says OK / Loading / Offline. */}
              </div>
              {s?.error && (
                <div className="mt-2 text-[11px] text-muted-foreground">Note: {s.error}</div>
              )}
              <div className="mt-3">
                <Button
                  size="sm"
                  variant="outline"
                  className="min-h-[44px]"
                  onClick={() => loadDataset(d.id, { bustCache: true })}
                >
                  Retry
                </Button>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function Info({ label, value, title }: { label: string; value: string; title?: string }) {
  return (
    <div>
      <div className="label-mono">{label}</div>
      <div className="text-card-foreground font-medium tabular-nums truncate" title={title ?? value}>
        {value}
      </div>
    </div>
  );
}

/**
 * Compact timestamp that fits a 4-column stat cell: time-only for today
 * ("10:51 PM"), short date + time otherwise. The full stamp lives in the
 * cell's title attribute.
 */
function formatStamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const time = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  if (d.toDateString() === new Date().toDateString()) return time;
  return `${d.toLocaleDateString([], { month: "short", day: "numeric" })}, ${time}`;
}
