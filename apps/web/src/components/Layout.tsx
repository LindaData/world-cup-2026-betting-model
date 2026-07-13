import { useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { CalendarDays, FlaskConical, Home, Wallet } from "lucide-react";
import { cn } from "@/lib/utils";
import { useData } from "@/context/DataContext";
import { BETTING_DESK_ENABLED } from "@/lib/flags";
import { getPredictions } from "@/lib/modelFeeds";

/** Header slot the global Notes launcher portals into (quiet icon, no FAB). */
export const NOTES_LAUNCHER_SLOT_ID = "notes-launcher-slot";

/** One-time onboarding banner: flips to "1" on dismiss, never shows again. */
const ONBOARDING_BANNER_KEY = "gsp:onboarding-banner:v1";

/** Shown once under the header, then remembered forever in localStorage. */
const ONBOARDING_COPY =
  "Green numbers are our model's win chances. Tap any match to see its full forecast.";

/** Appears in the desktop footer and as a quiet line at mobile list ends. */
const RESEARCH_DISCLAIMER = "Forecasts are research, not betting advice.";

function readBannerDismissed(): boolean {
  try {
    return localStorage.getItem(ONBOARDING_BANNER_KEY) === "1";
  } catch {
    return false;
  }
}

interface NavItem {
  to: string;
  label: string;
  icon: typeof Home;
  /** Route prefixes (besides `to`) that keep this tab highlighted. */
  childPrefixes: string[];
}

// Exactly 4 tabs (3 when the private betting desk is disabled).
const navItems: NavItem[] = [
  { to: "/", label: "Today", icon: Home, childPrefixes: [] },
  {
    to: "/matches",
    label: "Matches",
    icon: CalendarDays,
    childPrefixes: ["/football", "/nba", "/mlb"],
  },
  ...(BETTING_DESK_ENABLED
    ? [
        {
          to: "/bankroll",
          label: "Portfolio",
          icon: Wallet,
          childPrefixes: ["/portfolio", "/edge", "/desk"],
        },
      ]
    : []),
  {
    to: "/research",
    label: "Research",
    icon: FlaskConical,
    childPrefixes: [
      "/status",
      "/datasets",
      "/model",
      "/signals",
      "/coverage",
      "/dictionary",
      "/quality",
      "/basket",
      "/explore",
      "/approval",
    ],
  },
];

/** Sub-routes highlight their parent tab so the user never loses orientation. */
function isTabActive(item: NavItem, pathname: string): boolean {
  if (item.to === "/") return pathname === "/";
  const prefixes = [item.to, ...item.childPrefixes];
  return prefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

function formatRefreshTime(iso: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export default function Layout() {
  const { results, lastRefresh } = useData();
  const { pathname } = useLocation();
  const refreshedAt = formatRefreshTime(lastRefresh);
  const { preliminary } = getPredictions(results);
  const [bannerDismissed, setBannerDismissed] = useState(readBannerDismissed);

  const dismissBanner = () => {
    setBannerDismissed(true);
    try {
      localStorage.setItem(ONBOARDING_BANNER_KEY, "1");
    } catch {
      // Private-mode storage failures just mean the banner shows again next visit.
    }
  };

  return (
    <div className="min-h-screen flex flex-col bg-background text-foreground">
      <header className="sticky top-0 z-30 border-b border-border bg-background/95 backdrop-blur pt-[env(safe-area-inset-top)]">
        <div className="mx-auto flex min-h-14 w-full max-w-5xl items-center justify-between gap-3 px-4">
          <div className="flex min-w-0 items-center gap-2">
            <NavLink
              to="/"
              className="flex min-w-0 items-center gap-2.5"
              aria-label="LindaData Sports home"
            >
              <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-black text-primary-foreground">
                LD
              </span>
              <span className="truncate text-sm font-bold tracking-tight">
                LindaData Sports
              </span>
            </NavLink>
            {preliminary && (
              <span
                className="label-mono shrink-0 rounded border border-border px-1.5 py-0.5"
                title="Preview numbers — the production model publishes daily."
              >
                Preview model
              </span>
            )}
          </div>

          <nav
            className="hidden items-center gap-1 lg:flex"
            aria-label="Primary navigation"
          >
            {navItems.map((item) => {
              const Icon = item.icon;
              const active = isTabActive(item, pathname);
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-md px-3 py-2 text-sm font-semibold transition-colors",
                    active
                      ? "text-primary"
                      : "text-muted-foreground hover:bg-card hover:text-foreground",
                  )}
                >
                  <Icon className="h-4 w-4" aria-hidden="true" />
                  {item.label}
                </NavLink>
              );
            })}
          </nav>

          <div className="flex shrink-0 items-center gap-2">
            {refreshedAt && (
              <span
                className="label-mono hidden tabular-nums sm:inline"
                title="Last data refresh"
              >
                Updated {refreshedAt}
              </span>
            )}
            {/* The global Notes launcher portals into this slot as a quiet icon button. */}
            <div id={NOTES_LAUNCHER_SLOT_ID} className="flex items-center" />
          </div>
        </div>
      </header>

      {!bannerDismissed && (
        <div className="border-b border-border bg-card">
          <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-3 px-4 py-2.5">
            <p className="text-sm text-card-foreground">{ONBOARDING_COPY}</p>
            <button
              type="button"
              onClick={dismissBanner}
              className="min-h-11 shrink-0 rounded-md px-2 text-sm font-semibold text-primary hover:bg-muted"
            >
              Dismiss
            </button>
          </div>
        </div>
      )}

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-4 pb-[calc(5.5rem+env(safe-area-inset-bottom))] sm:py-6 lg:pb-10">
        <Outlet />
        {/* Mobile gets the disclaimer as a quiet line at the end of every list;
            desktop carries it in the footer instead. */}
        <p className="mt-8 text-center text-xs text-muted-foreground lg:hidden">
          {RESEARCH_DISCLAIMER}
        </p>
      </main>

      <footer className="hidden border-t border-border lg:block">
        <div className="mx-auto w-full max-w-5xl px-4 py-4">
          <p className="text-xs text-muted-foreground">{RESEARCH_DISCLAIMER}</p>
        </div>
      </footer>

      <nav
        className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
        aria-label="Mobile navigation"
      >
        <ul
          className="grid"
          style={{ gridTemplateColumns: `repeat(${navItems.length}, minmax(0, 1fr))` }}
        >
          {navItems.map((item) => {
            const Icon = item.icon;
            const active = isTabActive(item, pathname);
            return (
              <li key={item.to}>
                <NavLink
                  to={item.to}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex min-h-14 flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-semibold active:bg-card",
                    active ? "text-primary" : "text-muted-foreground",
                  )}
                >
                  <Icon className="h-5 w-5" aria-hidden="true" />
                  {item.label}
                </NavLink>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}
