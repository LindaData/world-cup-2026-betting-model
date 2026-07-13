import { useMemo } from "react";
import { cn } from "@/lib/utils";
import { useData } from "@/context/DataContext";
import { LiveScoreCard } from "@/components/LiveScoreCard";
import { GamesView } from "@/components/GamesView";
import { StandingsView } from "@/components/StandingsView";
import { StatusBadge } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import { useSkeletonTimeout } from "@/hooks/use-skeleton-timeout";
import { getPredictions } from "@/lib/modelFeeds";
import type { GameRow, LiveFeed, StandingRow } from "@/types";

/** Per-sport section wording (soccer defaults; NBA/MLB localize these). */
interface SectionCopy {
  liveTitle?: string;
  standingsTitle?: string;
  gamesTitle?: string;
  emptyLive?: string;
  emptyStandings?: string;
  emptyGames?: string;
  /** Offline states teach what returns per section, never a generic triple. */
  offlineLive?: string;
  offlineStandings?: string;
  offlineGames?: string;
}

interface SportPageProps {
  title: string;
  liveKey: string;
  gamesKey: string;
  standingsKey: string;
  subtitle?: string;
  copy?: SectionCopy;
  mapGames?: (data: unknown) => GameRow[];
  mapStandings?: (data: unknown) => StandingRow[];
}

export function SportPage({
  title,
  liveKey,
  gamesKey,
  standingsKey,
  subtitle,
  copy,
  mapGames,
  mapStandings,
}: SportPageProps) {
  const { results, loading } = useData();
  // Skeletons are time-boxed: after ~3s the sections resolve to taught empty
  // states even if the feeds are still being retried.
  const skeletonExpired = useSkeletonTimeout();
  const live = results[liveKey];
  const games = results[gamesKey];
  const standings = results[standingsKey];

  const liveFeed = live?.data as LiveFeed | null;
  const liveEvents = liveFeed?.events ?? [];
  const gameRows = mapGames
    ? mapGames(games?.data ?? null)
    : ((games?.data as GameRow[] | null) ?? []);
  const standingRows = mapStandings
    ? mapStandings(standings?.data ?? null)
    : ((standings?.data as StandingRow[] | null) ?? []);
  const { map: predictions, preliminary } = useMemo(
    () => getPredictions(results),
    [results],
  );

  // Same order on every breakpoint: live scores (only while something is
  // actually live), then the fixture feed with the model's bars — the
  // product — then standings. The quiet no-live state collapses into a
  // one-line strip instead of a full-height card above the fold.
  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {subtitle ?? "Historical research data. Not betting advice."}
        </p>
      </div>

      {loading && !live && !skeletonExpired ? (
        <Section
          title={copy?.liveTitle ?? "Live & Recent"}
          badge={live && <StatusBadge origin={live.origin} />}
        >
          <SkeletonGrid />
        </Section>
      ) : liveEvents.length > 0 ? (
        <Section
          title={copy?.liveTitle ?? "Live & Recent"}
          badge={live && <StatusBadge origin={live.origin} />}
        >
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {liveEvents.map((e) => (
              <LiveScoreCard
                key={e.event_id}
                event={e}
                prediction={predictions[e.event_id]}
                preliminary={preliminary}
              />
            ))}
          </div>
        </Section>
      ) : (
        <SlimStrip
          msg={
            feedOffline(live)
              ? copy?.offlineLive ??
                "Feed offline — live scores return here on their own once it reconnects."
              : copy?.emptyLive ??
                "No live matches right now. Scores tick here in real time while games are on."
          }
        />
      )}

      <Section
        title={copy?.gamesTitle ?? "Fixtures & Results"}
        badge={games && <StatusBadge origin={games.origin} />}
      >
        {loading && !games && !skeletonExpired ? (
          <Skeleton className="h-64 w-full" />
        ) : gameRows.length ? (
          <GamesView rows={gameRows} predictions={predictions} preliminary={preliminary} />
        ) : (
          <EmptyMsg
            msg={
              copy?.emptyGames ??
              "No matches yet. Fixtures, final scores, and the model's win probabilities show up here once the data feed goes live."
            }
            offlineMsg={
              copy?.offlineGames ??
              "Feed offline — the match schedule, final scores, and model probabilities return here on their own once it reconnects."
            }
            offline={feedOffline(games)}
          />
        )}
      </Section>

      <Section
        title={copy?.standingsTitle ?? "Standings"}
        badge={standings && <StatusBadge origin={standings.origin} />}
      >
        {loading && !standings && !skeletonExpired ? (
          <Skeleton className="h-40 w-full" />
        ) : standingRows.length ? (
          <StandingsView rows={standingRows} />
        ) : (
          <EmptyMsg
            msg={
              copy?.emptyStandings ??
              "No standings yet. Team tables land here as soon as the standings feed publishes."
            }
            offlineMsg={
              copy?.offlineStandings ??
              "Feed offline — group tables with points and goal difference return here on their own once it reconnects."
            }
            offline={feedOffline(standings)}
          />
        )}
      </Section>
    </div>
  );
}

/** One-line quiet state for "nothing is live" — never a full-height card. */
function SlimStrip({ msg }: { msg: string }) {
  return (
    <p className="rounded-md border border-border bg-card px-3 py-2 text-xs text-muted-foreground">
      {msg}
    </p>
  );
}

/** True when the section's feed actually failed (vs simply having no rows). */
function feedOffline(result?: { origin: string; error?: string }): boolean {
  return result?.origin === "empty" && Boolean(result.error);
}

function Section({
  title,
  badge,
  children,
  className,
}: {
  title: string;
  badge?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="flex items-center gap-3">
        <h2 className="label-mono">{title}</h2>
        {badge}
      </div>
      {children}
    </section>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {[0, 1, 2].map((i) => (
        <Skeleton key={i} className="h-32 w-full" />
      ))}
    </div>
  );
}

/**
 * One message per state, never both: a healthy-but-quiet feed teaches what
 * will appear, and an offline feed still teaches what returns to this
 * specific section (never the same generic line three times in a row).
 */
function EmptyMsg({
  msg,
  offlineMsg,
  offline,
}: {
  msg: string;
  offlineMsg: string;
  offline?: boolean;
}) {
  return (
    <div className="surface-card p-6 text-center text-sm text-muted-foreground">
      <p>{offline ? offlineMsg : msg}</p>
    </div>
  );
}
