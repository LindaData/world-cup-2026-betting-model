import { describe, expect, it } from "vitest";
import {
  normalizeWagerStatus,
  parseLedgerOdds,
  parseLedgerProbability,
  summarizeLedger,
  trackWagers,
  type WagerInput,
} from "./betLedger";

const rows: WagerInput[] = [
  {
    date: "2026-06-01",
    sport: "MLB",
    selection: "Test dog",
    market: "Moneyline",
    americanOdds: 150,
    stake: 20,
    status: "open",
    modelProbability: 0.45,
    closingOdds: 130,
    book: "Example",
    notes: "",
  },
  {
    date: "2026-06-02",
    sport: "NBA",
    selection: "Test favorite",
    market: "Spread",
    americanOdds: -110,
    stake: 20,
    status: "win",
    modelProbability: 0.55,
    closingOdds: -125,
    book: "Example",
    notes: "",
  },
  {
    date: "2026-06-03",
    sport: "NHL",
    selection: "Loss test",
    market: "Total",
    americanOdds: -105,
    stake: 10,
    status: "loss",
    modelProbability: null,
    closingOdds: null,
    book: "Example",
    notes: "",
  },
];

describe("bet ledger", () => {
  it("summarizes open exposure and settled bankroll performance", () => {
    const tracked = trackWagers(rows);
    const summary = summarizeLedger(tracked, 1000);

    expect(summary.openRows).toBe(1);
    expect(summary.openExposure).toBe(20);
    expect(summary.openPotentialProfit).toBe(30);
    expect(summary.settledProfit).toBeCloseTo(8.1818, 4);
    expect(summary.currentBankroll).toBeCloseTo(1008.1818, 4);
    expect(summary.roiPct).toBeCloseTo(27.2727, 4);
    expect(summary.winRate).toBeCloseTo(0.5);
  });

  it("tracks model edge and closing-line movement", () => {
    const tracked = trackWagers(rows);

    expect(tracked[0].modelEdgePct).toBeCloseTo(5);
    expect(tracked[0].clvPct).toBeGreaterThan(3);
  });

  it("normalizes common wager inputs", () => {
    expect(normalizeWagerStatus("won")).toBe("win");
    expect(normalizeWagerStatus("cancelled")).toBe("void");
    expect(normalizeWagerStatus("pending")).toBe("open");
    expect(parseLedgerProbability("54.5%")).toBeCloseTo(0.545);
    expect(parseLedgerProbability("0.545")).toBeCloseTo(0.545);
    expect(parseLedgerOdds("+150")).toBe(150);
  });
});
