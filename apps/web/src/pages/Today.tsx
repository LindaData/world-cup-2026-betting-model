import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import Papa from "papaparse";
import { ArrowRight, PenLine } from "lucide-react";
import { useData } from "@/context/DataContext";
import { LiveScoreCard } from "@/components/LiveScoreCard";
import { ProbabilityBar } from "@/components/ProbabilityBar";
import { StatusChip } from "@/components/StatusBadge";
import { Skeleton } from "@/components/ui/skeleton";
import { useSkeletonTimeout } from "@/hooks/use-skeleton-timeout";
import { BETTING_DESK_ENABLED } from "@/lib/flags";
import { formatMoney } from "@/lib/edgeMath";
import {
  SAMPLE_LEDGER_CSV,
  isSampleLedgerCsv,
  isValidWagerInput,
  normalizeWagerStatus,
  parseLedgerOdds,
  parseLedgerProbability,
  summarizeLedger,
  trackWagers,
  type LedgerSummary,
  type WagerInput,
} from "@/lib/betLedger";
import {
  friendlyTeamName,
  isFinishedStatus,
  isPlaceholderTeam,
  matchVerdict,
  placeholderMatchLabel,
} from "@/lib/matchVerdict";
import type { LiveFeed, Manifest } from "@/types";

/** Must match the Bankroll page's storage key so both read the same ledger. */
const LEDGER_STORAGE_KEY = "gsp:bankroll-ledger:v1";

const LIVE_FEED_KEYS = ["football_live", "nba_live", "mlb_live"] as const;

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

interface PredictionEntry {
  home_team?: string;
  away_team?: string;
  home: number;
  draw: number;
  away: number;
}

interface PredictionsFeed {
  predictions?: Record<string, PredictionEntry>;
  model_version?: string;
  generated_at_utc?: string;
}

