import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  ArrowRight,
  BarChart3,
  CheckCircle2,
  Database,
  LineChart,
  Loader2,
  RefreshCw,
  ShieldAlert,
  Target,
  Ticket,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { loadCatalog, type Catalog, type CatalogEntry } from "@/lib/catalog";

const MODEL_GROUPS = [
  {
    key: "markets",
    title: "Market data",
    description: "Odds, bookmakers, bet types, live odds, and market mapping.",
    entities: ["odds", "betting_reference"],
  },
  {
    key: "event_context",
    title: "Event context",
    description: "Fixtures, head-to-head, standings, venues, leagues, and schedule context.",
    entities: ["fixtures", "head_to_head", "standings", "venues", "leagues", "games", "scores"],
  },
  {
    key: "availability",
    title: "Availability",
    description: "Injuries, lineups, squads, sidelined history, and roster context.",
    entities: ["injuries", "lineups", "fixture_lineups", "squads", "sidelined"],
  },
  {
    key: "performance",
    title: "Performance",
    description: "Team statistics, player statistics, player rankings, events, and transfers.",
    entities: [
      "team_statistics",
      "player_statistics",
      "player_game_statistics",
      "player_rankings",
      "fixture_events",
      "transfers",
      "players",
      "teams",
    ],
  },
];

const WORKFLOW = [
  {
    title: "Read current signals",
    body: "Use team form, average margin, live board status, and the market-data checklist as the daily starting point.",
    href: "/signals",
    action: "Open signals",
  },
  {
    title: "Price a scenario",
    body: "Enter your model probability and a market line to calculate implied probability, EV, and capped sizing.",
    href: "/edge",
    action: "Open pricing lab",
  },
  {
    title: "Compare a batch",
    body: "Rank multiple model probabilities against market prices, then export the best scenarios for review.",
    href: "/portfolio",
    action: "Open scenario lab",
  },
  {
    title: "Audit the model",
    body: "Paste settled prediction logs to measure calibration, Brier score, closing-line value, realized P&L, and ROI.",
    href: "/model",
    action: "Open model audit",
  },
  {
    title: "Track performance",
    body: "Log open and settled positions to monitor exposure, realized return, CLV, and capital movement.",
    href: "/bankroll",
    action: "Open performance ledger",
  },
  {
    title: "Review priority feeds",
    body: "Clear or flag market, availability, and fixture feeds before trusting downstream features.",
    href: "/approval",
    action: "Open review board",
  },
  {
    title: "Inspect raw tables",
    body: "Use the data lab for field-level checks, quick filters, schema inspection, and CSV exports.",
    href: "/explore",
    action: "Open data lab",
  },
  {
    title: "Check source health",
    body: "Confirm whether the public app is using the fallback catalog or a fresh published data lake.",
    href: "/status",
    action: "Check feeds",
  },
];

