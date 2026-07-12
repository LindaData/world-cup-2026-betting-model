import { describe, expect, it } from "vitest";
import {
  auditPredictions,
  calibrationBins,
  normalizeResult,
  parseProbability,
  summarizeAudit,
  type AuditInput,
} from "./modelAudit";

const rows: AuditInput[] = [
  {
    date: "2026-06-01",
    sport: "MLB",
    selection: "Test dog",
    market: "Moneyline",
    americanOdds: 150,
    modelProbability: 0.45,
    closingOdds: 130,
    stake: 20,
    result: "win",
    notes: "",
  },
  {
    date: "2026-06-02",
    sport: "NBA",
    selection: "Test favorite",
    market: "Spread",
    americanOdds: -110,
    modelProbability: 0.55,
    closingOdds: -125,
    stake: 20,
    result: "loss",
    notes: "",
  },
  {
    date: "2026-06-03",
    sport: "NHL",
    selection: "Push test",
    market: "Total",
    americanOdds: -105,
    modelProbability: 0.52,
    closingOdds: null,
    stake: 10,
    result: "push",
    notes: "",
  },
];

describe("model audit", () => {
  it("summarizes settled prediction economics and calibration", () => {
    const audited = auditPredictions(rows);
    const summary = summarizeAudit(audited);

    expect(summary.totalRows).toBe(3);
    expect(summary.settledRows).toBe(3);
    expect(summary.gradedRows).toBe(2);
    expect(summary.profit).toBeCloseTo(10);
    expect(summary.roiPct).toBeCloseTo(20);
    expect(summary.brierScore).toBeCloseTo(0.3025);
    expect(summary.hitRate).toBeCloseTo(0.5);
    expect(summary.expectedProfit).toBeGreaterThan(3);
  });

  it("groups predictions into probability calibration bins", () => {
    const bins = calibrationBins(auditPredictions(rows));
    const dogBin = bins.find((bin) => bin.label === "45-50%");
    const favoriteBin = bins.find((bin) => bin.label === "55-60%");

    expect(dogBin?.rows).toBe(1);
    expect(dogBin?.realizedWinRate).toBe(1);
    expect(favoriteBin?.rows).toBe(1);
    expect(favoriteBin?.realizedWinRate).toBe(0);
  });

  it("normalizes common result and probability inputs", () => {
    expect(normalizeResult("won")).toBe("win");
    expect(normalizeResult("L")).toBe("loss");
    expect(normalizeResult("void")).toBe("push");
    expect(parseProbability("54.5%")).toBeCloseTo(0.545);
    expect(parseProbability("0.545")).toBeCloseTo(0.545);
  });
});
