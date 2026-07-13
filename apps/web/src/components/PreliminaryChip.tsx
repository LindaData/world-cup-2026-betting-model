import { cn } from "@/lib/utils";

/**
 * Neutral marker for model numbers that come from the placeholder pipeline
 * (feed provider === "placeholder"). Deliberately quiet — muted border, no
 * dot, no color — so it reads as a footnote, never as a data-state warning.
 * Distinct from StatusChip: that family describes where data came from; this
 * one describes how final the model's numbers are.
 */
export function PreliminaryChip({ className }: { className?: string }) {
  return (
    <span
      title="Preview numbers — the production model publishes daily."
      className={cn(
        "chip font-mono uppercase tracking-wide border border-border text-muted-foreground",
        className,
      )}
    >
      Preliminary
    </span>
  );
}
