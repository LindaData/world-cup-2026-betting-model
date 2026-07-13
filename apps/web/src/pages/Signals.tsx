import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  Activity,
  AlertTriangle,
  BarChart3,
  Database,
  LineChart,
  Radio,
  Search,
  ShieldAlert,
  Target,
  TrendingUp,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useData } from "@/context/DataContext";
import { BETTING_DESK_ENABLED } from "@/lib/flags";
import type { GameRow, LiveFeed, StandingRow } from "@/types";

type SportFilter = "All" | "NBA" | "MLB";

interface TeamSignal {
  sport: "NBA" | "MLB";
  team: string;
  games: number;
  wins: number;
  losses: number;
  winPct: number;
  avgFor: number;
  avgAgainst: number;
  avgMargin: number;
  lastFive: string[];
  lastGameDate: string;
  standing?: StandingRow;
}

export default function Signals() {
  const { results, loading, lastRefresh, refresh } = useData();
  const [sport, setSport] = useState<SportFilter>("All");
  const [query, setQuery] = useState("");

  const games = useMemo(
    () => [
      ...(((results.basketball_games?.data as GameRow[] | null) ?? []).map((row) => ({ ...row, sport: "NBA" as const }))),
      ...(((results.baseball_games?.data as GameRow[] | null) ?? []).map((row) => ({ ...row, sport: "MLB" as const }))),
    ],
    [results],
  );

  const standings = useMemo(
    () => [
      ...(((results.basketball_standings?.data as StandingRow[] | null) ?? []).map((row) => ({ ...row, sport: "NBA" }))),
      ...(((results.baseball_standings?.data as StandingRow[] | null) ?? []).map((row) => ({ ...row, sport: "MLB" }))),
    ],
    [results],
  );

  const liveEvents = useMemo(() => {
    const nba = (results.nba_live?.data as LiveFeed | null)?.events ?? [];
    const mlb = (results.mlb_live?.data as LiveFeed | null)?.events ?? [];
    return [...nba.map((event) => ({ ...event, sport: "NBA" })), ...mlb.map((event) => ({ ...event, sport: "MLB" }))];
  }, [results]);

  const signals = useMemo(() => buildTeamSignals(games, standings), [games, standings]);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return signals
      .filter((item) => sport === "All" || item.sport === sport)
      .filter((item) => !q || item.team.toLowerCase().includes(q))
      .sort((a, b) => b.avgMargin - a.avgMargin || b.winPct - a.winPct || a.team.localeCompare(b.team));
  }, [query, signals, sport]);

  const leaders = filtered.slice(0, 8);
  const board = useMemo(() => summarizeBoard(filtered, liveEvents), [filtered, liveEvents]);

  return (
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="surface-card sportsbook-glow overflow-hidden">
        <div className="grid gap-4 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_360px]">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-primary/35 bg-primary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-primary">
              <TrendingUp className="h-3.5 w-3.5" />
              Signals Workbench
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl font-black leading-tight">
                Team form and matchup context from the feeds you have now.
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
                These are descriptive indicators from historical and live feeds. They are not picks, guarantees, or
                recommendations. Market interpretation still needs prices, injuries, and model validation.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={() => void refresh()} disabled={loading}>
                <Activity className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} /> Refresh feeds
              </Button>
              {/* The SQL lab is an ops tool — it only exists on desk builds. */}
              {BETTING_DESK_ENABLED && (
                <Button variant="outline" className="border-secondary/45 text-secondary hover:bg-secondary/10" asChild>
                  <Link to="/explore">
                    <Database className="h-4 w-4" /> Inspect raw data
                  </Link>
                </Button>
              )}
            </div>
            <p className="text-[11px] text-muted-foreground">
              Last refresh: {lastRefresh ? new Date(lastRefresh).toLocaleString() : "loading"}
            </p>
          </div>

          <aside className="market-panel bg-black/25 p-4">
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Signal board</div>
                <div className="mt-1 text-2xl font-black">{filtered.length}</div>
              </div>
              <LineChart className="h-8 w-8 text-primary" />
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <BoardCell label="Games parsed" value={board.games} />
              <BoardCell label="Live events" value={board.liveEvents} tone="amber" />
              <BoardCell label="Top form" value={board.topForm} />
              <BoardCell label="Need odds" value="Yes" tone="red" />
            </div>
          </aside>
        </div>
      </header>

      <section className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Teams rated" value={filtered.length} icon={Target} />
        <Metric label="Live events" value={board.liveEvents} icon={Radio} tone="amber" />
        <Metric label="Completed games" value={board.games} icon={BarChart3} />
        <Metric label="Market data gap" value="Odds" icon={ShieldAlert} tone="red" />
      </section>

      <section className="surface-card p-3">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap gap-2">
            {(["All", "NBA", "MLB"] as SportFilter[]).map((value) => (
              <button
                key={value}
                onClick={() => setSport(value)}
                className={`min-h-10 rounded-md border px-3 text-sm font-semibold ${
                  sport === value
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-white/10 bg-black/20 text-foreground/75 hover:bg-white/[0.05]"
                }`}
              >
                {value}
              </button>
            ))}
          </div>
          <div className="relative w-full lg:max-w-sm">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search team"
              className="min-h-10 bg-black/25 pl-9"
            />
          </div>
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Form leaderboard</div>
              <h2 className="mt-1 text-lg font-black">Best current team indicators</h2>
            </div>
            <div className="grid gap-3 p-4 md:grid-cols-2">
              {leaders.map((team) => (
                <TeamCard key={`${team.sport}-${team.team}`} team={team} />
              ))}
              {!leaders.length && (
                <div className="p-4 text-sm text-muted-foreground">No teams match this filter.</div>
              )}
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">All signals</div>
              <h2 className="mt-1 text-lg font-black">Team form table</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-sm">
                <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="p-3">Team</th>
                    <th className="p-3">Sport</th>
                    <th className="p-3">Games</th>
                    <th className="p-3">W-L</th>
                    <th className="p-3">Win %</th>
                    <th className="p-3">Avg margin</th>
                    <th className="p-3">Avg for</th>
                    <th className="p-3">Avg against</th>
                    <th className="p-3">Recent</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((team) => (
                    <tr key={`${team.sport}-${team.team}`} className="border-t border-white/5">
                      <td className="p-3 font-semibold">{team.team}</td>
                      <td className="p-3">{team.sport}</td>
                      <td className="p-3 tabular-nums">{team.games}</td>
                      <td className="p-3 tabular-nums">{team.wins}-{team.losses}</td>
                      <td className="p-3 tabular-nums">{formatPct(team.winPct)}</td>
                      <td className={team.avgMargin >= 0 ? "p-3 tabular-nums text-primary" : "p-3 tabular-nums text-red-300"}>
                        {formatSigned(team.avgMargin)}
                      </td>
                      <td className="p-3 tabular-nums">{team.avgFor.toFixed(1)}</td>
                      <td className="p-3 tabular-nums">{team.avgAgainst.toFixed(1)}</td>
                      <td className="p-3">
                        <FormStrip results={team.lastFive} />
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
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Market edge checklist</div>
            <h2 className="mt-1 text-lg font-black">Before this becomes a pick</h2>
            <div className="mt-4 space-y-3">
              <ChecklistItem status="ok" title="Historical results" body="NBA and MLB fallback game results are available." />
              <ChecklistItem status="ok" title="Standings context" body="Current fallback standings are available." />
              <ChecklistItem status="warn" title="Odds and prices" body="Public fallback does not include market pricing feeds yet." />
              <ChecklistItem status="warn" title="Availability inputs" body="Injury, lineup, and roster feeds need a successful data-lake publish." />
              <ChecklistItem status="warn" title="Model validation" body="Backtests, calibration, and decision rules still need to be built." />
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Live board</div>
            <h2 className="mt-1 text-lg font-black">Today / recent live feed</h2>
            <div className="mt-4 space-y-2">
              {liveEvents.length ? (
                liveEvents.slice(0, 8).map((event) => (
                  <div key={`${event.sport}-${event.event_id}`} className="rounded-lg border border-white/10 bg-black/20 p-3">
                    <div className="flex items-center justify-between gap-2 text-[11px] text-muted-foreground">
                      <span>{event.sport}</span>
                      <span>{event.status_short || event.status}</span>
                    </div>
                    <div className="mt-2 grid grid-cols-[1fr_auto] gap-y-1 text-sm">
                      <span className="truncate">{event.away_team}</span>
                      <span className="font-black tabular-nums">{event.away_score || "-"}</span>
                      <span className="truncate">{event.home_team}</span>
                      <span className="font-black tabular-nums">{event.home_score || "-"}</span>
                    </div>
                  </div>
                ))
              ) : (
                <div className="rounded-lg border border-white/10 bg-black/20 p-3 text-sm text-muted-foreground">
                  No live games in the current public feed.
                </div>
              )}
            </div>
          </section>
        </aside>
      </section>
    </div>
  );
}

