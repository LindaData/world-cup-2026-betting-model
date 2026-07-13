import { createContext, useContext, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { ArrowDown, ArrowUp } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ProbabilityBar } from "@/components/ProbabilityBar";
import { cn } from "@/lib/utils";
import {
  friendlyTeamName,
  isFinishedStatus,
  isPlaceholderTeam,
  matchVerdict,
  placeholderMatchLabel,
} from "@/lib/matchVerdict";
import type { GameRow } from "@/types";
import type { ModelPrediction, PredictionMap } from "@/lib/modelFeeds";

// Types live in modelFeeds now; re-exported so existing imports keep working.
export type { ModelPrediction, PredictionMap } from "@/lib/modelFeeds";

/**
 * How the surrounding page presents fixtures.
 *
 * "grouped" (soccer, the default): the list splits into "Up next" (soonest
 * kickoff first) above "Played" (most recent first). The grouping IS the
 * order, so no sort chips render — one less control to learn.
 *
 * "sortable" (NBA/MLB): keeps the chip-sorted view unchanged.
 *
 * Matches.tsx provides the value for the selected sport.
 */
export type GamesViewVariant = "grouped" | "sortable";
export const GamesViewVariantContext = createContext<GamesViewVariant>("grouped");

type SortKey = "kickoff" | "date_utc" | "home_team" | "away_team";

const SORTS: { key: SortKey; label: string }[] = [
  { key: "kickoff", label: "Next" },
  { key: "date_utc", label: "Date" },
  { key: "home_team", label: "Home" },
  { key: "away_team", label: "Away" },
];

