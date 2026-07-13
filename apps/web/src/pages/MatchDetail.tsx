import { useMemo } from "react";
import { Link, useParams } from "react-router-dom";
import { ChevronLeft } from "lucide-react";
import { useData } from "@/context/DataContext";
import { ProbabilityBar } from "@/components/ProbabilityBar";
import { PreliminaryChip } from "@/components/PreliminaryChip";
import { StatusChip } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import { useSkeletonTimeout } from "@/hooks/use-skeleton-timeout";
import { getPredictions, type ModelPrediction } from "@/lib/modelFeeds";
import {
  friendlyTeamName,
  isFinishedStatus,
  isPlaceholderTeam,
  matchVerdict,
  placeholderMatchLabel,
} from "@/lib/matchVerdict";

/**
 * Match detail — what tapping any match card opens. One question per state:
 * upcoming asks "who does the model think wins?" (hero probability), played
 * asks "what happened?" (hero score + neutral verdict), TBD teaches when the
 * numbers arrive. No tabs, no jargon, one screen.
 */

interface FixtureRow {
  game_id: string;
  date_utc: string;
  status: string;
  league?: string;
  home_team: string;
  away_team: string;
  home_score?: string | number | null;
  away_score?: string | number | null;
  venue?: string;
}

export default function MatchDetail() {
  const { id } = useParams<{ id: string }>();
  const { results, loading } = useData();

  const fixtures = useMemo(
    () => asFixtures(results.football_fixtures?.data),
    [results.football_fixtures],
  );
  const fixture = useMemo(
    () => fixtures.find((f) => f.game_id === id) ?? null,
    [fixtures, id],
  );
  const { map, preliminary } = getPredictions(results);
  const prediction = (id ? map[id] : undefined) ?? null;
  const fixturesDemo = results.football_fixtures?.origin === "demo";

  // Same time-boxed skeleton rule as Today: brief placeholders while feeds
  // resolve, then real states — never skeletons forever.
  const skeletonExpired = useSkeletonTimeout();
  if (!fixture && loading && !skeletonExpired) {
    return (
      <div className="mx-auto max-w-xl space-y-4" aria-busy="true">
        <Skeleton className="h-6 w-28" />
        <Skeleton className="h-20 w-full" />
        <Skeleton className="h-44 w-full" />
      </div>
    );
  }

  if (!fixture) {
    return (
      <div className="mx-auto max-w-xl space-y-4">
        <BackLink />
        <div className="surface-card p-6">
          <p className="text-sm font-medium text-card-foreground">
            We couldn't find that match.
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            The link may be out of date. Every World Cup fixture lives on the Matches tab.
          </p>
          <Link
            to="/matches"
            className="mt-3 inline-flex min-h-11 items-center rounded-md bg-primary px-4 text-sm font-semibold text-primary-foreground transition-opacity hover:opacity-90"
          >
            Browse all matches
          </Link>
        </div>
      </div>
    );
  }

  const finished = isFinishedStatus(fixture.status);
  // Bracket placeholders ("Winner SF1") get a human title and friendly names
  // so the final never reads as broken data.
  const bracketLabel = placeholderMatchLabel(fixture.home_team, fixture.away_team);
  const homeName = friendlyTeamName(fixture.home_team);
  const awayName = friendlyTeamName(fixture.away_team);
  const teamsTbd =
    isPlaceholderTeam(fixture.home_team) || isPlaceholderTeam(fixture.away_team);

  const meta = [
    finished ? "Full time" : null,
    formatKickoff(fixture.date_utc),
    fixture.venue,
    fixture.league,
  ]
    .filter(Boolean)
    .join(" · ");

  const verdict = prediction
    ? matchVerdict({
        homeTeam: fixture.home_team,
        awayTeam: fixture.away_team,
        probs: prediction,
        finished,
        homeScore: fixture.home_score,
        awayScore: fixture.away_score,
      })
    : null;

  return (
    <div className="mx-auto max-w-xl space-y-4">
      <BackLink />

      <header>
        {bracketLabel && <p className="label-mono">{bracketLabel}</p>}
        <h1 className="text-2xl font-bold tracking-tight text-foreground md:text-3xl">
          {homeName} <span className="font-normal text-muted-foreground">vs</span> {awayName}
        </h1>
        <div className="mt-1.5 flex flex-wrap items-center gap-2">
          <p className="text-xs text-muted-foreground">{meta}</p>
          {fixturesDemo && <StatusChip tone="muted" label="Demo" />}
        </div>
      </header>

      {finished ? (
        <FinalScoreCard
          fixture={fixture}
          homeName={homeName}
          awayName={awayName}
          prediction={prediction}
          preliminary={preliminary}
          verdictText={verdict?.text ?? null}
        />
      ) : teamsTbd ? (
        <TeamsTbdCard />
      ) : (
        <ModelCallCard
          homeName={homeName}
          awayName={awayName}
          prediction={prediction}
          preliminary={preliminary}
        />
      )}
    </div>
  );
}

function BackLink() {
  return (
    <Link
      to="/matches"
      className="inline-flex min-h-11 items-center gap-1 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
    >
      <ChevronLeft className="h-4 w-4" aria-hidden="true" />
      Matches
    </Link>
  );
}

/* ------------------------------- state cards ------------------------------ */

/**
 * Played match: the score is the hero. The winner's number stays in the
 * foreground, the other side goes quiet — red is never used for a scoreline.
 * The model's pre-match call sits beneath as an honest footnote.
 */
