import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  Calculator,
  CheckCircle2,
  Download,
  LineChart,
  Save,
  Trash2,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { downloadCsv } from "@/lib/download";
import {
  calculateEdge,
  decisionLabel,
  formatAmericanOdds,
  formatMoney as money,
  formatPercent as pct,
  isValidEdgeInput,
} from "@/lib/edgeMath";

const STORAGE_KEY = "gsp:edge-lab:v1";

type EdgeRecord = {
  id: string;
  label: string;
  sport: string;
  market: string;
  americanOdds: number;
  modelProbability: number;
  bankroll: number;
  capPct: number;
  createdAt: string;
};

export default function EdgeLab() {
  const [label, setLabel] = useState("Example: Knicks moneyline");
  const [sport, setSport] = useState("NBA");
  const [market, setMarket] = useState("Moneyline");
  const [americanOdds, setAmericanOdds] = useState("-110");
  const [modelProbability, setModelProbability] = useState("55");
  const [bankroll, setBankroll] = useState("1000");
  const [capPct, setCapPct] = useState("2");
  const [history, setHistory] = useState<EdgeRecord[]>(readHistory);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
    } catch {
      /* ignore */
    }
  }, [history]);

  const parsed = useMemo(
    () => ({
      americanOdds: Number(americanOdds),
      modelProbability: Number(modelProbability) / 100,
      bankroll: Number(bankroll),
      capPct: Number(capPct),
    }),
    [americanOdds, bankroll, capPct, modelProbability],
  );

  const result = useMemo(() => {
    if (!isValidEdgeInput(parsed.americanOdds, parsed.modelProbability, parsed.bankroll, parsed.capPct)) return null;
    return calculateEdge(parsed.americanOdds, parsed.modelProbability, parsed.bankroll, parsed.capPct);
  }, [parsed]);

  const save = () => {
    if (!result) return;
    const record: EdgeRecord = {
      id: crypto.randomUUID(),
      label: label.trim() || "Untitled edge check",
      sport: sport.trim() || "Unknown",
      market: market.trim() || "Unknown",
      americanOdds: parsed.americanOdds,
      modelProbability: parsed.modelProbability,
      bankroll: parsed.bankroll,
      capPct: parsed.capPct,
      createdAt: new Date().toISOString(),
    };
    setHistory((items) => [record, ...items].slice(0, 50));
  };

  const load = (record: EdgeRecord) => {
    setLabel(record.label);
    setSport(record.sport);
    setMarket(record.market);
    setAmericanOdds(String(record.americanOdds));
    setModelProbability(String(Math.round(record.modelProbability * 10000) / 100));
    setBankroll(String(record.bankroll));
    setCapPct(String(record.capPct));
  };

  const exportHistory = () => {
    downloadCsv(
      "game_stat_pulse_edge_lab.csv",
      history.map((record) => {
        const math = calculateEdge(record.americanOdds, record.modelProbability, record.bankroll, record.capPct);
        return {
          label: record.label,
          sport: record.sport,
          market: record.market,
          american_odds: formatAmericanOdds(record.americanOdds),
          model_probability_pct: pct(record.modelProbability),
          implied_probability_pct: pct(math.impliedProbability),
          fair_american_odds: formatAmericanOdds(math.fairAmericanOdds),
          edge_pct: pct(math.edgePct / 100),
          ev_per_100: money(math.evPerHundred),
          kelly_pct: pct(math.kellyPct / 100),
          half_kelly_pct: pct(math.halfKellyPct / 100),
          capped_stake: money(math.cappedStake),
          created_at: record.createdAt,
        };
      }),
    );
  };

  return (
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="surface-card sportsbook-glow overflow-hidden">
        <div className="grid gap-4 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_380px]">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-secondary/40 bg-secondary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-secondary">
              <Calculator className="h-3.5 w-3.5" />
              Edge Lab
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl font-black leading-tight">
                Convert odds and your model probability into EV and sizing.
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
                Enter a market line and your estimated win probability. The lab returns implied probability, fair odds,
                expected value, Kelly fraction, and capped stake size.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={save} disabled={!result}>
                <Save className="h-4 w-4" /> Save check
              </Button>
              <Button variant="outline" className="border-secondary/45 text-secondary hover:bg-secondary/10" asChild>
                <Link to="/signals">
                  <LineChart className="h-4 w-4" /> Use signals
                </Link>
              </Button>
            </div>
          </div>

          <aside className="market-panel bg-black/25 p-4">
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Current decision</div>
                <div className={result?.decision === "positive" ? "mt-1 text-2xl font-black text-primary" : result?.decision === "thin" ? "mt-1 text-2xl font-black text-secondary" : "mt-1 text-2xl font-black text-red-300"}>
                  {result ? decisionLabel(result.decision) : "Invalid"}
                </div>
              </div>
              {result?.decision === "positive" ? (
                <CheckCircle2 className="h-9 w-9 text-primary" />
              ) : (
                <AlertTriangle className="h-9 w-9 text-secondary" />
              )}
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <MetricCell label="EV / $100" value={result ? money(result.evPerHundred) : "-"} tone={result && result.evPerHundred > 0 ? "green" : "red"} />
              <MetricCell label="Edge" value={result ? `${result.edgePct.toFixed(1)}%` : "-"} tone={result && result.edgePct > 0 ? "green" : "red"} />
              <MetricCell label="Half Kelly" value={result ? `${result.halfKellyPct.toFixed(2)}%` : "-"} tone="amber" />
              <MetricCell label="Stake" value={result ? money(result.cappedStake) : "-"} />
            </div>
          </aside>
        </div>
      </header>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Scenario inputs</div>
            <h2 className="mt-1 text-lg font-black">Line and model estimate</h2>
            <div className="mt-4 grid gap-3 md:grid-cols-2">
              <Field label="Ticket label" value={label} onChange={setLabel} />
              <Field label="Sport" value={sport} onChange={setSport} />
              <Field label="Market" value={market} onChange={setMarket} />
              <Field label="American odds" value={americanOdds} onChange={setAmericanOdds} inputMode="numeric" />
              <Field label="Model probability %" value={modelProbability} onChange={setModelProbability} inputMode="decimal" />
              <Field label="Bankroll $" value={bankroll} onChange={setBankroll} inputMode="decimal" />
              <Field label="Max stake cap %" value={capPct} onChange={setCapPct} inputMode="decimal" />
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Math output</div>
              <h2 className="mt-1 text-lg font-black">Price, edge, and sizing</h2>
            </div>
            {result ? (
              <div className="grid gap-3 p-4 md:grid-cols-2 xl:grid-cols-3">
                <Output label="Decimal odds" value={result.decimalOdds.toFixed(3)} />
                <Output label="Implied probability" value={pct(result.impliedProbability)} />
                <Output label="Model probability" value={pct(parsed.modelProbability)} />
                <Output label="Fair American odds" value={formatAmericanOdds(result.fairAmericanOdds)} />
                <Output label="EV per $1" value={money(result.evPerDollar)} tone={result.evPerDollar > 0 ? "green" : "red"} />
                <Output label="EV per $100" value={money(result.evPerHundred)} tone={result.evPerHundred > 0 ? "green" : "red"} />
                <Output label="Full Kelly" value={`${result.kellyPct.toFixed(2)}%`} tone="amber" />
                <Output label="Half Kelly" value={`${result.halfKellyPct.toFixed(2)}%`} tone="amber" />
                <Output label="Capped stake" value={money(result.cappedStake)} />
              </div>
            ) : (
              <div className="p-4 text-sm text-muted-foreground">
                Enter valid odds, model probability between 0 and 100, bankroll above 0, and cap at or above 0.
              </div>
            )}
          </section>
        </div>

        <aside className="min-w-0 space-y-4">
          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Guardrails</div>
            <h2 className="mt-1 text-lg font-black">Use this correctly</h2>
            <div className="mt-4 space-y-3 text-sm text-muted-foreground">
              <p>This calculator depends entirely on your model probability. Bad probability estimates create bad EV.</p>
              <p>Positive EV is not a guarantee. It only means the entered probability exceeds the market's implied price.</p>
              <p>The stake output is capped by your max stake percentage so a large Kelly number does not dominate bankroll risk.</p>
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Saved checks</div>
                <h2 className="mt-1 text-lg font-black">Local history</h2>
              </div>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={exportHistory} disabled={!history.length} aria-label="Export edge checks">
                  <Download className="h-4 w-4" />
                </Button>
                <Button variant="outline" size="sm" onClick={() => setHistory([])} disabled={!history.length} aria-label="Clear edge checks">
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            </div>
            <div className="mt-4 space-y-2">
              {history.length ? (
                history.map((record) => {
                  const math = calculateEdge(record.americanOdds, record.modelProbability, record.bankroll, record.capPct);
                  return (
                    <button
                      key={record.id}
                      type="button"
                      onClick={() => load(record)}
                      className="w-full rounded-lg border border-white/10 bg-black/20 p-3 text-left hover:border-primary/35"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="truncate text-sm font-semibold">{record.label}</div>
                          <div className="mt-1 text-[11px] text-muted-foreground">
                            {record.sport} / {record.market} / {formatAmericanOdds(record.americanOdds)}
                          </div>
                        </div>
                        <span className={math.evPerHundred > 0 ? "text-sm font-black text-primary" : "text-sm font-black text-red-300"}>
                          {money(math.evPerHundred)}
                        </span>
                      </div>
                    </button>
                  );
                })
              ) : (
                <div className="rounded-lg border border-white/10 bg-black/20 p-3 text-sm text-muted-foreground">
                  Saved edge checks stay in this browser.
                </div>
              )}
            </div>
          </section>
        </aside>
      </section>
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

function Output({ label, value, tone = "green" }: { label: string; value: string; tone?: "green" | "amber" | "red" }) {
  const color = tone === "amber" ? "text-secondary" : tone === "red" ? "text-red-300" : "text-primary";
  return (
    <div className="market-panel p-3">
      <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={`mt-1 text-xl font-black tabular-nums ${color}`}>{value}</div>
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

function readHistory(): EdgeRecord[] {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