export default function Today() {
  const { results, loading } = useData();

  // Coarse clock for the countdown; ticks once a minute (information update,
  // not decoration, so no reduced-motion concern).
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(id);
  }, []);

  const fixtures = useMemo(
    () => asFixtures(results.football_fixtures?.data),
    [results.football_fixtures],
  );
  const predictionsFeed = (results.model_predictions?.data as PredictionsFeed | null) ?? null;
  const predictions = predictionsFeed?.predictions ?? {};
  const manifest = (results.manifest?.data as Manifest | null) ?? null;

  const liveEvents = useMemo(
    () =>
      LIVE_FEED_KEYS.flatMap((key) =>
        (((results[key]?.data as LiveFeed | null)?.events) ?? []).filter(
          (event) => event.state === "in",
        ),
      ),
    [results],
  );

  const todayKey = localDateKey(now);
  const todaysMatches = useMemo(
    () => fixtures.filter((f) => localDateKey(new Date(f.date_utc)) === todayKey),
    [fixtures, todayKey],
  );
  const upcoming = useMemo(
    () =>
      fixtures
        .filter((f) => new Date(f.date_utc).getTime() > now.getTime())
        .sort((a, b) => new Date(a.date_utc).getTime() - new Date(b.date_utc).getTime()),
    [fixtures, now],
  );
  const nextMatch = upcoming[0] ?? null;

  const ledger = useMemo(() => readLedgerSummary(todayKey), [todayKey]);

  // Skeletons are time-boxed (~3s): if feeds are still unresolved after that,
  // the page renders its taught empty states instead of placeholders forever.
  const skeletonExpired = useSkeletonTimeout();
  const booting = loading && Object.keys(results).length === 0 && !skeletonExpired;
  if (booting) {
    return (
      <div className="space-y-6" aria-busy="true">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  // One DEMO rule everywhere: a single page-level chip when everything on the
  // page is demo data, card/section-level chips only otherwise — never both
  // in the same viewport.
  const fixturesDemo = results.football_fixtures?.origin === "demo";
  const ledgerDemo = !BETTING_DESK_ENABLED || !ledger || ledger.isSample;
  const pageDemo = fixturesDemo && ledgerDemo;

  return (
    <div className="space-y-6 pb-36 lg:pb-4">
      <header>
        <p className="label-mono">{formatHeaderDate(now)}</p>
        <div className="mt-0.5 flex items-center gap-2">
          <h1 className="text-xl font-bold">Today</h1>
          {pageDemo && <StatusChip tone="muted" label="Demo" />}
        </div>
      </header>

      {BETTING_DESK_ENABLED ? (
        <BankrollHero ledger={ledger} showDemoChip={!pageDemo} />
      ) : (
        <PublicHero
          nextMatch={nextMatch}
          now={now}
          predictionsFeed={predictionsFeed}
          manifest={manifest}
        />
      )}

      <Section label="Live now">
        {liveEvents.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {liveEvents.map((event) => (
              <LiveScoreCard key={event.event_id} event={event} />
            ))}
          </div>
        ) : (
          <EmptyState
            title="Nothing is live right now."
            body="The moment a match kicks off, its score lands here and updates through full time."
          />
        )}
      </Section>

      <Section
        label="Today's matches"
        chip={fixturesDemo && !pageDemo ? <StatusChip tone="muted" label="Demo" /> : null}
      >
        {todaysMatches.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2">
            {todaysMatches.map((fixture) => (
              <MatchCard
                key={fixture.game_id}
                fixture={fixture}
                prediction={predictions[fixture.game_id] ?? null}
              />
            ))}
          </div>
        ) : upcoming.length > 0 ? (
          <div className="space-y-2.5">
            <EmptyState
              title="No kickoffs today."
              body="Here's what's next on the calendar — match cards move up here on game day."
            />
            {/* The upcoming cards get their own label so the section header
                never contradicts its content (none of these are today). */}
            <h3 className="label-mono pt-1">Up next</h3>
            <div className="grid gap-3 sm:grid-cols-2">
              {upcoming.slice(0, 4).map((fixture) => (
                <MatchCard
                  key={fixture.game_id}
                  fixture={fixture}
                  prediction={predictions[fixture.game_id] ?? null}
                  showDate
                />
              ))}
            </div>
          </div>
        ) : (
          <EmptyState
            title="No matches scheduled yet."
            body="Once the fixture feed publishes, each match day shows team matchups, kickoff times, and a home/draw/away probability bar for what the model thinks of every result."
            link={{ to: "/status", label: "Check feed status" }}
          />
        )}
      </Section>

      {/* The primary slot does real work instead of duplicating the Portfolio
          tab: it deep-links straight into the ledger editor. In-flow on
          desktop, bottom-anchored above the tab bar on mobile. */}
      {BETTING_DESK_ENABLED ? (
        <>
          <div className="hidden pt-1 lg:block">
            <PrimaryAction to="/bankroll?log=1" label="Log today's bet" icon="pen" />
          </div>
          <div className="fixed inset-x-0 bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-20 border-t border-border bg-background/95 p-3 backdrop-blur lg:hidden">
            <PrimaryAction to="/bankroll?log=1" label="Log today's bet" icon="pen" fullWidth />
          </div>
        </>
      ) : (
        <div className="pt-1">
          <PrimaryAction to="/matches" label="See all matches" icon="arrow" />
        </div>
      )}
    </div>
  );
}

function PrimaryAction({
  to,
  label,
  icon,
  fullWidth = false,
}: {
  to: string;
  label: string;
  icon: "pen" | "arrow";
  fullWidth?: boolean;
}) {
  const Icon = icon === "pen" ? PenLine : ArrowRight;
  return (
    <Link
      to={to}
      className={`flex h-11 w-full items-center justify-center gap-2 rounded-md bg-primary px-6 font-semibold text-primary-foreground transition-opacity hover:opacity-90 ${
        fullWidth ? "" : "sm:w-auto sm:max-w-xs"
      }`}
    >
      {label}
      <Icon className="h-4 w-4" aria-hidden="true" />
    </Link>
  );
}

