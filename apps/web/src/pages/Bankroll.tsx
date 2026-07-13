import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Papa from "papaparse";
import { AlertTriangle, ChevronDown, Download, PenLine } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PageHeader } from "@/components/PageHeader";
import { PortfolioSubNav } from "@/components/PortfolioSubNav";
import { StatusChip } from "@/components/StatusBadge";
import { downloadCsv } from "@/lib/download";
import { formatAmericanOdds, formatMoney, formatPercent } from "@/lib/edgeMath";
import {
  SAMPLE_LEDGER_CSV,
  isSampleLedgerCsv,
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

const SAMPLE_CSV = SAMPLE_LEDGER_CSV;

type StoredLedger = {
  startingBankroll: string;
  csvText: string;
};

export default function Bankroll() {
  const stored = useMemo(readStoredLedger, []);
  const [startingBankroll, setStartingBankrollState] = useState(stored.startingBankroll);
  const [csvText, setCsvTextState] = useState(stored.csvText);
  const [notice, setNotice] = useState<string | null>(null);
  // The bundled sample is a preview, not the user's ledger: nothing is
  // persisted until they explicitly edit, load the sample, or clear.
  const [persistEnabled, setPersistEnabled] = useState(stored.existed);
  const setCsvText = useCallback((value: string) => {
    setPersistEnabled(true);
    setCsvTextState(value);
  }, []);
  const setStartingBankroll = useCallback((value: string) => {
    setPersistEnabled(true);
    setStartingBankrollState(value);
  }, []);

  const [editorOpen, setEditorOpen] = useState(false);
  const editorRef = useRef<HTMLElement | null>(null);
  const openLedgerEditor = useCallback(() => {
    setEditorOpen(true);
    // Wait a frame for the collapsible content to mount before scrolling.
    window.setTimeout(() => {
      const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
      editorRef.current?.scrollIntoView({
        behavior: reduceMotion ? "auto" : "smooth",
        block: "start",
      });
    }, 0);
  }, []);

  // Today's "Log today's bet" deep-links here with ?log=1.
  const [searchParams] = useSearchParams();
  const wantsEditor = searchParams.get("log") != null;
  useEffect(() => {
    if (wantsEditor) openLedgerEditor();
  }, [wantsEditor, openLedgerEditor]);

  useEffect(() => {
    if (!persistEnabled) return;
    try {
      const payload: StoredLedger = { startingBankroll, csvText };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch {
      /* ignore */
    }
  }, [csvText, persistEnabled, startingBankroll]);

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

  const delta = summary.currentBankroll - summary.startingBankroll;
  const deltaClass = delta > 0 ? "text-gain" : delta < 0 ? "text-loss" : "text-muted-foreground";
  const isSample = isSampleLedgerCsv(csvText);

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-36 lg:pb-0">
      {/* When the whole ledger is the bundled sample, the entire page — open
          positions, insights, settled wagers — is demo data, so one
          page-level chip scopes everything (and the card chip goes away). */}
      <PageHeader
        title="Portfolio"
        badge={isSample ? <StatusChip tone="muted" label="Demo" /> : undefined}
      />
      <PortfolioSubNav active="desk" />

      <header className="surface-card p-4 sm:p-6">
        <div className="label-mono">Bankroll</div>
        <div className="num-hero mt-2">{formatMoney(summary.currentBankroll)}</div>
        <div className={`mt-1 text-sm font-semibold tabular-nums ${deltaClass}`}>
          {delta >= 0 ? "+" : ""}
          {formatMoney(delta)} since start
          {summary.settledStake ? ` · ${summary.roiPct.toFixed(1)}% return on settled stakes` : ""}
        </div>

        <div className="mt-5 grid grid-cols-2 gap-3 border-t border-border pt-4 sm:grid-cols-4">
          <Stat label="Open risk" value={formatMoney(summary.openExposure)} />
          <Stat label="Open positions" value={String(summary.openRows)} />
          <Stat
            label="Settled return"
            value={formatMoney(summary.settledProfit)}
            tone={summary.settledProfit > 0 ? "gain" : summary.settledProfit < 0 ? "loss" : undefined}
          />
          <Stat
            label="Vs final odds"
            value={
              summary.avgClvPct == null
                ? "—"
                : `${summary.avgClvPct > 0 ? "+" : ""}${summary.avgClvPct.toFixed(2)} pts`
            }
          />
        </div>

        {/* Logging a bet is THE action of a betting desk, so it gets the one
            green primary. Export is a utility and stays quiet. On mobile the
            primary is bottom-anchored instead (see the fixed bar below). */}
        <div className="mt-5 flex flex-wrap items-center gap-3">
          <Button className="hidden min-h-11 sm:px-8 lg:inline-flex" onClick={openLedgerEditor}>
            <PenLine className="h-4 w-4" /> Log a bet
          </Button>
          <Button
            variant="outline"
            className="min-h-11 flex-1 sm:flex-none lg:flex-none"
            onClick={exportLedger}
            disabled={!wagers.length}
          >
            <Download className="h-4 w-4" /> Export ledger
          </Button>
          <Link to="/model" className="text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline">
            Open model audit
          </Link>
        </div>
      </header>

      <section className="space-y-3">
        <div className="label-mono px-1">Open positions</div>
        {openWagers.length ? (
          <div className="grid gap-3 md:grid-cols-2">
            {openWagers.slice(0, 8).map((wager, index) => (
              <OpenWagerCard key={`${wager.date}-${wager.selection}-${index}`} wager={wager} />
            ))}
          </div>
        ) : (
          <div className="surface-card p-4 text-sm text-muted-foreground">
            No open positions right now. Rows with status "open" in your ledger will show up here with stake, upside, and model edge.
          </div>
        )}
      </section>

      <section className="space-y-3">
        <div className="label-mono px-1">Insights</div>
        <div className="grid gap-3 md:grid-cols-3">
          {insightCards.map((card) => (
            <InsightCard key={card.title} {...card} />
          ))}
        </div>
      </section>

      <section className="surface-card overflow-hidden">
        <div className="border-b border-border px-4 py-3">
          <div className="label-mono">Settled wagers</div>
        </div>
        {settledWagers.length ? (
          <>
            {/* Mobile: each wager collapses to a stacked card row (profit is the hero). */}
            <ul className="divide-y divide-border md:hidden">
              {settledWagers.map((wager, index) => (
                <SettledWagerRow key={`${wager.date}-${wager.selection}-${index}`} wager={wager} />
              ))}
            </ul>
            {/* Desktop: full table. */}
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full min-w-[980px] text-sm">
                <thead className="text-left">
                  <tr>
                    <Th>Date</Th>
                    <Th>Selection</Th>
                    <Th>Sport</Th>
                    <Th>Market</Th>
                    <Th>Odds</Th>
                    <Th>Stake</Th>
                    <Th>Status</Th>
                    <Th>Profit</Th>
                    <Th>Edge</Th>
                    <Th>Vs final odds</Th>
                    <Th>Book</Th>
                  </tr>
                </thead>
                <tbody>
                  {settledWagers.map((wager, index) => (
                    <LedgerRow key={`${wager.date}-${wager.selection}-${index}`} wager={wager} />
                  ))}
                </tbody>
              </table>
            </div>
          </>
        ) : (
          <div className="p-4 text-sm text-muted-foreground">
            No settled wagers yet. Once rows are graded win, loss, or push they appear here with
            profit, edge, and how your price compared with the final odds.
          </div>
        )}
      </section>

      <section className="surface-card overflow-hidden">
        <Tabs defaultValue="sport">
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-2.5">
            <div className="label-mono">Return by</div>
            <TabsList className="h-9">
              <TabsTrigger value="sport" className="min-h-8 px-4">
                Sport
              </TabsTrigger>
              <TabsTrigger value="book" className="min-h-8 px-4">
                Book
              </TabsTrigger>
            </TabsList>
          </div>
          <TabsContent value="sport" className="mt-0">
            <SegmentTable rows={bySport.slice(0, 6)} valueLabel="Sport" />
          </TabsContent>
          <TabsContent value="book" className="mt-0">
            <SegmentTable rows={byBook.slice(0, 6)} valueLabel="Book" />
          </TabsContent>
        </Tabs>
      </section>

      <section ref={editorRef} className="surface-card scroll-mt-20 p-4 sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="label-mono">Ledger</div>
            <div className="mt-3 flex gap-6">
              <Stat label="Risk of bankroll" value={`${summary.exposurePct.toFixed(1)}%`} />
              <Stat label="Open upside" value={formatMoney(summary.openPotentialProfit)} />
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" className="min-h-11" onClick={() => setCsvText(SAMPLE_CSV)}>
              Load sample
            </Button>
            <Button variant="ghost" className="min-h-11 text-muted-foreground" onClick={() => setCsvText("")}>
              Clear
            </Button>
          </div>
        </div>

        {/* Raw CSV editing is plumbing, not portfolio: closed by default,
            opened by the "Log a bet" primary. */}
        <Collapsible
          className="mt-4 border-t border-border pt-1"
          open={editorOpen}
          onOpenChange={setEditorOpen}
        >
          <CollapsibleTrigger className="group flex min-h-11 w-full items-center justify-between gap-2 text-left text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground">
            Edit ledger
            <ChevronDown
              className="h-4 w-4 transition-transform group-data-[state=open]:rotate-180"
              aria-hidden="true"
            />
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="grid gap-4 pt-3 sm:grid-cols-[220px_minmax(0,1fr)]">
              <label className="block">
                <span className="label-mono">Starting capital $</span>
                <Input
                  value={startingBankroll}
                  onChange={(event) => setStartingBankroll(event.target.value)}
                  inputMode="decimal"
                  className="mt-1 min-h-11 text-lg font-bold tabular-nums"
                />
              </label>
              <div>
                <span className="label-mono">Ledger rows (CSV)</span>
                <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                  Selection, price, and stake are required. Model probability, final odds, sport,
                  book, and notes unlock the deeper views.
                </p>
                <Textarea
                  value={csvText}
                  onChange={(event) => setCsvText(event.target.value)}
                  className="mt-3 min-h-[18rem] font-mono text-xs"
                  placeholder="date,sport,selection,market,american_odds,stake,status,model_probability,closing_odds,book,notes"
                />
                {notice && (
                  <div className="mt-3 flex gap-2 rounded-md border border-border bg-background p-3 text-sm text-muted-foreground">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {notice}
                  </div>
                )}
              </div>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </section>

      {/* Mobile: the one primary action, bottom-anchored above the tab bar. */}
      <div className="fixed inset-x-0 bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-20 border-t border-border bg-background/95 p-3 backdrop-blur lg:hidden">
        <Button className="min-h-11 w-full" onClick={openLedgerEditor}>
          <PenLine className="h-4 w-4" /> Log a bet
        </Button>
      </div>
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

function OpenWagerCard({ wager }: { wager: TrackedWager }) {
  return (
    <article className="surface-card p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="label-mono">{wager.sport || "Sport"}</div>
          <h3 className="truncate text-base font-bold">{wager.selection}</h3>
          <p className="mt-0.5 truncate text-xs text-muted-foreground">
            {wager.market || "Market"} · {wager.book || "Book"}
          </p>
        </div>
        <span className="rounded-md border border-border bg-background px-2 py-1 text-sm font-bold tabular-nums">
          {formatAmericanOdds(wager.americanOdds)}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3 border-t border-border pt-3">
        <Stat label="Stake" value={formatMoney(wager.stake)} />
        <Stat label="Upside" value={formatMoney(wager.potentialProfit)} tone="gain" />
        <Stat label="Edge" value={wager.modelEdgePct == null ? "—" : `${wager.modelEdgePct.toFixed(1)}%`} />
      </div>
      {wager.notes && <div className="mt-3 text-xs leading-relaxed text-muted-foreground">{wager.notes}</div>}
    </article>
  );
}

function LedgerRow({ wager }: { wager: TrackedWager }) {
  const statusClass =
    wager.status === "win" ? "text-gain" : wager.status === "loss" ? "text-loss" : "text-muted-foreground";
  const profitClass = wager.profit > 0 ? "text-gain" : wager.profit < 0 ? "text-loss" : "text-muted-foreground";
  return (
    <tr className="border-t border-border">
      <td className="p-3 tabular-nums text-muted-foreground">{wager.date || "—"}</td>
      <td className="p-3 font-semibold">{wager.selection}</td>
      <td className="p-3 text-muted-foreground">{wager.sport || "—"}</td>
      <td className="p-3 text-muted-foreground">{wager.market || "—"}</td>
      <td className="p-3 tabular-nums">{formatAmericanOdds(wager.americanOdds)}</td>
      <td className="p-3 tabular-nums">{formatMoney(wager.stake)}</td>
      <td className={`p-3 text-xs font-bold uppercase tracking-wide ${statusClass}`}>{wager.status}</td>
      <td className={`p-3 font-bold tabular-nums ${profitClass}`}>{formatMoney(wager.profit)}</td>
      {/* Green only for strictly positive values: the single accent must keep
          its meaning. Zero/negative reads muted (red stays for money losses). */}
      <td className={wager.modelEdgePct != null && wager.modelEdgePct > 0 ? "p-3 tabular-nums text-gain" : "p-3 tabular-nums text-muted-foreground"}>
        {wager.modelEdgePct == null ? "—" : `${wager.modelEdgePct.toFixed(2)}%`}
      </td>
      <td className={wager.clvPct != null && wager.clvPct > 0 ? "p-3 tabular-nums text-gain" : "p-3 tabular-nums text-muted-foreground"}>
        {wager.clvPct == null ? "—" : `${wager.clvPct.toFixed(2)} pts`}
      </td>
      <td className="p-3 text-muted-foreground">{wager.book || "—"}</td>
    </tr>
  );
}

/**
 * Mobile settled-wager row: selection + date on the left, profit as the
 * right-aligned hero, odds/market/book as a muted second line. Nothing is
 * clipped off-screen.
 */
function SettledWagerRow({ wager }: { wager: TrackedWager }) {
  const profitClass = wager.profit > 0 ? "text-gain" : wager.profit < 0 ? "text-loss" : "text-muted-foreground";
  const statusClass =
    wager.status === "win" ? "text-gain" : wager.status === "loss" ? "text-loss" : "text-muted-foreground";
  return (
    <li className="flex items-start justify-between gap-3 p-4">
      <div className="min-w-0">
        <div className="truncate text-sm font-semibold">{wager.selection}</div>
        <div className="mt-0.5 truncate text-xs text-muted-foreground tabular-nums">
          {[wager.date, wager.market, formatAmericanOdds(wager.americanOdds), wager.book]
            .filter(Boolean)
            .join(" · ")}
        </div>
      </div>
      <div className="shrink-0 text-right">
        <div className={`text-lg font-bold tabular-nums ${profitClass}`}>
          {wager.profit > 0 ? "+" : ""}
          {formatMoney(wager.profit)}
        </div>
        <div className={`text-[10px] font-bold uppercase tracking-wide ${statusClass}`}>
          {wager.status}
        </div>
      </div>
    </li>
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
      tone: "neutral" as const,
    },
    // One metric, one unit, plain words: the headline is how far your price
    // ended up from where the odds finished, and the body explains that same
    // number without market jargon.
    {
      title: "Your price vs the final odds",
      value:
        summary.avgClvPct == null
          ? "Not enough data"
          : summary.avgClvPct >= 0
            ? `Better by ${summary.avgClvPct.toFixed(2)} pts`
            : `Worse by ${Math.abs(summary.avgClvPct).toFixed(2)} pts`,
      detail:
        summary.avgClvPct == null
          ? "Add the final odds to each row to see whether you got better prices than where the market ended up."
          : summary.avgClvPct >= 0
            ? "On average you got better prices than where the odds finished — a good sign your bets were placed at the right time."
            : "On average the odds finished better than the prices you took — later bets would have paid more.",
      tone: summary.avgClvPct != null && summary.avgClvPct > 0 ? ("gain" as const) : ("neutral" as const),
    },
    {
      title: "Best settled segment",
      value: bestSettledSport?.settledRows ? bestSettledSport.key : "No settled results",
      detail: bestSettledSport?.settledRows
        ? `${formatMoney(bestSettledSport.settledProfit)} return at ${bestSettledSport.roiPct.toFixed(1)}% ROI. ${topBook?.key ? `Most volume: ${topBook.key}.` : ""}`
        : "Grade a few rows to see which sports or sources are driving outcomes.",
      tone: bestSettledSport?.settledProfit && bestSettledSport.settledProfit >= 0 ? ("gain" as const) : ("neutral" as const),
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
  tone: "gain" | "neutral";
}) {
  return (
    <article className="surface-card p-4">
      <div className="label-mono">{title}</div>
      <div className={`mt-1 text-lg font-bold ${tone === "gain" ? "text-gain" : "text-foreground"}`}>{value}</div>
      <p className="mt-2 text-xs leading-relaxed text-muted-foreground">{detail}</p>
    </article>
  );
}

function SegmentTable({ rows, valueLabel }: { rows: SegmentSummary[]; valueLabel: string }) {
  if (!rows.length) {
    return (
      <div className="p-4 text-sm text-muted-foreground">
        Nothing to break down yet. Add ledger rows and returns by {valueLabel.toLowerCase()} will appear here.
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[440px] text-sm">
        <thead className="text-left">
          <tr>
            <Th>{valueLabel}</Th>
            <Th>Rows</Th>
            <Th>Open risk</Th>
            <Th>Return</Th>
            <Th>ROI</Th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.key} className="border-t border-border">
              <td className="p-3 font-semibold">{row.key}</td>
              <td className="p-3 tabular-nums text-muted-foreground">{row.rows}</td>
              <td className="p-3 tabular-nums">{formatMoney(row.openExposure)}</td>
              <td className={row.settledProfit > 0 ? "p-3 font-semibold tabular-nums text-gain" : row.settledProfit < 0 ? "p-3 font-semibold tabular-nums text-loss" : "p-3 tabular-nums text-muted-foreground"}>
                {formatMoney(row.settledProfit)}
              </td>
              <td className={row.settledRows && row.roiPct > 0 ? "p-3 tabular-nums text-gain" : row.settledRows && row.roiPct < 0 ? "p-3 tabular-nums text-loss" : "p-3 tabular-nums text-muted-foreground"}>
                {row.settledRows ? `${row.roiPct.toFixed(1)}%` : "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
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

/**
 * Reads the persisted ledger. When nothing is stored the bundled sample is
 * shown as a chipped demo preview (`existed: false`) — it is NOT written back
 * to localStorage until the user makes an explicit edit.
 */
function readStoredLedger(): StoredLedger & { existed: boolean } {
  const preview = { startingBankroll: "1000", csvText: SAMPLE_CSV, existed: false };
  if (typeof window === "undefined") return preview;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw == null) return preview;
    const parsed = JSON.parse(raw);
    return {
      startingBankroll: String(parsed?.startingBankroll ?? "1000"),
      csvText: String(parsed?.csvText ?? SAMPLE_CSV),
      existed: true,
    };
  } catch {
    return preview;
  }
}