export function GamesView({
  rows,
  predictions,
}: {
  rows: GameRow[];
  predictions?: PredictionMap;
}) {
  const variant = useContext(GamesViewVariantContext);
  const grouped = variant === "grouped";
  const [q, setQ] = useState("");
  // Default is "next kickoff first": the hero slot goes to the next match a
  // reader can act on, never a far-future placeholder. The Date chip keeps
  // the plain chronological views (sortable variant only).
  const [sortKey, setSortKey] = useState<SortKey>("kickoff");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("desc");
  const [page, setPage] = useState(0);
  const pageSize = 24;

  // `list` is the paged order. `playedStart` marks where the "Played" group
  // begins in the grouped variant (-1 when the list is one flat sort).
  const { list, playedStart } = useMemo(() => {
    const ql = q.trim().toLowerCase();
    const f = ql
      ? rows.filter(
          (r) =>
            r.home_team?.toLowerCase().includes(ql) ||
            r.away_team?.toLowerCase().includes(ql) ||
            r.date_utc?.toLowerCase().includes(ql),
        )
      : rows;
    if (grouped || sortKey === "kickoff") {
      // Upcoming matches ascending from now, then recent results descending.
      const nowMs = Date.now();
      const time = (r: GameRow) => {
        const t = new Date(r.date_utc ?? "").getTime();
        return Number.isNaN(t) ? 0 : t;
      };
      const upcoming = f.filter((r) => time(r) >= nowMs).sort((a, b) => time(a) - time(b));
      const past = f.filter((r) => time(r) < nowMs).sort((a, b) => time(b) - time(a));
      return {
        list: [...upcoming, ...past],
        playedStart: grouped ? upcoming.length : -1,
      };
    }
    const sorted = [...f].sort((a, b) => {
      const av = a[sortKey] ?? "";
      const bv = b[sortKey] ?? "";
      const cmp = av.localeCompare(bv, undefined, { numeric: true });
      return sortDir === "asc" ? cmp : -cmp;
    });
    return { list: sorted, playedStart: -1 };
  }, [rows, q, sortKey, sortDir, grouped]);

  const totalPages = Math.max(1, Math.ceil(list.length / pageSize));
  const safePage = Math.min(page, totalPages - 1);
  const sliceStart = safePage * pageSize;
  const slice = list.slice(sliceStart, sliceStart + pageSize);

  // Because the grouped list is always "all upcoming, then all played", a
  // page slice is a run of upcoming followed by a run of played — one cut.
  const upNextCount =
    playedStart >= 0
      ? Math.min(Math.max(playedStart - sliceStart, 0), slice.length)
      : slice.length;
  const upNext = slice.slice(0, upNextCount);
  const played = slice.slice(upNextCount);

  const toggleSort = (k: SortKey) => {
    // "Next" has one fixed order (upcoming first), so re-tapping it is a no-op.
    if (k === "kickoff") {
      setSortKey(k);
      return;
    }
    if (k === sortKey) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(k);
      setSortDir(k === "date_utc" ? "desc" : "asc");
    }
  };

  return (
    <div className="space-y-3">
      {/* Quiet toolbar: search, count, and (sortable variant only) sort chips.
          The grouped feed drops the chips — its two sections are the order. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <Input
          placeholder="Search team or date"
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setPage(0);
          }}
          className="h-11 bg-card sm:max-w-xs"
        />
        <div className="flex items-center justify-between gap-3 sm:justify-end">
          {!grouped && (
            <div className="flex items-center gap-1" role="group" aria-label="Sort matches">
              {SORTS.map((s) => {
                const active = s.key === sortKey;
                return (
                  <button
                    key={s.key}
                    type="button"
                    aria-pressed={active}
                    onClick={() => toggleSort(s.key)}
                    className={cn(
                      // Same chip family as the standings group filters: 44px
                      // hit area, visible border so all three read as buttons.
                      "chip min-h-11 border px-3 transition-colors",
                      active
                        ? "border-border bg-muted text-foreground"
                        : "border-border/60 bg-card text-muted-foreground hover:text-foreground",
                    )}
                  >
                    {s.label}
                    {active &&
                      s.key !== "kickoff" &&
                      (sortDir === "asc" ? (
                        <ArrowUp className="h-3 w-3" aria-hidden="true" />
                      ) : (
                        <ArrowDown className="h-3 w-3" aria-hidden="true" />
                      ))}
                  </button>
                );
              })}
            </div>
          )}
          <span className="label-mono tabular-nums">
            {list.length.toLocaleString()} matches
          </span>
        </div>
      </div>

      {/* Match cards */}
      {slice.length > 0 ? (
        grouped ? (
          <div className="space-y-5">
            {upNext.length > 0 && (
              <section aria-label="Up next" className="space-y-2">
                <h3 className="label-mono">Up next</h3>
                <div className="grid gap-2 sm:grid-cols-2">
                  {upNext.map((g) => (
                    <MatchCard key={g.game_id} game={g} prediction={predictions?.[g.game_id]} />
                  ))}
                </div>
              </section>
            )}
            {played.length > 0 && (
              <section aria-label="Played" className="space-y-2">
                <h3 className="label-mono">Played</h3>
                <div className="grid gap-2 sm:grid-cols-2">
                  {played.map((g) => (
                    <MatchCard
                      key={g.game_id}
                      game={g}
                      prediction={predictions?.[g.game_id]}
                      played
                    />
                  ))}
                </div>
              </section>
            )}
          </div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {slice.map((g) => (
              <MatchCard key={g.game_id} game={g} prediction={predictions?.[g.game_id]} />
            ))}
          </div>
        )
      ) : (
        <div className="surface-card p-6 text-center text-sm text-muted-foreground">
          No matches found. Try a different team or date.
        </div>
      )}

      {/* Quiet pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <Button
            variant="ghost"
            size="sm"
            className="label-mono min-h-11 px-4 hover:text-foreground"
            disabled={safePage === 0}
            onClick={() => setPage((p) => Math.max(0, p - 1))}
          >
            Prev
          </Button>
          <span className="label-mono tabular-nums">
            Page {safePage + 1} / {totalPages}
          </span>
          <Button
            variant="ghost"
            size="sm"
            className="label-mono min-h-11 px-4 hover:text-foreground"
            disabled={safePage >= totalPages - 1}
            onClick={() => setPage((p) => p + 1)}
          >
            Next
          </Button>
        </div>
      )}
    </div>
  );
}

function MatchCard({
  game,
  prediction,
  played = false,
}: {
  game: GameRow;
  prediction?: ModelPrediction;
  /** Played rows keep the score + "Model leaned X" line and skip the bar. */
  played?: boolean;
}) {
  // Bracket placeholders read as broken data: give the fixture a human title
  // ("Third-place match") and friendly participant names instead.
  const bracketLabel = placeholderMatchLabel(game.home_team, game.away_team);
  const homeName = friendlyTeamName(game.home_team);
  const awayName = friendlyTeamName(game.away_team);
  // Teams-TBD fixtures never show a hard probability bar: a concrete 44% for
  // teams that don't exist yet is false precision.
  const teamsTbd = isPlaceholderTeam(game.home_team) || isPlaceholderTeam(game.away_team);
  const verdict = prediction
    ? matchVerdict({
        homeTeam: game.home_team,
        awayTeam: game.away_team,
        probs: prediction,
        finished: isFinishedStatus(game.status),
        homeScore: game.home_score,
        awayScore: game.away_score,
      })
    : null;
  // Every card is a link into the match page — full-card hit area, and a
  // plain Link stays in the tab order for keyboard readers.
  return (
    <Link
      to={`/match/${game.game_id}`}
      className="surface-card block p-4 transition-colors hover:border-muted-foreground/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <div className="flex items-center justify-between gap-2">
        <span className="label-mono tabular-nums">{formatDate(game.date_utc)}</span>
        <span className="label-mono truncate">{game.status}</span>
      </div>

      {bracketLabel && (
        <p className="mt-3 text-sm font-semibold text-card-foreground">
          {bracketLabel}
          <span className="ml-2 font-normal text-muted-foreground">
            Teams decided after the semi-finals
          </span>
        </p>
      )}

      <div className="mt-3 grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1.5">
        <TeamName
          name={homeName}
          dot={prediction && !teamsTbd && !played ? "bg-gain" : undefined}
        />
        <ScoreNum value={game.home_score} />
        <TeamName
          name={awayName}
          dot={prediction && !teamsTbd && !played ? "bg-away" : undefined}
        />
        <ScoreNum value={game.away_score} />
      </div>

      {prediction &&
        (teamsTbd || played ? (
          verdict && <p className="mt-3 text-xs text-muted-foreground">{verdict.text}</p>
        ) : (
          <div className="mt-3 space-y-1.5">
            <ProbabilityBar probs={prediction} labels={{ home: homeName, away: awayName }} />
            {verdict && <p className="text-xs text-muted-foreground">{verdict.text}</p>}
          </div>
        ))}
    </Link>
  );
}

function TeamName({ name, dot }: { name: string; dot?: string }) {
  return (
    <div className="flex min-w-0 items-center gap-2">
      {dot && (
        <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", dot)} aria-hidden="true" />
      )}
      <span className="truncate text-sm font-semibold text-card-foreground">{name}</span>
    </div>
  );
}

function ScoreNum({ value }: { value: string }) {
  return (
    <div className="text-2xl font-extrabold leading-none tabular-nums text-card-foreground">
      {value || "–"}
    </div>
  );
}

function formatDate(iso: string) {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
