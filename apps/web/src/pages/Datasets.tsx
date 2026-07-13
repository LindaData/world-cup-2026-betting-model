import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Database, Download, Eye, FileSpreadsheet, FileJson, Loader2, ListTree } from "lucide-react";
import { Button } from "@/components/ui/button";
import { loadCatalog, type Catalog, type CatalogEntry } from "@/lib/catalog";
import { downloadRawJson, downloadSampleCsv, sanitizeFilename } from "@/lib/download";
import { toast } from "@/hooks/use-toast";

type SportFilter = "all" | string;
type EntityFilter = "all" | string;

const ENTITY_LABELS: Partial<Record<string, string>> = {
  games: "Games",
  teams: "Teams",
  players: "Players",
  standings: "Standings",
  team_statistics: "Team statistics",
  player_statistics: "Player statistics",
  scores: "Scores",
  odds: "Odds",
  leagues: "Leagues",
  head_to_head: "Head-to-head",
  fixture_events: "Fixture events",
  fixture_lineups: "Fixture lineups",
  fixture_statistics: "Fixture statistics",
  player_game_statistics: "Player game statistics",
  injuries: "Injuries",
  provider_predictions: "Provider predictions",
  coaches: "Coaches",
  squads: "Squads",
  player_team_history: "Player team history",
  transfers: "Transfers",
  trophies: "Trophies",
  sidelined: "Sidelined",
  player_rankings: "Player rankings",
  betting_reference: "Betting reference",
  operational_metadata: "Operational metadata",
};

const SPORT_LABELS: Partial<Record<string, string>> = {
  NBA: "Basketball",
  MLB: "Baseball",
  Football: "Football",
  Meta: "Meta",
};

