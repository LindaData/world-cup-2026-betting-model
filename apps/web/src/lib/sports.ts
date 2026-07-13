/**
 * Canonical sport display names. One source of truth so the Matches switcher,
 * Portfolio breakdowns, and any future surface all call a sport the same
 * thing ("Soccer", never "Football" on one tab and "Soccer" on another).
 */
export const SPORT_LABELS = {
  football: "Soccer",
  nba: "NBA",
  mlb: "MLB",
} as const;

export type SportKey = keyof typeof SPORT_LABELS;
