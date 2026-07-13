import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { Loader2, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { loadCatalog, type CatalogEntry } from "@/lib/catalog";
import { DATASETS, loadDataset, getState } from "@/lib/parquetData";
import { downloadCsv } from "@/lib/download";

interface DictRow {
  dataset_id: string;
  dataset_name: string;
  field_name: string;
  source_field_name: string;
  data_type: string;
  description: string;
  example_value: string;
  classification: "raw" | "normalized" | "derived" | "lineage";
}

const LINEAGE_FIELDS = new Set([
  "source_api",
  "source_endpoint",
  "source_file",
  "source_fetched_at_utc",
  "ingested_at_utc",
  "schema_version",
]);

export default function Dictionary() {
  const [params, setParams] = useSearchParams();
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  const [rows, setRows] = useState<DictRow[]>([]);
  const [loading, setLoading] = useState(true);
  const dsParam = params.get("dataset");

  useEffect(() => {
    loadCatalog().then((c) => setEntries(c.entries));
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      const targets = DATASETS.filter((d) => !dsParam || d.id === dsParam);
      await Promise.allSettled(targets.map((d) => loadDataset(d.id)));
      if (cancelled) return;
      const out: DictRow[] = [];
      for (const d of targets) {
        const s = getState(d.id);
        for (const col of s.columns) {
          const isLineage = LINEAGE_FIELDS.has(col.name);
          out.push({
            dataset_id: d.id,
            dataset_name: d.display_name,
            field_name: col.name,
            source_field_name: col.name,
            data_type: col.type,
            description: "Domain review required.",
            example_value: "",
            classification: isLineage ? "lineage" : "normalized",
          });
        }
      }
      if (!cancelled) {
        setRows(out);
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [dsParam]);

  const datasetOptions = useMemo(
    () => [{ id: "", name: "All datasets" }, ...entries.map((e) => ({ id: e.dataset_id, name: e.display_name }))],
    [entries],
  );

  return (
    <div className="space-y-5">
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold">Data dictionary</h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Every field from every loaded dataset. Descriptions marked “Domain review required” are awaiting input
            from a baseball or basketball reviewer.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <select
            className="bg-background border border-white/10 rounded-md px-3 min-h-[44px] text-sm"
            value={dsParam ?? ""}
            onChange={(e) => {
              const v = e.target.value;
              if (v) setParams({ dataset: v });
              else setParams({});
            }}
          >
            {datasetOptions.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
          </select>
          <Button
            variant="outline"
            className="gap-2"
            onClick={() => downloadCsv("data_dictionary.csv", rows as unknown as Record<string, unknown>[])}
            disabled={rows.length === 0}
          >
            <Download className="w-4 h-4" /> CSV
          </Button>
        </div>
      </header>

      {loading ? (
        <div className="surface-card p-6 text-sm text-muted-foreground flex items-center gap-2">
          <Loader2 className="w-4 h-4 animate-spin" /> Loading schema…
        </div>
      ) : rows.length === 0 ? (
        <div className="surface-card p-6 text-sm text-muted-foreground">No fields available yet.</div>
      ) : (
        <div className="surface-card overflow-auto">
          <table className="w-full text-sm">
            <thead className="bg-white/5 sticky top-0">
              <tr>
                {["Dataset", "Field", "Type", "Class", "Description"].map((h) => (
                  <th key={h} className="text-left p-2 font-medium text-muted-foreground">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i} className="border-t border-white/5">
                  <td className="p-2 text-muted-foreground">{r.dataset_name}</td>
                  <td className="p-2 font-mono text-xs">{r.field_name}</td>
                  <td className="p-2 text-muted-foreground">{r.data_type}</td>
                  <td className="p-2">
                    <span className="chip bg-white/5 border border-white/10 text-foreground/80">{r.classification}</span>
                  </td>
                  <td className="p-2 text-muted-foreground">{r.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
