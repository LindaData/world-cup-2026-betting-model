import { cn } from "@/lib/utils";

export interface ProbabilitySet {
  home: number;
  draw: number;
  away: number;
}

export interface ProbabilityBarProps {
  /** Model probabilities. Normalized internally, so 0-1 or 0-100 both work. */
  probs: ProbabilitySet;
  /** Optional market-implied probabilities; renders a thinner bar beneath. */
  marketProbs?: ProbabilitySet;
  /** Optional display names used in the accessible label (e.g. team names). */
  labels?: { home?: string; draw?: string; away?: string };
  className?: string;
}

const SEGMENTS = [
  { key: "home", color: "bg-gain text-primary-foreground", dot: "bg-gain" },
  { key: "draw", color: "bg-draw text-foreground/90", dot: "bg-draw" },
  { key: "away", color: "bg-away text-primary-foreground", dot: "bg-away" },
] as const;

/** Hide the in-segment percent label when the segment is too narrow to fit it. */
const MIN_LABEL_PCT = 10;

function normalize(probs: ProbabilitySet): ProbabilitySet {
  const home = Math.max(0, probs.home || 0);
  const draw = Math.max(0, probs.draw || 0);
  const away = Math.max(0, probs.away || 0);
  const total = home + draw + away;
  if (total <= 0) return { home: 0, draw: 0, away: 0 };
  return { home: home / total, draw: draw / total, away: away / total };
}

/**
 * Signature component: one segmented horizontal bar for home/draw/away
 * (green / slate / blue) with percent labels inside the segments. When
 * market probabilities exist, a second thinner bar renders beneath.
 */
export function ProbabilityBar({ probs, marketProbs, labels, className }: ProbabilityBarProps) {
  const model = normalize(probs);
  const market = marketProbs ? normalize(marketProbs) : null;

  const names = {
    home: labels?.home ?? "Home",
    draw: labels?.draw ?? "Draw",
    away: labels?.away ?? "Away",
  };
  const pct = (v: number) => Math.round(v * 100);
  const ariaLabel =
    `Model: ${names.home} ${pct(model.home)}%, ${names.draw} ${pct(model.draw)}%, ${names.away} ${pct(model.away)}%` +
    (market
      ? `. Market: ${names.home} ${pct(market.home)}%, ${names.draw} ${pct(market.draw)}%, ${names.away} ${pct(market.away)}%`
      : "");

  return (
    <div className={cn("w-full", className)} role="img" aria-label={ariaLabel}>
      <div className="flex h-6 w-full overflow-hidden rounded-md" data-testid="probability-bar">
        {SEGMENTS.map(({ key, color }) => {
          const value = pct(model[key]);
          return (
            <div
              key={key}
              data-testid={`prob-segment-${key}`}
              className={cn("flex items-center justify-center overflow-hidden", color)}
              style={{ width: `${model[key] * 100}%` }}
            >
              {value >= MIN_LABEL_PCT && (
                <span className="text-[11px] font-bold tabular-nums leading-none">
                  {value}%
                </span>
              )}
            </div>
          );
        })}
      </div>

      {market && (
        <div
          className="mt-1 flex h-1.5 w-full overflow-hidden rounded-sm opacity-70"
          data-testid="market-bar"
        >
          {SEGMENTS.map(({ key, color }) => (
            <div
              key={key}
              data-testid={`market-segment-${key}`}
              className={color.split(" ")[0]}
              style={{ width: `${market[key] * 100}%` }}
            />
          ))}
        </div>
      )}

      {/* Names for every segment — a first-time reader must never have to
          guess that the grey middle means "Draw". One quiet line, always on. */}
      <div
        className="mt-1 flex items-center justify-between gap-2 text-[10px] uppercase tracking-wide text-muted-foreground"
        data-testid="prob-legend"
        aria-hidden="true"
      >
        {SEGMENTS.map(({ key, dot }) => (
          <span key={key} className="flex min-w-0 items-center gap-1">
            <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", dot)} />
            <span className="truncate font-mono">
              {names[key]}{" "}
              <span className="tabular-nums">{pct(model[key])}%</span>
            </span>
          </span>
        ))}
      </div>
    </div>
  );
}

export default ProbabilityBar;
