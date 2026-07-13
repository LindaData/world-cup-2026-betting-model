import { Link } from "react-router-dom";
import {
  Activity,
  BookOpen,
  ChevronRight,
  ClipboardCheck,
  Database,
  Grid3x3,
  Inbox,
  Microscope,
  Radio,
  ShieldCheck,
  SquareTerminal,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { useBasketCount } from "@/hooks/use-basket-count";
import { BETTING_DESK_ENABLED } from "@/lib/flags";

interface ResearchTool {
  to: string;
  icon: LucideIcon;
  name: string;
  blurb: string;
  desktopHeavy?: boolean;
  /**
   * Internal data-engineering surface (SQL lab, feed ops, review queues).
   * Ops tools only render on private desk builds — the public Research tab
   * stays trust-building content a first-time reader can parse in 5 seconds.
   */
  ops?: boolean;
}

const TOOLS: ResearchTool[] = [
  {
    to: "/model",
    icon: Microscope,
    name: "Model audit",
    blurb: "How the model has done on past matches, match by match.",
  },
  {
    to: "/signals",
    icon: Radio,
    name: "Signals",
    blurb: "The stats the model watches and how much each one matters.",
  },
  {
    to: "/approval",
    icon: ShieldCheck,
    name: "Data approval",
    blurb: "New data is reviewed here before it can move a prediction.",
    desktopHeavy: true,
    ops: true,
  },
  {
    to: "/datasets",
    icon: Database,
    name: "Datasets",
    blurb: "Every table we keep, where it came from, and when it last updated.",
    ops: true,
  },
  {
    to: "/explore",
    icon: SquareTerminal,
    name: "Query lab",
    blurb: "Ask your own questions of the raw data with SQL.",
    desktopHeavy: true,
    ops: true,
  },
  {
    to: "/coverage",
    icon: Grid3x3,
    name: "Coverage",
    blurb: "Which teams and matches we have solid data for, and where it is thin.",
    desktopHeavy: true,
    ops: true,
  },
  {
    to: "/dictionary",
    icon: BookOpen,
    name: "Dictionary",
    blurb: "What every column and stat name actually means.",
  },
  {
    to: "/quality",
    icon: ClipboardCheck,
    name: "QA checks",
    blurb: "Automatic checks that flag broken or suspicious data.",
    ops: true,
  },
  {
    to: "/basket",
    icon: Inbox,
    name: "Review queue",
    blurb: "Items you flagged while browsing, waiting for a closer look.",
    ops: true,
  },
  {
    to: "/status",
    icon: Activity,
    name: "Feed status",
    blurb: "Whether each data feed is live, cached, or running on demo data.",
    ops: true,
  },
];

export default function Research() {
  const basketCount = useBasketCount();
  // Public builds keep the tab to trust-building content (Model audit,
  // Signals, Dictionary); the ops console only exists on desk builds.
  const tools = TOOLS.filter((tool) => BETTING_DESK_ENABLED || !tool.ops);

  return (
    <div className="space-y-6">
      <div>
        <p className="label-mono">Research</p>
        <h1 className="text-2xl md:text-3xl font-bold mt-1">Why trust this</h1>
        <p className="text-sm text-foreground mt-1 max-w-prose">
          How the model is built and how accurate it has been.
        </p>
        <p className="text-sm text-muted-foreground mt-1 max-w-prose">
          Everything behind the numbers: how the model is graded, where the data
          comes from, and the checks that keep it honest.
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {tools.map((tool) => {
          const Icon = tool.icon;
          const isQueue = tool.to === "/basket";
          return (
            <Link
              key={tool.to}
              to={tool.to}
              className="surface-card group flex items-center gap-4 p-4 min-h-[44px] transition-colors hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <div className="shrink-0 w-10 h-10 rounded-md bg-muted flex items-center justify-center">
                <Icon className="w-5 h-5 text-primary" aria-hidden="true" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-semibold text-card-foreground">
                    {tool.name}
                  </span>
                  {isQueue && basketCount > 0 && (
                    <span
                      className="chip bg-primary/15 text-primary tabular-nums"
                      aria-label={`${basketCount} items in review queue`}
                    >
                      {basketCount}
                    </span>
                  )}
                </div>
                <p className="text-sm text-muted-foreground mt-0.5">
                  {tool.blurb}
                </p>
                {/* Badge trails the description in one consistent slot so all
                    card titles left-align with the blurb directly beneath. */}
                {tool.desktopHeavy && (
                  <span className="label-mono mt-1.5 inline-block border border-border rounded px-1.5 py-0.5">
                    Best on desktop
                  </span>
                )}
              </div>
              <ChevronRight
                className="shrink-0 w-4 h-4 text-muted-foreground transition-transform group-hover:translate-x-0.5 motion-reduce:transform-none"
                aria-hidden="true"
              />
            </Link>
          );
        })}
      </div>
    </div>
  );
}
