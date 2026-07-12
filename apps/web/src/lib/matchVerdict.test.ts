import { describe, expect, it } from "vitest";
import {
  friendlyTeamName,
  isFinishedStatus,
  isPlaceholderTeam,
  matchVerdict,
  placeholderMatchLabel,
} from "./matchVerdict";

describe("placeholder team names", () => {
  it("maps bracket codes to friendly labels", () => {
    expect(friendlyTeamName("Loser SF1")).toBe("Semi-final 1 loser");
    expect(friendlyTeamName("Winner SF2")).toBe("Semi-final 2 winner");
    expect(friendlyTeamName("France")).toBe("France");
  });

  it("detects placeholders and titles all-placeholder fixtures", () => {
    expect(isPlaceholderTeam("Loser SF1")).toBe(true);
    expect(isPlaceholderTeam("Argentina")).toBe(false);
    expect(placeholderMatchLabel("Loser SF1", "Loser SF2")).toBe("Third-place match");
    expect(placeholderMatchLabel("Winner SF1", "Winner SF2")).toBe("Final");
    expect(placeholderMatchLabel("France", "Loser SF2")).toBeNull();
  });
});

describe("matchVerdict", () => {
  const probs = { home: 0.51, draw: 0.27, away: 0.22 };

  it("uses present tense before kickoff", () => {
    expect(
      matchVerdict({ homeTeam: "Argentina", awayTeam: "Netherlands", probs }),
    ).toEqual({ text: "Model thinks Argentina wins 51%", result: null });
  });

  it("teaches instead of quoting a number for placeholder participants", () => {
    const expected = {
      text: "Teams aren't set yet — model odds appear here once both teams are decided.",
      result: null,
    };
    expect(
      matchVerdict({
        homeTeam: "Loser SF1",
        awayTeam: "Loser SF2",
        probs: { home: 0.4, draw: 0.24, away: 0.36 },
      }),
    ).toEqual(expected);
    // Mixed fixtures (one real team) are still TBD fixtures.
    expect(
      matchVerdict({
        homeTeam: "France",
        awayTeam: "Winner SF2",
        probs: { home: 0.4, draw: 0.24, away: 0.36 },
      }),
    ).toEqual(expected);
  });

  it("uses neutral outcome phrasing after full time", () => {
    expect(
      matchVerdict({
        homeTeam: "Argentina",
        awayTeam: "Netherlands",
        probs,
        finished: true,
        homeScore: 1,
        awayScore: 0,
      }),
    ).toEqual({ text: "Model leaned Argentina (51%) — Argentina won", result: "correct" });

    expect(
      matchVerdict({
        homeTeam: "Argentina",
        awayTeam: "Netherlands",
        probs,
        finished: true,
        homeScore: "0",
        awayScore: "2",
      }),
    ).toEqual({ text: "Model leaned Argentina (51%) — Netherlands won", result: "missed" });

    expect(
      matchVerdict({
        homeTeam: "Argentina",
        awayTeam: "Netherlands",
        probs,
        finished: true,
        homeScore: 1,
        awayScore: 1,
      }),
    ).toEqual({ text: "Model leaned Argentina (51%) — it ended a draw", result: "missed" });
  });

  it("returns null when probabilities are empty", () => {
    expect(
      matchVerdict({ homeTeam: "A", awayTeam: "B", probs: { home: 0, draw: 0, away: 0 } }),
    ).toBeNull();
  });

  it("recognises finished statuses", () => {
    expect(isFinishedStatus("Full Time")).toBe(true);
    expect(isFinishedStatus("Final")).toBe(true);
    expect(isFinishedStatus("Scheduled")).toBe(false);
  });
});