function FinalScoreCard({
  fixture,
  homeName,
  awayName,
  prediction,
  preliminary,
  verdictText,
}: {
  fixture: FixtureRow;
  homeName: string;
  awayName: string;
  prediction: ModelPrediction | null;
  preliminary: boolean;
  verdictText: string | null;
}) {
  const homeGoals = Number(fixture.home_score);
  const awayGoals = Number(fixture.away_score);
  const gradeable = Number.isFinite(homeGoals) && Number.isFinite(awayGoals);
  const dim = (side: "home" | "away") =>
    gradeable && homeGoals !== awayGoals && (side === "home" ? homeGoals < awayGoals : awayGoals < homeGoals);

  return (
    <section className="surface-card p-5">
      <p className="label-mono">Full time</p>
      <div className="mt-2 grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1">
        <span className={teamNameClass(dim("home"))}>{homeName}</span>
        <span className={scoreClass(dim("home"))}>{scoreText(fixture.home_score)}</span>
        <span className={teamNameClass(dim("away"))}>{awayName}</span>
        <span className={scoreClass(dim("away"))}>{scoreText(fixture.away_score)}</span>
      </div>

      {prediction && (
        <div className="mt-4 border-t border-border pt-4">
          <div className="flex flex-wrap items-center gap-2">
            <p className="label-mono">Model's pre-match call</p>
            {preliminary && <PreliminaryChip />}
          </div>
          <ProbabilityBar
            className="mt-2"
            probs={prediction}
            labels={{ home: homeName, away: awayName }}
          />
          {verdictText && <p className="mt-2 text-sm text-muted-foreground">{verdictText}</p>}
        </div>
      )}
    </section>
  );
}

/** Upcoming match: the model's number is the hero of the screen. */
function ModelCallCard({
  homeName,
  awayName,
  prediction,
  preliminary,
}: {
  homeName: string;
  awayName: string;
  prediction: ModelPrediction | null;
  preliminary: boolean;
}) {
  if (!prediction) {
    return (
      <section className="surface-card p-5">
        <p className="label-mono">Model's call</p>
        <p className="num-hero mt-1 text-muted-foreground">—</p>
        <p className="mt-1.5 text-sm text-muted-foreground">
          The model's win probabilities for this match land before kickoff.
        </p>
      </section>
    );
  }

  const lead = leadingCall(prediction, homeName, awayName);
  return (
    <section className="surface-card p-5">
      <div className="flex flex-wrap items-center gap-2">
        <p className="label-mono">Model's call</p>
        {preliminary && <PreliminaryChip />}
      </div>
      <p className={`num-hero mt-1 ${lead.className}`}>
        {lead.name} {lead.pct}%
      </p>
      <ProbabilityBar
        className="mt-4"
        probs={prediction}
        labels={{ home: homeName, away: awayName }}
      />
      <p className="mt-3 text-sm text-muted-foreground">
        Our model simulates this match thousands of times — this is how often each side wins.
      </p>
    </section>
  );
}

/** Bracket fixture whose participants don't exist yet: teach, never guess. */
function TeamsTbdCard() {
  return (
    <section className="surface-card p-5">
      <p className="label-mono">Model's call</p>
      <p className="mt-1 text-lg font-semibold text-card-foreground">
        Teams are set after the semi-finals
      </p>
      <p className="mt-1.5 text-sm text-muted-foreground">
        Once both teams are decided, the model's win probabilities for this match appear here.
      </p>
    </section>
  );
}

/* -------------------------------- helpers -------------------------------- */

function teamNameClass(dimmed: boolean): string {
  return `min-w-0 truncate text-lg font-semibold ${
    dimmed ? "text-muted-foreground" : "text-card-foreground"
  }`;
}

function scoreClass(dimmed: boolean): string {
  return `num-hero ${dimmed ? "text-muted-foreground" : "text-card-foreground"}`;
}

function scoreText(value: string | number | null | undefined): string {
  const text = value == null ? "" : String(value);
  return text === "" ? "–" : text;
}

/**
 * The model's headline: whichever outcome leads, as one big plain-words
 * number ("France 44%"). Hero color follows the bar — green home, blue away,
 * neutral draw — so the number and its segment read as the same thing.
 */
function leadingCall(
  prediction: ModelPrediction,
  homeName: string,
  awayName: string,
): { name: string; pct: number; className: string } {
  const home = Math.max(prediction.home || 0, 0);
  const draw = Math.max(prediction.draw || 0, 0);
  const away = Math.max(prediction.away || 0, 0);
  const total = home + draw + away;
  const pct = (v: number) => (total > 0 ? Math.round((v / total) * 100) : 0);
  if (home >= draw && home >= away) {
    return { name: homeName, pct: pct(home), className: "text-gain" };
  }
  if (away >= draw) {
    return { name: awayName, pct: pct(away), className: "text-away" };
  }
  return { name: "Draw", pct: pct(draw), className: "text-card-foreground" };
}

function asFixtures(data: unknown): FixtureRow[] {
  if (!Array.isArray(data)) return [];
  return data.filter(
    (row): row is FixtureRow =>
      !!row &&
      typeof row === "object" &&
      typeof (row as FixtureRow).game_id === "string" &&
      typeof (row as FixtureRow).date_utc === "string" &&
      typeof (row as FixtureRow).home_team === "string" &&
      typeof (row as FixtureRow).away_team === "string",
  );
}

function formatKickoff(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(d);
}
