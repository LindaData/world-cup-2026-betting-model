import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  BarChart3,
  CheckCircle2,
  ChevronDown,
  ClipboardList,
  Download,
  Loader2,
  RefreshCw,
  Search,
  ShieldAlert,
  TrendingUp,
  XCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { loadCatalog, type CatalogEntry } from "@/lib/catalog";
import { downloadCsv, streamCsvSample } from "@/lib/download";

const STORAGE_KEY = "gsp:data-approval:v1";
const SAMPLE_LIMIT = 25;

type Decision = "pending" | "approved" | "changes_requested";
type Review = { decision: Decision; notes: string; reviewed_at_utc: string | null };
type SchemaColumn = { name: string; type: string };
type Preview = {
  columns: string[];
  rows: Record<string, unknown>[];
  schema: SchemaColumn[];
  raw: unknown;
};

const EMPTY: Preview = { columns: [], rows: [], schema: [], raw: null };

export default function Approval() {
  const [params, setParams] = useSearchParams();
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  const [selectedId, setSelectedId] = useState(params.get("dataset") ?? "");
  const [reviews, setReviews] = useState<Record<string, Review>>(readReviews);
  const [preview, setPreview] = useState<Preview>(EMPTY);
  const [query, setQuery] = useState("");
  const [sport, setSport] = useState("all");
  const [decision, setDecision] = useState<Decision | "all">("all");
  const [loading, setLoading] = useState(true);
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [catalogError, setCatalogError] = useState<string | null>(null);
  const [catalogMeta, setCatalogMeta] = useState("");
  const [tab, setTab] = useState<"data" | "schema" | "raw">("data");
  const [queueOpen, setQueueOpen] = useState(false);

  const refresh = async () => {
    setLoading(true);
    setCatalogError(null);
    try {
      const catalog = await loadCatalog(true);
      setEntries(catalog.entries);
      setCatalogMeta(`${catalog.source} · ${formatDate(catalog.generated_at_utc)}`);
      setSelectedId((current) =>
        catalog.entries.some((entry) => entry.dataset_id === current)
          ? current
          : catalog.entries[0]?.dataset_id ?? "",
      );
    } catch (cause) {
      setCatalogError((cause as Error).message || "The dataset catalog could not be loaded.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(reviews));
    } catch {
      // Approval still works for this session when browser storage is unavailable.
    }
  }, [reviews]);

  useEffect(() => {
    if (!selectedId) return;
    setParams({ dataset: selectedId }, { replace: true });
    const entry = entries.find((item) => item.dataset_id === selectedId);
    if (entry) void fetchPreview(entry, setPreview, setLoadingPreview, setError);
  }, [selectedId, entries, setParams]);

  const selected = entries.find((entry) => entry.dataset_id === selectedId) ?? null;
  const currentReview = selected ? reviews[selected.dataset_id] ?? blankReview() : blankReview();
  const sports = ["all", ...Array.from(new Set(entries.map((entry) => entry.sport))).sort()];

  const filtered = useMemo(
    () =>
      entries.filter((entry) => {
        const text = `${entry.display_name} ${entry.dataset_id} ${entry.source_endpoint ?? ""}`.toLowerCase();
        const review = reviews[entry.dataset_id] ?? blankReview();
        return (
          (!query || text.includes(query.toLowerCase())) &&
          (sport === "all" || entry.sport === sport) &&
          (decision === "all" || review.decision === decision)
        );
      }),
    [entries, reviews, query, sport, decision],
  );

  const counts = useMemo(
    () => ({
      total: entries.length,
      pending: entries.filter(
        (entry) => (reviews[entry.dataset_id]?.decision ?? "pending") === "pending",
      ).length,
      approved: entries.filter((entry) => reviews[entry.dataset_id]?.decision === "approved").length,
      changes: entries.filter(
        (entry) => reviews[entry.dataset_id]?.decision === "changes_requested",
      ).length,
    }),
    [entries, reviews],
  );

  const reviewedCount = counts.approved + counts.changes;
  const progress = counts.total ? Math.round((reviewedCount / counts.total) * 100) : 0;

  const updateReview = (patch: Partial<Review>) => {
    if (!selected) return;
    setReviews((all) => ({
      ...all,
      [selected.dataset_id]: {
        ...(all[selected.dataset_id] ?? blankReview()),
        ...patch,
      },
    }));
  };

  const chooseNextPending = () => {
    if (!selected) return;
    const next = entries.find(
      (entry) =>
        entry.dataset_id !== selected.dataset_id &&
        (reviews[entry.dataset_id]?.decision ?? "pending") === "pending",
    );
    if (next) {
      setSelectedId(next.dataset_id);
      setTab("data");
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  };

  const setReviewDecision = (next: Decision, moveNext = false) => {
    updateReview({
      decision: next,
      reviewed_at_utc: next === "pending" ? null : new Date().toISOString(),
    });
    if (moveNext && next !== "pending") chooseNextPending();
  };

  const selectDataset = (id: string) => {
    setSelectedId(id);
    setTab("data");
    setQueueOpen(false);
    window.requestAnimationFrame(() => {
      document.getElementById("dataset-review")?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  };

  const exportDecisions = () =>
    downloadCsv(
      "game_stat_pulse_data_approvals.csv",
      entries.map((entry) => {
        const review = reviews[entry.dataset_id] ?? blankReview();
        return {
          dataset_id: entry.dataset_id,
          dataset_name: entry.display_name,
          sport: entry.sport,
          entity: entry.entity,
          source_endpoint: entry.source_endpoint,
          row_count: entry.row_count ?? "",
          column_count: entry.column_count ?? "",
          availability_status: entry.availability_status,
          decision: review.decision,
          notes: review.notes,
          reviewed_at_utc: review.reviewed_at_utc ?? "",
        };
      }),
    );

  const queueProps = {
    entries: filtered,
    selectedId,
    reviews,
    query,
    sport,
    decision,
    sports,
    loading,
    onQuery: setQuery,
    onSport: setSport,
    onDecision: setDecision,
    onSelect: selectDataset,
  };

  return (
    <div className="space-y-3 sm:space-y-5 pb-28 lg:pb-0">
      <header className="relative overflow-hidden rounded-lg border border-white/10 bg-[linear-gradient(135deg,hsl(var(--navy-light)),hsl(var(--navy-deep)))] sportsbook-glow">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,hsl(var(--primary)/0.16),transparent_28rem),radial-gradient(circle_at_top_right,hsl(var(--secondary)/0.12),transparent_22rem)]" aria-hidden="true" />
        <div className="relative grid gap-5 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_380px] lg:items-end">
          <div className="max-w-3xl space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-primary/40 bg-primary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-primary">
              <span className="h-2 w-2 rounded-full bg-primary shadow-[0_0_16px_hsl(var(--primary))]" />
              Dataset Intake
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl lg:text-5xl font-black leading-[0.98] tracking-normal">
                Review every source feed before it enters the model.
              </h1>
              <p className="mt-3 max-w-2xl text-sm sm:text-base text-foreground/[0.76]">
                Inspect samples, schema, availability, and notes across odds, fixtures, roster context, and
                performance feeds. This is the intake layer for analysis, not the presentation layer.
              </p>
            </div>
            <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap">
              <Button className="min-h-11 bg-primary text-primary-foreground hover:bg-primary/90" onClick={() => void refresh()} disabled={loading}>
                <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} /> Sync catalog
              </Button>
              <Button className="min-h-11 border-secondary/45 text-secondary hover:bg-secondary/10" variant="outline" onClick={exportDecisions} disabled={!entries.length}>
                <Download className="w-4 h-4" /> Export review log
              </Button>
            </div>
            <p className="text-[10px] sm:text-[11px] text-muted-foreground break-words">
              Catalog: {catalogMeta || "loading"}
            </p>
          </div>

          <aside className="market-panel p-4 bg-black/40 backdrop-blur-md">
            <div className="mb-3 flex items-center justify-between gap-3">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Review progress</div>
                <div className="mt-1 text-lg font-black tabular-nums">{progress}% cleared</div>
              </div>
              <ClipboardList className="h-8 w-8 text-secondary" />
            </div>
            <div className="mb-3 h-2.5 overflow-hidden rounded-sm bg-white/10">
              <div className="h-full bg-primary transition-all" style={{ width: `${progress}%` }} />
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="odds-cell">
                <div className="text-[10px] uppercase text-muted-foreground">Reviewed</div>
                <div>{reviewedCount}/{counts.total}</div>
              </div>
              <div className="odds-cell">
                <div className="text-[10px] uppercase text-muted-foreground">Pending</div>
                <div className="text-secondary">{counts.pending}</div>
              </div>
            </div>
          </aside>
        </div>
      </header>

      {catalogError && (
        <div className="surface-card p-4 text-sm text-amber-300 flex gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" /> {catalogError}
        </div>
      )}

      <section className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Metric label="Datasets" value={counts.total} icon={BarChart3} />
        <Metric label="Open reviews" value={counts.pending} icon={ClipboardList} tone="amber" />
        <Metric label="Ready" value={counts.approved} icon={TrendingUp} tone="green" />
        <Metric label="Flagged" value={counts.changes} icon={ShieldAlert} tone="red" />
      </section>

      <section className="lg:hidden surface-card overflow-hidden">
        <button
          type="button"
          onClick={() => setQueueOpen((value) => !value)}
          className="w-full min-h-14 p-3 flex items-center justify-between gap-3 text-left"
          aria-expanded={queueOpen}
        >
          <div className="min-w-0">
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Current dataset</div>
            <div className="font-semibold truncate">{selected?.display_name ?? "Choose a dataset"}</div>
            <div className="text-[11px] text-muted-foreground">{counts.pending} reviews still open</div>
          </div>
          <ChevronDown className={`w-5 h-5 shrink-0 transition-transform ${queueOpen ? "rotate-180" : ""}`} />
        </button>
        {queueOpen && <div className="border-t border-white/10 p-3"><QueuePanel {...queueProps} /></div>}
      </section>

      <div className="grid lg:grid-cols-[320px_minmax(0,1fr)] gap-4 items-start">
        <aside className="hidden lg:block surface-card p-3 sticky top-20">
          <QueuePanel {...queueProps} />
        </aside>

        {!selected ? (
          <div className="surface-card p-8 text-sm text-muted-foreground">Choose a dataset to begin.</div>
        ) : (
          <div id="dataset-review" className="space-y-3 sm:space-y-4 min-w-0 scroll-mt-20">
            <section className="surface-card overflow-hidden">
              <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3 sm:px-5">
                <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Dataset review</div>
              </div>
              <div className="space-y-4 p-4 sm:p-5">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-lg sm:text-xl font-semibold leading-tight">{selected.display_name}</h2>
                    <DecisionBadge decision={currentReview.decision} />
                    <AvailabilityBadge status={selected.availability_status} />
                  </div>
                  <p className="text-sm text-muted-foreground mt-2">{selected.description}</p>
                  <div className="grid grid-cols-2 gap-2 mt-3 text-xs sm:grid-cols-4">
                    <Info label="Fields" value={preview.columns.length} />
                    <Info label="Sample rows" value={preview.rows.length} />
                    <Info label="Rows" value={selected.row_count ?? "?"} />
                    <Info label="Columns" value={selected.column_count ?? "?"} />
                  </div>
                  <p className="text-[11px] text-muted-foreground mt-2 break-all">{selected.source_endpoint}</p>
                </div>

                <div className="hidden lg:flex flex-wrap gap-2">
                  <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={() => setReviewDecision("approved", true)}>
                    <CheckCircle2 className="w-4 h-4" /> Mark ready & next
                  </Button>
                  <Button variant="destructive" onClick={() => setReviewDecision("changes_requested", true)}>
                    <XCircle className="w-4 h-4" /> Flag issue & next
                  </Button>
                  <Button variant="outline" onClick={() => setReviewDecision("pending")}>Reset</Button>
                </div>

                <textarea
                  value={currentReview.notes}
                  onChange={(event) => updateReview({ notes: event.target.value })}
                  placeholder="Optional note: missing fields, bad values, naming issues, or why it is approved."
                  className="w-full min-h-28 rounded-md border border-input bg-black/25 p-3 text-base sm:text-sm outline-none focus:ring-2 focus:ring-primary/40"
                />

                <button
                  type="button"
                  onClick={() => setReviewDecision("pending")}
                  className="lg:hidden min-h-11 text-sm text-muted-foreground underline underline-offset-4"
                >
                  Reset this decision
                </button>
              </div>
            </section>

            <section className="surface-card overflow-hidden">
              <div className="p-3 border-b border-white/10 space-y-2">
                <div className="grid grid-cols-3 gap-1.5">
                  {(["data", "schema", "raw"] as const).map((key) => (
                    <button
                      key={key}
                      onClick={() => setTab(key)}
                      className={`min-h-11 px-2 rounded-md text-sm font-medium ${
                        tab === key ? "bg-primary text-primary-foreground" : "bg-white/5"
                      }`}
                    >
                      {key === "data" ? "Records" : key === "schema" ? "Fields" : "Raw"}
                    </button>
                  ))}
                </div>
                <div className="text-[11px] text-muted-foreground text-center">
                  All {preview.columns.length} fields / up to {SAMPLE_LIMIT} sample records
                </div>
              </div>

              {loadingPreview ? (
                <div className="p-8 text-sm text-muted-foreground flex gap-2">
                  <Loader2 className="w-4 h-4 animate-spin" /> Loading preview...
                </div>
              ) : error ? (
                <div className="p-6 text-sm text-amber-300 flex gap-2">
                  <AlertTriangle className="w-4 h-4 shrink-0" /> {error}
                </div>
              ) : tab === "data" ? (
                <DataTable preview={preview} />
              ) : tab === "schema" ? (
                <SchemaTable preview={preview} />
              ) : (
                <pre className="max-h-[65vh] overflow-auto whitespace-pre-wrap break-words p-4 text-xs bg-black/20">
                  {preview.raw
                    ? JSON.stringify(preview.raw, null, 2)
                    : "Raw JSON is intentionally not published on the public review site."}
                </pre>
              )}
            </section>
          </div>
        )}
      </div>

      {selected && (
        <div className="lg:hidden fixed left-0 right-0 bottom-[calc(4.25rem+env(safe-area-inset-bottom))] z-40 border-t border-white/10 bg-[hsl(var(--navy-deep))]/95 backdrop-blur p-2.5">
          <div className="grid grid-cols-2 gap-2 max-w-xl mx-auto">
            <Button className="min-h-12 text-sm" onClick={() => setReviewDecision("approved", true)}>
              <CheckCircle2 className="w-5 h-5" /> Mark ready
            </Button>
            <Button className="min-h-12 text-sm" variant="destructive" onClick={() => setReviewDecision("changes_requested", true)}>
              <XCircle className="w-5 h-5" /> Flag issue
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

type QueuePanelProps = {
  entries: CatalogEntry[];
  selectedId: string;
  reviews: Record<string, Review>;
  query: string;
  sport: string;
  decision: Decision | "all";
  sports: string[];
  loading: boolean;
  onQuery: (value: string) => void;
  onSport: (value: string) => void;
  onDecision: (value: Decision | "all") => void;
  onSelect: (id: string) => void;
};

function QueuePanel({
  entries,
  selectedId,
  reviews,
  query,
  sport,
  decision,
  sports,
  loading,
  onQuery,
  onSport,
  onDecision,
  onSelect,
}: QueuePanelProps) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Dataset queue</div>
          <div className="text-sm font-semibold">{entries.length} datasets shown</div>
        </div>
        <span className="rounded-sm bg-primary/15 px-2 py-1 text-[10px] font-black uppercase text-primary">Review</span>
      </div>
      <div className="relative">
        <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(event) => onQuery(event.target.value)}
          placeholder="Search datasets"
          className="pl-9 min-h-11 bg-black/25 text-base sm:text-sm"
        />
      </div>

      <div className="grid grid-cols-2 gap-2">
        <select
          value={sport}
          onChange={(event) => onSport(event.target.value)}
          className="min-h-11 rounded-md border border-input bg-black/25 px-2 text-sm"
        >
          {sports.map((value) => (
            <option key={value} value={value}>{value === "all" ? "All sports" : value}</option>
          ))}
        </select>
        <select
          value={decision}
          onChange={(event) => onDecision(event.target.value as Decision | "all")}
          className="min-h-11 rounded-md border border-input bg-black/25 px-2 text-sm"
        >
          <option value="all">All decisions</option>
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="changes_requested">Changes</option>
        </select>
      </div>

      <div className="max-h-[58vh] overflow-auto space-y-2 pr-1">
        {loading ? (
          <div className="p-4 text-sm text-muted-foreground flex gap-2">
            <Loader2 className="w-4 h-4 animate-spin" /> Loading...
          </div>
        ) : entries.length ? (
          entries.map((entry) => {
            const review = reviews[entry.dataset_id] ?? blankReview();
            return (
              <button
                key={entry.dataset_id}
                onClick={() => onSelect(entry.dataset_id)}
                className={`w-full min-h-20 rounded-lg border p-3 text-left transition ${
                  selectedId === entry.dataset_id
                    ? "border-primary bg-primary/10 shadow-[0_0_0_1px_hsl(var(--primary)/0.25)]"
                    : "border-white/10 bg-black/20 hover:border-white/20 hover:bg-white/[0.04]"
                }`}
              >
                <div className="flex justify-between gap-2">
                  <span className="font-medium text-sm leading-tight">{entry.display_name}</span>
                  <DecisionIcon decision={review.decision} />
                </div>
                <div className="text-[11px] text-muted-foreground mt-1 break-all">
                  {entry.entity} - {entry.source_endpoint}
                </div>
                <div className="mt-2 grid grid-cols-[1fr_auto] items-center gap-2 text-[10px] text-muted-foreground">
                  <span className="rounded-sm bg-white/[0.045] px-2 py-1">
                    {entry.column_count ?? "?"} fields / {entry.row_count ?? "?"} rows
                  </span>
                  <AvailabilityBadge status={entry.availability_status} />
                </div>
              </button>
            );
          })
        ) : (
          <div className="p-4 text-sm text-muted-foreground">No datasets match these filters.</div>
        )}
      </div>
    </div>
  );
}

async function fetchPreview(
  entry: CatalogEntry,
  setPreview: (value: Preview) => void,
  setLoading: (value: boolean) => void,
  setError: (value: string | null) => void,
) {
  setLoading(true);
  setError(null);
  setPreview(EMPTY);
  try {
    let rows: Record<string, unknown>[] = [];
    let columns: string[] = [];
    let raw: unknown = null;
    let schema: SchemaColumn[] = [];

    if (entry.sample_csv_url) {
      const sample = await streamCsvSample(entry.sample_csv_url, SAMPLE_LIMIT);
      rows = sample.rows;
      columns = sample.headers;
    }
    if (entry.raw_json_url) {
      const response = await fetch(bust(entry.raw_json_url), { cache: "no-store" });
      if (response.ok) raw = await response.json();
    }
    if (!rows.length && raw) {
      rows = extractRows(raw).slice(0, SAMPLE_LIMIT).map((row) => flatten(row));
      columns = unionColumns(rows);
    }
    if (entry.schema_url) {
      const response = await fetch(bust(entry.schema_url), { cache: "no-store" });
      if (response.ok) {
        schema = ((await response.json()) as { columns?: SchemaColumn[] }).columns ?? [];
      }
    }
    if (!columns.length) columns = schema.map((column) => column.name);
    if (!schema.length) schema = columns.map((name) => ({ name, type: inferType(rows, name) }));
    if (!columns.length) {
      throw new Error(
        entry.availability_status === "missing"
          ? "This endpoint did not return a review sample. Check its API access or parameters."
          : "No review sample is available for this dataset yet.",
      );
    }
    setPreview({ columns, rows, schema, raw });
  } catch (cause) {
    setError((cause as Error).message);
  } finally {
    setLoading(false);
  }
}

function DataTable({ preview }: { preview: Preview }) {
  if (!preview.columns.length) {
    return <div className="p-8 text-sm text-muted-foreground">No sampled fields available.</div>;
  }

  return (
    <>
      <MobileRecordViewer preview={preview} />
      <div className="hidden lg:block max-h-[65vh] overflow-auto">
        <table className="min-w-max w-full text-xs">
          <thead className="sticky top-0 bg-card z-10">
            <tr>
              <th className="sticky left-0 bg-card p-2 z-20">#</th>
              {preview.columns.map((column) => (
                <th key={column} className="p-2 text-left whitespace-nowrap">{column}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {preview.rows.map((row, index) => (
              <tr key={index} className="border-t border-white/5">
                <td className="sticky left-0 bg-card p-2 text-muted-foreground">{index + 1}</td>
                {preview.columns.map((column) => {
                  const value = cell(row[column]);
                  return (
                    <td key={column} className="p-2 max-w-[320px] whitespace-nowrap">
                      <span className="block max-w-[320px] truncate" title={value}>{value || "—"}</span>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

function MobileRecordViewer({ preview }: { preview: Preview }) {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    setIndex(0);
  }, [preview]);

  if (!preview.rows.length) {
    return <div className="lg:hidden p-6 text-sm text-muted-foreground">Fields were found, but there are no sample records.</div>;
  }

  const safeIndex = Math.min(index, preview.rows.length - 1);
  const row = preview.rows[safeIndex];

  return (
    <div className="lg:hidden">
      <div className="sticky top-14 z-20 flex items-center justify-between gap-2 p-3 bg-card border-b border-white/10">
        <Button
          size="sm"
          variant="outline"
          className="min-h-10"
          disabled={safeIndex === 0}
          onClick={() => setIndex((value) => Math.max(0, value - 1))}
        >
          <ArrowLeft className="w-4 h-4" /> Previous
        </Button>
        <div className="text-xs font-medium">Record {safeIndex + 1} of {preview.rows.length}</div>
        <Button
          size="sm"
          variant="outline"
          className="min-h-10"
          disabled={safeIndex === preview.rows.length - 1}
          onClick={() => setIndex((value) => Math.min(preview.rows.length - 1, value + 1))}
        >
          Next <ArrowRight className="w-4 h-4" />
        </Button>
      </div>

      <div className="divide-y divide-white/10">
        {preview.columns.map((column) => (
          <div key={column} className="p-4">
            <div className="text-[10px] uppercase tracking-wider text-primary font-semibold break-all">{column}</div>
            <div className="mt-1.5 text-sm leading-relaxed break-words whitespace-pre-wrap">{cell(row[column]) || "—"}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function SchemaTable({ preview }: { preview: Preview }) {
  return (
    <>
      <div className="lg:hidden divide-y divide-white/10">
        {preview.schema.map((column, index) => (
          <div key={`${column.name}-${index}`} className="p-4 flex items-start justify-between gap-4">
            <div className="min-w-0">
              <div className="text-[10px] text-muted-foreground">Field {index + 1}</div>
              <div className="font-mono text-xs mt-1 break-all">{column.name}</div>
            </div>
            <span className="shrink-0 rounded-full bg-white/5 px-2.5 py-1 text-[10px] text-muted-foreground">{column.type}</span>
          </div>
        ))}
      </div>
      <div className="hidden lg:block max-h-[65vh] overflow-auto">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-card">
            <tr>
              <th className="p-3 text-left">#</th>
              <th className="p-3 text-left">Field</th>
              <th className="p-3 text-left">Type</th>
            </tr>
          </thead>
          <tbody>
            {preview.schema.map((column, index) => (
              <tr key={`${column.name}-${index}`} className="border-t border-white/5">
                <td className="p-3 text-muted-foreground">{index + 1}</td>
                <td className="p-3 font-mono text-xs">{column.name}</td>
                <td className="p-3 text-muted-foreground">{column.type}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

function Metric({
  label,
  value,
  icon: Icon,
  tone = "green",
}: {
  label: string;
  value: number;
  icon: typeof BarChart3;
  tone?: "green" | "amber" | "red";
}) {
  const toneClass = {
    green: "text-primary bg-primary/10 border-primary/25",
    amber: "text-secondary bg-secondary/10 border-secondary/25",
    red: "text-red-300 bg-red-500/10 border-red-500/25",
  }[tone];

  return (
    <div className="surface-card min-w-0 p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[9px] sm:text-[10px] uppercase tracking-wide text-muted-foreground truncate">{label}</div>
          <div className="mt-1 text-xl sm:text-2xl font-black tabular-nums">{value}</div>
        </div>
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-md border ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-lg bg-white/[0.04] p-3">
      <div className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</div>
      <div className="font-semibold mt-1">{value}</div>
    </div>
  );
}

function DecisionIcon({ decision }: { decision: Decision }) {
  return decision === "approved" ? (
    <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
  ) : decision === "changes_requested" ? (
    <XCircle className="w-4 h-4 text-red-400 shrink-0" />
  ) : (
    <span className="w-4 h-4 rounded-full border border-muted-foreground shrink-0" />
  );
}

function DecisionBadge({ decision }: { decision: Decision }) {
  const label = decision === "approved" ? "Approved" : decision === "changes_requested" ? "Changes requested" : "Pending";
  const style = decision === "approved"
    ? "bg-emerald-500/15 text-emerald-300"
    : decision === "changes_requested"
      ? "bg-red-500/15 text-red-300"
      : "bg-white/10 text-muted-foreground";
  return <span className={`rounded-full px-2 py-1 text-[10px] font-medium ${style}`}>{label}</span>;
}

function AvailabilityBadge({ status }: { status: CatalogEntry["availability_status"] }) {
  const style = status === "available"
    ? "text-emerald-300"
    : status === "degraded"
      ? "text-amber-300"
      : "text-red-300";
  return <span className={`capitalize ${style}`}>{status}</span>;
}

function blankReview(): Review {
  return { decision: "pending", notes: "", reviewed_at_utc: null };
}

function readReviews(): Record<string, Review> {
  if (typeof window === "undefined") return {};
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}");
  } catch {
    return {};
  }
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function bust(url: string) {
  return `${url}${url.includes("?") ? "&" : "?"}t=${Date.now()}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function extractRows(raw: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw)) return raw.filter(isRecord);
  if (!isRecord(raw)) return [];
  const response = raw.response;
  return Array.isArray(response)
    ? response.filter(isRecord)
    : isRecord(response)
      ? [response]
      : [raw];
}

function flatten(
  record: Record<string, unknown>,
  prefix = "",
  output: Record<string, unknown> = {},
) {
  Object.entries(record).forEach(([key, value]) => {
    const name = prefix ? `${prefix}.${key}` : key;
    if (isRecord(value)) flatten(value, name, output);
    else output[name] = Array.isArray(value) ? JSON.stringify(value) : value;
  });
  return output;
}

function unionColumns(rows: Record<string, unknown>[]) {
  return Array.from(new Set(rows.flatMap((row) => Object.keys(row))));
}

function inferType(rows: Record<string, unknown>[], column: string) {
  const value = rows.map((row) => row[column]).find((item) => item != null && item !== "");
  return value == null ? "unknown" : typeof value;
}

function cell(value: unknown) {
  return value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value);
}
