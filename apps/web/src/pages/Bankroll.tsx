import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import Papa from "papaparse";
import {
  AlertTriangle,
  ArrowUpRight,
  Banknote,
  Brain,
  Database,
  Download,
  LineChart,
  Microscope,
  ShieldAlert,
  Target,
  WalletCards,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { downloadCsv } from "@/lib/download";
import { formatAmericanOdds, formatMoney, formatPercent } from "@/lib/edgeMath";
import {
  isValidWagerInput,
  normalizeWagerStatus,
  parseLedgerOdds,
  parseLedgerProbability,
  summarizeLedger,
  trackWagers,
  type TrackedWager,
  type WagerInput,
} from "@/lib/betLedger";

const STORAGE_KEY = "gsp:bankroll-ledger:v1";

const SAMPLE_CSV = `date,sport,selection,market,american_odds,stake,status,model_probability,closing_odds,book,notes
2026-06-01,MLB,Dodgers ML,Moneyline,-118,20,win,56.5,-130,DraftKings,Starter edge
2026-06-02,NBA,Celtics spread,Spread,-105,18,loss,53,-112,FanDuel,Power rating lean
2026-06-03,Soccer,Inter Miami over,Total,+115,14,win,48,+102,Caesars,Tempo projection
2026-06-04,NHL,Rangers puck line,Puck line,+140,12,open,43,+125,BetMGM,Open plus-price
2026-06-05,MLB,Orioles ML,Moneyline,-102,16,win,52,-116,DraftKings,Market moved
2026-06-06,NBA,Liberty total,Total,-110,15,push,54,-105,FanDuel,Landed on number
2026-06-07,NFL,Chiefs futures,Futures,+180,10,open,40,+155,Caesars,Longer hold
2026-06-08,MLB,Mariners under,Total,-108,14,loss,51.5,-120,BetMGM,Weather model`;

type StoredLedger = {
  startingBankroll: string;
  csvText: string;
};

export default function Bankroll() {
  const stored = useMemo(readStoredLedger, []);
  const [startingBankroll, setStartingBankroll] = useState(stored.startingBankroll);
  const [csvText, setCsvText] = useState(stored.csvText);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    try {
      const payload: StoredLedger = { startingBankroll, csvText };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch {
      /* ignore */
    }
  }, [csvText, startingBankroll]);

  const parsedBankroll = Number(startingBankroll);
  const parsed = useMemo(() => parseWagerCsv(csvText), [csvText]);
  const wagers = useMemo(() => trackWagers(parsed.validRows), [parsed.validRows]);
  const summary = useMemo(() => summarizeLedger(wagers, Number.isFinite(parsedBankroll) ? parsedBankroll : 0), [parsedBankroll, wagers]);
  const openWagers = useMemo(() => wagers.filter((wager) => wager.isOpen), [wagers]);
  const settledWagers = useMemo(() => wagers.filter((wager) => wager.isSettled), [wagers]);
  const bySport = useMemo(() => summarizeSegments(wagers, (wager) => wager.sport || "Unspecified"), [wagers]);
  const byBook = useMemo(() => summarizeSegments(wagers, (wager) => wager.book || "Unspecified"), [wagers]);
  const insightCards = useMemo(() => buildInsightCards(summary, bySport, byBook), [summary, bySport, byBook]);

  useEffect(() => {
    if (parsed.errors.length) {
      setNotice(parsed.errors[0]);
    } else if (parsed.invalidRows) {
      setNotice(`${parsed.invalidRows} row${parsed.invalidRows === 1 ? "" : "s"} skipped because required fields were invalid.`);
    } else {
      setNotice(null);
    }
  }, [parsed.errors, parsed.invalidRows]);

  const exportLedger = () => {
    downloadCsv(
      "game_stat_pulse_bankroll_ledger.csv",
      wagers.map((wager) => ({
        date: wager.date,
        sport: wager.sport,
        selection: wager.selection,
        market: wager.market,
        american_odds: formatAmericanOdds(wager.americanOdds),
        stake: formatMoney(wager.stake),
        status: wager.status,
        profit: formatMoney(wager.profit),
        potential_profit: formatMoney(wager.potentialProfit),
        exposure: formatMoney(wager.exposure),
        model_probability: wager.modelProbability == null ? "" : formatPercent(wager.modelProbability),
        model_edge_pct: wager.modelEdgePct == null ? "" : `${wager.modelEdgePct.toFixed(2)}%`,
        closing_odds: wager.closingOdds == null ? "" : formatAmericanOdds(wager.closingOdds),
        clv_pct: wager.clvPct == null ? "" : `${wager.clvPct.toFixed(2)} pts`,
        book: wager.book,
        notes: wager.notes,
      })),
    );
  };

  return (
    <div className="space-y-5 pb-28 lg:pb-0">
      <header className="surface-card sportsbook-glow overflow-hidden">
        <div className="grid gap-4 p-4 sm:p-6 lg:grid-cols-[minmax(0,1fr)_390px]">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2 rounded-md border border-primary/35 bg-primary/10 px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.24em] text-primary">
              <Microscope className="h-3.5 w-3.5" />
              Performance Ledger
            </div>
            <div>
              <h1 className="text-2xl sm:text-4xl font-black leading-tight">
                Monitor exposure, realized return, and execution quality.
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
                Paste a local CSV ledger with prices, stake, status, model probability, closing line, and notes.
                Use it to understand where returns, concentration, and closing-line performance are coming from.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={exportLedger} disabled={!wagers.length}>
                <Download className="h-4 w-4" /> Export ledger
              </Button>
              <Button variant="outline" className="border-secondary/45 text-secondary hover:bg-secondary/10" asChild>
                <Link to="/model">
                  <Brain className="h-4 w-4" /> Open model audit
                </Link>
              </Button>
            </div>
          </div>

          <aside className="market-panel bg-black/25 p-4">
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">Current capital</div>
                <div className={summary.currentBankroll >= summary.startingBankroll ? "mt-1 text-2xl font-black text-primary" : "mt-1 text-2xl font-black text-red-300"}>
                  {formatMoney(summary.currentBankroll)}
                </div>
              </div>
              <Banknote className="h-9 w-9 text-primary" />
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <MetricCell label="Open risk" value={formatMoney(summary.openExposure)} tone="amber" />
              <MetricCell label="Settled return" value={formatMoney(summary.settledProfit)} tone={summary.settledProfit >= 0 ? "green" : "red"} />
              <MetricCell label="ROI" value={`${summary.roiPct.toFixed(1)}%`} tone={summary.roiPct >= 0 ? "green" : "red"} />
              <MetricCell label="Avg edge" value={summary.avgModelEdgePct == null ? "-" : `${summary.avgModelEdgePct.toFixed(1)}%`} />
            </div>
          </aside>
        </div>
      </header>

      <section className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
        <Metric label="Open positions" value={summary.openRows} icon={ShieldAlert} tone="amber" />
        <Metric label="Open exposure" value={formatMoney(summary.openExposure)} icon={WalletCards} tone="amber" />
        <Metric label="Settled return" value={formatMoney(summary.settledProfit)} icon={Target} tone={summary.settledProfit >= 0 ? "green" : "red"} />
        <Metric label="ROI" value={`${summary.roiPct.toFixed(1)}%`} icon={LineChart} tone={summary.roiPct >= 0 ? "green" : "red"} />
        <Metric label="Avg CLV" value={summary.avgClvPct == null ? "-" : `${summary.avgClvPct.toFixed(2)} pts`} icon={LineChart} />
      </section>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_390px]">
        <div className="min-w-0 space-y-4">
          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Insight brief</div>
              <h2 className="mt-1 text-lg font-black">What the ledger says</h2>
            </div>
            <div className="grid gap-3 p-4 md:grid-cols-3">
              {insightCards.map((card) => (
                <InsightCard key={card.title} {...card} />
              ))}
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Open positions</div>
              <h2 className="mt-1 text-lg font-black">Unsettled exposure</h2>
            </div>
            <div className="grid gap-3 p-4 md:grid-cols-2">
              {openWagers.slice(0, 8).map((wager, index) => (
                <OpenWagerCard key={`${wager.date}-${wager.selection}-${index}`} wager={wager} />
              ))}
              {!openWagers.length && (
                <div className="rounded-lg border border-white/10 bg-black/20 p-4 text-sm text-muted-foreground">
                  No open exposure in the current ledger.
                </div>
              )}
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Settled ledger</div>
              <h2 className="mt-1 text-lg font-black">Realized records</h2>
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
                    <th className="p-3">Stake</th>
                    <th className="p-3">Status</th>
                    <th className="p-3">Profit</th>
                    <th className="p-3">Edge</th>
                    <th className="p-3">CLV</th>
                    <th className="p-3">Book</th>
                  </tr>
                </thead>
                <tbody>
                  {settledWagers.map((wager, index) => (
                    <LedgerRow key={`${wager.date}-${wager.selection}-${index}`} wager={wager} />
                  ))}
                  {!settledWagers.length && (
                    <tr>
                      <td colSpan={11} className="p-4 text-sm text-muted-foreground">
                        No settled wagers in the current ledger.
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
            <div className="text-[10px] uppercase tracking-[0.22em] text-secondary">Ledger settings</div>
            <h2 className="mt-1 text-lg font-black">Starting capital</h2>
            <label className="mt-4 block">
              <span className="text-[10px] uppercase tracking-wide text-muted-foreground">Starting capital $</span>
              <Input
                value={startingBankroll}
                onChange={(event) => setStartingBankroll(event.target.value)}
                inputMode="decimal"
                className="mt-1 min-h-11 bg-black/25"
              />
            </label>
            <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
              <MetricCell label="Risk %" value={`${summary.exposurePct.toFixed(1)}%`} tone={summary.exposurePct > 10 ? "red" : "green"} />
              <MetricCell label="Open upside" value={formatMoney(summary.openPotentialProfit)} />
            </div>
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Segment analysis</div>
              <h2 className="mt-1 text-lg font-black">Return by sport</h2>
            </div>
            <SegmentTable rows={bySport.slice(0, 6)} valueLabel="Sport" />
          </section>

          <section className="surface-card overflow-hidden">
            <div className="border-b border-white/10 bg-white/[0.035] px-4 py-3">
              <div className="text-[10px] uppercase tracking-[0.22em] text-primary">Source analysis</div>
              <h2 className="mt-1 text-lg font-black">Return by book</h2>
            </div>
            <SegmentTable rows={byBook.slice(0, 6)} valueLabel="Book" />
          </section>

          <section className="surface-card p-4">
            <div className="text-[10px] uppercase tracking-[0.22em] text-primary">CSV input</div>
            <h2 className="mt-1 text-lg font-black">Local ledger rows</h2>
            <p className="mt-2 text-xs leading-relaxed text-muted-foreground">
              Required fields are selection, price, and stake. Optional fields such as model probability, closing line,
              sport, source, and notes unlock the deeper diagnostic views.
            </p>
            <Textarea
              value={csvText}
              onChange={(event) => setCsvText(event.target.value)}
              className="mt-4 min-h-[22rem] bg-black/25 font-mono text-xs"
              placeholder="date,sport,selection,market,american_odds,stake,status,model_probability,closing_odds,book,notes"
            />
            {notice && (
              <div className="mt-3 flex gap-2 rounded-lg border border-amber-500/25 bg-amber-500/10 p-3 text-sm text-amber-300">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {notice}
              </div>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              <Button className="bg-primary text-primary-foreground hover:bg-primary/90" onClick={() => setCsvText(SAMPLE_CSV)}>
                <Database className="h-4 w-4" /> Load sample
              </Button>
              <Button variant="outline" onClick={() => setCsvText("")}>
                Clear
              </Button>
            </div>
          </section>
        </aside>
      </section>
    </div>
  );
}

function OpenWagerCard({ wager }: { wager: TrackedWager }) {
  return (
    <article className="market-panel p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground">{wager.sport || "Sport"}</div>
          <h3 className="truncate text-lg font-black">{wager.selection}</h3>
          <p className="mt-1 truncate text-xs text-muted-foreground">{wager.market || "Market"} / {wager.book || "Book"}</p>
        </div>
        <span className="rounded-sm bg-secondary/15 px-2 py-1 text-sm font-black text-secondary">
          {formatAmericanOdds(wager.americanOdds)}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
        <MetricCell label="Stake" value={formatMoney(wager.stake)} tone="amber" />
        <MetricCell label="Upside" value={formatMoney(wager.potentialProfit)} />
        <MetricCell label="Edge" value={wager.modelEdgePct == null ? "-" : `${wager.modelEdgePct.toFixed(1)}%`} tone={wager.modelEdgePct == null || wager.modelEdgePct >= 0 ? "green" : "red"} />
      </div>
      <div className="mt-3 text-xs leading-relaxed text-muted-foreground">{wager.notes || "No note recorded."}</div>
    </article>
  );
}

function LedgerRow({ wager }: { wager: TrackedWager }) {
  const resultClass =
    wager.status === "win"
      ? "text-primary"
      : wager.status === "loss"
        ? "text-red-300"
        : wager.status === "push"
          ? "text-secondary"
          : "text-muted-foreground";
  return (
    <tr className="border-t border-white/5">
      <td className="p-3 tabular-nums text-muted-foreground">{wager.date || "-"}</td>
      <td className="p-3 font-semibold">{wager.selection}</td>
      <td className="p-3">{wager.sport || "-"}</td>
      <td className="p-3">{wager.market || "-"}</td>
      <td className="p-3 tabular-nums">{formatAmericanOdds(wager.americanOdds)}</td>
      <td className="p-3 tabular-nums">{formatMoney(wager.stake)}</td>
      <td className={`p-3 font-black uppercase ${resultClass}`}>{wager.status}</td>
      <td className={wager.profit >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>{formatMoney(wager.profit)}</td>
      <td className={wager.modelEdgePct == null ? "p-3 text-muted-foreground" : wager.modelEdgePct >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>
        {wager.modelEdgePct == null ? "-" : `${wager.modelEdgePct.toFixed(2)}%`}
      </td>
      <td className={wager.clvPct == null ? "p-3 text-muted-foreground" : wager.clvPct >= 0 ? "p-3 font-black text-primary" : "p-3 font-black text-red-300"}>
        {wager.clvPct == null ? "-" : `${wager.clvPct.toFixed(2)} pts`}
      </td>
      <td className="p-3">{wager.book || "-"}</td>
    </tr>
  );
}

type SegmentSummary = {
  key: string;
  rows: number;
  openRows: number;
  settledRows: number;
  openExposure: number;
  settledStake: number;
  settledProfit: number;
  roiPct: number;
  avgEdgePct: number | null;
  avgClvPct: number | null;
};

function summarizeSegments(wagers: TrackedWager[], pickKey: (wager: TrackedWager) => string): SegmentSummary[] {
  const groups = new Map<string, TrackedWager[]>();
  wagers.forEach((wager) => {
    const key = pickKey(wager) || "Unspecified";
    groups.set(key, [...(groups.get(key) ?? []), wager]);
  });

  return Array.from(groups.entries())
    .map(([key, rows]) => {
      const settledRows = rows.filter((row) => row.isSettled);
      const settledStake = settledRows.reduce((sum, row) => sum + row.stake, 0);
      const settledProfit = settledRows.reduce((sum, row) => sum + row.profit, 0);
      const edgeRows = rows.filter((row) => row.modelEdgePct != null);
      const clvRows = rows.filter((row) => row.clvPct != null);
      return {
        key,
        rows: rows.length,
        openRows: rows.filter((row) => row.isOpen).length,
        settledRows: settledRows.length,
        openExposure: rows.reduce((sum, row) => sum + row.exposure, 0),
        settledStake,
        settledProfit,
        roiPct: settledStake ? (settledProfit / settledStake) * 100 : 0,
        avgEdgePct: edgeRows.length ? edgeRows.reduce((sum, row) => sum + (row.modelEdgePct ?? 0), 0) / edgeRows.length : null,
        avgClvPct: clvRows.length ? clvRows.reduce((sum, row) => sum + (row.clvPct ?? 0), 0) / clvRows.length : null,
      };
    })
    .sort((a, b) => b.settledProfit - a.settledProfit || b.openExposure - a.openExposure || a.key.localeCompare(b.key));
}

function buildInsightCards(summary: ReturnType<typeof summarizeLedger>, bySport: SegmentSummary[], byBook: SegmentSummary[]) {
  const topOpenSport = [...bySport].sort((a, b) => b.openExposure - a.openExposure)[0];
  const bestSettledSport = [...bySport].sort((a, b) => b.settledProfit - a.settledProfit)[0];
  const topBook = [...byBook].sort((a, b) => b.settledStake - a.settledStake)[0];

  return [
    {
      title: "Risk concentration",
      value: topOpenSport?.openExposure ? topOpenSport.key : "No open risk",
      detail: topOpenSport?.openExposure
        ? `${formatMoney(topOpenSport.openExposure)} across ${topOpenSport.openRows} open row${topOpenSport.openRows === 1 ? "" : "s"}`
        : "No unsettled positions are currently in the ledger.",
      tone: topOpenSport?.openExposure && summary.exposurePct > 10 ? ("red" as const) : ("amber" as const),
    },
    {
      title: "Execution quality",
      value: summary.avgClvPct == null ? "Not enough data" : `${summary.avgClvPct.toFixed(2)} pts CLV`,
      detail:
        summary.avgModelEdgePct == null
          ? "Add model_probability values to measure how far your estimates are from market-implied probability."
          : `Average model edge ${summary.avgModelEdgePct.toFixed(2)}% across priced rows.`,
      tone: summary.avgClvPct != null && summary.avgClvPct >= 0 ? ("green" as const) : ("amber" as const),
    },
    {
      title: "Best settled segment",
      value: bestSettledSport?.settledRows ? bestSettledSport.key : "No settled results",
      detail: bestSettledSport?.settledRows
        ? `${formatMoney(bestSettledSport.settledProfit)} return at ${bestSettledSport.roiPct.toFixed(1)}% ROI. ${topBook?.key ? `Most volume: ${topBook.key}.` : ""}`
        : "Grade a few rows to see which sports or sources are driving outcomes.",
      tone: bestSettledSport?.settledProfit && bestSettledSport.settledProfit >= 0 ? ("green" as const) : ("amber" as const),
    },
  ];
}

function InsightCard({
  title,
  value,
  detail,
  tone,
}: {
  title: string;
  value: string;
  detail: string;
  tone: "green" | "amber" | "red";
}) {
  const toneClass = {
    green: "border-primary/25 bg-primary/5",
    amber: "border-secondary/25 bg-secondary/5",
    red: "border-red-500/25 bg-red-500/5",
  }[tone];
  const iconClass = {
    green: "text-primary",
    amber: "text-secondary",
    red: "text-red-300",
  }[tone];

  return (
    <article className={`rounded-lg border p-4 ${toneClass}`}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-[10px] uppercase tracking-[0.22em] text-muted-foreground">{title}</div>
          <div className="mt-1 text-lg font-black">{value}</div>
        </div>
        <ArrowUpRight className={`h-5 w-5 shrink-0 ${iconClass}`} />
      </div>
      <p className="mt-3 text-xs leading-relaxed text-muted-foreground">{detail}</p>
    </article>
  );
}

function SegmentTable({ rows, valueLabel }: { rows: SegmentSummary[]; valueLabel: string }) {
  if (!rows.length) {
    return <div className="p-4 text-sm text-muted-foreground">No segment data available yet.</div>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[520px] text-sm">
        <thead className="bg-white/[0.035] text-left text-[10px] uppercase tracking-wide text-muted-foreground">
          <tr>
            <th className="p-3">{valueLabel}</th>
            <th className="p-3">Rows</th>
            <th className="p-3">Open risk</th>
            <th className="p-3">Return</th>
            <th className="p-3">ROI</th>
            <th className="p-3">Avg edge</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.key} className="border-t border-white/5">
              <td className="p-3 font-semibold">{row.key}</td>
              <td className="p-3 tabular-nums">{row.rows}</td>
              <td className="p-3 tabular-nums">{formatMoney(row.openExposure)}</td>
              <td className={row.settledProfit >= 0 ? "p-3 tabular-nums text-primary" : "p-3 tabular-nums text-red-300"}>
                {formatMoney(row.settledProfit)}
              </td>
              <td className={row.roiPct >= 0 ? "p-3 tabular-nums text-primary" : "p-3 tabular-nums text-red-300"}>
                {row.settledRows ? `${row.roiPct.toFixed(1)}%` : "-"}
              </td>
              <td className="p-3 tabular-nums text-muted-foreground">
                {row.avgEdgePct == null ? "-" : `${row.avgEdgePct.toFixed(1)}%`}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
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
  icon: typeof WalletCards;
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

function parseWagerCsv(csvText: string): { validRows: WagerInput[]; invalidRows: number; errors: string[] } {
  if (!csvText.trim()) return { validRows: [], invalidRows: 0, errors: [] };
  const parsed = Papa.parse<Record<string, string>>(csvText.trim(), {
    header: true,
    skipEmptyLines: true,
    transformHeader: (header) => header.trim().toLowerCase(),
  });
  const rows = parsed.data.map(csvRecordToWager);
  const validRows = rows.filter(isValidWagerInput);
  return {
    validRows,
    invalidRows: rows.length - validRows.length,
    errors: parsed.errors.map((error) => error.message),
  };
}

function csvRecordToWager(record: Record<string, string>): WagerInput {
  const closingRaw = pick(record, ["closing_odds", "closing_price", "close", "close_odds"]);
  const closingOdds = closingRaw ? parseLedgerOdds(closingRaw) : NaN;
  return {
    date: pick(record, ["date", "event_date", "settled_at"]),
    sport: pick(record, ["sport", "league"]),
    selection: pick(record, ["selection", "pick", "team", "name"]),
    market: pick(record, ["market", "bet_type", "type"]) || "Moneyline",
    americanOdds: parseLedgerOdds(pick(record, ["american_odds", "odds", "price", "line"])),
    stake: Number(pick(record, ["stake", "risk", "amount"]) || "0"),
    status: normalizeWagerStatus(pick(record, ["status", "result", "outcome", "grade"])),
    modelProbability: parseLedgerProbability(pick(record, ["model_probability", "model_probability_pct", "probability", "prob", "win_probability"])),
    closingOdds: Number.isFinite(closingOdds) && closingOdds !== 0 ? closingOdds : null,
    book: pick(record, ["book", "sportsbook", "bookmaker"]),
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

function readStoredLedger(): StoredLedger {
  if (typeof window === "undefined") return { startingBankroll: "1000", csvText: SAMPLE_CSV };
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "");
    return {
      startingBankroll: String(parsed?.startingBankroll ?? "1000"),
      csvText: String(parsed?.csvText ?? SAMPLE_CSV),
    };
  } catch {
    return { startingBankroll: "1000", csvText: SAMPLE_CSV };
  }
}
