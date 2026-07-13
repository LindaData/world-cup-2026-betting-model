/**
 * Plain-word model captions for match cards, shared by Today and Matches so
 * the same fixture always reads the same way.
 *
 * Handles two edge cases the raw feed data gets wrong on consumer screens:
 * - Bracket placeholders ("Loser SF1") become human labels ("Semi-final 1
 *   loser"), and instead of quoting a hard probability for teams that do not
 *   exist yet, the caption teaches when the model odds will appear.
 * - Finished matches switch to neutral past tense that keeps the probability
 *   honest: "Model leaned Argentina (51%) — Argentina won". No scorekeeping
 *   glyphs; real accuracy grading lives in Research > Model audit.
 */

export type VerdictResult = "correct" | "missed";

export interface Verdict {
  text: string;
  /** Set only for finished matches with a gradeable score. */
  result: VerdictResult | null;
}

interface VerdictProbs {
  home: number;
  draw: number;
  away: number;
}

/** True when a team name is a bracket placeholder, not a real team. */
export function isPlaceholderTeam(name: string): boolean {
  const trimmed = (name ?? "").trim();
  return (
    /^(winner|loser)\b/i.test(trimmed) ||
    // ESPN publishes trailing forms like "Semifinal 1 Winner".
    /\b(winner|loser)$/i.test(trimmed) ||
    /^tbd\b/i.test(trimmed)
  );
}

/** "Loser SF1" → "Semi-final 1 loser"; real team names pass through. */
export function friendlyTeamName(name: string): string {
  const match = (name ?? "").trim().match(/^(winner|loser)\s+(sf|qf|m)?\s*(\d+)$/i);
  if (!match) return name;
  const stageCode = (match[2] ?? "").toLowerCase();
  const stage = stageCode === "sf" ? "Semi-final" : stageCode === "qf" ? "Quarter-final" : "Match";
  return `${stage} ${match[3]} ${match[1].toLowerCase()}`;
}

/**
 * Friendly title for an all-placeholder fixture ("Third-place match",
 * "Final"), or null when at least one real team is known.
 */
export function placeholderMatchLabel(homeTeam: string, awayTeam: string): string | null {
  if (!isPlaceholderTeam(homeTeam) || !isPlaceholderTeam(awayTeam)) return null;
  // Both feed spellings: "Loser SF1" (demo/API) and "Semifinal 1 Loser" (ESPN).
  const sfLoser = (n: number) =>
    new RegExp(`^(loser\\s+sf\\s*${n}|semi-?final\\s*${n}\\s+loser)$`, "i");
  const sfWinner = (n: number) =>
    new RegExp(`^(winner\\s+sf\\s*${n}|semi-?final\\s*${n}\\s+winner)$`, "i");
  if (sfLoser(1).test(homeTeam.trim()) && sfLoser(2).test(awayTeam.trim())) {
    return "Third-place match";
  }
  if (sfWinner(1).test(homeTeam.trim()) && sfWinner(2).test(awayTeam.trim())) {
    return "Final";
  }
  return null;
}

/** True for feed statuses that mean the match has ended. */
export function isFinishedStatus(status: string | undefined | null): boolean {
  return /full.?time|final|finished|ended|^ft$/i.test(status ?? "");
}

/**
 * One caption per match card. Present tense before kickoff, teaching copy for
 * placeholder participants, neutral past tense with the outcome after full
 * time.
 */
export function matchVerdict({
  homeTeam,
  awayTeam,
  probs,
  finished = false,
  homeScore,
  awayScore,
}: {
  homeTeam: string;
  awayTeam: string;
  probs: VerdictProbs;
  finished?: boolean;
  homeScore?: string | number | null;
  awayScore?: string | number | null;
}): Verdict | null {
  const home = Math.max(probs.home || 0, 0);
  const draw = Math.max(probs.draw || 0, 0);
  const away = Math.max(probs.away || 0, 0);
  const total = home + draw + away;
  if (total <= 0) return null;

  const pct = (value: number) => Math.round((value / total) * 100);
  const pick: "home" | "away" | "draw" =
    home >= draw && home >= away ? "home" : away >= draw ? "away" : "draw";
  const pickPct = pct(pick === "home" ? home : pick === "away" ? away : draw);
  const pickTeam = pick === "home" ? homeTeam : awayTeam;

  // Placeholder participants: never quote a hard number for teams that are
  // not decided yet — teach when the model odds will appear instead.
  if (isPlaceholderTeam(homeTeam) || isPlaceholderTeam(awayTeam)) {
    return {
      text: "Teams aren't set yet — model odds appear here once both teams are decided.",
      result: null,
    };
  }

  // Finished match with a gradeable score: neutral past tense that keeps the
  // probability honest (a 41% lean that loses is not a "miss").
  const homeGoals = Number(homeScore);
  const awayGoals = Number(awayScore);
  if (finished && Number.isFinite(homeGoals) && Number.isFinite(awayGoals)) {
    const actual: "home" | "away" | "draw" =
      homeGoals > awayGoals ? "home" : awayGoals > homeGoals ? "away" : "draw";
    const result: VerdictResult = actual === pick ? "correct" : "missed";
    const subject = pick === "draw" ? "a draw" : pickTeam;
    const outcome =
      actual === "draw" ? "it ended a draw" : `${actual === "home" ? homeTeam : awayTeam} won`;
    return {
      text: `Model leaned ${subject} (${pickPct}%) — ${outcome}`,
      result,
    };
  }

  if (pick === "draw") {
    return { text: `Model thinks a draw is most likely at ${pickPct}%`, result: null };
  }
  return { text: `Model thinks ${pickTeam} wins ${pickPct}%`, result: null };
}