function buildTeamSignals(games: Array<GameRow & { sport: "NBA" | "MLB" }>, standings: Array<StandingRow & { sport: string }>): TeamSignal[] {
  const byTeam = new Map<string, Array<{ row: GameRow & { sport: "NBA" | "MLB" }; forScore: number; againstScore: number; home: boolean }>>();

  for (const row of games) {
    const homeScore = Number(row.home_score);
    const awayScore = Number(row.away_score);
    if (!Number.isFinite(homeScore) || !Number.isFinite(awayScore)) continue;
    if (!row.home_team || !row.away_team) continue;

    const homeKey = `${row.sport}:${row.home_team}`;
    const awayKey = `${row.sport}:${row.away_team}`;
    byTeam.set(homeKey, [...(byTeam.get(homeKey) ?? []), { row, forScore: homeScore, againstScore: awayScore, home: true }]);
    byTeam.set(awayKey, [...(byTeam.get(awayKey) ?? []), { row, forScore: awayScore, againstScore: homeScore, home: false }]);
  }

  return Array.from(byTeam.entries()).map(([key, rows]) => {
    const [sport, team] = key.split(":");
    const sorted = [...rows].sort((a, b) => new Date(b.row.date_utc).getTime() - new Date(a.row.date_utc).getTime());
    const wins = sorted.filter((item) => item.forScore > item.againstScore).length;
    const losses = sorted.filter((item) => item.forScore < item.againstScore).length;
    const margins = sorted.map((item) => item.forScore - item.againstScore);
    const standing = standings.find((item) => item.sport === sport && item.team === team);
    return {
      sport: sport as "NBA" | "MLB",
      team,
      games: sorted.length,
      wins,
      losses,
      winPct: sorted.length ? wins / sorted.length : 0,
      avgFor: avg(sorted.map((item) => item.forScore)),
      avgAgainst: avg(sorted.map((item) => item.againstScore)),
      avgMargin: avg(margins),
      lastFive: sorted.slice(0, 5).map((item) => (item.forScore > item.againstScore ? "W" : item.forScore < item.againstScore ? "L" : "T")),
      lastGameDate: sorted[0]?.row.date_utc ?? "",
      standing,
    };
  });
}

