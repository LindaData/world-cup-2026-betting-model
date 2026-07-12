import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { useSearchParams } from "react-router-dom";
import { addToBasket } from "@/lib/reviewBasket";
import { toast } from "@/hooks/use-toast";
import {
  RefreshCw,
  Download,
  Copy,
  X,
  Database,
  Search,
  Filter,
  FileSpreadsheet,
  FileJson,
  Info,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DATASETS,
  type DatasetDef,
  type DatasetState,
  type LoadStatus,
  loadDataset,
  subscribe,
  getAllStates,
  getState,
  quoteIdent,
  sqlString,
  saveSetting,
  loadSetting,
} from "@/lib/parquetData";
import { exportCsv, onInitProgress, runSql, type InitProgress } from "@/lib/duck";

type TabKey = "explore" | "schema" | "quality" | "downloads" | "lineage";

/* ====================== shared subscription hook ====================== */
function useDatasetStates(): DatasetState[] {
  return useSyncExternalStore(
    (cb) => subscribe(cb),
    () => getAllStates(),
    () => getAllStates(),
  );
}

function useInitProgress(): InitProgress {
  const [p, setP] = useState<InitProgress>({ stage: "idle" });
  useEffect(() => onInitProgress(setP), []);
  return p;
}

const STATUS_LABEL: Record<LoadStatus, string> = {
  idle: "Idle",
  loading: "Loading",
  ready: "Ready",
  csv_fallback: "CSV fallback",
  cached: "Cached",
  partial: "Partial",
  unavailable: "Unavailable",
};

function StatusChip({ status }: { status: LoadStatus }) {
  const map: Record<LoadStatus, string> = {
    idle: "bg-muted text-muted-foreground border border-white/10",
    loading: "bg-sky-500/15 text-sky-300 border border-sky-500/30",
    ready: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
    csv_fallback: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
    cached: "bg-sky-500/15 text-sky-300 border border-sky-500/30",
    partial: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
    unavailable: "bg-red-500/15 text-red-300 border border-red-500/30",
  };
  const icon: Record<LoadStatus, string> = {
    idle: "•",
    loading: "◌",
    ready: "●",
    csv_fallback: "▲",
    cached: "■",
    partial: "▲",
    unavailable: "✕",
  };
  return (
    <span
      role="status"
      aria-label={`Dataset status: ${STATUS_LABEL[status]}`}
      className={`chip ${map[status]}`}
    >
      <span aria-hidden>{icon[status]}</span>
      {STATUS_LABEL[status]}
    </span>
  );
}

