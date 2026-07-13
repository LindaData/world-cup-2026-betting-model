import { useMemo } from "react";
import { cn } from "@/lib/utils";
import { useData } from "@/context/DataContext";
import { LiveScoreCard } from "@/components/LiveScoreCard";
import { GamesView, type PredictionMap } from "@/components/GamesView";
import { StandingsView } from "@/components/StandingsView";
import { StatusBadge } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import { useSkeletonTimeout } from "@/hooks/use-skeleton-timeout";
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

/** Pull the {game_id: {home, draw, away}} map out of the model_predictions feed. */
function extractPredictions(data: unknown): PredictionMap {
  if (!data || typeof data !== "object") return {};
  const preds = (data as { predictions?: unknown }).predictions;
  if (!preds || typeof preds !== "object") return {};
  const out: PredictionMap = {};
  for (const [id, v] of Object.entries(preds as Record<string, unknown>)) {
    if (!v || typeof v !== "object") continue;
    const p = v as Record<string, unknown>;
    if (
      typeof p.home === "number" &&
      typeof p.draw === "number" &&
      typeof p.away === "number"
    ) {
      out[id] = { home: p.home, draw: p.draw, away: p.away };
    }
  }
  return out;
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
  const predictionSource = results["model_predictions"];

  const liveFeed = live?.data as LiveFeed | null;
  const gameRows = mapGames
    ? mapGames(games?.data ?? null)
    : ((games?.data as GameRow[] | null) ?? []);
  const standingRows = mapStandings
    ? mapStandings(standings?.data ?? null)
    : ((standings?.data as StandingRow[] | null) ?? []);
  const predictions = useMemo(
    () => extractPredictions(predictionSource?.data ?? null),
    [predictionSource],
  );

  // Mobile answers "who plays next?" first: fixtures render above the full
  // standings table. Desktop keeps standings before fixtures (order classes
  // only reorder below md).
  return (
    <div className="flex flex-col gap-8">
      <div className="order-none">
        <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {subtitle ?? "Historical research data. Not betting advice."}
        </p>
      </div>

      <Section
        className="order-1"
        title={copy?.liveTitle ?? "Live & Recent"}
        badge={live && <StatusBadge origin={live.origin} />}
      >
        {loading && !live && !skeletonExpired ? (
          <SkeletonGrid />
        ) : liveFeed && liveFeed.events.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {liveFeed.events.map((e) => (
              <LiveScoreCard key={e.event_id} event={e} prediction={predictions[e.event_id]} />
            ))}
          </div>
        ) : (
          <EmptyMsg
            msg={
              copy?.emptyLive ??
              "No live matches right now. Scores tick here in real time while games are on."
            }
            offlineMsg={
              copy?.offlineLive ??
              "Feed offline — live scores return here on their own once it reconnects."
            }
            offline={feedOffline(live)}
          />
        )}
      </Section>

      <Section
        className="order-3 md:order-2"
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

      <Section
        className="order-2 md:order-3"
        title={copy?.gamesTitle ?? "Fixtures & Results"}
        badge={games && <StatusBadge origin={games.origin} />}
      >
        {loading && !games && !skeletonExpired ? (
          <Skeleton className="h-64 w-full" />
        ) : gameRows.length ? (
          <GamesView rows={gameRows} predictions={predictions} />
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
    </div>
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
