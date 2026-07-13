import { PreliminaryChip } from "@/components/PreliminaryChip";
import { ProbabilityBar } from "@/components/ProbabilityBar";
import { cn } from "@/lib/utils";
import type { LiveEvent } from "@/types";

export function LiveScoreCard({
  event,
  prediction,
  preliminary = false,
}: {
  event: LiveEvent;
  /** Model win probabilities for this event, when the model has them. */
  prediction?: { home: number; draw: number; away: number };
  /** True while the prediction feed is placeholder output. */
  preliminary?: boolean;
}) {
  const isLive = event.state === "in";
  return (
    <div className="surface-card p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        {/* Green = the one accent; red stays reserved for losses. */}
        <span
          className={cn("chip", isLive ? "bg-gain/15 text-gain" : "bg-muted text-muted-foreground")}
        >
          {isLive && (
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-current" aria-hidden="true" />
          )}
          {event.status_short || event.status}
        </span>
        {event.venue && <span className="label-mono ml-2 truncate">{event.venue}</span>}
      </div>

      <div className="space-y-2">
        <Row team={event.home_team} score={event.home_score} record={event.home_record} />
        <Row team={event.away_team} score={event.away_score} record={event.away_record} />
      </div>

      {prediction && (
        <div className="mt-3 space-y-1.5">
          <ProbabilityBar
            probs={prediction}
            labels={{ home: event.home_team, away: event.away_team }}
          />
          {preliminary && <PreliminaryChip />}
        </div>
      )}

      {event.broadcasts && event.broadcasts.length > 0 && (
        <div className="label-mono mt-3">{event.broadcasts.join(" · ")}</div>
      )}
    </div>
  );
}

function Row({ team, score, record }: { team: string; score: string; record?: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0">
        <div className="truncate text-sm font-semibold text-card-foreground">{team}</div>
        {record && <div className="label-mono mt-0.5 tabular-nums">{record}</div>}
      </div>
      <div className="num-hero text-card-foreground">{score || "–"}</div>
    </div>
  );
}
