import { Link } from "react-router-dom";
import { useData } from "@/context/DataContext";
import { LiveScoreCard } from "@/components/LiveScoreCard";
import { StatusBadge } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import type { LiveFeed, Manifest } from "@/types";

export default function Index() {
  const { results, loading } = useData();
  const manifest = results.manifest?.data as Manifest | null;
  const nbaLive = results.nba_live?.data as LiveFeed | null;
  const mlbLive = results.mlb_live?.data as LiveFeed | null;

  const nbaEvents = nbaLive?.events ?? [];
  const mlbEvents = mlbLive?.events ?? [];
  const allLive = [...nbaEvents, ...mlbEvents];

  return (
    <div className="space-y-8">
      <div className="surface-card p-6 md:p-8 bg-gradient-to-br from-[hsl(var(--navy-light))] to-[hsl(var(--navy-deep))] text-foreground border-white/10">
        <div className="text-xs uppercase tracking-widest text-primary mb-2">
          Sports Research Data
        </div>
        <h1 className="text-2xl md:text-4xl font-bold mb-2">LindaData Sports Hub</h1>
        <p className="text-sm md:text-base text-foreground/70 max-w-2xl">
          Live scores, standings, and a season of historical game data for the NBA and MLB,
          sourced from the public LindaData research repository.
        </p>
        <p className="text-[11px] text-muted-foreground mt-4">
          All figures are historical research data — no betting advice or guarantees.
        </p>
      </div>

      <section className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatCard
          label="NBA Games"
          value={manifest?.sports.basketball.available_games}
          loading={loading}
        />
        <StatCard
          label="NBA Standings"
          value={manifest?.sports.basketball.standings_rows}
          loading={loading}
        />
        <StatCard
          label="MLB Games"
          value={manifest?.sports.baseball.available_games}
          loading={loading}
        />
        <StatCard
          label="MLB Standings"
          value={manifest?.sports.baseball.standings_rows}
          loading={loading}
        />
      </section>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold">Live & Recent Scores</h2>
          <div className="flex gap-2">
            {results.nba_live && (
              <StatusBadge origin={results.nba_live.origin} />
            )}
            {results.mlb_live && (
              <StatusBadge origin={results.mlb_live.origin} />
            )}
          </div>
        </div>
        {loading && allLive.length === 0 ? (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-32" />
            ))}
          </div>
        ) : allLive.length === 0 ? (
          <div className="surface-card p-6 text-center text-sm text-muted-foreground">
            No live games right now. Check back later.
          </div>
        ) : (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {allLive.slice(0, 6).map((e) => (
              <LiveScoreCard key={e.event_id} event={e} />
            ))}
          </div>
        )}
      </section>

      <section className="grid sm:grid-cols-3 gap-3">
        <Link
          to="/nba"
          className="surface-card p-5 hover:ring-2 hover:ring-primary transition"
        >
          <div className="text-xs uppercase tracking-wider text-primary mb-1">Explore</div>
          <div className="text-xl font-semibold text-card-foreground">NBA Hub →</div>
          <div className="text-sm text-muted-foreground mt-1">
            Live scores, standings, and full season game log.
          </div>
        </Link>
        <Link
          to="/mlb"
          className="surface-card p-5 hover:ring-2 hover:ring-primary transition"
        >
          <div className="text-xs uppercase tracking-wider text-primary mb-1">Explore</div>
          <div className="text-xl font-semibold text-card-foreground">MLB Hub →</div>
          <div className="text-sm text-muted-foreground mt-1">
            Live scores, standings, and full season game log.
          </div>
        </Link>
        <Link
          to="/raw"
          className="surface-card p-5 hover:ring-2 hover:ring-primary transition"
        >
          <div className="text-xs uppercase tracking-wider text-primary mb-1">Research</div>
          <div className="text-xl font-semibold text-card-foreground">Explore raw datasets →</div>
          <div className="text-sm text-muted-foreground mt-1">
            Query Parquet files in your browser. CSV download available.
          </div>
        </Link>
      </section>
    </div>
  );
}

function StatCard({
  label,
  value,
  loading,
}: {
  label: string;
  value: number | undefined;
  loading: boolean;
}) {
  return (
    <div className="surface-card p-4">
      <div className="text-[11px] uppercase tracking-wider text-muted-foreground">{label}</div>
      <div className="text-2xl font-bold tabular-nums text-card-foreground mt-1">
        {loading && value == null ? "…" : (value ?? 0).toLocaleString()}
      </div>
    </div>
  );
}
