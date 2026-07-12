import { useMemo, useState } from "react";
import { ArrowUpDown } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import type { GameRow } from "@/types";

type SortKey = "date_utc" | "home_team" | "away_team" | "home_score" | "away_score";

export function GamesView({ rows }: { rows: GameRow[] }) {
  const [q, setQ] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("date_utc");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("desc");
  const [page, setPage] = useState(0);
  const pageSize = 25;

  const filtered = useMemo(() => {
    const ql = q.trim().toLowerCase();
    const f = ql
      ? rows.filter(
          (r) =>
            r.home_team?.toLowerCase().includes(ql) ||
            r.away_team?.toLowerCase().includes(ql) ||
            r.date_utc?.toLowerCase().includes(ql),
        )
      : rows;
    const sorted = [...f].sort((a, b) => {
      const av = a[sortKey] ?? "";
      const bv = b[sortKey] ?? "";
      const cmp = av.localeCompare(bv, undefined, { numeric: true });
      return sortDir === "asc" ? cmp : -cmp;
    });
    return sorted;
  }, [rows, q, sortKey, sortDir]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const safePage = Math.min(page, totalPages - 1);
  const slice = filtered.slice(safePage * pageSize, safePage * pageSize + pageSize);

  const toggleSort = (k: SortKey) => {
    if (k === sortKey) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(k);
      setSortDir(k === "date_utc" ? "desc" : "asc");
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-col sm:flex-row gap-2 sm:items-center sm:justify-between">
        <Input
          placeholder="Search team or date…"
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setPage(0);
          }}
          className="sm:max-w-xs bg-card text-card-foreground"
        />
        <div className="text-xs text-muted-foreground">
          {filtered.length.toLocaleString()} games
        </div>
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-2">
        {slice.map((g) => (
          <div key={g.game_id} className="surface-card p-3">
            <div className="flex justify-between text-[11px] text-muted-foreground mb-1.5">
              <span>{formatDate(g.date_utc)}</span>
              <span>{g.status}</span>
            </div>
            <div className="grid grid-cols-[1fr_auto] gap-y-1 items-center">
              <div className="font-medium text-card-foreground truncate">{g.away_team}</div>
              <div className="font-bold tabular-nums text-card-foreground">{g.away_score}</div>
              <div className="font-medium text-card-foreground truncate">{g.home_team}</div>
              <div className="font-bold tabular-nums text-card-foreground">{g.home_score}</div>
            </div>
          </div>
        ))}
        {slice.length === 0 && (
          <div className="text-center text-sm text-muted-foreground py-8">No games match.</div>
        )}
      </div>

      {/* Desktop table */}
      <div className="hidden md:block surface-card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-card-foreground">
            <tr>
              <Th onClick={() => toggleSort("date_utc")}>Date</Th>
              <Th onClick={() => toggleSort("away_team")}>Away</Th>
              <Th onClick={() => toggleSort("away_score")} className="text-right">Score</Th>
              <Th onClick={() => toggleSort("home_team")}>Home</Th>
              <Th onClick={() => toggleSort("home_score")} className="text-right">Score</Th>
              <th className="px-3 py-2 text-left font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {slice.map((g) => (
              <tr key={g.game_id} className="border-t border-black/5 text-card-foreground">
                <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">{formatDate(g.date_utc)}</td>
                <td className="px-3 py-2">{g.away_team}</td>
                <td className="px-3 py-2 text-right tabular-nums font-medium">{g.away_score}</td>
                <td className="px-3 py-2">{g.home_team}</td>
                <td className="px-3 py-2 text-right tabular-nums font-medium">{g.home_score}</td>
                <td className="px-3 py-2 text-muted-foreground">{g.status}</td>
              </tr>
            ))}
            {slice.length === 0 && (
              <tr>
                <td colSpan={6} className="text-center py-6 text-muted-foreground">
                  No games match.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <Button
          variant="outline"
          size="sm"
          disabled={safePage === 0}
          onClick={() => setPage((p) => Math.max(0, p - 1))}
        >
          Prev
        </Button>
        <span>
          Page {safePage + 1} / {totalPages}
        </span>
        <Button
          variant="outline"
          size="sm"
          disabled={safePage >= totalPages - 1}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </Button>
      </div>
    </div>
  );
}

function Th({
  children,
  onClick,
  className = "",
}: {
  children: React.ReactNode;
  onClick?: () => void;
  className?: string;
}) {
  return (
    <th
      onClick={onClick}
      className={`px-3 py-2 text-left font-medium cursor-pointer select-none ${className}`}
    >
      <span className="inline-flex items-center gap-1">
        {children}
        <ArrowUpDown className="w-3 h-3 opacity-50" />
      </span>
    </th>
  );
}

function formatDate(iso: string) {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
