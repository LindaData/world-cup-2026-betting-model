import { useData } from "@/context/DataContext";
import { LiveScoreCard } from "@/components/LiveScoreCard";
import { GamesView } from "@/components/GamesView";
import { StandingsView } from "@/components/StandingsView";
import { StatusBadge } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import type { GameRow, LiveFeed, StandingRow } from "@/types";

interface SportPageProps {
  title: string;
  liveKey: string;
  gamesKey: string;
  standingsKey: string;
  subtitle?: string;
  mapGames?: (data: unknown) => GameRow[];
  mapStandings?: (data: unknown) => StandingRow[];
}

export function SportPage({
  title,
  liveKey,
  gamesKey,
  standingsKey,
  subtitle,
  mapGames,
  mapStandings,
}: SportPageProps) {
  const { results, loading } = useData();
  const live = results[liveKey];
  const games = results[gamesKey];
  const standings = results[standingsKey];

  const liveFeed = live?.data as LiveFeed | null;
  const gameRows = mapGames
    ? mapGames(games?.data ?? null)
    : ((games?.data as GameRow[] | null) ?? []);
  const standingRows = mapStandings
    ? mapStandings(standings?.data ?? null)
    : ((standings?.data as StandingRow[] | null) ?? []);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold">{title}</h1>
        <p className="text-sm text-muted-foreground mt-1">
          {subtitle ?? "Historical research data. Not betting advice."}
        </p>
      </div>

      <Section title="Live & Recent" badge={live && <StatusBadge origin={live.origin} />}>
        {loading && !live ? (
          <SkeletonGrid />
        ) : liveFeed && liveFeed.events.length > 0 ? (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {liveFeed.events.map((e) => (
              <LiveScoreCard key={e.event_id} event={e} />
            ))}
          </div>
        ) : (
          <EmptyMsg msg="No live games right now." />
        )}
      </Section>

      <Section
        title="Standings"
        badge={standings && <StatusBadge origin={standings.origin} />}
      >
        {loading && !standings ? (
          <Skeleton className="h-40 w-full" />
        ) : standingRows.length ? (
          <StandingsView rows={standingRows} />
        ) : (
          <EmptyMsg msg="Standings unavailable." />
        )}
      </Section>

      <Section
        title="Historical Games"
        badge={games && <StatusBadge origin={games.origin} />}
      >
        {loading && !games ? (
          <Skeleton className="h-64 w-full" />
        ) : gameRows.length ? (
          <GamesView rows={gameRows} />
        ) : (
          <EmptyMsg msg="No games available." />
        )}
      </Section>
    </div>
  );
}

function Section({
  title,
  badge,
  children,
}: {
  title: string;
  badge?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div className="flex items-center gap-3">
        <h2 className="text-lg font-semibold">{title}</h2>
        {badge}
      </div>
      {children}
    </section>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
      {[0, 1, 2].map((i) => (
        <Skeleton key={i} className="h-32 w-full" />
      ))}
    </div>
  );
}

function EmptyMsg({ msg }: { msg: string }) {
  return (
    <div className="surface-card p-6 text-center text-sm text-muted-foreground">{msg}</div>
  );
}
