import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import Papa from "papaparse";
import { AlertTriangle, Download, Plus, Trash2, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { downloadCsv } from "@/lib/download";
import {
  calculateEdge,
  decisionLabel,
  formatAmericanOdds,
  formatMoney,
  formatPercent,
  isValidEdgeInput,
  type EdgeMath,
} from "@/lib/edgeMath";

const STORAGE_KEY = "gsp:portfolio-lab:v1";

type PortfolioRow = {
  id: string;
  selection: string;
  sport: string;
  market: string;
  americanOdds: string;
  modelProbability: string;
  notes: string;
};

type PricedRow = PortfolioRow & {
  oddsValue: number;
  probabilityValue: number;
  math: EdgeMath | null;
};

type StoredPortfolio = {
  rows: PortfolioRow[];
  bankroll: string;
  capPct: string;
  csvText: string;
};

const SAMPLE_CSV = `selection,sport,market,american_odds,model_probability,notes
Dodgers ML,MLB,Moneyline,-118,56.5,Starter edge
Celtics spread,NBA,Spread,-105,53.0,Power rating lean
Inter Miami over,Soccer,Total,+115,48.0,Tempo projection`;

const SAMPLE_ROWS: PortfolioRow[] = [
  createRow("Dodgers ML", "MLB", "Moneyline", "-118", "56.5", "Starter edge"),
  createRow("Celtics spread", "NBA", "Spread", "-105", "53", "Power rating lean"),
  createRow("Inter Miami over", "Soccer", "Total", "+115", "48", "Tempo projection"),
  createRow("Rangers puck line", "NHL", "Puck line", "+140", "43", "Plus-price test"),
];

export default function Portfolio() {
  const stored = useMemo(readStoredPortfolio, []);
  const [rows, setRows] = useState<PortfolioRow[]>(stored.rows);
  const [bankroll, setBankroll] = useState(stored.bankroll);
  const [capPct, setCapPct] = useState(stored.capPct);
  const [csvText, setCsvText] = useState(stored.csvText);
  const [importError, setImportError] = useState<string | null>(null);
  const [showPositiveOnly, setShowPositiveOnly] = useState(true);

  useEffect(() => {
    try {
      const payload: StoredPortfolio = { rows, bankroll, capPct, csvText };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch {
      /* ignore */
    }
  }, [bankroll, capPct, csvText, rows]);

  const parsedBankroll = Number(bankroll);
  const parsedCapPct = Number(capPct);

  const pricedRows = useMemo(
    () => rows.map((row) => priceRow(row, parsedBankroll, parsedCapPct)),
    [parsedBankroll, parsedCapPct, rows],
  );

  const rankedRows = useMemo(() => {
    const valid = pricedRows.filter((row) => row.math);
    const filtered = showPositiveOnly ? valid.filter((row) => (row.math?.evPerDollar ?? 0) > 0) : valid;
    return [...filtered].sort(
      (a, b) =>
        (b.math?.evPerDollar ?? -Infinity) - (a.math?.evPerDollar ?? -Infinity) ||
        (b.math?.edgePct ?? -Infinity) - (a.math?.edgePct ?? -Infinity),
    );
  }, [pricedRows, showPositiveOnly]);

  const summary = useMemo(() => summarize(pricedRows), [pricedRows]);

  const updateRow = (id: string, patch: Partial<PortfolioRow>) => {
    setRows((items) => items.map((item) => (item.id === id ? { ...item, ...patch } : item)));
  };

  const addRow = () => {
    setRows((items) => [...items, createRow("", "", "Moneyline", "-110", "52.5", "")]);
  };

  const removeRow = (id: string) => {
    setRows((items) => (items.length > 1 ? items.filter((item) => item.id !== id) : items));
  };

  const loadSample = () => {
    setRows(SAMPLE_ROWS.map((row) => ({ ...row, id: newId() })));
    setCsvText(SAMPLE_CSV);
    setImportError(null);
  };

  const importCsv = () => {
    const parsed = Papa.parse<Record<string, string>>(csvText.trim(), {
      header: true,
      skipEmptyLines: true,
      transformHeader: (header) => header.trim().toLowerCase(),
    });

    if (parsed.errors.length) {
      setImportError(parsed.errors[0]?.message ?? "CSV could not be parsed.");
      return;
    }

    const imported = parsed.data
      .map(csvRecordToRow)
      .filter((row) => row.selection || row.sport || row.market || row.americanOdds || row.modelProbability);

    if (!imported.length) {
      setImportError("No rows found.");
      return;
    }

    setRows(imported);
    setImportError(null);
  };

  const exportPortfolio = () => {
    downloadCsv(
      "game_stat_pulse_portfolio.csv",
      pricedRows.map((row) => ({
        selection: row.selection,
        sport: row.sport,
        market: row.market,
        american_odds: Number.isFinite(row.oddsValue) ? formatAmericanOdds(row.oddsValue) : row.americanOdds,
        model_probability_pct: Number.isFinite(row.probabilityValue) ? formatPercent(row.probabilityValue) : row.modelProbability,
        implied_probability_pct: row.math ? formatPercent(row.math.impliedProbability) : "",
        fair_american_odds: row.math ? formatAmericanOdds(row.math.fairAmericanOdds) : "",
        edge_pct: row.math ? `${row.math.edgePct.toFixed(2)}%` : "",
        ev_per_100: row.math ? formatMoney(row.math.evPerHundred) : "",
        half_kelly_pct: row.math ? `${row.math.halfKellyPct.toFixed(2)}%` : "",
        capped_stake: row.math ? formatMoney(row.math.cappedStake) : "",
        portfolio_ev: row.math ? formatMoney(row.math.cappedStake * row.math.evPerDollar) : "",
        decision: row.math ? decisionLabel(row.math.decision) : "Invalid",
        notes: row.notes,
      })),
    );
  };

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-28 lg:pb-0">
      <header className="surface-card p-4 sm:p-6">
        <div className="label-mono">Portfolio · Expected profit</div>
        <div className={`num-hero mt-2 ${summary.portfolioEv > 0 ? "text-gain" : summary.portfolioEv < 0 ? "text-loss" : ""}`}>
          {formatMoney(summary.portfolioEv)}
        </div>
        <div className="mt-1 text-sm text-muted-foreground">
          {summary.positiveRows} of {summary.validRows} priced selections have positive expected value.
        </div>

        <div className="mt-5 grid grid-cols-2 gap-3 border-t border-border pt-4 sm:grid-cols-4">
          <Stat label="Selections" value={String(summary.totalRows)} />
          <Stat label="Positive EV" value={String(summary.positiveRows)} tone={summary.positiveRows ? "gain" : undefined} />
          <Stat label="Exposure" value={formatMoney(summary.exposure)} />
          <Stat label="Best EV / $100" value={formatMoney(summary.bestEvPerHundred)} tone={summary.bestEvPerHundred > 0 ? "gain" : undefined} />
        </div>

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <Button className="min-h-11 flex-1 sm:flex-none sm:px-8" onClick={exportPortfolio} disabled={!pricedRows.length}>
            <Download className="h-4 w-4" /> Export card
          </Button>
          <Link to="/edge" className="text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
            Price a single line
          </Link>
        </div>
      </header>

      <section className="space-y-3">
        <div className="flex items-center justify-between gap-3 px-1">
          <div className="label-mono">Best priced opportunities</div>
          <button
            type="button"
            onClick={() => setShowPositiveOnly((value) => !value)}
            className={`min-h-11 rounded-md border px-3 text-xs font-semibold ${
              showPositiveOnly ? "border-gain/40 bg-gain/10 text-gain" : "border-border bg-card text-muted-foreground"
            }`}
          >
            {showPositiveOnly ? "Positive EV only" : "All valid rows"}
          </button>
        </div>
        {rankedRows.length ? (
          <div className="grid gap-3 md:grid-cols-2">
            {rankedRows.slice(0, 8).map((row) => (
              <OpportunityCard key={row.id} row={row} />
            ))}
          </div>
        ) : (
          <div className="surface-card p-4 text-sm text-muted-foreground">
            {showPositiveOnly
              ? "Nothing prices positive right now. Toggle to all valid rows, or adjust odds and model probabilities below."
              : "No rows are ready to price yet. Add a selection with odds and a model probability and it will rank here."}
          </div>
        )}
      </section>

      <section className="surface-card overflow-hidden">
        <div className="flex flex-col gap-3 border-b border-border px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="label-mono">Selections</div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={addRow}>
              <Plus className="h-4 w-4" /> Add row
            </Button>
            <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={loadSample}>
              Load sample
            </Button>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[980px] text-sm">
            <thead className="text-left">
              <tr>
                <Th>Selection</Th>
                <Th>Sport</Th>
                <Th>Market</Th>
                <Th>Odds</Th>
                <Th>Model %</Th>
                <Th>EV / $100</Th>
                <Th>Stake</Th>
                <Th>Notes</Th>
                <Th>Remove</Th>
              </tr>
            </thead>
            <tbody>
              {pricedRows.map((row) => (
                <tr key={row.id} className="border-t border-border align-top">
                  <td className="p-2">
                    <Input value={row.selection} onChange={(event) => updateRow(row.id, { selection: event.target.value })} className="min-h-10" />
                  </td>
                  <td className="p-2">
                    <Input value={row.sport} onChange={(event) => updateRow(row.id, { sport: event.target.value })} className="min-h-10" />
                  </td>
                  <td className="p-2">
                    <Input value={row.market} onChange={(event) => updateRow(row.id, { market: event.target.value })} className="min-h-10" />
                  </td>
                  <td className="p-2">
                    <Input inputMode="numeric" value={row.americanOdds} onChange={(event) => updateRow(row.id, { americanOdds: event.target.value })} className="min-h-10 font-semibold tabular-nums" />
                  </td>
                  <td className="p-2">
                    <Input inputMode="decimal" value={row.modelProbability} onChange={(event) => updateRow(row.id, { modelProbability: event.target.value })} className="min-h-10 font-semibold tabular-nums" />
                  </td>
                  <td className={row.math ? (row.math.evPerHundred > 0 ? "p-3 font-bold tabular-nums text-gain" : "p-3 font-bold tabular-nums text-loss") : "p-3 text-muted-foreground"}>
                    {row.math ? formatMoney(row.math.evPerHundred) : "Invalid"}
                  </td>
                  <td className="p-3 font-bold tabular-nums">{row.math ? formatMoney(row.math.cappedStake) : "—"}</td>
                  <td className="p-2">
                    <Input value={row.notes} onChange={(event) => updateRow(row.id, { notes: event.target.value })} className="min-h-10" />
                  </td>
                  <td className="p-2">
                    <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={() => removeRow(row.id)} aria-label={`Remove ${row.selection || "selection"}`}>
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="grid gap-3 md:grid-cols-2">
        <div className="surface-card p-4 sm:p-6">
          <div className="label-mono">Sizing</div>
          <div className="mt-4 grid gap-4">
            <Field label="Bankroll $" value={bankroll} onChange={setBankroll} inputMode="decimal" />
            <Field label="Max stake cap %" value={capPct} onChange={setCapPct} inputMode="decimal" />
          </div>
          <div className="mt-5 space-y-2 border-t border-border pt-4 text-xs leading-relaxed text-muted-foreground">
            <p>Rows are ranked from your probabilities and entered odds; invalid prices are excluded from totals.</p>
            <p>Expected profit uses the capped stake size, not full Kelly. Correlated rows still need manual review.</p>
          </div>
        </div>

        <div className="surface-card p-4 sm:p-6">
          <div className="label-mono">CSV import</div>
          <Textarea
            value={csvText}
            onChange={(event) => setCsvText(event.target.value)}
            className="mt-3 min-h-40 font-mono text-xs"
            placeholder="selection,sport,market,american_odds,model_probability,notes"
          />
          {importError && (
            <div className="mt-3 flex gap-2 rounded-md border border-border bg-background p-3 text-sm text-muted-foreground">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {importError}
            </div>
          )}
          <div className="mt-3 flex flex-wrap gap-2">
            <Button variant="outline" className="min-h-11" onClick={importCsv}>
              <Upload className="h-4 w-4" /> Import rows
            </Button>
            <Button variant="ghost" className="min-h-11 text-muted-foreground" onClick={loadSample}>
              Load sample
            </Button>
          </div>
        </div>
      </section>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="label-mono p-3 font-medium">{children}</th>;
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "gain" | "loss" }) {
  const color = tone === "gain" ? "text-gain" : tone === "loss" ? "text-loss" : "text-foreground";
  return (
    <div className="min-w-0">
      <div className="label-mono truncate">{label}</div>
      <div className={`mt-0.5 truncate text-lg font-bold tabular-nums ${color}`}>{value}</div>
    </div>
  );
}

function OpportunityCard({ row }: { row: PricedRow }) {
  if (!row.math) return null;
  const evTone = row.math.evPerHundred > 0 ? "text-gain" : "text-loss";
  return (
    <article className="surface-card p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="label-mono">{row.sport || "Sport"}</div>
          <h3 className="truncate text-base font-bold">{row.selection || "Untitled selection"}</h3>
          <p className="mt-0.5 truncate text-xs text-muted-foreground">{row.market || "Market"}</p>
        </div>
        <span className="rounded-md border border-border bg-background px-2 py-1 text-sm font-bold tabular-nums">
          {formatAmericanOdds(row.oddsValue)}
        </span>
      </div>
      <div className="mt-3 flex items-end justify-between gap-3 border-t border-border pt-3">
        <div>
          <div className="label-mono">EV / $100</div>
          <div className={`text-2xl font-extrabold tabular-nums ${evTone}`}>{formatMoney(row.math.evPerHundred)}</div>
        </div>
        <div className="text-right">
          <div className="label-mono">Stake</div>
          <div className="text-2xl font-extrabold tabular-nums">{formatMoney(row.math.cappedStake)}</div>
        </div>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3">
        <Stat label="Model" value={formatPercent(row.probabilityValue)} />
        <Stat label="Implied" value={formatPercent(row.math.impliedProbability)} />
        <Stat label="Edge" value={`${row.math.edgePct.toFixed(1)}%`} tone={row.math.edgePct > 0 ? "gain" : undefined} />
      </div>
      <div className={`label-mono mt-3 ${row.math.evPerHundred > 0 ? "text-gain" : ""}`}>{decisionLabel(row.math.decision)}</div>
    </article>
  );
}

function Field({
  label,
  value,
  onChange,
  inputMode,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  inputMode?: "numeric" | "decimal";
}) {
  return (
    <label className="block">
      <span className="label-mono">{label}</span>
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        inputMode={inputMode}
        className="mt-1 min-h-11 text-lg font-bold tabular-nums"
      />
    </label>
  );
}

function priceRow(row: PortfolioRow, bankroll: number, capPct: number): PricedRow {
  const oddsValue = Number(String(row.americanOdds).replace("+", ""));
  const probabilityValue = parseProbability(row.modelProbability);
  const math = isValidEdgeInput(oddsValue, probabilityValue, bankroll, capPct)
    ? calculateEdge(oddsValue, probabilityValue, bankroll, capPct)
    : null;

  return { ...row, oddsValue, probabilityValue, math };
}

function summarize(rows: PricedRow[]) {
  const valid = rows.filter((row) => row.math);
  const positive = valid.filter((row) => (row.math?.evPerDollar ?? 0) > 0);
  const exposure = positive.reduce((sum, row) => sum + (row.math?.cappedStake ?? 0), 0);
  const portfolioEv = positive.reduce((sum, row) => sum + (row.math ? row.math.cappedStake * row.math.evPerDollar : 0), 0);
  const bestEvPerHundred = valid.reduce((best, row) => Math.max(best, row.math?.evPerHundred ?? -Infinity), 0);

  return {
    totalRows: rows.length,
    validRows: valid.length,
    positiveRows: positive.length,
    exposure,
    portfolioEv,
    bestEvPerHundred,
  };
}

function csvRecordToRow(record: Record<string, string>): PortfolioRow {
  const selection = pick(record, ["selection", "pick", "team", "name"]);
  const sport = pick(record, ["sport", "league"]);
  const market = pick(record, ["market", "bet_type", "type"]) || "Moneyline";
  const odds = pick(record, ["american_odds", "odds", "price", "line"]) || "-110";
  const probability = normalizeProbabilityInput(pick(record, ["model_probability", "model_probability_pct", "probability", "prob", "win_probability"]));
  const notes = pick(record, ["notes", "note", "reason"]);
  return createRow(selection, sport, market, odds, probability, notes);
}

function pick(record: Record<string, string>, keys: string[]) {
  for (const key of keys) {
    const value = record[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return "";
}

function parseProbability(value: string) {
  const cleaned = String(value).replace("%", "").trim();
  const n = Number(cleaned);
  if (!Number.isFinite(n)) return NaN;
  return n > 1 ? n / 100 : n;
}

function normalizeProbabilityInput(value: string) {
  const probability = parseProbability(value);
  if (!Number.isFinite(probability)) return "";
  return String(Math.round(probability * 10000) / 100);
}

function readStoredPortfolio(): StoredPortfolio {
  if (typeof window === "undefined") return defaultPortfolio();
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "");
    if (Array.isArray(parsed?.rows) && parsed.rows.length) {
      return {
        rows: parsed.rows,
        bankroll: String(parsed.bankroll ?? "1000"),
        capPct: String(parsed.capPct ?? "2"),
        csvText: String(parsed.csvText ?? SAMPLE_CSV),
      };
    }
  } catch {
    /* ignore */
  }
  return defaultPortfolio();
}

function defaultPortfolio(): StoredPortfolio {
  return {
    rows: SAMPLE_ROWS.map((row) => ({ ...row, id: newId() })),
    bankroll: "1000",
    capPct: "2",
    csvText: SAMPLE_CSV,
  };
}

function createRow(
  selection = "",
  sport = "",
  market = "Moneyline",
  americanOdds = "-110",
  modelProbability = "52.5",
  notes = "",
): PortfolioRow {
  return {
    id: newId(),
    selection,
    sport,
    market,
    americanOdds,
    modelProbability,
    notes,
  };
}

function newId() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}
