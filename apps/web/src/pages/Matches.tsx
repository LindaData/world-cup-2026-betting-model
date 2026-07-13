import { lazy, Suspense } from "react";
import { useSearchParams } from "react-router-dom";
import { cn } from "@/lib/utils";
import { SPORT_LABELS } from "@/lib/sports";
import { Skeleton } from "@/components/ui/skeleton";
import { GamesViewVariantContext } from "@/components/GamesView";

const Football = lazy(() => import("./Football"));
const NBA = lazy(() => import("./NBA"));
const MLB = lazy(() => import("./MLB"));

// Labels come from the shared sports constant so every tab, table, and ledger
// calls the same sport by the same name ("Soccer", not "Football").
const SPORTS = [
  { key: "football", label: SPORT_LABELS.football, Page: Football },
  { key: "nba", label: SPORT_LABELS.nba, Page: NBA },
  { key: "mlb", label: SPORT_LABELS.mlb, Page: MLB },
] as const;

type SportKey = (typeof SPORTS)[number]["key"];

export default function Matches() {
  const [params, setParams] = useSearchParams();
  const raw = (params.get("sport") ?? "football").toLowerCase();
  const sport: SportKey = SPORTS.some((s) => s.key === raw)
    ? (raw as SportKey)
    : "football";
  const Page = SPORTS.find((s) => s.key === sport)!.Page;

  const selectSport = (key: SportKey) => {
    const next = new URLSearchParams(params);
    if (key === "football") next.delete("sport");
    else next.set("sport", key);
    setParams(next, { replace: true });
  };

  return (
    <div className="space-y-5">
      <div
        role="group"
        aria-label="Choose a sport"
        className="inline-flex rounded-lg border border-border bg-card p-1"
      >
        {SPORTS.map((s) => (
          <button
            key={s.key}
            type="button"
            aria-pressed={s.key === sport}
            onClick={() => selectSport(s.key)}
            className={cn(
              "min-h-11 rounded-md px-4 text-sm font-semibold transition-colors",
              s.key === sport
                ? "bg-muted text-primary"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {s.label}
          </button>
        ))}
      </div>

      {/* Soccer reads as a grouped feed ("Up next" then "Played") with no
          sort chips; NBA/MLB keep their sortable schedule view. */}
      <GamesViewVariantContext.Provider
        value={sport === "football" ? "grouped" : "sortable"}
      >
        <Suspense fallback={<MatchesSkeleton />}>
          <Page />
        </Suspense>
      </GamesViewVariantContext.Provider>
    </div>
  );
}

function MatchesSkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-8 w-48" />
      <Skeleton className="h-40 w-full" />
      <Skeleton className="h-64 w-full" />
    </div>
  );
}
