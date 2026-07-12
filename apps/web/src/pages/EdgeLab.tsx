import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronDown, Download, Save, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { PageHeader } from "@/components/PageHeader";
import { PortfolioSubNav } from "@/components/PortfolioSubNav";
import { StatusChip } from "@/components/StatusBadge";
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
  // The prefilled numbers are an example, not a live recommendation: the hero
  // stays chipped "Example" until the user edits any input.
  const [touched, setTouched] = useState(false);

  const edit = <T,>(setter: (value: T) => void) => (value: T) => {
    setTouched(true);
    setter(value);
  };

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
    setTouched(true);
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

  const evTone = result && result.evPerHundred > 0 ? "text-gain" : result ? "text-loss" : "text-muted-foreground";

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-36 lg:pb-0">
      <PageHeader title="Portfolio" />
      <PortfolioSubNav active="edge" />

      {/* Plain words in the hero; the formal terms (Kelly, EV, implied
          probability) stay inside "Show the math" below. */}
      <header className="surface-card p-4 sm:p-6">
        <div className="flex items-center gap-2">
          <div className="label-mono">Expected profit per $100</div>
          {!touched && <StatusChip tone="muted" label="Example" />}
        </div>
        <div className={`num-hero mt-2 ${evTone}`}>{result ? money(result.evPerHundred) : "—"}</div>
        <div className="mt-1 text-sm text-muted-foreground">
          {result
            ? `${decisionLabel(result.decision)} · your ${pct(parsed.modelProbability)} vs the market's ${pct(result.impliedProbability)}`
            : "Enter valid odds, a probability between 0 and 100, a bankroll above 0, and a cap at or above 0."}
        </div>

        <div className="mt-5 grid grid-cols-2 gap-3 border-t border-border pt-4 sm:grid-cols-3">
          <Stat label="Edge" value={result ? `${result.edgePct.toFixed(1)}%` : "—"} tone={result && result.edgePct > 0 ? "gain" : undefined} />
          <Stat label="Fair price" value={result ? formatAmericanOdds(result.fairAmericanOdds) : "—"} />
          <Stat label="Suggested stake" value={result ? money(result.cappedStake) : "—"} />
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Suggested stake bets half of the mathematically ideal amount, capped at{" "}
          {Number.isFinite(parsed.capPct) ? parsed.capPct : 0}% of your bankroll.
        </p>

        {/* Desktop keeps the in-card primary; on mobile the same action is
            bottom-anchored above the tab bar (fixed bar below) so it stays
            reachable after editing the last form field. */}
        <div className="mt-5 flex flex-wrap items-center gap-3">
          <Button className="hidden min-h-11 sm:px-8 lg:inline-flex" onClick={save} disabled={!result}>
            <Save className="h-4 w-4" /> Save check
          </Button>
          <Link to="/signals" className="text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
            Use signals
          </Link>
        </div>
      </header>

      <section className="surface-card p-4 sm:p-6">
        <div className="label-mono">Line and model estimate</div>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <Field label="Ticket label" value={label} onChange={edit(setLabel)} />
          <Field label="Sport" value={sport} onChange={edit(setSport)} />
          <Field label="Market" value={market} onChange={edit(setMarket)} />
          <Field label="American odds" value={americanOdds} onChange={edit(setAmericanOdds)} inputMode="numeric" big />
          <Field label="Model probability %" value={modelProbability} onChange={edit(setModelProbability)} inputMode="decimal" big />
          <Field label="Bankroll $" value={bankroll} onChange={edit(setBankroll)} inputMode="decimal" big />
          <Field label="Max stake cap %" value={capPct} onChange={edit(setCapPct)} inputMode="decimal" big />
        </div>
      </section>

      {/* Jargon lives behind a disclosure: the four plain-word numbers in the
          hero are the only always-visible outputs. */}
      <Collapsible className="surface-card overflow-hidden">
        <CollapsibleTrigger className="group flex min-h-11 w-full items-center justify-between gap-2 px-4 py-3 text-left text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground">
          Show the math
          <ChevronDown
            className="h-4 w-4 transition-transform group-data-[state=open]:rotate-180"
            aria-hidden="true"
          />
        </CollapsibleTrigger>
        <CollapsibleContent>
          {result ? (
            <div className="grid grid-cols-2 gap-3 border-t border-border p-4 xl:grid-cols-3">
              <Output label="Decimal odds" value={result.decimalOdds.toFixed(3)} />
              <Output label="Implied probability" value={pct(result.impliedProbability)} />
              <Output label="Model probability" value={pct(parsed.modelProbability)} />
              <Output label="Fair American odds" value={formatAmericanOdds(result.fairAmericanOdds)} />
              <Output label="EV per $1" value={money(result.evPerDollar)} tone={result.evPerDollar > 0 ? "gain" : "loss"} />
              <Output label="EV per $100" value={money(result.evPerHundred)} tone={result.evPerHundred > 0 ? "gain" : "loss"} />
              <Output label="Full Kelly" value={`${result.kellyPct.toFixed(2)}%`} />
              <Output label="Half Kelly" value={`${result.halfKellyPct.toFixed(2)}%`} />
              <Output label="Capped stake" value={money(result.cappedStake)} />
            </div>
          ) : (
            <div className="border-t border-border p-4 text-sm text-muted-foreground">
              Once the inputs above are valid, implied probability, fair odds, EV, Kelly sizing, and the capped stake appear here.
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      <section className="grid gap-3 md:grid-cols-2">
        <div className="surface-card p-4 sm:p-6">
          <div className="label-mono">Use this correctly</div>
          <div className="mt-3 space-y-2 text-sm leading-relaxed text-muted-foreground">
            <p>This calculator depends entirely on your model probability. If that estimate is off, every number here is off with it.</p>
            <p>A positive expected profit is not a guarantee. It only means your probability estimate is higher than the one built into the market's price.</p>
            <p>The stake output is capped by your max stake percentage, so the math can never suggest risking a big chunk of your bankroll on one bet.</p>
          </div>
        </div>

        <div className="surface-card p-4 sm:p-6">
          <div className="flex items-center justify-between gap-3">
            <div className="label-mono">Saved checks</div>
            <div className="flex gap-2">
              <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={exportHistory} disabled={!history.length} aria-label="Export edge checks">
                <Download className="h-4 w-4" />
              </Button>
              <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={() => setHistory([])} disabled={!history.length} aria-label="Clear edge checks">
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          </div>
          <div className="mt-3 space-y-2">
            {history.length ? (
              history.map((record) => {
                const math = calculateEdge(record.americanOdds, record.modelProbability, record.bankroll, record.capPct);
                return (
                  <button
                    key={record.id}
                    type="button"
                    onClick={() => load(record)}
                    className="w-full rounded-md border border-border bg-background p-3 text-left hover:border-gain/40"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="truncate text-sm font-semibold">{record.label}</div>
                        <div className="mt-0.5 text-[11px] text-muted-foreground">
                          {record.sport} · {record.market} · {formatAmericanOdds(record.americanOdds)}
                        </div>
                      </div>
                      <span className={math.evPerHundred > 0 ? "text-sm font-bold tabular-nums text-gain" : "text-sm font-bold tabular-nums text-loss"}>
                        {money(math.evPerHundred)}
                      </span>
                    </div>
                  </button>
                );
              })
            ) : (
              <div className="rounded-md border border-border bg-background p-3 text-sm text-muted-foreground">
                Nothing saved yet. Save a check and it stays in this browser so you can reload the inputs later.
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Mobile: the one primary action, bottom-anchored above the tab bar
          (same pattern as Today and the Desk page). */}
      <div className="fixed inset-x-0 bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-20 border-t border-border bg-background/95 p-3 backdrop-blur lg:hidden">
        <Button className="min-h-11 w-full" onClick={save} disabled={!result}>
          <Save className="h-4 w-4" /> Save check
        </Button>
      </div>
    </div>
  );
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

function Field({
  label,
  value,
  onChange,
  inputMode,
  big,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  inputMode?: "numeric" | "decimal";
  big?: boolean;
}) {
  return (
    <label className="block">
      <span className="label-mono">{label}</span>
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        inputMode={inputMode}
        className={big ? "mt-1 min-h-11 text-lg font-bold tabular-nums" : "mt-1 min-h-11"}
      />
    </label>
  );
}

function Output({ label, value, tone }: { label: string; value: string; tone?: "gain" | "loss" }) {
  const color = tone === "gain" ? "text-gain" : tone === "loss" ? "text-loss" : "text-foreground";
  return (
    <div className="rounded-md border border-border bg-background p-3">
      <div className="label-mono">{label}</div>
      <div className={`mt-1 text-xl font-bold tabular-nums ${color}`}>{value}</div>
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
