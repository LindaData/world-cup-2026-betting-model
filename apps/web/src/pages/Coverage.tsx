import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { loadCatalog, type CatalogEntry } from "@/lib/catalog";
import { downloadCsv } from "@/lib/download";
import { Button } from "@/components/ui/button";
import { Download } from "lucide-react";

export default function Coverage() {
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  useEffect(() => {
    loadCatalog().then((c) => setEntries(c.entries));
  }, []);

  const matrix = useMemo(() => {
    const rows: { sport: string; league: string; season: string; entity: string; rows: number | null; coverage: string; status: string; dataset_id: string }[] = [];
    for (const e of entries) {
      rows.push({
        sport: e.sport,
        league: e.league_name ?? "—",
        season: e.season ?? "—",
        entity: e.entity,
        rows: e.row_count,
        coverage:
          e.earliest_date || e.latest_date
            ? `${e.earliest_date ?? "?"} → ${e.latest_date ?? "?"}`
            : "—",
        status: e.availability_status,
        dataset_id: e.dataset_id,
      });
    }
    return rows.sort(
      (a, b) =>
        a.sport.localeCompare(b.sport) ||
        a.league.localeCompare(b.league) ||
        a.season.localeCompare(b.season) ||
        a.entity.localeCompare(b.entity),
    );
  }, [entries]);

  return (
    <div className="space-y-5">
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold">Data coverage</h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Which sports, leagues, seasons, and entities currently have data — and which do not.
          </p>
        </div>
        <Button
          variant="outline"
          className="gap-2"
          onClick={() => downloadCsv("coverage_matrix.csv", matrix as unknown as Record<string, unknown>[])}
        >
          <Download className="w-4 h-4" /> CSV
        </Button>
      </header>

      {/* Mobile cards */}
      <div className="md:hidden space-y-2">
        {matrix.map((r) => (
          <Link
            key={r.dataset_id}
            to={`/explore?dataset=${r.dataset_id}`}
            className="surface-card p-3 block"
          >
            <div className="flex items-center justify-between gap-2">
              <div className="font-medium text-card-foreground truncate">
                {r.sport} · {r.entity}
              </div>
              <span className={statusChip(r.status)}>{r.status}</span>
            </div>
            <div className="text-[11px] text-muted-foreground mt-1">
              {r.league} · {r.season} · {(r.rows ?? 0).toLocaleString()} rows
            </div>
            <div className="text-[11px] text-muted-foreground">{r.coverage}</div>
          </Link>
        ))}
      </div>

      {/* Desktop table */}
      <div className="hidden md:block surface-card overflow-auto">
        <table className="w-full text-sm">
          <thead className="bg-white/5">
            <tr>
              {["Sport", "League", "Season", "Entity", "Rows", "Coverage", "Status"].map((h) => (
                <th key={h} className="text-left p-2 font-medium text-muted-foreground">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {matrix.map((r) => (
              <tr key={r.dataset_id} className="border-t border-white/5 hover:bg-white/[0.03]">
                <td className="p-2">{r.sport}</td>
                <td className="p-2">{r.league}</td>
                <td className="p-2">{r.season}</td>
                <td className="p-2">{r.entity}</td>
                <td className="p-2 tabular-nums">{r.rows == null ? "—" : r.rows.toLocaleString()}</td>
                <td className="p-2 text-muted-foreground">{r.coverage}</td>
                <td className="p-2">
                  <span className={statusChip(r.status)}>{r.status}</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function statusChip(s: string) {
  const base = "chip ";
  if (s === "available") return base + "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30";
  if (s === "degraded") return base + "bg-amber-500/15 text-amber-300 border border-amber-500/30";
  return base + "bg-red-500/15 text-red-300 border border-red-500/30";
}