/* ------------------------------ hero blocks ------------------------------ */

function BankrollHero({
  ledger,
  showDemoChip = true,
}: {
  ledger: { summary: LedgerSummary; todayProfit: number; isSample: boolean } | null;
  /** False when a page-level Demo chip already scopes this card. */
  showDemoChip?: boolean;
}) {
  if (!ledger) {
    // Teaching empty state that previews the real thing: a properly styled
    // $0.00 hero, never a bare dash that reads as a rendering failure.
    return (
      <section className="surface-card p-5">
        <p className="label-mono">Bankroll</p>
        <p className="num-hero mt-1 text-muted-foreground">{formatMoney(0)}</p>
        <p className="mt-1.5 text-xs text-muted-foreground">
          Log your first bet in Portfolio and your bankroll — with today's profit or loss — shows
          up here.
        </p>
      </section>
    );
  }

  const { summary, todayProfit, isSample } = ledger;
  const deltaClass =
    todayProfit > 0 ? "text-gain" : todayProfit < 0 ? "text-loss" : "text-muted-foreground";
  const deltaText =
    todayProfit === 0
      ? "No bets settled today"
      : `${todayProfit > 0 ? "+" : ""}${formatMoney(todayProfit)} today`;

  return (
    <section className="surface-card p-5">
      <div className="flex items-center gap-2">
        <p className="label-mono">Bankroll</p>
        {isSample && showDemoChip && <StatusChip tone="muted" label="Demo" />}
      </div>
      <p className="num-hero mt-1">{formatMoney(summary.currentBankroll)}</p>
      <p className={`mt-1 text-sm font-semibold tabular-nums ${deltaClass}`}>{deltaText}</p>
      {summary.openRows > 0 && (
        <p className="mt-1 text-xs text-muted-foreground tabular-nums">
          {summary.openRows} open bet{summary.openRows === 1 ? "" : "s"} ·{" "}
          {formatMoney(summary.openExposure)} at risk
        </p>
      )}
    </section>
  );
}

function PublicHero({
  nextMatch,
  now,
  predictionsFeed,
  manifest,
}: {
  nextMatch: FixtureRow | null;
  now: Date;
  predictionsFeed: PredictionsFeed | null;
  manifest: Manifest | null;
}) {
  const predictionCount = Object.keys(predictionsFeed?.predictions ?? {}).length;
  const publishedGames = Object.values(manifest?.sports ?? {}).reduce(
    (sum, sport) => sum + (sport.published_games || 0),
    0,
  );
  const recordCaption =
    predictionCount > 0
      ? `${predictionCount} prediction${predictionCount === 1 ? "" : "s"} live${
          predictionsFeed?.model_version ? ` · ${predictionsFeed.model_version}` : ""
        } — wins and losses appear once matches are graded.`
      : publishedGames > 0
        ? `Tracking ${publishedGames} published matches — the model's win-loss record appears after the first graded matchday.`
        : "The model's win-loss record appears here after the first graded matchday.";

  return (
    <section className="surface-card grid gap-5 p-5 sm:grid-cols-2">
      <div>
        <p className="label-mono">Next match</p>
        {nextMatch ? (
          <>
            <p className="num-hero mt-1">{formatCountdown(new Date(nextMatch.date_utc), now)}</p>
            <p className="mt-1 text-sm text-foreground">
              {nextMatch.home_team} vs {nextMatch.away_team}
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {formatKickoff(new Date(nextMatch.date_utc), true)}
              {nextMatch.venue ? ` · ${nextMatch.venue}` : ""}
            </p>
          </>
        ) : (
          <>
            <p className="num-hero mt-1 text-muted-foreground">—</p>
            <p className="mt-1.5 text-xs text-muted-foreground">
              When fixtures publish, a countdown to the next kickoff lives here.
            </p>
          </>
        )}
      </div>
      <div className="border-t border-border pt-4 sm:border-l sm:border-t-0 sm:pl-5 sm:pt-0">
        <p className="label-mono">Model record</p>
        <p className="num-hero mt-1 text-muted-foreground">—</p>
        <p className="mt-1.5 text-xs text-muted-foreground">{recordCaption}</p>
      </div>
    </section>
  );
}