export default function Datasets() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [loading, setLoading] = useState(true);
  const [sport, setSport] = useState<SportFilter>("all");
  const [entity, setEntity] = useState<EntityFilter>("all");
  const [downloading, setDownloading] = useState<Record<string, "sample" | "json" | null>>({});

  useEffect(() => {
    loadCatalog().then((c) => {
      setCatalog(c);
      setLoading(false);
    });
  }, []);

  const entries = useMemo(() => catalog?.entries ?? [], [catalog]);
  const filtered = useMemo(() => {
    return entries.filter(
      (e) => (sport === "all" || e.sport === sport) && (entity === "all" || e.entity === entity),
    );
  }, [entries, sport, entity]);

  const sportFilters = useMemo<SportFilter[]>(
    () => ["all", ...Array.from(new Set(entries.map((e) => e.sport))).sort()],
    [entries],
  );

  const entityFilters = useMemo<EntityFilter[]>(
    () => ["all", ...Array.from(new Set(entries.map((e) => e.entity))).sort()],
    [entries],
  );

  const stats = useMemo(() => {
    const sports = new Set(entries.map((e) => e.sport));
    const seasons = new Set(entries.map((e) => e.season).filter(Boolean) as string[]);
    const rawJson = entries.filter((e) => !!e.raw_json_url || !!e.raw_json_prefix).length;
    const parquet = entries.filter((e) => !!e.parquet_url).length;
    const records = entries.reduce((a, e) => a + (e.row_count ?? 0), 0);
    return {
      datasets: entries.length,
      records,
      sports: sports.size,
      seasons: seasons.size,
      rawJson,
      parquet,
    };
  }, [entries]);

  async function handleSample(e: CatalogEntry) {
    if (!e.sample_csv_url) {
      toast({ title: "No sample available yet", description: "A 100-row sample CSV is not yet published for this dataset." });
      return;
    }
    setDownloading((d) => ({ ...d, [e.dataset_id]: "sample" }));
    try {
      const fname = `${sanitizeFilename(e.dataset_id)}_${e.season ?? "current"}_sample_100.csv`;
      const { rowCount } = await downloadSampleCsv(e.sample_csv_url, fname, 100);
      toast({ title: "Sample downloaded", description: `${rowCount} rows · ${fname}` });
    } catch (err) {
      toast({ title: "Download failed", description: (err as Error).message, variant: "destructive" });
    } finally {
      setDownloading((d) => ({ ...d, [e.dataset_id]: null }));
    }
  }

  async function handleRawJson(e: CatalogEntry) {
    if (!e.raw_json_url) return;
    setDownloading((d) => ({ ...d, [e.dataset_id]: "json" }));
    try {
      const fname = `${sanitizeFilename(e.dataset_id)}_raw.json`;
      await downloadRawJson(e.raw_json_url, fname);
      toast({ title: "Raw JSON downloaded", description: fname });
    } catch (err) {
      toast({ title: "Download failed", description: (err as Error).message, variant: "destructive" });
    } finally {
      setDownloading((d) => ({ ...d, [e.dataset_id]: null }));
    }
  }

  return (
    <div className="space-y-6">
      <header className="surface-card sportsbook-glow p-5 md:p-6 bg-[linear-gradient(135deg,hsl(var(--navy-light)),hsl(var(--navy-deep)))] border-white/10">
        <div className="text-[11px] uppercase tracking-[0.24em] text-primary mb-2">Dataset catalog</div>
        <h1 className="text-2xl md:text-3xl font-black text-foreground">Browse source feeds and research inputs</h1>
        <p className="text-sm text-foreground/70 mt-2 max-w-2xl">
          Raw and normalized sports-data snapshots for feed review, feature engineering, and downstream model work.
          Parquet remains the analytical format; CSV and JSON samples are available for fast inspection.
        </p>
        <p className="text-[11px] text-muted-foreground mt-3">
          Catalog source:{" "}
          <span className="text-foreground/80">
            {loading ? "loading…" : catalog?.source === "r2" ? "Cloudflare R2" : "GitHub fallback"}
          </span>
          {catalog?.generated_at_utc && (
            <span className="ml-2">· refreshed {new Date(catalog.generated_at_utc).toLocaleString()}</span>
          )}
        </p>
      </header>

      <section aria-label="Catalog stats" className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <StatTile label="Datasets" value={stats.datasets} />
        <StatTile label="Records" value={stats.records} />
        <StatTile label="Sports" value={stats.sports} />
        <StatTile label="Seasons" value={stats.seasons} />
        <StatTile label="Raw JSON" value={stats.rawJson} />
        <StatTile label="Parquet" value={stats.parquet} />
      </section>

      <section className="space-y-3" aria-label="Filters">
        <div className="flex flex-wrap gap-2">
          {sportFilters.map((s) => (
            <FilterChip key={s} active={sport === s} onClick={() => setSport(s)}>
              {s === "all" ? "All sports" : SPORT_LABELS[s] ?? s}
            </FilterChip>
          ))}
        </div>
        <div className="flex flex-wrap gap-2">
          {entityFilters.map((e) => (
            <FilterChip key={e} active={entity === e} onClick={() => setEntity(e)}>
              {e === "all" ? "All entities" : entityLabel(e)}
            </FilterChip>
          ))}
        </div>
      </section>

      {loading ? (
        <div className="surface-card p-6 text-sm text-muted-foreground flex items-center gap-2">
          <Loader2 className="w-4 h-4 animate-spin" /> Loading catalog…
        </div>
      ) : filtered.length === 0 ? (
        <div className="surface-card p-6 text-sm text-muted-foreground">No datasets match these filters.</div>
      ) : (
        <section className="grid grid-cols-1 md:grid-cols-2 gap-3" aria-label="Datasets">
          {filtered.map((e) => {
            const dl = downloading[e.dataset_id];
            return (
              <article key={e.dataset_id} className="surface-card p-4 flex flex-col hover:border-primary/30 transition">
                <header className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <h3 className="font-black text-card-foreground truncate">{e.display_name}</h3>
                    <p className="text-[11px] text-muted-foreground">
                      {e.sport} · {entityLabel(e.entity)}
                      {e.granularity ? ` · ${e.granularity}` : ""}
                      {e.season ? ` · ${e.season}` : ""}
                    </p>
                  </div>
                  <AvailabilityChip status={e.availability_status} />
                </header>
                <p className="text-xs text-muted-foreground mt-2 line-clamp-2">{e.description}</p>

                <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-0.5 text-[11px]">
                  <DT label="Rows" value={fmtNum(e.row_count)} />
                  <DT label="Columns" value={fmtNum(e.column_count)} />
                  <DT label="Size" value={fmtBytes(e.file_size_bytes)} />
                  <DT label="Coverage" value={e.earliest_date || e.latest_date ? `${e.earliest_date ?? "?"} → ${e.latest_date ?? "?"}` : "—"} />
                  <DT label="Format" value={[e.parquet_url ? "Parquet" : null, e.sample_csv_url ? "CSV" : null, e.raw_json_url ? "JSON" : null].filter(Boolean).join(" · ") || "—"} />
                  <DT label="Updated" value={e.generated_at_utc ? new Date(e.generated_at_utc).toLocaleDateString() : "—"} />
                </dl>

                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Link
                    to={`/explore?dataset=${e.dataset_id}`}
                    className="min-h-[44px] inline-flex items-center justify-center gap-2 rounded-md bg-primary text-primary-foreground text-sm font-medium px-3"
                  >
                    <Eye className="w-4 h-4" /> Open board
                  </Link>
                  <Button
                    variant="outline"
                    className="min-h-[44px] gap-2"
                    disabled={!e.sample_csv_url || dl === "sample"}
                    onClick={() => handleSample(e)}
                  >
                    {dl === "sample" ? <Loader2 className="w-4 h-4 animate-spin" /> : <FileSpreadsheet className="w-4 h-4" />}
                    Sample CSV
                  </Button>
                  <Button
                    variant="outline"
                    className="min-h-[44px] gap-2"
                    disabled={!e.parquet_url}
                    asChild={!!e.parquet_url}
                  >
                    {e.parquet_url ? (
                      <a href={e.parquet_url} rel="noopener" download>
                        <Download className="w-4 h-4" /> Parquet
                      </a>
                    ) : (
                      <span><Download className="w-4 h-4" /> Parquet</span>
                    )}
                  </Button>
                  <Button
                    variant="outline"
                    className="min-h-[44px] gap-2"
                    disabled={!e.raw_json_url || dl === "json"}
                    onClick={() => handleRawJson(e)}
                  >
                    {dl === "json" ? <Loader2 className="w-4 h-4 animate-spin" /> : <FileJson className="w-4 h-4" />}
                    Raw JSON
                  </Button>
                </div>

                <div className="mt-3 flex flex-wrap items-center gap-3 text-[11px] text-muted-foreground">
                  <Link to={`/dictionary?dataset=${e.dataset_id}`} className="inline-flex items-center gap-1 hover:text-foreground">
                    <ListTree className="w-3 h-3" /> Schema
                  </Link>
                  <Link to={`/explore?dataset=${e.dataset_id}&tab=lineage`} className="inline-flex items-center gap-1 hover:text-foreground">
                    <Database className="w-3 h-3" /> Source lineage
                  </Link>
                  {e.primary_key && <span>PK: {e.primary_key}</span>}
                </div>
              </article>
            );
          })}
        </section>
      )}

      <p className="text-[11px] text-muted-foreground border border-white/5 rounded-md p-3">
        Game Stat Pulse provides raw and normalized sports-data snapshots for research, domain review, and future model
        development. Parquet is the primary analytical format. Sample and filtered CSV downloads are available for
        Excel, Google Sheets, and general review.
      </p>
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: number }) {
  return (
    <div className="surface-card p-3">
      <div className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</div>
      <div className="text-xl font-bold tabular-nums text-card-foreground mt-1">{(value ?? 0).toLocaleString()}</div>
    </div>
  );
}

function entityLabel(entity: string) {
  return ENTITY_LABELS[entity] ?? entity.replace(/_/g, " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function FilterChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      aria-pressed={active}
      className={`min-h-[40px] px-3 rounded-full text-xs font-medium border transition ${
        active
          ? "bg-primary text-primary-foreground border-primary"
          : "bg-white/5 text-foreground/80 border-white/10 hover:bg-white/10"
      }`}
    >
      {children}
    </button>
  );
}

function AvailabilityChip({ status }: { status: CatalogEntry["availability_status"] }) {
  const map: Record<CatalogEntry["availability_status"], string> = {
    available: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
    degraded: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
    missing: "bg-red-500/15 text-red-300 border border-red-500/30",
  };
  return <span className={`chip ${map[status]}`}>{status}</span>;
}

function DT({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-card-foreground text-right truncate">{value}</dd>
    </>
  );
}
function fmtNum(n: number | null) {
  return n == null ? "—" : n.toLocaleString();
}
function fmtBytes(n: number | null) {
  if (n == null) return "—";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}