/* ============================ ROOT ============================ */
export default function RawDataLab() {
  const states = useDatasetStates();
  const initProgress = useInitProgress();

  const [params, setParams] = useSearchParams();
  const urlDataset = params.get("dataset");
  const urlTab = params.get("tab") as TabKey | null;
  const initialId = urlDataset && DATASETS.some((d) => d.id === urlDataset)
    ? urlDataset
    : loadSetting("selectedId", DATASETS[0].id);
  const [selectedId, setSelectedId] = useState<string>(initialId);
  const [tab, setTab] = useState<TabKey>(urlTab && ["explore","schema","quality","downloads","lineage"].includes(urlTab) ? urlTab : "explore");

  useEffect(() => {
    saveSetting("selectedId", selectedId);
    setParams((p) => {
      const next = new URLSearchParams(p);
      next.set("dataset", selectedId);
      return next;
    }, { replace: true });
  }, [selectedId, setParams]);

  // Lazy boot: load the selected dataset on first reach
  useEffect(() => {
    const s = getState(selectedId);
    if (s.status === "idle") void loadDataset(selectedId);
  }, [selectedId]);

  const dataset = DATASETS.find((d) => d.id === selectedId) ?? DATASETS[0];
  const state = states.find((s) => s.id === selectedId) ?? getState(selectedId);

  const refresh = useCallback(
    (id: string) => loadDataset(id, { bustCache: true }),
    [],
  );
  const refreshAll = useCallback(async () => {
    await Promise.allSettled(DATASETS.map((d) => loadDataset(d.id, { bustCache: true })));
  }, []);

  return (
    <div className="space-y-5">
      {/* Header */}
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <h1 className="text-2xl md:text-3xl font-bold flex items-center gap-2">
            <Database className="w-6 h-6 text-primary" aria-hidden />
            Raw Data Lab
          </h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Browser-based explorer powered by DuckDB-WASM and Parquet. Historical research only —
            no betting, profitability, or prediction claims.
          </p>
        </div>
        <div className="flex gap-2">
          <Button
            variant="outline"
            onClick={refreshAll}
            className="gap-2 min-h-[44px]"
            aria-label="Retry failed datasets"
          >
            <RefreshCw className="w-4 h-4" />
            Retry failed
          </Button>
        </div>
      </header>

      {/* Engine status */}
      {initProgress.stage !== "ready" && initProgress.stage !== "idle" && (
        <div className="surface-card p-3 text-sm">
          <div className="flex items-center gap-2">
            <RefreshCw className="w-4 h-4 animate-spin text-primary" />
            <span className="text-card-foreground font-medium">DuckDB engine</span>
            <span className="text-muted-foreground">{initProgress.message}</span>
          </div>
        </div>
      )}
      {initProgress.stage === "error" && (
        <div className="surface-card p-3 text-sm text-red-500">
          DuckDB failed to start: {initProgress.message}
        </div>
      )}

      {/* Transparency notice */}
      <div
        className="text-[12px] text-muted-foreground border border-white/5 rounded-md p-3 bg-white/[0.02] flex gap-2"
        role="note"
      >
        <Info className="w-4 h-4 flex-shrink-0 mt-0.5 text-primary" aria-hidden />
        <p>
          Raw Data Lab provides public historical and live sports-data snapshots for research and
          development. Parquet is used for efficient storage and analysis. CSV downloads are
          available for broader compatibility.
        </p>
      </div>

      {/* Dataset cards */}
      <section aria-label="Datasets">
        <h2 className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Datasets</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
          {DATASETS.map((d) => {
            const s = states.find((x) => x.id === d.id) ?? getState(d.id);
            const selected = d.id === selectedId;
            return (
              <button
                key={d.id}
                onClick={() => setSelectedId(d.id)}
                aria-pressed={selected}
                className={`surface-card text-left p-3 min-h-[96px] focus:outline-none focus-visible:ring-2 focus-visible:ring-primary transition ${
                  selected ? "ring-2 ring-primary" : "hover:bg-white/[0.04]"
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="font-semibold text-card-foreground truncate">{d.display_name}</div>
                    <div className="text-[11px] text-muted-foreground">
                      {d.sport} · {d.dataset_type}
                      {d.season ? ` · ${d.season}` : ""}
                    </div>
                  </div>
                  <StatusChip status={s.status} />
                </div>
                <dl className="mt-2 grid grid-cols-2 gap-x-2 gap-y-0.5 text-[11px]">
                  <DT label="Format" value={formatFormat(s)} />
                  <DT label="Rows" value={s.rowCount ? s.rowCount.toLocaleString() : "—"} />
                  <DT label="Size" value={formatBytes(s.fileSizeBytes)} />
                  <DT label="Loaded" value={shortTime(s.loadedAt)} />
                </dl>
                {(s.earliestDate || s.latestDate) && (
                  <div className="mt-1.5 text-[11px] text-muted-foreground truncate">
                    {shortDate(s.earliestDate)} → {shortDate(s.latestDate)}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </section>

      {/* Tabs */}
      <nav aria-label="Sections" className="flex gap-1 overflow-x-auto -mx-1 px-1 pb-1 sticky top-14 z-20 bg-background/80 backdrop-blur">
        {([
          { k: "explore", label: "Explore" },
          { k: "schema", label: "Schema" },
          { k: "quality", label: "Quality" },
          { k: "downloads", label: "Downloads" },
          { k: "lineage", label: "Lineage" },
        ] as { k: TabKey; label: string }[]).map((t) => (
          <button
            key={t.k}
            onClick={() => setTab(t.k)}
            aria-current={tab === t.k ? "page" : undefined}
            className={`min-h-[44px] px-4 rounded-md text-sm font-medium whitespace-nowrap focus:outline-none focus-visible:ring-2 focus-visible:ring-primary ${
              tab === t.k ? "bg-primary text-primary-foreground" : "bg-white/5 text-foreground/80"
            }`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      {/* Dataset-level refresh */}
      <div className="flex items-center justify-between text-xs text-muted-foreground -mt-2">
        <div className="truncate">
          <strong className="text-foreground">{dataset.display_name}</strong>
          {state.format && <span className="ml-2">· {state.format.toUpperCase()}</span>}
          {state.status === "csv_fallback" && (
            <span className="ml-2 text-amber-400">Parquet file not yet available — using CSV fallback.</span>
          )}
        </div>
        <Button
          size="sm"
          variant="outline"
          className="min-h-[36px]"
          onClick={() => refresh(dataset.id)}
          disabled={state.status === "loading"}
        >
          <RefreshCw className={`w-3 h-3 ${state.status === "loading" ? "animate-spin" : ""}`} />
          Refresh
        </Button>
      </div>

      {/* Body */}
      {state.status === "loading" && <SkeletonRows />}
      {state.status === "unavailable" && (
        <div className="surface-card p-4 text-sm">
          <div className="text-red-400 font-medium">Dataset unavailable</div>
          <div className="text-muted-foreground mt-1">{state.error}</div>
          <Button className="mt-3" size="sm" onClick={() => refresh(dataset.id)}>
            Retry
          </Button>
        </div>
      )}
      {state.table && state.status !== "loading" && (
        <>
          {tab === "explore" && <ExploreTab dataset={dataset} state={state} />}
          {tab === "schema" && <SchemaTab dataset={dataset} state={state} />}
          {tab === "quality" && <QualityTab dataset={dataset} state={state} />}
          {tab === "downloads" && <DownloadsTab dataset={dataset} state={state} />}
          {tab === "lineage" && <LineageTab dataset={dataset} state={state} />}
        </>
      )}
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className="space-y-2" aria-busy="true" aria-label="Loading dataset">
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i} className="surface-card p-4 animate-pulse">
          <div className="h-3 w-2/3 bg-muted rounded mb-2" />
          <div className="h-3 w-1/3 bg-muted rounded" />
        </div>
      ))}
    </div>
  );
}

function DT({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-card-foreground text-right truncate">{value}</dd>
    </>
  );
}

function formatFormat(s: DatasetState): string {
  if (!s.format) return "—";
  if (s.format === "parquet") return "Parquet";
  if (s.format === "json") return "JSON fallback";
  return "CSV fallback";
}
function formatBytes(n: number | null): string {
  if (n == null) return "—";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}
function shortTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
function shortDate(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso.slice(0, 10) : d.toLocaleDateString();
}

/* ============================ EXPLORE ============================ */

type SampleMode = "latest" | "earliest" | "first" | "random" | "full";

function ExploreTab({ dataset, state }: { dataset: DatasetDef; state: DatasetState }) {
  const columns = state.columns;
  const dateCol = useMemo(
    () => columns.find((c) => /^date_utc$|date|timestamp/i.test(c.name))?.name ?? null,
    [columns],
  );
  const defaultCols = useMemo(() => pickDefaultColumns(dataset, columns.map((c) => c.name)), [dataset, columns]);

  const [search, setSearch] = useState("");
  const [filters, setFilters] = useState<Record<string, string>>({});
  const [visibleCols, setVisibleCols] = useState<string[]>(defaultCols);
  const [sortCol, setSortCol] = useState<string | null>(dateCol);
  const [sortDir, setSortDir] = useState<"asc" | "desc">("desc");
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(25);
  const [sampleMode, setSampleMode] = useState<SampleMode>("latest");
  const [sampleSize, setSampleSize] = useState(25);
  const [seed, setSeed] = useState(1);
  const [colChooser, setColChooser] = useState(false);
  const [filterPanel, setFilterPanel] = useState(false);
  const [inspected, setInspected] = useState<Record<string, unknown> | null>(null);

  useEffect(() => {
    setVisibleCols(defaultCols);
    setSearch("");
    setFilters({});
    setSortCol(dateCol);
    setSortDir("desc");
    setPage(0);
  }, [dataset.id, defaultCols, dateCol]);

  // Build WHERE clause
  const whereSql = useMemo(() => {
    const parts: string[] = [];
    const s = search.trim();
    if (s) {
      const like = sqlString(`%${s}%`);
      const expr = columns
        .map((c) => `CAST(${quoteIdent(c.name)} AS VARCHAR) ILIKE ${like}`)
        .join(" OR ");
      if (expr) parts.push(`(${expr})`);
    }
    for (const [col, val] of Object.entries(filters)) {
      const v = val.trim();
      if (!v) continue;
      parts.push(`CAST(${quoteIdent(col)} AS VARCHAR) ILIKE ${sqlString(`%${v}%`)}`);
    }
    return parts.length ? `WHERE ${parts.join(" AND ")}` : "";
  }, [search, filters, columns]);

  const orderSql = useMemo(() => {
    if (!sortCol) return "";
    return `ORDER BY ${quoteIdent(sortCol)} ${sortDir.toUpperCase()}`;
  }, [sortCol, sortDir]);

  // Build sample subquery (latest/earliest/first/random/full)
  const baseQuery = useMemo(() => {
    const tbl = state.table!;
    if (sampleMode === "full") return `SELECT * FROM ${tbl}`;
    if (sampleMode === "first") return `SELECT * FROM ${tbl} LIMIT ${sampleSize}`;
    if (sampleMode === "latest" && dateCol)
      return `SELECT * FROM ${tbl} ORDER BY ${quoteIdent(dateCol)} DESC NULLS LAST LIMIT ${sampleSize}`;
    if (sampleMode === "earliest" && dateCol)
      return `SELECT * FROM ${tbl} ORDER BY ${quoteIdent(dateCol)} ASC NULLS LAST LIMIT ${sampleSize}`;
    if (sampleMode === "random")
      return `SELECT * FROM (SELECT *, hash(rowid::VARCHAR || '${seed}') AS _h FROM ${tbl}) ORDER BY _h LIMIT ${sampleSize}`;
    return `SELECT * FROM ${tbl} LIMIT ${sampleSize}`;
  }, [state.table, sampleMode, sampleSize, seed, dateCol]);

  // Filtered count + paginated rows
  const [totalFiltered, setTotalFiltered] = useState<number>(0);
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setRunning(true);
      try {
        const sample = `(${baseQuery}) AS _sample`;
        const countRows = await runSql<{ n: number }>(
          `SELECT COUNT(*)::INT AS n FROM ${sample} ${whereSql}`,
        );
        const total = Number(countRows[0]?.n ?? 0);
        const pageSql = `SELECT * FROM ${sample} ${whereSql} ${orderSql} LIMIT ${pageSize} OFFSET ${page * pageSize}`;
        const data = await runSql(pageSql);
        if (!cancelled) {
          setTotalFiltered(total);
          setRows(data);
        }
      } catch (e) {
        if (!cancelled) {
          setTotalFiltered(0);
          setRows([]);
          console.error(e);
        }
      } finally {
        if (!cancelled) setRunning(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [baseQuery, whereSql, orderSql, pageSize, page]);

  const totalPages = Math.max(1, Math.ceil(totalFiltered / pageSize));
  const safePage = Math.min(page, totalPages - 1);

  return (
    <div className="space-y-3">
      {/* Top controls */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[160px]">
          <Search className="w-4 h-4 absolute left-2 top-1/2 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            placeholder="Search all visible fields"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(0);
            }}
            className="pl-8 h-11 bg-background text-foreground"
            aria-label="Search records"
          />
        </div>
        <Button
          variant="outline"
          className="min-h-[44px]"
          onClick={() => setFilterPanel((o) => !o)}
          aria-expanded={filterPanel}
        >
          <Filter className="w-4 h-4" /> Filters
        </Button>
        <Button variant="outline" className="min-h-[44px]" onClick={() => setColChooser((o) => !o)}>
          Columns ({visibleCols.length}/{columns.length})
        </Button>
      </div>

      {/* Filter panel */}
      {filterPanel && (
        <div className="surface-card p-3 space-y-2">
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
            <Select
              label="Sample"
              value={sampleMode}
              onChange={(v) => {
                setSampleMode(v as SampleMode);
                setPage(0);
              }}
              options={[
                ["latest", "Latest"],
                ["earliest", "Earliest"],
                ["first", "First records"],
                ["random", "Random"],
                ["full", "Full query"],
              ]}
            />
            <Select
              label="Sample size"
              value={String(sampleSize)}
              onChange={(v) => setSampleSize(Number(v))}
              disabled={sampleMode === "full"}
              options={[10, 25, 50, 100, 250, 500].map((n) => [String(n), String(n)])}
            />
            <Select
              label="Page size"
              value={String(pageSize)}
              onChange={(v) => {
                setPageSize(Number(v));
                setPage(0);
              }}
              options={[10, 25, 50, 100, 250].map((n) => [String(n), String(n)])}
            />
          </div>
          <div className="flex flex-wrap gap-2">
            {sampleMode === "random" && (
              <Button size="sm" variant="outline" className="min-h-[40px]" onClick={() => setSeed((s) => s + 1)}>
                New random sample
              </Button>
            )}
            <Button
              size="sm"
              variant="outline"
              className="min-h-[40px]"
              onClick={() => {
                if (!dateCol) return;
                setSortCol(dateCol);
                setSortDir("desc");
              }}
              disabled={!dateCol}
            >
              Sort newest
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="min-h-[40px]"
              onClick={() => {
                if (!dateCol) return;
                setSortCol(dateCol);
                setSortDir("asc");
              }}
              disabled={!dateCol}
            >
              Sort oldest
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="min-h-[40px]"
              onClick={() => {
                setSearch("");
                setFilters({});
                setSortCol(dateCol);
                setSortDir("desc");
                setPage(0);
              }}
            >
              Clear filters
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="min-h-[40px]"
              onClick={() => setVisibleCols(defaultCols)}
            >
              Reset columns
            </Button>
          </div>

          {/* Per-column filters */}
          <details className="text-xs">
            <summary className="cursor-pointer text-muted-foreground py-1">Per-column filters</summary>
            <div className="mt-2 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
              {visibleCols.map((c) => (
                <label key={c} className="block">
                  <span className="text-[10px] uppercase text-muted-foreground">{c}</span>
                  <Input
                    value={filters[c] ?? ""}
                    onChange={(e) => {
                      setFilters((f) => ({ ...f, [c]: e.target.value }));
                      setPage(0);
                    }}
                    placeholder="contains…"
                    className="h-9 bg-background text-foreground"
                  />
                </label>
              ))}
            </div>
          </details>
        </div>
      )}

      {/* Column chooser */}
      {colChooser && (
        <div className="surface-card p-3 max-h-56 overflow-auto">
          <div className="flex gap-2 mb-1 text-[11px]">
            <button className="text-primary hover:underline" onClick={() => setVisibleCols(columns.map((c) => c.name))}>
              All
            </button>
            <button className="text-primary hover:underline" onClick={() => setVisibleCols([])}>
              None
            </button>
            <button className="text-primary hover:underline ml-auto" onClick={() => setVisibleCols(defaultCols)}>
              Reset
            </button>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-1">
            {columns.map((c) => (
              <label key={c.name} className="flex items-center gap-1 text-[12px] text-card-foreground min-h-[28px]">
                <input
                  type="checkbox"
                  checked={visibleCols.includes(c.name)}
                  onChange={(e) =>
                    setVisibleCols((v) => (e.target.checked ? [...v, c.name] : v.filter((x) => x !== c.name)))
                  }
                />
                {c.name}
              </label>
            ))}
          </div>
        </div>
      )}

      {/* Count line */}
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <div aria-live="polite">
          Showing {Math.min(rows.length, pageSize).toLocaleString()} of {totalFiltered.toLocaleString()} records
          {running && <span className="ml-2">· querying…</span>}
        </div>
        {sampleMode !== "full" && totalFiltered < state.rowCount && (
          <Button size="sm" variant="outline" className="min-h-[36px]" onClick={() => setSampleMode("full")}>
            View more records
          </Button>
        )}
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-2">
        {rows.map((r, i) => (
          <RecordCard key={i} dataset={dataset} row={r} index={safePage * pageSize + i + 1} onTap={() => setInspected(r)} />
        ))}
        {!rows.length && !running && (
          <div className="text-sm text-muted-foreground text-center py-8">No records.</div>
        )}
      </div>

      {/* Desktop table */}
      <div className="hidden md:block surface-card overflow-x-auto max-h-[65vh]">
        <table className="text-xs min-w-full">
          <thead className="sticky top-0 bg-card z-10">
            <tr className="border-b border-black/10">
              <th scope="col" className="px-2 py-2 text-left font-medium">#</th>
              {visibleCols.map((c) => (
                <th
                  key={c}
                  scope="col"
                  className="px-2 py-2 text-left font-medium whitespace-nowrap cursor-pointer hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                  onClick={() => {
                    if (sortCol === c) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
                    else {
                      setSortCol(c);
                      setSortDir("asc");
                    }
                  }}
                  tabIndex={0}
                >
                  <span className="inline-flex items-center gap-1">
                    {c}
                    {sortCol === c && <span aria-hidden>{sortDir === "asc" ? "▲" : "▼"}</span>}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr
                key={i}
                onClick={() => setInspected(r)}
                className="border-t border-black/5 text-card-foreground hover:bg-muted/40 cursor-pointer"
              >
                <td className="px-2 py-1 text-muted-foreground tabular-nums">{safePage * pageSize + i + 1}</td>
                {visibleCols.map((c) => (
                  <td key={c} className="px-2 py-1 whitespace-nowrap max-w-[260px] truncate" title={String(r[c] ?? "")}>
                    {fmtCell(r[c])}
                  </td>
                ))}
              </tr>
            ))}
            {!rows.length && !running && (
              <tr>
                <td colSpan={visibleCols.length + 1} className="text-center py-6 text-muted-foreground">
                  No records.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <Button
          variant="outline"
          size="sm"
          className="min-h-[40px]"
          disabled={safePage === 0}
          onClick={() => setPage((p) => Math.max(0, p - 1))}
        >
          Prev
        </Button>
        <span>
          Page {safePage + 1} / {totalPages}
        </span>
        <Button
          variant="outline"
          size="sm"
          className="min-h-[40px]"
          disabled={safePage >= totalPages - 1}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </Button>
      </div>

      {inspected && <RecordInspector record={inspected} dataset={dataset} onClose={() => setInspected(null)} />}
    </div>
  );
}

function Select({
  label,
  value,
  onChange,
  options,
  disabled,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: [string, string][];
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        className="mt-0.5 w-full min-h-[44px] bg-background text-foreground border border-input rounded-md px-2 text-sm disabled:opacity-50"
      >
        {options.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </select>
    </label>
  );
}

function fmtCell(v: unknown): string {
  if (v == null) return "";
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}

function pickDefaultColumns(dataset: DatasetDef, all: string[]): string[] {
  const prefer = {
    games: ["date_utc", "status", "away_team", "away_score", "home_team", "home_score", "league", "season"],
    standings: ["position", "team", "group", "played", "wins", "losses", "percentage", "form"],
    live: ["date_utc", "status", "name", "home_team", "home_score", "away_team", "away_score"],
    manifest: all,
  } as const;
  const want = prefer[dataset.dataset_type] ?? all;
  const chosen = want.filter((w) => all.includes(w));
  return chosen.length ? chosen : all.slice(0, Math.min(8, all.length));
}

/* ============================ RECORD CARD ============================ */

function RecordCard({
  dataset,
  row,
  index,
  onTap,
}: {
  dataset: DatasetDef;
  row: Record<string, unknown>;
  index: number;
  onTap: () => void;
}) {
  if (dataset.dataset_type === "games" || dataset.dataset_type === "live") {
    return (
      <button
        onClick={onTap}
        className="surface-card p-3 w-full text-left min-h-[88px] focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <div className="flex justify-between text-[11px] text-muted-foreground mb-1">
          <span>#{index} · {shortDate(String(row.date_utc ?? ""))}</span>
          <span>{String(row.status ?? "")}</span>
        </div>
        <div className="grid grid-cols-[1fr_auto] gap-y-1 items-center text-card-foreground">
          <div className="font-medium truncate">{String(row.away_team ?? row.name ?? "")}</div>
          <div className="font-bold tabular-nums">{String(row.away_score ?? "")}</div>
          <div className="font-medium truncate">{String(row.home_team ?? "")}</div>
          <div className="font-bold tabular-nums">{String(row.home_score ?? "")}</div>
        </div>
        <div className="mt-1 text-[11px] text-muted-foreground truncate">
          {String(row.league ?? "")} {row.season ? `· ${row.season}` : ""}
        </div>
      </button>
    );
  }
  if (dataset.dataset_type === "standings") {
    return (
      <button
        onClick={onTap}
        className="surface-card p-3 w-full text-left min-h-[72px] focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 min-w-0">
            <span className="font-bold tabular-nums text-card-foreground w-6 text-right">
              {String(row.position ?? "")}
            </span>
            <span className="font-medium truncate text-card-foreground">{String(row.team ?? "")}</span>
          </div>
          <span className="chip bg-muted text-card-foreground">{String(row.group ?? "")}</span>
        </div>
        <div className="mt-2 grid grid-cols-5 gap-1 text-[11px] text-card-foreground">
          <Mini label="GP" value={String(row.played ?? "")} />
          <Mini label="W" value={String(row.wins ?? "")} />
          <Mini label="L" value={String(row.losses ?? "")} />
          <Mini label="Pct" value={String(row.percentage ?? "")} />
          <Mini label="Form" value={String(row.form ?? "")} />
        </div>
      </button>
    );
  }
  return (
    <button onClick={onTap} className="surface-card p-3 w-full text-left">
      <div className="text-[11px] text-muted-foreground">#{index}</div>
      <div className="text-card-foreground">Tap to inspect</div>
    </button>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="text-center">
      <div className="text-[9px] uppercase text-muted-foreground">{label}</div>
      <div className="tabular-nums">{value || "—"}</div>
    </div>
  );
}

/* ============================ INSPECTOR ============================ */

function RecordInspector({
  record,
  dataset,
  onClose,
}: {
  record: Record<string, unknown>;
  dataset: DatasetDef;
  onClose: () => void;
}) {
  const [view, setView] = useState<"fields" | "json">("fields");
  const json = JSON.stringify(record, null, 2);

  const copy = (text: string) => navigator.clipboard?.writeText(text).catch(() => {});
  const downloadJson = () =>
    downloadBlob(`${dataset.filename_base}_record.json`, new Blob([json], { type: "application/json" }));
  const downloadCsvFn = () => {
    const cols = Object.keys(record);
    const header = cols.map(csvEscape).join(",");
    const row = cols.map((c) => csvEscape(stringifyValue(record[c]))).join(",");
    downloadBlob(`${dataset.filename_base}_record.csv`, new Blob([header + "\n" + row], { type: "text/csv" }));
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div role="dialog" aria-modal="true" aria-label="Record details" className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-end md:items-center md:justify-end">
      <div className="bg-card text-card-foreground w-full md:max-w-md md:h-full max-h-[85vh] md:max-h-full rounded-t-2xl md:rounded-none overflow-hidden flex flex-col shadow-xl">
        <div className="flex items-center justify-between p-3 border-b border-black/10">
          <div className="font-semibold">Record details</div>
          <button onClick={onClose} className="p-2 rounded hover:bg-muted min-h-[44px] min-w-[44px]" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="flex gap-1 p-2 border-b border-black/5 flex-wrap">
          <button
            onClick={() => setView("fields")}
            className={`px-3 py-1.5 text-xs rounded min-h-[36px] ${view === "fields" ? "bg-primary text-primary-foreground" : "bg-muted"}`}
          >
            Fields
          </button>
          <button
            onClick={() => setView("json")}
            className={`px-3 py-1.5 text-xs rounded min-h-[36px] ${view === "json" ? "bg-primary text-primary-foreground" : "bg-muted"}`}
          >
            Pretty JSON
          </button>
          <button onClick={() => copy(json)} className="ml-auto px-3 py-1.5 text-xs rounded bg-muted min-h-[36px] inline-flex items-center gap-1">
            <Copy className="w-3 h-3" /> Copy JSON
          </button>
          <button onClick={downloadJson} className="px-3 py-1.5 text-xs rounded bg-muted min-h-[36px] inline-flex items-center gap-1">
            <Download className="w-3 h-3" /> JSON
          </button>
          <button onClick={downloadCsvFn} className="px-3 py-1.5 text-xs rounded bg-muted min-h-[36px] inline-flex items-center gap-1">
            <Download className="w-3 h-3" /> CSV
          </button>
          <button
            onClick={async () => {
              await addToBasket({
                dataset_id: dataset.id,
                dataset_name: dataset.display_name,
                record,
              });
              toast({ title: "Added to review basket" });
            }}
            className="px-3 py-1.5 text-xs rounded bg-primary text-primary-foreground min-h-[36px] inline-flex items-center gap-1"
          >
            + Basket
          </button>
        </div>
        <div className="overflow-auto p-3">
          {view === "fields" ? (
            <div className="space-y-2">
              {Object.entries(record).map(([k, v]) => {
                const empty = v == null || (typeof v === "string" && v.trim() === "");
                const type = inferType(v);
                const display = stringifyValue(v);
                return (
                  <div key={k} className="border border-black/5 rounded-md p-2">
                    <div className="flex items-center justify-between gap-2">
                      <code className="text-[11px] uppercase tracking-wider text-muted-foreground">{k}</code>
                      <div className="flex items-center gap-2">
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{type}</span>
                        {empty && (
                          <span className="text-[10px] px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-600">
                            missing
                          </span>
                        )}
                        <button onClick={() => copy(display)} className="text-[10px] inline-flex items-center gap-1 text-primary min-h-[28px] px-1">
                          <Copy className="w-3 h-3" /> Copy
                        </button>
                      </div>
                    </div>
                    <div className="font-mono text-xs break-all mt-1">{display || <em className="text-muted-foreground">—</em>}</div>
                  </div>
                );
              })}
            </div>
          ) : (
            <pre className="text-xs whitespace-pre-wrap break-all bg-muted/40 rounded p-2">{json}</pre>
          )}
        </div>
      </div>
    </div>
  );
}

function inferType(v: unknown): string {
  if (v == null) return "null";
  if (typeof v === "boolean") return "boolean";
  if (typeof v === "number") return Number.isInteger(v) ? "integer" : "number";
  if (typeof v === "object") return Array.isArray(v) ? "array" : "object";
  const s = String(v).trim();
  if (s === "") return "empty";
  if (/^-?\d+$/.test(s)) return "integer";
  if (/^-?\d+\.\d+$/.test(s)) return "number";
  if (/^\d{4}-\d{2}-\d{2}/.test(s) && !isNaN(new Date(s).getTime())) return "date";
  return "string";
}
function stringifyValue(v: unknown): string {
  if (v == null) return "";
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}

/* ============================ SCHEMA ============================ */

interface FieldStat {
  field: string;
  type: string;
  nonEmpty: number;
  missing: number;
  missingPct: number;
  unique: number;
  example: string;
  min?: string;
  max?: string;
  avg?: number;
  median?: number;
  top?: { value: string; count: number; pct: number }[];
}

const schemaCache = new Map<string, FieldStat[]>();

function SchemaTab({ dataset, state }: { dataset: DatasetDef; state: DatasetState }) {
  const [stats, setStats] = useState<FieldStat[] | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const key = `${dataset.id}:${state.loadedAt}`;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const cached = schemaCache.get(key);
      if (cached) {
        setStats(cached);
        return;
      }
      setRunning(true);
      setError(null);
      try {
        const out = await profileColumns(state.table!, state.columns, state.rowCount);
        if (!cancelled) {
          schemaCache.set(key, out);
          setStats(out);
        }
      } catch (e) {
        if (!cancelled) setError((e as Error).message);
      } finally {
        if (!cancelled) setRunning(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [key, state.table, state.columns, state.rowCount]);

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-xs text-muted-foreground">
          Profiling runs only when you open this tab; results are cached per dataset.
        </p>
        <Button
          size="sm"
          variant="outline"
          className="min-h-[40px]"
          disabled={!stats}
          onClick={() => {
            if (!stats) return;
            const csv = schemaToCsv(stats);
            downloadBlob(`${dataset.filename_base}_schema.csv`, new Blob([csv], { type: "text/csv" }));
          }}
        >
          <Download className="w-3 h-3" /> Schema CSV
        </Button>
      </div>
      {running && <SkeletonRows />}
      {error && <div className="surface-card p-3 text-red-400 text-sm">{error}</div>}
      <div className="space-y-2">
        {stats?.map((s) => (
          <div key={s.field} className="surface-card p-3">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div className="font-semibold text-card-foreground">{s.field}</div>
              <span className="chip bg-primary/10 text-primary border border-primary/20">{s.type}</span>
            </div>
            <dl className="mt-2 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
              <Stat label="Non-empty" value={s.nonEmpty.toLocaleString()} />
              <Stat label="Missing" value={`${s.missing.toLocaleString()} (${s.missingPct.toFixed(1)}%)`} />
              <Stat label="Unique" value={s.unique.toLocaleString()} />
              <Stat label="Example" value={s.example || "—"} />
              {s.avg != null && <Stat label="Min" value={String(s.min ?? "—")} />}
              {s.avg != null && <Stat label="Max" value={String(s.max ?? "—")} />}
              {s.avg != null && <Stat label="Avg" value={s.avg.toFixed(2)} />}
              {s.median != null && <Stat label="Median" value={String(s.median)} />}
              {s.top == null && s.avg == null && s.min && <Stat label="Earliest" value={String(s.min)} />}
              {s.top == null && s.avg == null && s.max && <Stat label="Latest" value={String(s.max)} />}
            </dl>
            {s.top && s.top.length > 0 && (
              <div className="mt-2">
                <div className="text-[10px] uppercase text-muted-foreground mb-1">Top values</div>
                <div className="flex flex-wrap gap-1">
                  {s.top.map((t) => (
                    <span key={t.value} className="chip bg-muted text-card-foreground">
                      {t.value} · {t.count.toLocaleString()} ({t.pct.toFixed(1)}%)
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[10px] uppercase text-muted-foreground">{label}</dt>
      <dd className="text-card-foreground truncate" title={value}>
        {value}
      </dd>
    </div>
  );
}

async function profileColumns(table: string, columns: { name: string; type: string }[], total: number) {
  const out: FieldStat[] = [];
  for (const c of columns) {
    const col = quoteIdent(c.name);
    try {
      const numeric = /INT|DECIMAL|DOUBLE|FLOAT|REAL|NUMERIC|BIGINT|SMALL/i.test(c.type);
      const dateLike = /DATE|TIMESTAMP/i.test(c.type) || /^date_utc$|date/i.test(c.name);

      const r = await runSql<{ nonempty: number; uniq: number; example: string | null }>(
        `SELECT
           COUNT(${col})::INT AS nonempty,
           COUNT(DISTINCT ${col})::INT AS uniq,
           ANY_VALUE(CAST(${col} AS VARCHAR)) AS example
         FROM ${table}
         WHERE ${col} IS NOT NULL AND CAST(${col} AS VARCHAR) <> ''`,
      );
      const nonEmpty = Number(r[0]?.nonempty ?? 0);
      const missing = total - nonEmpty;
      const stat: FieldStat = {
        field: c.name,
        type: c.type,
        nonEmpty,
        missing,
        missingPct: total ? (missing / total) * 100 : 0,
        unique: Number(r[0]?.uniq ?? 0),
        example: r[0]?.example ?? "",
      };

      if (numeric) {
        const n = await runSql<{ mn: number; mx: number; av: number; md: number }>(
          `SELECT MIN(${col})::DOUBLE AS mn, MAX(${col})::DOUBLE AS mx, AVG(${col})::DOUBLE AS av, MEDIAN(${col})::DOUBLE AS md FROM ${table}`,
        );
        stat.min = String(n[0]?.mn ?? "");
        stat.max = String(n[0]?.mx ?? "");
        stat.avg = Number(n[0]?.av ?? 0);
        stat.median = Number(n[0]?.md ?? 0);
      } else if (dateLike) {
        const d = await runSql<{ mn: string; mx: string }>(
          `SELECT MIN(${col})::VARCHAR AS mn, MAX(${col})::VARCHAR AS mx FROM ${table}`,
        );
        stat.min = d[0]?.mn ?? "";
        stat.max = d[0]?.mx ?? "";
      } else {
        const top = await runSql<{ v: string; n: number }>(
          `SELECT CAST(${col} AS VARCHAR) AS v, COUNT(*)::INT AS n FROM ${table}
           WHERE ${col} IS NOT NULL AND CAST(${col} AS VARCHAR) <> ''
           GROUP BY v ORDER BY n DESC LIMIT 5`,
        );
        stat.top = top.map((t) => ({
          value: t.v,
          count: Number(t.n),
          pct: total ? (Number(t.n) / total) * 100 : 0,
        }));
      }
      out.push(stat);
    } catch {
      out.push({
        field: c.name,
        type: c.type,
        nonEmpty: 0,
        missing: total,
        missingPct: 100,
        unique: 0,
        example: "",
      });
    }
  }
  return out;
}

function schemaToCsv(stats: FieldStat[]): string {
  const head = "field,type,non_empty,missing,missing_pct,unique,min,max,avg,median,example";
  const lines = stats.map((s) =>
    [
      s.field,
      s.type,
      s.nonEmpty,
      s.missing,
      s.missingPct.toFixed(2),
      s.unique,
      s.min ?? "",
      s.max ?? "",
      s.avg ?? "",
      s.median ?? "",
      s.example ?? "",
    ]
      .map((v) => csvEscape(String(v)))
      .join(","),
  );
  return [head, ...lines].join("\n");
}

/* ============================ QUALITY ============================ */

interface QualityResult {
  totalRows: number;
  uniqueTeams: number;
  dateRange: { earliest: string | null; latest: string | null };
  completed: number;
  scheduled: number;
  live: number;
  missingTeamNames: number;
  missingDates: number;
  missingScores: number;
  invalidScores: number;
  invalidTimestamps: number;
  emptySeasons: number;
  duplicateGameIds: number;
  duplicateRows: number;
  statusDist: { status: string; count: number }[];
  seasons: string[];
}

const qualityCache = new Map<string, QualityResult>();

function QualityTab({ dataset, state }: { dataset: DatasetDef; state: DatasetState }) {
  const [q, setQ] = useState<QualityResult | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const key = `${dataset.id}:${state.loadedAt}`;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const cached = qualityCache.get(key);
      if (cached) {
        setQ(cached);
        return;
      }
      setRunning(true);
      setError(null);
      try {
        const r = await computeQuality(state.table!, state.columns, state.rowCount);
        if (!cancelled) {
          qualityCache.set(key, r);
          setQ(r);
        }
      } catch (e) {
        if (!cancelled) setError((e as Error).message);
      } finally {
        if (!cancelled) setRunning(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [key, state.table, state.columns, state.rowCount]);

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Button
          size="sm"
          variant="outline"
          className="min-h-[40px]"
          disabled={!q}
          onClick={() => {
            if (!q) return;
            const csv = qualityToCsv(q);
            downloadBlob(`${dataset.filename_base}_quality_report.csv`, new Blob([csv], { type: "text/csv" }));
          }}
        >
          <Download className="w-3 h-3" /> Quality CSV
        </Button>
      </div>
      {running && <SkeletonRows />}
      {error && <div className="surface-card p-3 text-red-400 text-sm">{error}</div>}
      {q && (
        <>
          <div className="surface-card p-3">
            <h3 className="text-sm font-semibold mb-2 text-card-foreground">Summary</h3>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
              <Stat label="Total records" value={q.totalRows.toLocaleString()} />
              <Stat label="Unique teams" value={q.uniqueTeams.toLocaleString()} />
              <Stat
                label="Date range"
                value={
                  q.dateRange.earliest
                    ? `${shortDate(q.dateRange.earliest)} → ${shortDate(q.dateRange.latest)}`
                    : "—"
                }
              />
              <Stat label="Seasons" value={q.seasons.join(", ") || "—"} />
              <Stat label="Completed" value={q.completed.toLocaleString()} />
              <Stat label="Scheduled" value={q.scheduled.toLocaleString()} />
              <Stat label="Live" value={q.live.toLocaleString()} />
              <Stat label="Possible duplicates" value={(q.duplicateGameIds + q.duplicateRows).toLocaleString()} />
            </div>
          </div>
          <div className="surface-card p-3">
            <h3 className="text-sm font-semibold mb-2 text-card-foreground">Checks</h3>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
              <QCheck label="Duplicate game IDs" value={q.duplicateGameIds} />
              <QCheck label="Duplicate rows" value={q.duplicateRows} />
              <QCheck label="Missing team names" value={q.missingTeamNames} />
              <QCheck label="Missing dates" value={q.missingDates} />
              <QCheck label="Missing scores" value={q.missingScores} />
              <QCheck label="Invalid scores" value={q.invalidScores} />
              <QCheck label="Invalid timestamps" value={q.invalidTimestamps} />
              <QCheck label="Empty seasons" value={q.emptySeasons} />
            </div>
          </div>
          <div className="surface-card p-3">
            <h3 className="text-sm font-semibold mb-2 text-card-foreground">Status distribution</h3>
            <div className="flex flex-wrap gap-1">
              {q.statusDist.map((s) => (
                <span key={s.status} className="chip bg-muted text-card-foreground">
                  {s.status || "(blank)"} · {s.count.toLocaleString()}
                </span>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function QCheck({ label, value }: { label: string; value: number }) {
  const warn = value > 0;
  return (
    <div className={`p-2 rounded border ${warn ? "border-amber-500/40 bg-amber-500/5" : "border-white/5"}`}>
      <div className="text-[10px] uppercase text-muted-foreground">{label}</div>
      <div className={`text-base font-semibold ${warn ? "text-amber-500" : "text-card-foreground"}`}>
        {value.toLocaleString()}
      </div>
    </div>
  );
}

async function computeQuality(table: string, columns: { name: string }[], total: number): Promise<QualityResult> {
  const has = (n: string) => columns.some((c) => c.name === n);
  const colSql = (n: string, fallback = "NULL") => (has(n) ? quoteIdent(n) : fallback);

  const out: QualityResult = {
    totalRows: total,
    uniqueTeams: 0,
    dateRange: { earliest: null, latest: null },
    completed: 0,
    scheduled: 0,
    live: 0,
    missingTeamNames: 0,
    missingDates: 0,
    missingScores: 0,
    invalidScores: 0,
    invalidTimestamps: 0,
    emptySeasons: 0,
    duplicateGameIds: 0,
    duplicateRows: 0,
    statusDist: [],
    seasons: [],
  };

  // Unique teams
  if (has("home_team") || has("away_team") || has("team")) {
    if (has("home_team") && has("away_team")) {
      const r = await runSql<{ n: number }>(
        `SELECT COUNT(DISTINCT t)::INT AS n FROM (SELECT ${quoteIdent("home_team")} t FROM ${table} UNION ALL SELECT ${quoteIdent("away_team")} FROM ${table}) WHERE t IS NOT NULL AND t <> ''`,
      );
      out.uniqueTeams = Number(r[0]?.n ?? 0);
    } else if (has("team")) {
      const r = await runSql<{ n: number }>(
        `SELECT COUNT(DISTINCT ${quoteIdent("team")})::INT AS n FROM ${table} WHERE team IS NOT NULL`,
      );
      out.uniqueTeams = Number(r[0]?.n ?? 0);
    }
  }

  if (has("date_utc")) {
    const r = await runSql<{ mn: string; mx: string; inv: number; mis: number }>(
      `SELECT MIN(${quoteIdent("date_utc")})::VARCHAR AS mn, MAX(${quoteIdent("date_utc")})::VARCHAR AS mx,
              SUM(CASE WHEN ${quoteIdent("date_utc")} IS NOT NULL AND TRY_CAST(${quoteIdent("date_utc")} AS TIMESTAMP) IS NULL THEN 1 ELSE 0 END)::INT AS inv,
              SUM(CASE WHEN ${quoteIdent("date_utc")} IS NULL OR CAST(${quoteIdent("date_utc")} AS VARCHAR) = '' THEN 1 ELSE 0 END)::INT AS mis
       FROM ${table}`,
    );
    out.dateRange = { earliest: r[0]?.mn ?? null, latest: r[0]?.mx ?? null };
    out.invalidTimestamps = Number(r[0]?.inv ?? 0);
    out.missingDates = Number(r[0]?.mis ?? 0);
  }

  if (has("status")) {
    const dist = await runSql<{ s: string; n: number }>(
      `SELECT COALESCE(CAST(${quoteIdent("status")} AS VARCHAR), '') AS s, COUNT(*)::INT AS n FROM ${table} GROUP BY s ORDER BY n DESC`,
    );
    out.statusDist = dist.map((d) => ({ status: d.s, count: Number(d.n) }));
    for (const d of out.statusDist) {
      const s = (d.status || "").toLowerCase();
      if (/final|complete|ft\b/.test(s)) out.completed += d.count;
      else if (/sched|upcoming|^ns$/.test(s)) out.scheduled += d.count;
      else if (/live|progress|inning|^q\d/.test(s)) out.live += d.count;
    }
  }

  if (has("home_team") || has("away_team")) {
    const r = await runSql<{ n: number }>(
      `SELECT SUM(CASE WHEN ${colSql("home_team", "''")} IS NULL OR ${colSql("home_team", "''")} = '' OR ${colSql("away_team", "''")} IS NULL OR ${colSql("away_team", "''")} = '' THEN 1 ELSE 0 END)::INT AS n FROM ${table}`,
    );
    out.missingTeamNames = Number(r[0]?.n ?? 0);
  }

  if (has("home_score") || has("away_score")) {
    const r = await runSql<{ mis: number; inv: number }>(
      `SELECT
        SUM(CASE WHEN ${colSql("home_score", "''")} IS NULL OR CAST(${colSql("home_score", "''")} AS VARCHAR) = '' OR ${colSql("away_score", "''")} IS NULL OR CAST(${colSql("away_score", "''")} AS VARCHAR) = '' THEN 1 ELSE 0 END)::INT AS mis,
        SUM(CASE WHEN CAST(${colSql("home_score", "''")} AS VARCHAR) <> '' AND TRY_CAST(${colSql("home_score", "''")} AS DOUBLE) IS NULL THEN 1 ELSE 0 END)::INT AS inv
       FROM ${table}`,
    );
    out.missingScores = Number(r[0]?.mis ?? 0);
    out.invalidScores = Number(r[0]?.inv ?? 0);
  }

  if (has("season")) {
    const r = await runSql<{ s: string }>(
      `SELECT DISTINCT CAST(${quoteIdent("season")} AS VARCHAR) AS s FROM ${table} WHERE season IS NOT NULL AND CAST(${quoteIdent("season")} AS VARCHAR) <> '' ORDER BY s`,
    );
    out.seasons = r.map((x) => x.s);
    const e = await runSql<{ n: number }>(
      `SELECT SUM(CASE WHEN season IS NULL OR CAST(${quoteIdent("season")} AS VARCHAR) = '' THEN 1 ELSE 0 END)::INT AS n FROM ${table}`,
    );
    out.emptySeasons = Number(e[0]?.n ?? 0);
  }

  if (has("game_id")) {
    const r = await runSql<{ n: number }>(
      `SELECT COUNT(*)::INT AS n FROM (SELECT ${quoteIdent("game_id")}, COUNT(*) c FROM ${table} GROUP BY 1 HAVING c > 1)`,
    );
    out.duplicateGameIds = Number(r[0]?.n ?? 0);
  }

  return out;
}

function qualityToCsv(q: QualityResult): string {
  const rows: [string, string | number][] = [
    ["total_rows", q.totalRows],
    ["unique_teams", q.uniqueTeams],
    ["earliest_date", q.dateRange.earliest ?? ""],
    ["latest_date", q.dateRange.latest ?? ""],
    ["completed", q.completed],
    ["scheduled", q.scheduled],
    ["live", q.live],
    ["missing_team_names", q.missingTeamNames],
    ["missing_dates", q.missingDates],
    ["missing_scores", q.missingScores],
    ["invalid_scores", q.invalidScores],
    ["invalid_timestamps", q.invalidTimestamps],
    ["empty_seasons", q.emptySeasons],
    ["duplicate_game_ids", q.duplicateGameIds],
    ["duplicate_rows", q.duplicateRows],
    ["seasons", q.seasons.join("|")],
  ];
  const head = "metric,value";
  const body = rows.map(([k, v]) => `${csvEscape(k)},${csvEscape(String(v))}`).join("\n");
  const dist = "\n\nstatus,count\n" + q.statusDist.map((s) => `${csvEscape(s.status)},${s.count}`).join("\n");
  return head + "\n" + body + dist;
}

/* ============================ DOWNLOADS ============================ */

function DownloadsTab({ dataset, state }: { dataset: DatasetDef; state: DatasetState }) {
  const [busy, setBusy] = useState<string | null>(null);

  const filenameDate = new Date().toISOString().slice(0, 10);
  const fullName = `${dataset.filename_base}${dataset.season ? `_${dataset.season}` : ""}`;

  const downloadQuery = async (sql: string, filename: string, mime: string) => {
    setBusy(filename);
    try {
      const buf = await exportCsv(sql);
      const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;
      downloadBlob(filename, new Blob([ab], { type: mime }));
    } catch (e) {
      alert(`Failed: ${(e as Error).message}`);
    } finally {
      setBusy(null);
    }
  };

  const downloadJsonQuery = async (sql: string, filename: string) => {
    setBusy(filename);
    try {
      const rows = await runSql(sql);
      downloadBlob(filename, new Blob([JSON.stringify(rows, null, 2)], { type: "application/json" }));
    } catch (e) {
      alert(`Failed: ${(e as Error).message}`);
    } finally {
      setBusy(null);
    }
  };

  const fullSelect = `SELECT * FROM ${state.table}`;
  const sampleSelect = `SELECT * FROM ${state.table} LIMIT 100`;

  return (
    <div className="space-y-4">
      <div className="surface-card p-3 text-xs text-muted-foreground">
        <strong className="text-card-foreground">About Parquet:</strong> Parquet is the primary
        storage format because it uses less space and loads analytical data faster. CSV downloads
        are available for Excel, Google Sheets, and general use.
      </div>

      <section>
        <h3 className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Primary downloads</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <DownloadCard
            title="Original Parquet"
            desc="Smallest file. Best for Python, R, DuckDB, and analytics tools."
            icon={<Database className="w-4 h-4" />}
            disabled={state.format !== "parquet"}
            note={
              state.format !== "parquet"
                ? "Parquet not available yet — use the CSV version below."
                : undefined
            }
            onClick={() => window.open(dataset.parquet_url, "_blank", "noopener")}
            label="Open"
          />
          <DownloadCard
            title="CSV version"
            desc="Larger file that opens easily in Excel, Google Sheets, and most apps."
            icon={<FileSpreadsheet className="w-4 h-4" />}
            onClick={() => window.open(dataset.csv_fallback_url, "_blank", "noopener")}
            label="Open"
          />
          <DownloadCard
            title="Current filtered CSV"
            desc="Generated from the current Explore query in your browser."
            icon={<FileSpreadsheet className="w-4 h-4" />}
            busy={busy === `${dataset.filename_base}_filtered_${filenameDate}.csv`}
            onClick={() =>
              downloadQuery(
                fullSelect,
                `${dataset.filename_base}_filtered_${filenameDate}.csv`,
                "text/csv",
              )
            }
            label="Generate"
          />
        </div>
      </section>

      <section>
        <h3 className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Sample exports</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <DownloadCard
            title="Sample CSV (100 rows)"
            desc="Quick CSV sample of the current dataset."
            icon={<FileSpreadsheet className="w-4 h-4" />}
            busy={busy === `${dataset.filename_base}_sample_100.csv`}
            onClick={() => downloadQuery(sampleSelect, `${dataset.filename_base}_sample_100.csv`, "text/csv")}
            label="Generate"
          />
          <DownloadCard
            title="Sample JSON (100 rows)"
            desc="JSON sample for quick inspection."
            icon={<FileJson className="w-4 h-4" />}
            busy={busy === `${dataset.filename_base}_sample_100.json`}
            onClick={() => downloadJsonQuery(sampleSelect, `${dataset.filename_base}_sample_100.json`)}
            label="Generate"
          />
        </div>
      </section>

      <section>
        <h3 className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Advanced</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <DownloadCard
            title="Full results JSON"
            desc={`All ${state.rowCount.toLocaleString()} rows as JSON (large for big datasets).`}
            icon={<FileJson className="w-4 h-4" />}
            busy={busy === `${fullName}_full.json`}
            confirm={state.rowCount > 5000 ? `This will generate JSON for ${state.rowCount.toLocaleString()} rows. Continue?` : undefined}
            onClick={() => downloadJsonQuery(fullSelect, `${fullName}_full.json`)}
            label="Generate"
          />
          <DownloadCard
            title="Schema report CSV"
            desc="Field types, missing counts, examples."
            icon={<FileSpreadsheet className="w-4 h-4" />}
            onClick={() => alert("Open the Schema tab — the CSV download lives there.")}
            label="Open Schema"
          />
          <DownloadCard
            title="Quality report CSV"
            desc="Duplicates, missing, status distribution."
            icon={<FileSpreadsheet className="w-4 h-4" />}
            onClick={() => alert("Open the Quality tab — the CSV download lives there.")}
            label="Open Quality"
          />
        </div>
      </section>
    </div>
  );
}

function DownloadCard({
  title,
  desc,
  icon,
  onClick,
  label,
  busy,
  disabled,
  note,
  confirm,
}: {
  title: string;
  desc: string;
  icon: React.ReactNode;
  onClick: () => void;
  label: string;
  busy?: boolean;
  disabled?: boolean;
  note?: string;
  confirm?: string;
}) {
  return (
    <div className="surface-card p-3 flex flex-col gap-2">
      <div className="flex items-start gap-2">
        <div className="w-8 h-8 rounded-md bg-primary/10 text-primary flex items-center justify-center flex-shrink-0">
          {icon}
        </div>
        <div className="min-w-0">
          <div className="font-medium text-card-foreground">{title}</div>
          <div className="text-[12px] text-muted-foreground">{desc}</div>
          {note && <div className="text-[11px] text-amber-500 mt-1">{note}</div>}
        </div>
      </div>
      <Button
        size="sm"
        className="self-start min-h-[40px]"
        disabled={disabled || busy}
        onClick={() => {
          if (confirm && !window.confirm(confirm)) return;
          onClick();
        }}
      >
        {busy ? <RefreshCw className="w-3 h-3 animate-spin" /> : <Download className="w-3 h-3" />}
        {busy ? "Working…" : label}
      </Button>
    </div>
  );
}

/* ============================ LINEAGE ============================ */

function LineageTab({ dataset, state }: { dataset: DatasetDef; state: DatasetState }) {
  return (
    <div className="space-y-3">
      <div className="surface-card p-4">
        <h3 className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Source lineage</h3>
        <ol className="space-y-2 text-sm">
          <LStep n={1} title="Public API or scoreboard" desc="ESPN / API-Sports public endpoints." />
          <LStep n={2} title="GitHub Actions" desc="Scheduled workflows in the LindaData repository fetch, normalise, and publish snapshots." />
          <LStep n={3} title="Parquet + manifest files" desc="Committed to the repo and served via raw.githubusercontent.com." />
          <LStep n={4} title="LindaData Sports Hub" desc="Static Vite app reads Parquet directly in your browser via DuckDB-WASM." />
          <LStep n={5} title="Optional CSV download" desc="Generated client-side from query results." />
        </ol>
      </div>

      <div className="surface-card p-4 text-sm space-y-2">
        <div className="grid grid-cols-2 gap-3">
          <Stat label="Source repository" value="LindaData/world-cup-2026-betting-model" />
          <Stat label="Schema version" value="v1" />
          <Stat label="Format" value={state.format ?? "—"} />
          <Stat label="Row count" value={state.rowCount.toLocaleString()} />
          <Stat label="Generated (file)" value={state.generatedAt ? new Date(state.generatedAt).toLocaleString() : "—"} />
          <Stat label="Downloaded" value={state.loadedAt ? new Date(state.loadedAt).toLocaleString() : "—"} />
        </div>
        <div className="pt-2 border-t border-white/5 space-y-1">
          <a href={dataset.parquet_url} target="_blank" rel="noreferrer" className="block text-[11px] text-primary break-all hover:underline">
            Parquet URL: {dataset.parquet_url}
          </a>
          <a href={dataset.csv_fallback_url} target="_blank" rel="noreferrer" className="block text-[11px] text-primary break-all hover:underline">
            CSV fallback: {dataset.csv_fallback_url}
          </a>
          <a
            href="https://github.com/LindaData/world-cup-2026-betting-model"
            target="_blank"
            rel="noreferrer"
            className="block text-[11px] text-primary hover:underline"
          >
            Repository: github.com/LindaData/world-cup-2026-betting-model
          </a>
        </div>
      </div>
    </div>
  );
}

function LStep({ n, title, desc }: { n: number; title: string; desc: string }) {
  return (
    <li className="flex gap-3">
      <div className="w-7 h-7 flex-shrink-0 rounded-full bg-primary/15 text-primary text-xs font-bold flex items-center justify-center">
        {n}
      </div>
      <div>
        <div className="font-medium text-card-foreground">{title}</div>
        <div className="text-xs text-muted-foreground">{desc}</div>
      </div>
    </li>
  );
}

/* ============================ helpers ============================ */

function csvEscape(s: string): string {
  if (s == null) return "";
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
function downloadBlob(filename: string, blob: Blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
