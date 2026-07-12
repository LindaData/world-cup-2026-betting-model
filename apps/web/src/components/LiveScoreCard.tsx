import type { LiveEvent } from "@/types";

export function LiveScoreCard({ event }: { event: LiveEvent }) {
  const isPost = event.state === "post";
  const isLive = event.state === "in";
  return (
    <div className="surface-card p-4">
      <div className="flex items-center justify-between mb-3">
        <span
          className={`chip ${
            isLive
              ? "bg-red-100 text-red-700"
              : isPost
                ? "bg-slate-100 text-slate-700"
                : "bg-primary/15 text-primary"
          }`}
        >
          {isLive && <span className="w-1.5 h-1.5 rounded-full bg-current animate-pulse" />}
          {event.status_short || event.status}
        </span>
        {event.venue && (
          <span className="text-[11px] text-muted-foreground truncate ml-2">{event.venue}</span>
        )}
      </div>
      <div className="space-y-2">
        <Row team={event.away_team} score={event.away_score} record={event.away_record} />
        <Row team={event.home_team} score={event.home_score} record={event.home_record} />
      </div>
      {event.broadcasts && event.broadcasts.length > 0 && (
        <div className="mt-3 text-[11px] text-muted-foreground">
          {event.broadcasts.join(" • ")}
        </div>
      )}
    </div>
  );
}

function Row({ team, score, record }: { team: string; score: string; record?: string }) {
  return (
    <div className="flex items-center justify-between">
      <div className="min-w-0">
        <div className="font-medium text-card-foreground truncate">{team}</div>
        {record && <div className="text-[11px] text-muted-foreground">{record}</div>}
      </div>
      <div className="text-2xl font-bold tabular-nums text-card-foreground ml-3">{score || "–"}</div>
    </div>
  );
}
