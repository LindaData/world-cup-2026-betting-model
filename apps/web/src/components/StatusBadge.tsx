import { cn } from "@/lib/utils";
import type { LoadOrigin } from "@/lib/dataSources";

/**
 * One chip family for every data-state indicator (demo, live, cached,
 * offline…): dot + letterspaced mono uppercase label, styled with the theme
 * tokens only. Red stays reserved for losses/negative money, so "offline"
 * reads as a warning (amber), never as money lost.
 */
export type StatusTone = "live" | "info" | "warn" | "muted";

const toneStyles: Record<StatusTone, string> = {
  live: "bg-gain/15 text-gain border border-gain/30",
  info: "bg-away/15 text-away border border-away/30",
  warn: "bg-warn/15 text-warn border border-warn/30",
  muted: "bg-muted text-muted-foreground border border-border",
};

export function StatusChip({
  tone,
  label,
  className,
}: {
  tone: StatusTone;
  label: string;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "chip font-mono uppercase tracking-wide",
        toneStyles[tone],
        className,
      )}
    >
      <span className="w-1.5 h-1.5 rounded-full bg-current" />
      {label}
    </span>
  );
}

const originChips: Record<LoadOrigin, { tone: StatusTone; label: string }> = {
  network: { tone: "live", label: "Live" },
  fallback: { tone: "warn", label: "Fallback" },
  cache: { tone: "info", label: "Cached" },
  demo: { tone: "muted", label: "Demo" },
  empty: { tone: "warn", label: "Offline" },
};

export function StatusBadge({ origin, className }: { origin: LoadOrigin; className?: string }) {
  const { tone, label } = originChips[origin];
  return <StatusChip tone={tone} label={label} className={className} />;
}
