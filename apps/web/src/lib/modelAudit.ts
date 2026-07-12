import { americanToDecimal } from "./edgeMath";

export type AuditResult = "win" | "loss" | "push" | "open";

export type AuditInput = {
  date: string;
  sport: string;
  selection: string;
  market: string;
  americanOdds: number;
  modelProbability: number;
  closingOdds: number | null;
  stake: number;
  result: AuditResult;
  notes: string;
};

export type AuditedPrediction = AuditInput & {
  impliedProbability: number;
  closingImpliedProbability: number | null;
  edgePct: number;
  clvPct: number | null;
  evPerDollar: number;
  expectedProfit: number;
  profit: number;
  outcome: 0 | 1 | null;
  isSettled: boolean;
  isGraded: boolean;
};

export type AuditSummary = {
  totalRows: number;
  settledRows: number;
  gradedRows: number;
  wins: number;
  losses: number;
  pushes: number;
  openRows: number;
  hitRate: number;
  totalStake: number;
  profit: number;
  roiPct: number;
  expectedProfit: number;
  avgEdgePct: number;
  avgClvPct: number | null;
  avgModelProbability: number;
  avgImpliedProbability: number;
  brierScore: number | null;
  logLoss: number | null;
};

export type CalibrationBin = {
  label: string;
  min: number;
  max: number;
  rows: number;
  avgModelProbability: number;
  realizedWinRate: number | null;
  brierScore: number | null;
  profit: number;
  roiPct: number;
};

const BINS = [
  { label: "<45%", min: 0, max: 0.45 },
  { label: "45-50%", min: 0.45, max: 0.5 },
  { label: "50-55%", min: 0.5, max: 0.55 },
  { label: "55-60%", min: 0.55, max: 0.6 },
  { label: "60%+", min: 0.6, max: 1.01 },
];

export function auditPredictions(rows: AuditInput[]): AuditedPrediction[] {
  return rows.map((row) => {
    const decimalOdds = americanToDecimal(row.americanOdds);
    const impliedProbability = 1 / decimalOdds;
    const closingImpliedProbability = row.closingOdds ? 1 / americanToDecimal(row.closingOdds) : null;
    const b = decimalOdds - 1;
    const evPerDollar = row.modelProbability * b - (1 - row.modelProbability);
    const result = normalizeResult(row.result);
    const outcome = result === "win" ? 1 : result === "loss" ? 0 : null;
    const isSettled = result !== "open";
    const isGraded = outcome != null;

    return {
      ...row,
      result,
      impliedProbability,
      closingImpliedProbability,
      edgePct: (row.modelProbability - impliedProbability) * 100,
      clvPct: closingImpliedProbability == null ? null : (closingImpliedProbability - impliedProbability) * 100,
      evPerDollar,
      expectedProfit: evPerDollar * row.stake,
      profit: profitForResult(row.americanOdds, row.stake, result),
      outcome,
      isSettled,
      isGraded,
    };
  });
}

export function summarizeAudit(rows: AuditedPrediction[]): AuditSummary {
  const settled = rows.filter((row) => row.isSettled);
  const graded = rows.filter((row) => row.isGraded);
  const wins = rows.filter((row) => row.result === "win").length;
  const losses = rows.filter((row) => row.result === "loss").length;
  const pushes = rows.filter((row) => row.result === "push").length;
  const totalStake = settled.reduce((sum, row) => sum + row.stake, 0);
  const profit = settled.reduce((sum, row) => sum + row.profit, 0);
  const clvRows = rows.filter((row) => row.clvPct != null);

  return {
    totalRows: rows.length,
    settledRows: settled.length,
    gradedRows: graded.length,
    wins,
    losses,
    pushes,
    openRows: rows.filter((row) => row.result === "open").length,
    hitRate: graded.length ? wins / graded.length : 0,
    totalStake,
    profit,
    roiPct: totalStake ? (profit / totalStake) * 100 : 0,
    expectedProfit: rows.reduce((sum, row) => sum + row.expectedProfit, 0),
    avgEdgePct: avg(rows.map((row) => row.edgePct)),
    avgClvPct: clvRows.length ? avg(clvRows.map((row) => row.clvPct ?? 0)) : null,
    avgModelProbability: avg(rows.map((row) => row.modelProbability)),
    avgImpliedProbability: avg(rows.map((row) => row.impliedProbability)),
    brierScore: graded.length ? avg(graded.map((row) => (row.modelProbability - Number(row.outcome)) ** 2)) : null,
    logLoss: graded.length ? avg(graded.map((row) => logLoss(row.modelProbability, Number(row.outcome)))) : null,
  };
}

export function calibrationBins(rows: AuditedPrediction[]): CalibrationBin[] {
  return BINS.map((bin) => {
    const matched = rows.filter((row) => row.modelProbability >= bin.min && row.modelProbability < bin.max);
    const graded = matched.filter((row) => row.isGraded);
    const stake = matched.filter((row) => row.isSettled).reduce((sum, row) => sum + row.stake, 0);
    const profit = matched.reduce((sum, row) => sum + row.profit, 0);

    return {
      ...bin,
      rows: matched.length,
      avgModelProbability: avg(matched.map((row) => row.modelProbability)),
      realizedWinRate: graded.length ? avg(graded.map((row) => Number(row.outcome))) : null,
      brierScore: graded.length ? avg(graded.map((row) => (row.modelProbability - Number(row.outcome)) ** 2)) : null,
      profit,
      roiPct: stake ? (profit / stake) * 100 : 0,
    };
  });
}

export function normalizeResult(value: unknown): AuditResult {
  const text = String(value ?? "").trim().toLowerCase();
  if (["w", "win", "won", "1", "true"].includes(text)) return "win";
  if (["l", "loss", "lost", "0", "false"].includes(text)) return "loss";
  if (["p", "push", "void", "refund"].includes(text)) return "push";
  return "open";
}

export function parseProbability(value: unknown): number {
  const cleaned = String(value ?? "").replace("%", "").trim();
  const n = Number(cleaned);
  if (!Number.isFinite(n)) return NaN;
  return n > 1 ? n / 100 : n;
}

export function parseAmericanOdds(value: unknown): number {
  return Number(String(value ?? "").replace("+", "").trim());
}

export function isValidAuditInput(row: AuditInput) {
  return (
    row.selection.trim().length > 0 &&
    Number.isFinite(row.americanOdds) &&
    row.americanOdds !== 0 &&
    Number.isFinite(row.modelProbability) &&
    row.modelProbability > 0 &&
    row.modelProbability < 1 &&
    Number.isFinite(row.stake) &&
    row.stake >= 0
  );
}

function profitForResult(americanOdds: number, stake: number, result: AuditResult) {
  if (result === "win") return stake * (americanToDecimal(americanOdds) - 1);
  if (result === "loss") return -stake;
  return 0;
}

function logLoss(probability: number, outcome: number) {
  const p = Math.min(0.999999, Math.max(0.000001, probability));
  return -(outcome * Math.log(p) + (1 - outcome) * Math.log(1 - p));
}

function avg(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}
