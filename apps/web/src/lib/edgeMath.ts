export type EdgeDecision = "positive" | "thin" | "negative";

export type EdgeMath = {
  decimalOdds: number;
  impliedProbability: number;
  fairAmericanOdds: number;
  edgePct: number;
  evPerDollar: number;
  evPerHundred: number;
  kellyPct: number;
  halfKellyPct: number;
  cappedStake: number;
  cappedStakePct: number;
  decision: EdgeDecision;
};

export function calculateEdge(americanOdds: number, modelProbability: number, bankroll: number, capPct: number): EdgeMath {
  const decimalOdds = americanToDecimal(americanOdds);
  const impliedProbability = 1 / decimalOdds;
  const b = decimalOdds - 1;
  const q = 1 - modelProbability;
  const evPerDollar = modelProbability * b - q;
  const kellyRaw = b > 0 ? (b * modelProbability - q) / b : 0;
  const kellyPct = Math.max(0, kellyRaw) * 100;
  const halfKellyPct = kellyPct / 2;
  const cappedStakePct = Math.min(halfKellyPct, Math.max(0, capPct));
  const edgePct = (modelProbability - impliedProbability) * 100;

  return {
    decimalOdds,
    impliedProbability,
    fairAmericanOdds: probabilityToAmerican(modelProbability),
    edgePct,
    evPerDollar,
    evPerHundred: evPerDollar * 100,
    kellyPct,
    halfKellyPct,
    cappedStake: bankroll * (cappedStakePct / 100),
    cappedStakePct,
    decision: evPerDollar > 0.025 ? "positive" : evPerDollar > 0 ? "thin" : "negative",
  };
}

export function americanToDecimal(odds: number) {
  if (odds > 0) return 1 + odds / 100;
  return 1 + 100 / Math.abs(odds);
}

export function probabilityToAmerican(probability: number) {
  if (probability <= 0 || probability >= 1) return 0;
  if (probability >= 0.5) return -(100 * probability) / (1 - probability);
  return (100 * (1 - probability)) / probability;
}

export function isValidEdgeInput(americanOdds: number, modelProbability: number, bankroll: number, capPct: number) {
  return (
    Number.isFinite(americanOdds) &&
    americanOdds !== 0 &&
    Number.isFinite(modelProbability) &&
    modelProbability > 0 &&
    modelProbability < 1 &&
    Number.isFinite(bankroll) &&
    bankroll > 0 &&
    Number.isFinite(capPct) &&
    capPct >= 0
  );
}

export function decisionLabel(decision: EdgeDecision) {
  return decision === "positive" ? "Positive EV" : decision === "thin" ? "Thin edge" : "No edge";
}

export function formatPercent(value: number, digits = 2) {
  return `${(value * 100).toFixed(digits)}%`;
}

export function formatMoney(value: number, digits = 2) {
  const sign = value < 0 ? "-" : "";
  return `${sign}$${Math.abs(value).toFixed(digits)}`;
}

export function formatAmericanOdds(odds: number) {
  const rounded = Math.round(odds);
  return rounded > 0 ? `+${rounded}` : String(rounded);
}
