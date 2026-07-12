import { cn } from "@/lib/utils";
import type { LoadOrigin } from "@/lib/dataSources";

const styles: Record<LoadOrigin, string> = {
  network: "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30",
  fallback: "bg-amber-500/15 text-amber-400 border border-amber-500/30",
  cache: "bg-sky-500/15 text-sky-400 border border-sky-500/30",
  empty: "bg-red-500/15 text-red-400 border border-red-500/30",
};

const labels: Record<LoadOrigin, string> = {
  network: "Live",
  fallback: "Fallback",
  cache: "Cached",
  empty: "Unavailable",
};

export function StatusBadge({ origin, className }: { origin: LoadOrigin; className?: string }) {
  return (
    <span className={cn("chip", styles[origin], className)}>
      <span className="w-1.5 h-1.5 rounded-full bg-current" />
      {labels[origin]}
    </span>
  );
}
