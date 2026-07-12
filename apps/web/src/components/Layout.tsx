import { NavLink, Outlet } from "react-router-dom";
import {
  Activity,
  Banknote,
  BookOpen,
  Calculator,
  CheckSquare2,
  ClipboardList,
  Database,
  FlaskConical,
  LayoutGrid,
  ListChecks,
  ShieldCheck,
  TrendingUp,
  Target,
} from "lucide-react";
import { Trophy, Dribbble, CircleDot } from "lucide-react";
import { cn } from "@/lib/utils";
import { useBasketCount } from "@/hooks/use-basket-count";
import { BETTING_DESK_ENABLED } from "@/lib/flags";

interface NavItem {
  to: string;
  label: string;
  icon: typeof Trophy;
  end?: boolean;
}

const publicNavItems: NavItem[] = [
  { to: "/", label: "World Cup", icon: Trophy, end: true },
  { to: "/nba", label: "NBA", icon: Dribbble },
  { to: "/mlb", label: "MLB", icon: CircleDot },
  { to: "/signals", label: "Signals", icon: TrendingUp },
  { to: "/model", label: "Model audit", icon: FlaskConical },
  { to: "/approval", label: "Review board", icon: CheckSquare2 },
  { to: "/datasets", label: "Datasets", icon: LayoutGrid },
  { to: "/explore", label: "Query lab", icon: Database },
  { to: "/coverage", label: "Coverage", icon: Activity },
  { to: "/dictionary", label: "Dictionary", icon: BookOpen },
  { to: "/quality", label: "QA checks", icon: ShieldCheck },
  { to: "/basket", label: "Review queue", icon: ListChecks },
  { to: "/status", label: "Feed status", icon: Activity },
];

const deskNavItems: NavItem[] = [
  { to: "/desk", label: "Research desk", icon: Target },
  { to: "/edge", label: "Pricing", icon: Calculator },
  { to: "/portfolio", label: "Scenarios", icon: ClipboardList },
  { to: "/bankroll", label: "Ledger", icon: Banknote },
];

const navItems = BETTING_DESK_ENABLED
  ? [...publicNavItems.slice(0, 5), ...deskNavItems, ...publicNavItems.slice(5)]
  : publicNavItems;

const mobileItems = BETTING_DESK_ENABLED
  ? [
      { to: "/", label: "World Cup", icon: Trophy, end: true },
      { to: "/desk", label: "Desk", icon: Target },
      { to: "/edge", label: "Price", icon: Calculator },
      { to: "/bankroll", label: "Ledger", icon: Banknote },
      { to: "/model", label: "Audit", icon: FlaskConical },
      { to: "/status", label: "Status", icon: Activity },
    ]
  : [
      { to: "/", label: "World Cup", icon: Trophy, end: true },
      { to: "/nba", label: "NBA", icon: Dribbble },
      { to: "/mlb", label: "MLB", icon: CircleDot },
      { to: "/signals", label: "Signals", icon: TrendingUp },
      { to: "/model", label: "Audit", icon: FlaskConical },
      { to: "/status", label: "Status", icon: Activity },
    ];

const workspaceRail = [
  ["Fixtures", "Context"],
  ["Odds", "Pricing"],
  ["Lineups", "Availability"],
  ["Players", "Form"],
  ["Ledger", "Tracking"],
  ["Audit", "Validation"],
  ["Coverage", "API"],
  ["Status", "Health"],
];

const tickerItems = [
  "API-Football feeds load when GitHub Actions secrets are present",
  "Published review site uses fallback samples until the data lake refreshes",
  "Signals, pricing, audit, and ledger views are built for research workflow",
  "Coverage pages track which sports and entities are currently live",
];