function summarizeBoard(signals: TeamSignal[], liveEvents: Array<{ event_id: string }>) {
  return {
    games: signals.reduce((sum, item) => sum + item.games, 0) / 2,
    liveEvents: liveEvents.length,
    topForm: signals.filter((item) => item.lastFive.slice(0, 5).filter((result) => result === "W").length >= 4).length,
  };
}

function TeamCard({ team }: { team: TeamSignal }) {
  return (
    <article className="market-panel p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground">{team.sport}</div>
          <h3 className="truncate text-lg font-black">{team.team}</h3>
        </div>
        <span className={team.avgMargin >= 0 ? "rounded-sm bg-primary/15 px-2 py-1 text-sm font-black text-primary" : "rounded-sm bg-red-500/15 px-2 py-1 text-sm font-black text-red-300"}>
          {formatSigned(team.avgMargin)}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
        <BoardCell label="W-L" value={`${team.wins}-${team.losses}`} />
        <BoardCell label="Win %" value={formatPct(team.winPct)} />
        <BoardCell label="Games" value={team.games} tone="amber" />
      </div>
      <div className="mt-3 flex items-center justify-between gap-3 text-xs text-muted-foreground">
        <FormStrip results={team.lastFive} />
        <span>{team.standing?.group ?? formatDate(team.lastGameDate)}</span>
      </div>
    </article>
  );
}

function ChecklistItem({ status, title, body }: { status: "ok" | "warn"; title: string; body: string }) {
  return (
    <div className="rounded-lg border border-white/10 bg-black/20 p-3">
      <div className="flex items-center gap-2">
        {status === "ok" ? <Target className="h-4 w-4 text-primary" /> : <AlertTriangle className="h-4 w-4 text-secondary" />}
        <h3 className="font-semibold">{title}</h3>
      </div>
      <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

function Metric({
  label,
  value,
  icon: Icon,
  tone = "green",
}: {
  label: string;
  value: number | string;
  icon: typeof Target;
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
          <div className="mt-1 text-2xl font-black tabular-nums">{typeof value === "number" ? value.toLocaleString() : value}</div>
        </div>
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-md border ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </div>
  );
}

function BoardCell({ label, value, tone = "green" }: { label: string; value: number | string; tone?: "green" | "amber" | "red" }) {
  const color = tone === "amber" ? "text-secondary" : tone === "red" ? "text-red-300" : "text-primary";
  return (
    <div className="odds-cell">
      <div className="text-[10px] uppercase text-muted-foreground">{label}</div>
      <div className={color}>{typeof value === "number" ? value.toLocaleString() : value}</div>
    </div>
  );
}

function FormStrip({ results }: { results: string[] }) {
  return (
    <div className="flex gap-1" aria-label={`Recent form ${results.join("")}`}>
      {results.map((result, index) => (
        <span
          key={`${result}-${index}`}
          className={
            result === "W"
              ? "flex h-6 w-6 items-center justify-center rounded-sm bg-primary/20 text-[10px] font-black text-primary"
              : result === "L"
                ? "flex h-6 w-6 items-center justify-center rounded-sm bg-red-500/15 text-[10px] font-black text-red-300"
                : "flex h-6 w-6 items-center justify-center rounded-sm bg-white/10 text-[10px] font-black text-muted-foreground"
          }
        >
          {result}
        </span>
      ))}
    </div>
  );
}

function avg(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function formatPct(value: number) {
  return `${Math.round(value * 100)}%`;
}

function formatSigned(value: number) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(1)}`;
}

function formatDate(value: string) {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString();
}