/* ------------------------------ match cards ------------------------------ */

function MatchCard({
  fixture,
  prediction,
  showDate = false,
}: {
  fixture: FixtureRow;
  prediction: PredictionEntry | null;
  showDate?: boolean;
}) {
  const kickoff = new Date(fixture.date_utc);
  const finished = isFinished(fixture);
  // Bracket placeholders ("Loser SF1") get a human title and friendly names
  // so a TBD third-place match never reads as broken data.
  const bracketLabel = placeholderMatchLabel(fixture.home_team, fixture.away_team);
  const homeName = friendlyTeamName(fixture.home_team);
  const awayName = friendlyTeamName(fixture.away_team);
  // Teams-TBD fixtures never render a hard probability bar — a concrete 44%
  // for teams that don't exist yet is false precision, not honesty.
  const teamsTbd =
    isPlaceholderTeam(fixture.home_team) || isPlaceholderTeam(fixture.away_team);
  const meta = [
    finished ? "Full time" : formatKickoff(kickoff, showDate),
    bracketLabel ? "Teams decided after the semi-finals" : null,
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
    <div className="surface-card p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-semibold text-card-foreground">
            {bracketLabel ?? (
              <>
                {homeName} <span className="font-normal text-muted-foreground">vs</span>{" "}
                {awayName}
              </>
            )}
          </p>
          <p className="mt-0.5 truncate text-xs text-muted-foreground">{meta}</p>
        </div>
        {finished && (
          <p className="shrink-0 text-2xl font-extrabold tabular-nums text-card-foreground">
            {fixture.home_score}–{fixture.away_score}
          </p>
        )}
      </div>
      {teamsTbd ? (
        <p className="mt-3 text-xs text-muted-foreground">
          {verdict?.text ??
            "Teams aren't set yet — model odds appear here once both teams are decided."}
        </p>
      ) : prediction ? (
        <div className="mt-3 space-y-1.5">
          <ProbabilityBar
            probs={{ home: prediction.home, draw: prediction.draw, away: prediction.away }}
            labels={{ home: homeName, away: awayName }}
          />
          {verdict && <p className="text-xs text-muted-foreground">{verdict.text}</p>}
        </div>
      ) : (
        <p className="mt-3 text-xs text-muted-foreground">
          Model prediction lands before kickoff.
        </p>
      )}
    </div>
  );
}

/* ------------------------------ scaffolding ------------------------------ */

function Section({
  label,
  chip,
  children,
}: {
  label: string;
  chip?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="space-y-2.5">
      <div className="flex items-center gap-2">
        <h2 className="label-mono">{label}</h2>
        {chip}
      </div>
      {children}
    </section>
  );
}

function EmptyState({
  title,
  body,
  link,
}: {
  title: string;
  body: string;
  link?: { to: string; label: string };
}) {
  return (
    <div className="surface-card p-5">
      <p className="text-sm font-medium text-card-foreground">{title}</p>
      <p className="mt-1 text-xs text-muted-foreground">{body}</p>
      {link && (
        <Link
          to={link.to}
          className="mt-2 inline-block text-xs font-medium text-muted-foreground underline underline-offset-4 hover:text-foreground"
        >
          {link.label}
        </Link>
      )}
    </div>
  );
}

/* -------------------------------- helpers -------------------------------- */

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

function isFinished(fixture: FixtureRow): boolean {
  return isFinishedStatus(fixture.status);
}

function localDateKey(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

function formatHeaderDate(d: Date): string {
  return new Intl.DateTimeFormat(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
  }).format(d);
}

