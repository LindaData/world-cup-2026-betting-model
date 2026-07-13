import { useEffect, useState } from "react";
import { Trash2, Download, FileJson } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  clearBasket,
  listBasket,
  removeItem,
  subscribeBasket,
  updateItem,
  type BasketItem,
  type ReviewStatus,
} from "@/lib/reviewBasket";
import { downloadCsv, downloadJson } from "@/lib/download";
import { toast } from "@/hooks/use-toast";

const STATUS_OPTIONS: { value: ReviewStatus; label: string }[] = [
  { value: "unmarked", label: "Unmarked" },
  { value: "looks_correct", label: "Looks correct" },
  { value: "needs_explanation", label: "Needs explanation" },
  { value: "possible_data_issue", label: "Possible data issue" },
  { value: "important_for_modeling", label: "Important for modeling" },
];

export default function ReviewBasket() {
  const [items, setItems] = useState<BasketItem[]>([]);
  const [loading, setLoading] = useState(true);

  const reload = async () => {
    setItems(await listBasket());
    setLoading(false);
  };

  useEffect(() => {
    reload();
    return subscribeBasket(reload);
  }, []);

  const exportCsv = () => {
    const rows = items.map((i) => ({
      basket_id: i.id,
      dataset_id: i.dataset_id,
      dataset_name: i.dataset_name,
      review_status: i.status,
      reviewer_note: i.note,
      added_at: i.added_at,
      ...flatten(i.record),
    }));
    downloadCsv("review_notes.csv", rows);
    toast({ title: "Exported", description: `${rows.length} review notes` });
  };

  const exportJson = () => {
    downloadJson("review_basket.json", items);
  };

  return (
    <div className="space-y-5">
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold">Review basket</h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Records you've flagged for review. Stored locally on this device (IndexedDB). Add notes, mark a status,
            then export everything as a single CSV for hand-off to the domain reviewer.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" className="gap-2" disabled={!items.length} onClick={exportCsv}>
            <Download className="w-4 h-4" /> review_notes.csv
          </Button>
          <Button variant="outline" className="gap-2" disabled={!items.length} onClick={exportJson}>
            <FileJson className="w-4 h-4" /> JSON
          </Button>
          <Button
            variant="outline"
            className="gap-2"
            disabled={!items.length}
            onClick={async () => {
              if (confirm("Clear the entire review basket?")) {
                await clearBasket();
              }
            }}
          >
            <Trash2 className="w-4 h-4" /> Clear
          </Button>
        </div>
      </header>

      {loading ? (
        <div className="surface-card p-6 text-sm text-muted-foreground">Loading…</div>
      ) : items.length === 0 ? (
        <div className="surface-card p-6 text-sm text-muted-foreground">
          Your basket is empty. Open a dataset in Explore, tap a record, and use “Add to review basket” to start a
          review list.
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((item) => (
            <article key={item.id} className="surface-card p-4 space-y-2">
              <header className="flex items-start justify-between gap-2 flex-wrap">
                <div className="min-w-0">
                  <div className="text-[11px] uppercase tracking-wider text-muted-foreground">
                    {item.dataset_name}
                  </div>
                  <div className="font-semibold text-card-foreground truncate">
                    {summarise(item.record)}
                  </div>
                  <div className="text-[11px] text-muted-foreground">
                    Added {new Date(item.added_at).toLocaleString()}
                  </div>
                </div>
                <div className="flex gap-2">
                  <select
                    value={item.status}
                    onChange={(e) => updateItem(item.id, { status: e.target.value as ReviewStatus })}
                    className="bg-background border border-white/10 rounded-md px-2 min-h-[40px] text-xs"
                  >
                    {STATUS_OPTIONS.map((o) => (
                      <option key={o.value} value={o.value}>
                        {o.label}
                      </option>
                    ))}
                  </select>
                  <Button variant="ghost" size="sm" onClick={() => removeItem(item.id)} aria-label="Remove">
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </header>
              <Textarea
                placeholder="Reviewer note (e.g. score looks off, missing scheduling info, etc.)"
                value={item.note}
                onChange={(e) => updateItem(item.id, { note: e.target.value })}
                className="min-h-[60px]"
              />
              <details className="text-xs">
                <summary className="cursor-pointer text-muted-foreground">All fields</summary>
                <pre className="mt-2 bg-black/30 rounded-md p-2 overflow-auto text-[11px] max-h-72">
                  {JSON.stringify(item.record, null, 2)}
                </pre>
              </details>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}

function summarise(r: Record<string, unknown>): string {
  const keys = ["display_name", "name", "home_team", "team", "event_id", "game_id", "team_id"];
  for (const k of keys) {
    if (r[k]) {
      const away = r["away_team"];
      if (k === "home_team" && away) return `${r[k]} vs ${away}`;
      return String(r[k]);
    }
  }
  const k = Object.keys(r)[0];
  return k ? `${k}: ${String(r[k])}` : "(record)";
}

function flatten(obj: Record<string, unknown>, prefix = "record."): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      Object.assign(out, flatten(v as Record<string, unknown>, `${prefix}${k}.`));
    } else {
      out[`${prefix}${k}`] = Array.isArray(v) ? JSON.stringify(v) : v;
    }
  }
  return out;
}
