import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import Papa from "papaparse";
import {
  AlertTriangle,
  BarChart3,
  ClipboardList,
  Download,
  FlaskConical,
  LineChart,
  ShieldCheck,
  Target,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { downloadCsv } from "@/lib/download";
import { formatAmericanOdds, formatMoney, formatPercent } from "@/lib/edgeMath";
import {
  auditPredictions,
  calibrationBins,
  isValidAuditInput,
  normalizeResult,
  parseAmericanOdds,
  parseProbability,
  summarizeAudit,
  type AuditInput,
  type AuditedPrediction,
} from "@/lib/modelAudit";

const STORAGE_KEY = "gsp:model-audit:v1";

const SAMPLE_CSV = `date,sport,selection,market,american_odds,model_probability,closing_odds,stake,result,notes
2026-05-01,MLB,Dodgers ML,Moneyline,-118,56.5,-130,20,win,Starter edge
2026-05-02,NBA,Celtics spread,Spread,-105,53,-112,18,loss,Power rating lean
2026-05-03,Soccer,Inter Miami over,Total,+115,48,+102,14,win,Tempo projection
2026-05-05,NHL,Rangers puck line,Puck line,+140,43,+125,12,loss,Plus-price test
2026-05-07,MLB,Orioles ML,Moneyline,-102,52,-116,16,win,Market moved
2026-05-09,NBA,Liberty total,Total,-110,54,-105,15,push,Number landed
2026-05-11,NFL,Chiefs futures,Futures,+180,40,+155,10,open,Unsettled position
2026-05-13,MLB,Mariners under,Total,-108,51.5,-120,14,loss,Weather model`;

export default function ModelAudit() {
  const [csvText, setCsvText] = useState(readStoredCsv);
  const [parseNotice, setParseNotice] = useState<string | null>(null);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, csvText);
    } catch {
      /* ignore */
    }
  }, [csvText]);

  const parsed = useMemo(() => parseAuditCsv(csvText), [csvText]);
  const audited = useMemo(() => auditPredictions(parsed.validRows), [parsed.validRows]);
  const summary = useMemo(() => summarizeAudit(audited), [audited]);
  const bins = useMemo(() => calibrationBins(audited), [audited]);
  const verdict = getVerdict(summary);

  useEffect(() => {
    if (parsed.errors.length) {
      setParseNotice(parsed.errors[0]);
    } else if (parsed.invalidRows > 0) {
      setParseNotice(`${parsed.invalidRows} row${parsed.invalidRows === 1 ? "" : "s"} skipped because required fields were invalid.`);
    } else {
      setParseNotice(null);
    }
  }, [parsed.errors, parsed.invalidRows]);

  const loadSample = () => {
    setCsvText(SAMPLE_CSV);
    setParseNotice(null);
  };

  const exportAudit = () => {
    downloadCsv(
      "game_stat_pulse_model_audit.csv",
      audited.map((row) => ({
        date: row.date,
        sport: row.sport,
        selection: row.selection,
        market: row.market,
        american_odds: formatAmericanOdds(row.americanOdds),
        model_probability: formatPercent(row.modelProbability),
        implied_probability: formatPercent(row.impliedProbability),
        edge_pct: `${row.edgePct.toFixed(2)}%`,
        closing_odds: row.closingOdds == null ? "" : formatAmericanOdds(row.closingOdds),
        clv_pct: row.clvPct == null ? "" : `${row.clvPct.toFixed(2)}%`,
        stake: formatMoney(row.stake),
        result: row.result,
        profit: formatMoney(row.profit),
        expected_profit: formatMoney(row.expectedProfit),
        notes: row.notes,
      })),
    );
  };

  return (
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="surface-card sportsbook-glow overflow-hidden">
        <div className="grid gap-4 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_390px]">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-secondary/40 bg-secondary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-secondary">
              <FlaskConical className="h-3.5 w-3.5" />
              Model Audit
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl font-black leading-tight">
                Validate your probabilities before trusting the next card.
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
                Paste a settled prediction log to track calibration, Brier score, log loss, closing-line movement,
                realized profit, and ROI by probability bucket.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={exportAudit} disabled={!audited.length}>
                <Download className="h-4 w-4" /> Export audit
              </Button>
              <Button variant="outline" className="border-secondary/45 text-secondary hover:bg-secondary/10" asChild>
                <Link to="/portfolio">
                  <ClipboardList className="h-4 w-4" /> Open scenarios
                </Link>
              </Button>
            </div>
          </div>

          <aside className="market-panel bg-black/25 p-4">
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Validation read</div>
                <div className={verdict.tone === "green" ? "mt-1 text-2xl font-black text-primary" : verdict.tone === "amber" ? "mt-1 text-2xl font-black text-secondary" : "mt-1 text-2xl font-black text-red-300"}>
                  {verdict.label}
                </div>
              </div>
              <ShieldCheck className="h-9 w-9 text-primary" />
            </div>
            <p className="mb-3 text-xs leading-relaxed text-muted-foreground">{verdict.body}</p>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <MetricCell label="Settled" value={`${summary.settledRows}/${summary.totalRows}`} />
              <MetricCell label="ROI" value={`${summary.roiPct.toFixed(1)}%`} tone={summary.roiPct >= 0 ? "green" : "red"} />
              <MetricCell label="Brier" value={summary.brierScore == null ? "-" : summary.brierScore.toFixed(3)} tone="amber" />
              <MetricCell label="CLV" value={summary.avgClvPct == null ? "-" : `${summary.avgClvPct.toFixed(2)} pts`} />
            </div>
          </aside>
        </div>
      </header>

      <section className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
        <Metric label="Settled bets" value={summary.settledRows} icon={ClipboardList} />
        <Metric label="Profit" value={formatMoney(summary.profit)} icon={Target} tone={summary.profit >= 0 ? "green" : "red"} />
        <Metric label="ROI" value={`${summary.roiPct.toFixed(1)}%`} icon={LineChart} tone={summary.roiPct >= 0 ? "green" : "red"} />
        <Metric label="Brier score" value={summary.brierScore == null ? "-" : summary.brierScore.toFixed(3)} icon={BarChart3} tone="amber" />
        <Metric label="Log loss" value={summary.logLoss == null ? "-" : summary.logLoss.toFixed(3)} icon={FlaskConical} tone="amber" />
      </section>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_390px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Calibration</div>
              <h2 className="mt-1 text-lg font-black">Probability buckets</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-sm">
                <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="p-3">Bucket</th>
                    <th className="p-3">Rows</th>
                    <th className="p-3">Avg model</th>
                    <th className="p-3">Realized win %</th>
                    <th className="p-3">Brier</th>
                    <th className="p-3">Profit</th>
                    <th className="p-3">ROI</th>
                  </tr>
                </thead>
                <tbody>
                  {bins.map((bin) => (
                    <tr key={bin.label} className="border-t border-white/5">
                      <td className="p-3 font-semibold">{bin.label}</td>
                      <td className="p-3 tabular-nums">{bin.rows}</td>
                      <td className="p-3 tabular-nums">{bin.rows ? formatPercent(bin.avgModelProbability) : "-"}</td>
                      <td className="p-3 tabular-nums">{bin.realizedWinRate == null ? "-" : formatPercent(bin.realizedWinRate, 1)}</td>
                      <td className="p-3 tabular-nums">{bin.brierScore == null ? "-" : bin.brierScore.toFixed(3)}</td>
                      <td className={bin.profit >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>{formatMoney(bin.profit)}</td>
                      <td className={bin.roiPct >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>{bin.rows ? `${bin.roiPct.toFixed(1)}%` : "-"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Prediction ledger</div>
              <h2 className="mt-1 text-lg font-black">Audit rows</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[980px] text-sm">
                <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="p-3">Date</th>
                    <th className="p-3">Selection</th>
                    <th className="p-3">Sport</th>
                    <th className="p-3">Market</th>
                    <th className="p-3">Odds</th>
                    <th className="p-3">Model</th>
                    <th className="p-3">Edge</th>
                    <th className="p-3">Close</th>
                    <th className="p-3">CLV</th>
                    <th className="p-3">Stake</th>
                    <th className="p-3">Result</th>
                    <th className="p-3">Profit</th>
                  </tr>
                </thead>
                <tbody>
                  {audited.map((row, index) => (
                    <AuditRow key={`${row.date}-${row.selection}-${index}`} row={row} />
                  ))}
                  {!audited.length && (
                    <tr>
                      <td colSpan={12} className="p-4 text-sm text-muted-foreground">
                        Paste a CSV prediction log to start the audit.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <aside className="min-w-0 space-y-4">
          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">CSV input</div>
            <h2 className="mt-1 text-lg font-black">Prediction log</h2>
            <Textarea
              value={csvText}
              onChange={(event) => setCsvText(event.target.value)}
              className="mt-4 min-h-[22rem] bg-black/25 font-mono text-xs"
              placeholder="date,sport,selection,market,american_odds,model_probability,closing_odds,stake,result,notes"
            />
            {parseNotice && (
              <div className="mt-3 flex gap-2 rounded-lg border border-amber-500/25 bg-amber-500/10 p-3 text-sm text-amber-300">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {parseNotice}
              </div>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={loadSample}>
                <Target className="h-4 w-4" /> Load sample
              </Button>
              <Button variant="outline" onClick={() => setCsvText("")}>
                Clear
              </Button>
            </div>
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Audit rules</div>
            <h2 className="mt-1 text-lg font-black">What this measures</h2>
            <div className="mt-4 space-y-3 text-sm text-muted-foreground">
              <p>Brier score and log loss use graded win/loss rows. Pushes and open positions are excluded from calibration error.</p>
              <p>CLV is closing implied probability minus opening implied probability. Positive points mean your logged price beat the close.</p>
              <p>ROI uses settled stake and realized profit, so sample size and correlation still need manual review.</p>
            </div>
          </section>
        </aside>
      </section>
    </div>
  );
}

function AuditRow({ row }: { row: AuditedPrediction }) {
  const resultClass =
    row.result === "win"
      ? "text-primary"
      : row.result === "loss"
        ? "text-red-300"
        : row.result === "push"
          ? "text-secondary"
          : "text-muted-foreground";
  return (
    <tr className="border-t border-white/5">
      <td className="p-3 tabular-nums text-muted-foreground">{row.date || "-"}</td>
      <td className="p-3 font-semibold">{row.selection}</td>
      <td className="p-3">{row.sport || "-"}</td>
      <td className="p-3">{row.market || "-"}</td>
      <td className="p-3 tabular-nums">{formatAmericanOdds(row.americanOdds)}</td>
      <td className="p-3 tabular-nums">{formatPercent(row.modelProbability)}</td>
      <td className={row.edgePct >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>{row.edgePct.toFixed(2)}%</td>
      <td className="p-3 tabular-nums">{row.closingOdds == null ? "-" : formatAmericanOdds(row.closingOdds)}</td>
      <td className={row.clvPct == null ? "p-3 text-muted-foreground" : row.clvPct >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>
        {row.clvPct == null ? "-" : `${row.clvPct.toFixed(2)} pts`}
      </td>
      <td className="p-3 tabular-nums">{formatMoney(row.stake)}</td>
      <td className={`p-3 font-black uppercase ${resultClass}`}>{row.result}</td>
      <td className={row.profit >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>{formatMoney(row.profit)}</td>
    </tr>
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

function parseAuditCsv(csvText: string): { validRows: AuditInput[]; invalidRows: number; errors: string[] } {
  if (!csvText.trim()) return { validRows: [], invalidRows: 0, errors: [] };
  const parsed = Papa.parse<Record<string, string>>(csvText.trim(), {
    header: true,
    skipEmptyLines: true,
    transformHeader: (header) => header.trim().toLowerCase(),
  });

  const rows = parsed.data.map(csvRecordToAuditInput);
  const validRows = rows.filter(isValidAuditInput);
  return {
    validRows,
    invalidRows: rows.length - validRows.length,
    errors: parsed.errors.map((error) => error.message),
  };
}

function csvRecordToAuditInput(record: Record<string, string>): AuditInput {
  const closingRaw = pick(record, ["closing_odds", "closing_price", "close", "close_odds"]);
  const closingOdds = closingRaw ? parseAmericanOdds(closingRaw) : NaN;
  return {
    date: pick(record, ["date", "event_date", "settled_at"]),
    sport: pick(record, ["sport", "league"]),
    selection: pick(record, ["selection", "pick", "team", "name"]),
    market: pick(record, ["market", "bet_type", "type"]) || "Moneyline",
    americanOdds: parseAmericanOdds(pick(record, ["american_odds", "odds", "price", "line"])),
    modelProbability: parseProbability(pick(record, ["model_probability", "model_probability_pct", "probability", "prob", "win_probability"])),
    closingOdds: Number.isFinite(closingOdds) && closingOdds !== 0 ? closingOdds : null,
    stake: Number(pick(record, ["stake", "risk", "amount"]) || "0"),
    result: normalizeResult(pick(record, ["result", "outcome", "grade", "status"])),
    notes: pick(record, ["notes", "note", "reason"]),
  };
}

function pick(record: Record<string, string>, keys: string[]) {
  for (const key of keys) {
    const value = record[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return "";
}

function readStoredCsv() {
  if (typeof window === "undefined") return SAMPLE_CSV;
  try {
    return localStorage.getItem(STORAGE_KEY) || SAMPLE_CSV;
  } catch {
    return SAMPLE_CSV;
  }
}

function getVerdict(summary: ReturnType<typeof summarizeAudit>) {
  if (summary.gradedRows < 30) {
    return {
      label: "Small sample",
      body: "Use this readout, but do not treat the model as validated until the log has more graded volume.",
      tone: "amber" as const,
    };
  }
  if ((summary.brierScore ?? 1) <= 0.22 && summary.roiPct > 0 && (summary.avgClvPct ?? 0) > 0) {
    return {
      label: "Passing",
      body: "Calibration, ROI, and closing-line movement are all currently pointing in the right direction.",
      tone: "green" as const,
    };
  }
  if (summary.roiPct < 0 || (summary.brierScore ?? 0) > 0.25) {
    return {
      label: "Needs work",
      body: "The audit is flagging weak realized economics or poor probability calibration.",
      tone: "red" as const,
    };
  }
  return {
    label: "Watch list",
    body: "Some validation signals are acceptable, but the model still needs tighter calibration or stronger closing-line performance.",
    tone: "amber" as const,
  };
}