function formatKickoff(d: Date, withDay: boolean): string {
  return new Intl.DateTimeFormat(
    undefined,
    withDay
      ? { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }
      : { hour: "numeric", minute: "2-digit" },
  ).format(d);
}

function formatCountdown(target: Date, now: Date): string {
  const ms = target.getTime() - now.getTime();
  if (ms <= 0) return "Kicking off";
  const mins = Math.floor(ms / 60_000);
  const days = Math.floor(mins / 1440);
  const hours = Math.floor((mins % 1440) / 60);
  const minutes = mins % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${Math.max(minutes, 1)}m`;
}

/**
 * Reads the bet ledger the Bankroll page persists to localStorage and folds
 * it into a summary plus today's settled profit.
 *
 * First run tells the same story as the Bankroll page: when nothing has been
 * saved yet, this falls back to the same bundled sample ledger Bankroll
 * previews (chipped "Demo"), so Today and Portfolio never contradict each
 * other. Returns null only when the user has explicitly cleared their ledger.
 */
function readLedgerSummary(
  todayKey: string,
): { summary: LedgerSummary; todayProfit: number; isSample: boolean } | null {
  if (typeof window === "undefined") return null;
  let stored: { startingBankroll?: unknown; csvText?: unknown } | null;
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(LEDGER_STORAGE_KEY);
    stored = JSON.parse(raw ?? "null");
  } catch {
    stored = null;
  }
  if (raw == null || !stored || typeof stored.csvText !== "string") {
    // Nothing saved: preview the same demo ledger the Bankroll page shows.
    stored = { startingBankroll: "1000", csvText: SAMPLE_LEDGER_CSV };
  }
  if (typeof stored.csvText !== "string" || !stored.csvText.trim()) return null;

  const parsed = Papa.parse<Record<string, string>>(stored.csvText.trim(), {
    header: true,
    skipEmptyLines: true,
    transformHeader: (header) => header.trim().toLowerCase(),
  });
  const rows = parsed.data.map(csvRecordToWager).filter(isValidWagerInput);
  const wagers = trackWagers(rows);
  const startingBankroll = Number(stored.startingBankroll);
  const summary = summarizeLedger(wagers, Number.isFinite(startingBankroll) ? startingBankroll : 0);
  const todayProfit = wagers
    .filter((wager) => wager.isSettled && wager.date === todayKey)
    .reduce((sum, wager) => sum + wager.profit, 0);
  return { summary, todayProfit, isSample: isSampleLedgerCsv(stored.csvText) };
}

/** Same column aliases the Bankroll page accepts, so both read one ledger. */
function csvRecordToWager(record: Record<string, string>): WagerInput {
  const pick = (...keys: string[]) => {
    for (const key of keys) {
      const value = record[key];
      if (value != null && String(value).trim()) return String(value).trim();
    }
    return "";
  };
  const closingRaw = pick("closing_odds", "closing_price", "close", "close_odds");
  const closingOdds = closingRaw ? parseLedgerOdds(closingRaw) : NaN;
  return {
    date: pick("date", "event_date", "settled_at"),
    sport: pick("sport", "league"),
    selection: pick("selection", "pick", "team", "name"),
    market: pick("market", "bet_type", "type") || "Moneyline",
    americanOdds: parseLedgerOdds(pick("american_odds", "odds", "price", "line")),
    stake: Number(pick("stake", "risk", "amount") || "0"),
    status: normalizeWagerStatus(pick("status", "result", "outcome", "grade")),
    modelProbability: parseLedgerProbability(
      pick("model_probability", "model_probability_pct", "probability", "prob", "win_probability"),
    ),
    closingOdds: Number.isFinite(closingOdds) && closingOdds !== 0 ? closingOdds : null,
    book: pick("book", "sportsbook", "bookmaker"),
    notes: pick("notes", "note", "reason"),
  };
}
