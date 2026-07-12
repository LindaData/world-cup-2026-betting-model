import { americanToDecimal } from "./edgeMath";

export type WagerStatus = "open" | "win" | "loss" | "push" | "void";

export type WagerInput = {
  date: string;
  sport: string;
  selection: string;
  market: string;
  americanOdds: number;
  stake: number;
  status: WagerStatus;
  modelProbability: number | null;
  closingOdds: number | null;
  book: string;
  notes: string;
};

export type TrackedWager = WagerInput & {
  decimalOdds: number;
  impliedProbability: number;
  potentialProfit: number;
  profit: number;
  exposure: number;
  closingImpliedProbability: number | null;
  clvPct: number | null;
  modelEdgePct: number | null;
  isOpen: boolean;
  isSettled: boolean;
};

export type LedgerSummary = {
  startingBankroll: number;
  currentBankroll: number;
  totalRows: number;
  openRows: number;
  settledRows: number;
  wins: number;
  losses: number;
  pushes: number;
  voids: number;
  openExposure: number;
  openPotentialProfit: number;
  settledStake: number;
  settledProfit: number;
  roiPct: number;
  winRate: number;
  exposurePct: number;
  avgClvPct: number | null;
  avgModelEdgePct: number | null;
};

export function trackWagers(rows: WagerInput[]): TrackedWager[] {
  return rows.map((row) => {
    const decimalOdds = americanToDecimal(row.americanOdds);
    const impliedProbability = 1 / decimalOdds;
    const closingImpliedProbability = row.closingOdds ? 1 / americanToDecimal(row.closingOdds) : null;
    const status = normalizeWagerStatus(row.status);
    const isOpen = status === "open";
    const isSettled = !isOpen;
    const potentialProfit = row.stake * (decimalOdds - 1);

    return {
      ...row,
      status,
      decimalOdds,
      impliedProbability,
      potentialProfit,
      profit: profitForStatus(row.americanOdds, row.stake, status),
      exposure: isOpen ? row.stake : 0,
      closingImpliedProbability,
      clvPct: closingImpliedProbability == null ? null : (closingImpliedProbability - impliedProbability) * 100,
      modelEdgePct: row.modelProbability == null ? null : (row.modelProbability - impliedProbability) * 100,
      isOpen,
      isSettled,
    };
  });
}

export function summarizeLedger(rows: TrackedWager[], startingBankroll: number): LedgerSummary {
  const settled = rows.filter((row) => row.isSettled);
  const graded = rows.filter((row) => row.status === "win" || row.status === "loss");
  const wins = rows.filter((row) => row.status === "win").length;
  const losses = rows.filter((row) => row.status === "loss").length;
  const settledStake = settled.reduce((sum, row) => sum + row.stake, 0);
  const settledProfit = settled.reduce((sum, row) => sum + row.profit, 0);
  const openExposure = rows.reduce((sum, row) => sum + row.exposure, 0);
  const clvRows = rows.filter((row) => row.clvPct != null);
  const edgeRows = rows.filter((row) => row.modelEdgePct != null);

  return {
    startingBankroll,
    currentBankroll: startingBankroll + settledProfit,
    totalRows: rows.length,
    openRows: rows.filter((row) => row.status === "open").length,
    settledRows: settled.length,
    wins,
    losses,
    pushes: rows.filter((row) => row.status === "push").length,
    voids: rows.filter((row) => row.status === "void").length,
    openExposure,
    openPotentialProfit: rows.filter((row) => row.isOpen).reduce((sum, row) => sum + row.potentialProfit, 0),
    settledStake,
    settledProfit,
    roiPct: settledStake ? (settledProfit / settledStake) * 100 : 0,
    winRate: graded.length ? wins / graded.length : 0,
    exposurePct: startingBankroll ? (openExposure / startingBankroll) * 100 : 0,
    avgClvPct: clvRows.length ? avg(clvRows.map((row) => row.clvPct ?? 0)) : null,
    avgModelEdgePct: edgeRows.length ? avg(edgeRows.map((row) => row.modelEdgePct ?? 0)) : null,
  };
}

export function normalizeWagerStatus(value: unknown): WagerStatus {
  const text = String(value ?? "").trim().toLowerCase();
  if (["w", "win", "won", "1", "true"].includes(text)) return "win";
  if (["l", "loss", "lost", "0", "false"].includes(text)) return "loss";
  if (["p", "push", "refund"].includes(text)) return "push";
  if (["void", "cancel", "cancelled", "canceled"].includes(text)) return "void";
  return "open";
}

export function parseLedgerProbability(value: unknown): number | null {
  const text = String(value ?? "").replace("%", "").trim();
  if (!text) return null;
  const n = Number(text);
  if (!Number.isFinite(n)) return null;
  const probability = n > 1 ? n / 100 : n;
  return probability > 0 && probability < 1 ? probability : null;
}

export function parseLedgerOdds(value: unknown): number {
  return Number(String(value ?? "").replace("+", "").trim());
}

export function isValidWagerInput(row: WagerInput) {
  return (
    row.selection.trim().length > 0 &&
    Number.isFinite(row.americanOdds) &&
    row.americanOdds !== 0 &&
    Number.isFinite(row.stake) &&
    row.stake >= 0
  );
}

function profitForStatus(americanOdds: number, stake: number, status: WagerStatus) {
  if (status === "win") return stake * (americanToDecimal(americanOdds) - 1);
  if (status === "loss") return -stake;
  return 0;
}

function avg(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}
