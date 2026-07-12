import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import Papa from "papaparse";
import {
  AlertTriangle,
  Calculator,
  ClipboardList,
  Download,
  LineChart,
  Plus,
  ShieldAlert,
  Target,
  Trash2,
  Upload,
} from "lucide-react";
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
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="surface-card sportsbook-glow overflow-hidden">
        <div className="grid gap-4 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_390px]">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-primary/35 bg-primary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-primary">
              <ClipboardList className="h-3.5 w-3.5" />
              Portfolio Lab
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl font-black leading-tight">
                Compare a batch of scenarios by edge, EV, and capped exposure.
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
                Batch price your model probabilities against market odds, then export the ranked scenarios for review.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={exportPortfolio} disabled={!pricedRows.length}>
                <Download className="h-4 w-4" /> Export card
              </Button>
              <Button variant="outline" className="border-secondary/45 text-secondary hover:bg-secondary/10" asChild>
                <Link to="/edge">
                  <Calculator className="h-4 w-4" /> Single edge
                </Link>
              </Button>
            </div>
          </div>

          <aside className="market-panel bg-black/25 p-4">
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Portfolio edge</div>
                <div className={summary.positiveRows ? "mt-1 text-2xl font-black text-primary" : "mt-1 text-2xl font-black text-secondary"}>
                  {summary.positiveRows} Positive
                </div>
              </div>
              <LineChart className="h-9 w-9 text-primary" />
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <MetricCell label="Valid lines" value={`${summary.validRows}/${summary.totalRows}`} />
              <MetricCell label="Exposure" value={formatMoney(summary.exposure)} tone="amber" />
              <MetricCell label="Card EV" value={formatMoney(summary.portfolioEv)} tone={summary.portfolioEv >= 0 ? "green" : "red"} />
              <MetricCell label="Best EV / $100" value={formatMoney(summary.bestEvPerHundred)} tone={summary.bestEvPerHundred >= 0 ? "green" : "red"} />
            </div>
          </aside>
        </div>
      </header>

      <section className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Selections" value={summary.totalRows} icon={ClipboardList} />
        <Metric label="Positive EV" value={summary.positiveRows} icon={Target} />
        <Metric label="Exposure" value={formatMoney(summary.exposure)} icon={ShieldAlert} tone="amber" />
        <Metric label="Expected profit" value={formatMoney(summary.portfolioEv)} icon={LineChart} tone={summary.portfolioEv >= 0 ? "green" : "red"} />
      </section>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Ranked card</div>
              <h2 className="mt-1 text-lg font-black">Best priced opportunities</h2>
            </div>
            <div className="grid gap-3 p-4 md:grid-cols-2">
              {rankedRows.slice(0, 8).map((row) => (
                <OpportunityCard key={row.id} row={row} />
              ))}
              {!rankedRows.length && (
                <div className="rounded-lg border border-white/10 bg-black/20 p-4 text-sm text-muted-foreground">
                  {showPositiveOnly ? "No valid positive-EV rows match the current filter." : "No valid rows are ready to price."}
                </div>
              )}
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="flex flex-col gap-3 border-b border-white/10 bg-white/[0.035] px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Model inputs</div>
                <h2 className="mt-1 text-lg font-black">Editable card</h2>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={addRow}>
                  <Plus className="h-4 w-4" /> Add
                </Button>
                <Button size="sm" variant="outline" onClick={loadSample}>
                  <Target className="h-4 w-4" /> Sample
                </Button>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[980px] text-sm">
                <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="p-3">Selection</th>
                    <th className="p-3">Sport</th>
                    <th className="p-3">Market</th>
                    <th className="p-3">Odds</th>
                    <th className="p-3">Model %</th>
                    <th className="p-3">EV / $100</th>
                    <th className="p-3">Stake</th>
                    <th className="p-3">Notes</th>
                    <th className="p-3">Remove</th>
                  </tr>
                </thead>
                <tbody>
                  {pricedRows.map((row) => (
                    <tr key={row.id} className="border-t border-white/5 align-top">
                      <td className="p-2">
                        <Input value={row.selection} onChange={(event) => updateRow(row.id, { selection: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className="p-2">
                        <Input value={row.sport} onChange={(event) => updateRow(row.id, { sport: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className="p-2">
                        <Input value={row.market} onChange={(event) => updateRow(row.id, { market: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className="p-2">
                        <Input inputMode="numeric" value={row.americanOdds} onChange={(event) => updateRow(row.id, { americanOdds: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className="p-2">
                        <Input inputMode="decimal" value={row.modelProbability} onChange={(event) => updateRow(row.id, { modelProbability: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className={row.math && row.math.evPerHundred > 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>
                        {row.math ? formatMoney(row.math.evPerHundred) : "Invalid"}
                      </td>
                      <td className="p-3 font-black text-secondary">{row.math ? formatMoney(row.math.cappedStake) : "-"}</td>
                      <td className="p-2">
                        <Input value={row.notes} onChange={(event) => updateRow(row.id, { notes: event.target.value })} className="min-h-10 bg-black/25" />
                      </td>
                      <td className="p-2">
                        <Button variant="outline" size="sm" onClick={() => removeRow(row.id)} aria-label={`Remove ${row.selection || "selection"}`}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <aside className="min-w-0 space-y-4">
          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Sizing controls</div>
            <h2 className="mt-1 text-lg font-black">Bankroll and cap</h2>
            <div className="mt-4 grid gap-3">
              <Field label="Bankroll $" value={bankroll} onChange={setBankroll} inputMode="decimal" />
              <Field label="Max stake cap %" value={capPct} onChange={setCapPct} inputMode="decimal" />
              <button
                type="button"
                onClick={() => setShowPositiveOnly((value) => !value)}
                className={`min-h-11 rounded-md border px-3 text-left text-sm font-semibold ${
                  showPositiveOnly
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-white/10 bg-black/20 text-foreground/75 hover:bg-white/[0.05]"
                }`}
              >
                {showPositiveOnly ? "Showing positive EV only" : "Showing all valid rows"}
              </button>
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">CSV import</div>
            <h2 className="mt-1 text-lg font-black">Paste model card</h2>
            <Textarea
              value={csvText}
              onChange={(event) => setCsvText(event.target.value)}
              className="mt-4 min-h-48 bg-black/25 font-mono text-xs"
              placeholder="selection,sport,market,american_odds,model_probability,notes"
            />
            {importError && (
              <div className="mt-3 flex gap-2 rounded-lg border border-amber-500/25 bg-amber-500/10 p-3 text-sm text-amber-300">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {importError}
              </div>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={importCsv}>
                <Upload className="h-4 w-4" /> Import
              </Button>
              <Button variant="outline" onClick={loadSample}>
                <ClipboardList className="h-4 w-4" /> Load sample
              </Button>
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Guardrails</div>
            <h2 className="mt-1 text-lg font-black">Card risk</h2>
            <div className="mt-4 space-y-3 text-sm text-muted-foreground">
              <p>Rows are ranked from your probabilities and entered odds; invalid prices are excluded from totals.</p>
              <p>Portfolio EV is calculated from capped stake size, not full Kelly size.</p>
              <p>Correlated rows still need manual review before using the output in any sizing workflow.</p>
            </div>
          </section>
        </aside>
      </section>
    </div>
  );
}

function OpportunityCard({ row }: { row: PricedRow }) {
  if (!row.math) return null;
  const tone = row.math.evPerHundred > 0 ? "text-primary" : "text-red-300";
  return (
    <article className="market-panel p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground">{row.sport || "Sport"}</div>
          <h3 className="truncate text-lg font-black">{row.selection || "Untitled selection"}</h3>
          <p className="mt-1 truncate text-xs text-muted-foreground">{row.market || "Market"}</p>
        </div>
        <span className="rounded-sm bg-secondary/15 px-2 py-1 text-sm font-black text-secondary">
          {formatAmericanOdds(row.oddsValue)}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
        <MetricCell label="Model" value={formatPercent(row.probabilityValue)} />
        <MetricCell label="Implied" value={formatPercent(row.math.impliedProbability)} tone="amber" />
        <MetricCell label="Edge" value={`${row.math.edgePct.toFixed(1)}%`} tone={row.math.edgePct >= 0 ? "green" : "red"} />
      </div>
      <div className="mt-3 flex items-center justify-between gap-3">
        <div>
          <div className="text-[10px] uppercase tracking-wide text-muted-foreground">EV / $100</div>
          <div className={`text-xl font-black ${tone}`}>{formatMoney(row.math.evPerHundred)}</div>
        </div>
        <div className="text-right">
          <div className="text-[10px] uppercase tracking-wide text-muted-foreground">Stake</div>
          <div className="text-xl font-black text-secondary">{formatMoney(row.math.cappedStake)}</div>
        </div>
      </div>
      <div className="mt-3 text-xs font-black uppercase tracking-wide text-primary">{decisionLabel(row.math.decision)}</div>
    </article>
  );
}

function Metric({
  label,
  value,
  icon: Icon,
  tone = "green",
}: {
  label: string;
  value: number | string;
  icon: typeof ClipboardList;
  tone?: "green" | "amber" | "red";
}) {
  const toneClass = {
    green: "text-primary bg-primary/10 border-primary/25",
    amber: "text-secondary bg-secondary/10 border-secondary/25",
    red: "text-red-300 bg-red-500/10 border-red-500/25",
  }[tone];

  return (
    <div className="surface-card min-w-0 p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
          <div className="mt-1 truncate text-2xl font-black tabular-nums">{typeof value === "number" ? value.toLocaleString() : value}</div>
        </div>
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-md border ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </div>
  );
}

function MetricCell({ label, value, tone = "green" }: { label: string; value: string; tone?: "green" | "amber" | "red" }) {
  const color = tone === "amber" ? "text-secondary" : tone === "red" ? "text-red-300" : "text-primary";
  return (
    <div className="odds-cell">
      <div className="text-[10px] uppercase text-muted-foreground">{label}</div>
      <div className={color}>{value}</div>
    </div>
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
      <span className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</span>
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        inputMode={inputMode}
        className="mt-1 min-h-11 bg-black/25"
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
