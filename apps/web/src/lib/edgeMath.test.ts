import { describe, expect, it } from "vitest";
import {
  calculateEdge,
  formatAmericanOdds,
  formatMoney,
  isValidEdgeInput,
} from "./edgeMath";

describe("edge math", () => {
  it("prices plus-money EV and capped half-Kelly stake", () => {
    const result = calculateEdge(150, 0.45, 1000, 2);

    expect(result.decimalOdds).toBeCloseTo(2.5);
    expect(result.impliedProbability).toBeCloseTo(0.4);
    expect(result.edgePct).toBeCloseTo(5);
    expect(result.evPerHundred).toBeCloseTo(12.5);
    expect(result.halfKellyPct).toBeCloseTo(4.1667, 3);
    expect(result.cappedStake).toBeCloseTo(20);
    expect(result.decision).toBe("positive");
  });

  it("rejects invalid prices and probabilities", () => {
    expect(isValidEdgeInput(0, 0.55, 1000, 2)).toBe(false);
    expect(isValidEdgeInput(-110, 1, 1000, 2)).toBe(false);
    expect(isValidEdgeInput(-110, 0.55, 0, 2)).toBe(false);
  });

  it("formats sportsbook prices and negative money clearly", () => {
    expect(formatAmericanOdds(115.4)).toBe("+115");
    expect(formatAmericanOdds(-181.8)).toBe("-182");
    expect(formatMoney(-3)).toBe("-$3.00");
  });
});
