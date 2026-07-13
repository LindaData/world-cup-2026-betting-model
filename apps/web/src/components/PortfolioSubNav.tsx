import { Link } from "react-router-dom";
import { cn } from "@/lib/utils";

/**
 * Segmented sub-nav for the two Portfolio pages so /bankroll (Desk) and
 * /edge (Edge check) are always reachable from each other. Same chip family
 * as the Matches sport switcher.
 */
const VIEWS = [
  { key: "desk", label: "Desk", to: "/bankroll" },
  { key: "edge", label: "Edge check", to: "/edge" },
] as const;

export type PortfolioView = (typeof VIEWS)[number]["key"];

export function PortfolioSubNav({ active }: { active: PortfolioView }) {
  return (
    <div
      role="group"
      aria-label="Portfolio pages"
      className="inline-flex rounded-lg border border-border bg-card p-1"
    >
      {VIEWS.map((view) => {
        const isActive = view.key === active;
        return (
          <Link
            key={view.key}
            to={view.to}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "flex min-h-11 items-center rounded-md px-4 text-sm font-semibold transition-colors",
              isActive
                ? "bg-muted text-primary"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {view.label}
          </Link>
        );
      })}
    </div>
  );
}

export default PortfolioSubNav;