export default function BettingDesk() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = async () => {
    setLoading(true);
    setError(null);
    try {
      setCatalog(await loadCatalog(true));
    } catch (cause) {
      setError((cause as Error).message || "Catalog could not be loaded.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const entries = useMemo(() => catalog?.entries ?? [], [catalog]);
  const stats = useMemo(() => summarizeCatalog(entries), [entries]);
  const modelGroups = useMemo(() => summarizeGroups(entries), [entries]);
  const sportRows = useMemo(() => summarizeSports(entries), [entries]);
  const priorityFeeds = useMemo(() => rankPriorityFeeds(entries), [entries]);
  const sourceLabel = catalog?.source === "r2" ? "Fresh data lake" : "Fallback catalog";

  return (
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="relative overflow-hidden rounded-lg border border-white/10 bg-[linear-gradient(135deg,hsl(var(--navy-light)),hsl(var(--navy-deep)))] sportsbook-glow">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,hsl(var(--primary)/0.14),transparent_28rem),radial-gradient(circle_at_top_right,hsl(var(--secondary)/0.12),transparent_22rem)]" aria-hidden="true" />
        <div className="relative grid gap-5 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_390px] lg:items-end">
          <div className="max-w-3xl space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-secondary/40 bg-secondary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-secondary">
              <Target className="h-3.5 w-3.5" />
              Research Desk
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl lg:text-5xl font-black leading-[0.98] tracking-normal">
                See feed readiness before you model anything.
              </h1>
              <p className="mt-3 max-w-2xl text-sm sm:text-base text-foreground/[0.76]">
                One surface for fixtures, odds, availability, and performance inputs so you can understand what is
                usable now, what is stale, and what still needs validation before downstream analysis.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="min-h-11 bg-primary text-primary-foreground hover:bg-primary/90" onClick={() => void refresh()} disabled={loading}>
                <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} /> Refresh desk
              </Button>
              <Button className="min-h-11 border-secondary/45 text-secondary hover:bg-secondary/10" variant="outline" asChild>
                <Link to="/datasets">
                  <Database className="h-4 w-4" /> Browse feeds
                </Link>
              </Button>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Catalog: {sourceLabel}
              {catalog?.generated_at_utc ? ` / ${new Date(catalog.generated_at_utc).toLocaleString()}` : ""}
            </p>
          </div>

          <aside className="market-panel bg-black/40 p-4 backdrop-blur-md">
            <div className="mb-3 flex items-center justify-between gap-3">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Coverage snapshot</div>
                <div className="mt-1 text-2xl font-black tabular-nums">{stats.readiness}%</div>
              </div>
              <LineChart className="h-9 w-9 text-primary" />
            </div>
            <div className="mb-3 h-2.5 overflow-hidden rounded-sm bg-white/10">
              <div className="h-full bg-primary transition-all" style={{ width: `${stats.readiness}%` }} />
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <DeskCell label="Ready feeds" value={stats.available} />
              <DeskCell label="Needs review" value={stats.degraded + stats.missing} tone="amber" />
              <DeskCell label="Core inputs" value={stats.bettingRelevant} />
              <DeskCell label="Sports" value={stats.sports} tone="amber" />
            </div>
          </aside>
        </div>
      </header>

      {error && (
        <div className="surface-card flex gap-2 p-4 text-sm text-amber-300">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {error}
        </div>
      )}

      <section className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Total feeds" value={stats.total} icon={Database} />
        <Metric label="Market inputs" value={stats.marketData} icon={BarChart3} tone="amber" />
        <Metric label="Availability inputs" value={stats.availability} icon={ShieldAlert} tone="red" />
        <Metric label="Model-ready feeds" value={stats.available} icon={CheckCircle2} />
      </section>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Model input coverage</div>
              <h2 className="mt-1 text-lg font-black">What the model can use right now</h2>
            </div>
            <div className="grid gap-3 p-4 md:grid-cols-2">
              {modelGroups.map((group) => (
                <article key={group.key} className="market-panel p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h3 className="font-black">{group.title}</h3>
                      <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{group.description}</p>
                    </div>
                    <span className="rounded-sm bg-primary/15 px-2 py-1 text-xs font-black text-primary">
                      {group.readiness}%
                    </span>
                  </div>
                  <div className="mt-3 h-2 overflow-hidden rounded-sm bg-white/10">
                    <div className="h-full bg-primary" style={{ width: `${group.readiness}%` }} />
                  </div>
                  <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
                    <DeskCell label="Feeds" value={group.total} />
                    <DeskCell label="Ready" value={group.available} />
                    <DeskCell label="Sports" value={group.sports} tone="amber" />
                  </div>
                </article>
              ))}
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Sports coverage</div>
              <h2 className="mt-1 text-lg font-black">Feed health by sport</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[620px] text-sm">
                <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="p-3">Sport</th>
                    <th className="p-3">Feeds</th>
                    <th className="p-3">Ready</th>
                    <th className="p-3">Action needed</th>
                    <th className="p-3">Core inputs</th>
                    <th className="p-3">Readiness</th>
                  </tr>
                </thead>
                <tbody>
                  {sportRows.map((row) => (
                    <tr key={row.sport} className="border-t border-white/5">
                      <td className="p-3 font-semibold">{row.sport}</td>
                      <td className="p-3 tabular-nums">{row.total}</td>
                      <td className="p-3 tabular-nums text-primary">{row.available}</td>
                      <td className="p-3 tabular-nums text-secondary">{row.actionNeeded}</td>
                      <td className="p-3 tabular-nums">{row.bettingRelevant}</td>
                      <td className="p-3">
                        <div className="flex items-center gap-2">
                          <div className="h-2 w-24 overflow-hidden rounded-sm bg-white/10">
                            <div className="h-full bg-primary" style={{ width: `${row.readiness}%` }} />
                          </div>
                          <span className="tabular-nums text-muted-foreground">{row.readiness}%</span>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <aside className="min-w-0 space-y-4">
          <section className="surface-card p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Next actions</div>
                <h2 className="mt-1 text-lg font-black">Desk workflow</h2>
              </div>
              <Ticket className="h-7 w-7 text-secondary" />
            </div>
            <div className="mt-4 space-y-3">
              {WORKFLOW.map((item) => (
                <Link key={item.href} to={item.href} className="block rounded-lg border border-white/10 bg-black/20 p-3 hover:border-primary/35">
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="font-semibold">{item.title}</h3>
                    <ArrowRight className="h-4 w-4 text-primary" />
                  </div>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{item.body}</p>
                  <div className="mt-2 text-xs font-black uppercase tracking-wide text-primary">{item.action}</div>
                </Link>
              ))}
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Priority feeds</div>
            <h2 className="mt-1 text-lg font-black">Review these first</h2>
            {loading ? (
              <div className="mt-4 flex gap-2 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading feeds...
              </div>
            ) : priorityFeeds.length ? (
              <div className="mt-4 space-y-2">
                {priorityFeeds.map((entry) => (
                  <Link
                    key={entry.dataset_id}
                    to={`/approval?dataset=${entry.dataset_id}`}
                    className="block rounded-lg border border-white/10 bg-black/20 p-3 hover:border-primary/35"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="truncate text-sm font-semibold">{entry.display_name}</div>
                        <div className="mt-1 text-[11px] text-muted-foreground">
                          {entry.sport} / {entityLabel(entry.entity)}
                        </div>
                      </div>
                      <AvailabilityChip status={entry.availability_status} />
                    </div>
                  </Link>
                ))}
              </div>
            ) : (
              <div className="mt-4 text-sm text-muted-foreground">No priority feeds are available yet.</div>
            )}
          </section>
        </aside>
      </section>
    </div>
  );
}

function summarizeCatalog(entries: CatalogEntry[]) {
  const total = entries.length;
  const available = entries.filter((entry) => entry.availability_status === "available").length;
  const degraded = entries.filter((entry) => entry.availability_status === "degraded").length;
  const missing = entries.filter((entry) => entry.availability_status === "missing").length;
  const sports = new Set(entries.map((entry) => entry.sport)).size;
  const bettingRelevant = entries.filter(isBettingRelevant).length;
  const marketData = entries.filter((entry) => ["odds", "betting_reference"].includes(entry.entity)).length;
  const availability = entries.filter((entry) =>
    ["injuries", "lineups", "fixture_lineups", "squads", "sidelined"].includes(entry.entity),
  ).length;
  const readiness = total ? Math.round((available / total) * 100) : 0;
  return { total, available, degraded, missing, sports, bettingRelevant, marketData, availability, readiness };
}

function summarizeGroups(entries: CatalogEntry[]) {
  return MODEL_GROUPS.map((group) => {
    const matched = entries.filter((entry) => group.entities.includes(entry.entity));
    const available = matched.filter((entry) => entry.availability_status === "available").length;
    const sports = new Set(matched.map((entry) => entry.sport)).size;
    return {
      ...group,
      total: matched.length,
      available,
      sports,
      readiness: matched.length ? Math.round((available / matched.length) * 100) : 0,
    };
  });
}

function summarizeSports(entries: CatalogEntry[]) {
  const bySport = new Map<string, CatalogEntry[]>();
  entries.forEach((entry) => bySport.set(entry.sport, [...(bySport.get(entry.sport) ?? []), entry]));
  return Array.from(bySport.entries())
    .map(([sport, sportEntries]) => {
      const available = sportEntries.filter((entry) => entry.availability_status === "available").length;
      const actionNeeded = sportEntries.length - available;
      return {
        sport,
        total: sportEntries.length,
        available,
        actionNeeded,
        bettingRelevant: sportEntries.filter(isBettingRelevant).length,
        readiness: sportEntries.length ? Math.round((available / sportEntries.length) * 100) : 0,
      };
    })
    .sort((a, b) => b.bettingRelevant - a.bettingRelevant || a.sport.localeCompare(b.sport));
}

function rankPriorityFeeds(entries: CatalogEntry[]) {
  const priorityEntities = ["odds", "betting_reference", "injuries", "lineups", "fixture_lineups", "fixtures", "head_to_head"];
  return entries
    .filter((entry) => priorityEntities.includes(entry.entity))
    .sort((a, b) => {
      const aStatus = a.availability_status === "available" ? 0 : a.availability_status === "degraded" ? 1 : 2;
      const bStatus = b.availability_status === "available" ? 0 : b.availability_status === "degraded" ? 1 : 2;
      return aStatus - bStatus || priorityEntities.indexOf(a.entity) - priorityEntities.indexOf(b.entity);
    })
    .slice(0, 8);
}

function isBettingRelevant(entry: CatalogEntry) {
  return MODEL_GROUPS.some((group) => group.entities.includes(entry.entity));
}

function Metric({
  label,
  value,
  icon: Icon,
  tone = "green",
}: {
  label: string;
  value: number;
  icon: typeof Database;
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
          <div className="truncate text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
          <div className="mt-1 text-2xl font-black tabular-nums">{value.toLocaleString()}</div>
        </div>
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-md border ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </div>
  );
}

function DeskCell({ label, value, tone = "green" }: { label: string; value: number | string; tone?: "green" | "amber" }) {
  return (
    <div className="odds-cell">
      <div className="text-[10px] uppercase text-muted-foreground">{label}</div>
      <div className={tone === "amber" ? "text-secondary" : "text-primary"}>{value}</div>
    </div>
  );
}

function AvailabilityChip({ status }: { status: CatalogEntry["availability_status"] }) {
  const map: Record<CatalogEntry["availability_status"], string> = {
    available: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
    degraded: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
    missing: "bg-red-500/15 text-red-300 border border-red-500/30",
  };
  return <span className={`chip shrink-0 capitalize ${map[status]}`}>{status}</span>;
}

function entityLabel(entity: string) {
  return entity.replace(/_/g, " ").replace(/\b\w/g, (char) => char.toUpperCase());
}
