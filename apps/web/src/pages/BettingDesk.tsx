import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { AlertTriangle, ArrowRight, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { loadCatalog, type Catalog, type CatalogEntry } from "@/lib/catalog";

const MODEL_GROUPS = [
  {
    key: "markets",
    title: "Market data",
    entities: ["odds", "betting_reference"],
  },
  {
    key: "event_context",
    title: "Event context",
    entities: ["fixtures", "head_to_head", "standings", "venues", "leagues", "games", "scores"],
  },
  {
    key: "availability",
    title: "Availability",
    entities: ["injuries", "lineups", "fixture_lineups", "squads", "sidelined"],
  },
  {
    key: "performance",
    title: "Performance",
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

const DESK_PAGES = [
  {
    href: "/edge",
    title: "Price a line",
    body: "Turn odds plus your win probability into EV, fair odds, and a capped stake.",
  },
  {
    href: "/portfolio",
    title: "Compare a card",
    body: "Rank a batch of selections by edge and expected profit, then export the best ones.",
  },
  {
    href: "/bankroll",
    title: "Bankroll & ledger",
    body: "Track open positions, settled returns, and closing-line value from your CSV ledger.",
  },
];

const RESEARCH_LINKS = [
  { href: "/signals", label: "Signals" },
  { href: "/model", label: "Model audit" },
  { href: "/datasets", label: "Data feeds" },
  { href: "/approval", label: "Review board" },
  { href: "/explore", label: "Data lab" },
  { href: "/status", label: "Source health" },
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
  const sourceLabel = catalog?.source === "r2" ? "fresh data lake" : "fallback catalog";

  return (
    <div className="mx-auto max-w-3xl space-y-5 pb-28 lg:pb-0">
      <header className="surface-card p-4 sm:p-6">
        <div className="label-mono">Betting desk</div>
        <div className="num-hero mt-2">{stats.readiness}%</div>
        <div className="mt-1 text-sm text-muted-foreground">
          {stats.total
            ? `${stats.available} of ${stats.total} data feeds are ready to use, from the ${sourceLabel}.`
            : loading
              ? "Checking which data feeds are ready to use..."
              : "No feed catalog loaded yet. Feed readiness will appear here once a catalog is published."}
        </div>

        <div className="mt-5 grid grid-cols-2 gap-3 border-t border-border pt-4 sm:grid-cols-4">
          <Stat label="Ready feeds" value={String(stats.available)} tone={stats.available ? "gain" : undefined} />
          <Stat label="Needs review" value={String(stats.degraded + stats.missing)} />
          <Stat label="Core inputs" value={String(stats.bettingRelevant)} />
          <Stat label="Sports" value={String(stats.sports)} />
        </div>

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <Button variant="outline" className="min-h-11" onClick={() => void refresh()} disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin motion-reduce:animate-none" : ""}`} /> Refresh feeds
          </Button>
          {catalog?.generated_at_utc && (
            <span className="label-mono">Updated {new Date(catalog.generated_at_utc).toLocaleString()}</span>
          )}
        </div>
      </header>

      {error && (
        <div className="surface-card flex gap-2 p-4 text-sm text-muted-foreground">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {error}
        </div>
      )}

      <section className="space-y-3">
        <div className="label-mono px-1">Desk tools</div>
        <div className="grid gap-3">
          {DESK_PAGES.map((page) => (
            <Link key={page.href} to={page.href} className="surface-card block p-4 hover:border-gain/40 sm:p-5">
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-base font-bold">{page.title}</h2>
                <ArrowRight className="h-4 w-4 shrink-0 text-gain" />
              </div>
              <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{page.body}</p>
            </Link>
          ))}
        </div>
      </section>

      <section className="surface-card p-4 sm:p-5">
        <div className="label-mono">Research & data</div>
        <div className="mt-3 flex flex-wrap gap-2">
          {RESEARCH_LINKS.map((link) => (
            <Link
              key={link.href}
              to={link.href}
              className="chip min-h-11 border border-border bg-background px-3 text-sm font-medium text-muted-foreground hover:border-gain/40 hover:text-foreground"
            >
              {link.label}
            </Link>
          ))}
        </div>
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
  const readiness = total ? Math.round((available / total) * 100) : 0;
  return { total, available, degraded, missing, sports, bettingRelevant, readiness };
}

function isBettingRelevant(entry: CatalogEntry) {
  return MODEL_GROUPS.some((group) => group.entities.includes(entry.entity));
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "gain" | "loss" }) {
  const color = tone === "gain" ? "text-gain" : tone === "loss" ? "text-loss" : "text-foreground";
  return (
    <div className="min-w-0">
      <div className="label-mono truncate">{label}</div>
      <div className={`mt-0.5 truncate text-lg font-bold tabular-nums ${color}`}>{value}</div>
    </div>
  );
}