export default function Layout() {
  const basketCount = useBasketCount();

  return (
    <div className="min-h-screen flex flex-col bg-background text-foreground">
      <header className="sticky top-0 z-30 border-b border-white/10 bg-[hsl(var(--navy-deep))]/95 backdrop-blur-xl pt-[env(safe-area-inset-top)]">
        <div className="border-b border-white/10 bg-black/35">
          <div className="max-w-[1720px] mx-auto px-3 sm:px-4 min-h-9 flex items-center gap-3 overflow-hidden">
            <span className="shrink-0 rounded-sm bg-red-500 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-white">
              Workspace
            </span>
            <div className="flex min-w-0 flex-1 items-center gap-6 overflow-hidden text-[11px] uppercase tracking-wide text-muted-foreground">
              {tickerItems.map((item) => (
                <span key={item} className="shrink-0 whitespace-nowrap">
                  {item}
                </span>
              ))}
            </div>
          </div>
        </div>

        <div className="max-w-[1720px] mx-auto px-3 sm:px-4 min-h-16 flex items-center justify-between gap-4">
          <NavLink to="/" className="flex items-center gap-3 min-w-0" aria-label="LindaData sports hub">
            <div className="w-10 h-10 rounded-md bg-primary text-primary-foreground flex items-center justify-center text-sm font-black shadow-[0_0_32px_hsl(var(--primary)/0.35)] shrink-0">
              LD
            </div>
            <div className="leading-tight min-w-0">
              <div className="text-sm sm:text-base font-black uppercase tracking-wide text-foreground truncate">
                LindaData Sports
              </div>
              <div className="hidden min-[390px]:block text-[10px] uppercase tracking-[0.24em] text-primary truncate">
                World Cup 2026 Forecasting Hub
              </div>
            </div>
          </NavLink>

          <nav className="no-scrollbar hidden lg:flex items-center gap-1 overflow-x-auto" aria-label="Primary navigation">
            {navItems.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    cn(
                      "px-3 py-2 rounded-md text-sm font-semibold transition flex items-center gap-1.5 whitespace-nowrap",
                      isActive
                        ? "bg-primary text-primary-foreground"
                        : "text-foreground/70 hover:text-foreground hover:bg-white/[0.07]",
                    )
                  }
                >
                  <Icon className="w-4 h-4" />
                  {item.label}
                  {item.to === "/basket" && basketCount > 0 && (
                    <span className="text-[10px] bg-secondary text-secondary-foreground rounded-sm px-1.5 py-0.5 min-w-[18px] text-center">
                      {basketCount}
                    </span>
                  )}
                </NavLink>
              );
            })}
          </nav>
        </div>

        <div className="border-t border-white/10 bg-white/[0.035]">
          <div className="no-scrollbar max-w-[1720px] mx-auto px-3 sm:px-4 overflow-x-auto">
            <div className="flex min-h-11 items-center gap-2">
              {workspaceRail.map(([label,detail]) => (
                <button
                  key={label}
                  type="button"
                  className="min-h-8 shrink-0 rounded-md border border-white/10 bg-black/25 px-3 text-left text-xs font-semibold text-foreground/85 hover:border-primary/50 hover:text-primary"
                >
                  <span className="mr-2 uppercase">{label}</span>
                  <span className={detail === "Health" || detail === "Validation" ? "text-secondary" : "text-primary"}>
                    {detail}
                  </span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </header>

      <main className="flex-1 max-w-[1720px] w-full mx-auto px-3 sm:px-4 py-3 sm:py-5 pb-[calc(7rem+env(safe-area-inset-bottom))] lg:pb-10">
        <Outlet />
      </main>

      <footer className="hidden lg:block border-t border-white/10 py-4 text-center text-xs text-muted-foreground">
        Sports insight workspace for feed review, modeling, validation, and performance analysis.
      </footer>

      <nav className="lg:hidden fixed bottom-0 inset-x-0 z-30 bg-[hsl(var(--navy-deep))]/95 backdrop-blur-xl border-t border-white/10 pb-[env(safe-area-inset-bottom)]" aria-label="Mobile navigation">
        <ul className="grid grid-cols-6">
          {mobileItems.map((item) => {
            const Icon = item.icon;
            return (
              <li key={item.to}>
                <NavLink
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    cn(
                      "min-h-[4.25rem] flex flex-col items-center justify-center py-2 gap-0.5 text-[10px] font-semibold relative active:bg-white/5",
                      isActive ? "text-primary" : "text-foreground/60",
                    )
                  }
                >
                  <Icon className="w-5 h-5" />
                  {item.label}
                  {item.to === "/basket" && basketCount > 0 && (
                    <span className="absolute top-1 right-3 text-[9px] bg-secondary text-secondary-foreground rounded-sm px-1.5 py-0.5 min-w-[16px] text-center">
                      {basketCount}
                    </span>
                  )}
                </NavLink>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}
