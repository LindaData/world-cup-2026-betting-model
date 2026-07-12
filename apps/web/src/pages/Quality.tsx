import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { loadCatalog, type CatalogEntry } from "@/lib/catalog";

export default function Quality() {
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  useEffect(() => {
    loadCatalog().then((c) => setEntries(c.entries));
  }, []);

  return (
    <div className="space-y-5">
      <header>
        <h1 className="text-2xl md:text-3xl font-bold">Data quality</h1>
        <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
          High-level quality snapshot per dataset. Run the full quality report inside Explore → Quality for duplicate
          keys, null percentages, type-conversion failures, and sport-specific checks.
        </p>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {entries.map((e) => (
          <article key={e.dataset_id} className="surface-card p-4">
            <header className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <h3 className="font-semibold text-card-foreground truncate">{e.display_name}</h3>
                <p className="text-[11px] text-muted-foreground">
                  {e.sport} · {e.entity}
                  {e.season ? ` · ${e.season}` : ""}
                </p>
              </div>
              <span className={chip(e.availability_status)}>{e.availability_status}</span>
            </header>
            <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-0.5 text-[11px]">
              <DT label="Quality report" value={e.quality_url ? "Published" : "Pending"} />
              <DT label="Schema doc" value={e.schema_url ? "Published" : "Pending"} />
              <DT label="Profile" value={e.profile_url ? "Published" : "Pending"} />
              <DT label="Primary key" value={e.primary_key ?? "—"} />
            </dl>
            <p className="text-[11px] text-muted-foreground mt-3">
              Problems are reported here only — Game Stat Pulse never deletes, corrects, or imputes records.
            </p>
            <div className="mt-3">
              <Link
                to={`/explore?dataset=${e.dataset_id}&tab=quality`}
                className="text-primary text-sm font-medium hover:underline"
              >
                Open full quality report →
              </Link>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}

function DT({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-card-foreground text-right truncate">{value}</dd>
    </>
  );
}
function chip(s: string) {
  const base = "chip ";
  if (s === "available") return base + "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30";
  if (s === "degraded") return base + "bg-amber-500/15 text-amber-300 border border-amber-500/30";
  return base + "bg-red-500/15 text-red-300 border border-red-500/30";
}
