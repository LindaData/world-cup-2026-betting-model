// Placeholder wrapper: the Matches screen agent replaces this file's contents.
// Renders the existing sport pages behind a ?sport= query param so the old
// /football, /nba, and /mlb routes keep working through redirects.
import { lazy, Suspense } from "react";
import { useSearchParams } from "react-router-dom";

const Football = lazy(() => import("./Football"));
const NBA = lazy(() => import("./NBA"));
const MLB = lazy(() => import("./MLB"));

const SPORTS = {
  football: Football,
  nba: NBA,
  mlb: MLB,
} as const;

type SportKey = keyof typeof SPORTS;

export default function Matches() {
  const [params] = useSearchParams();
  const raw = (params.get("sport") ?? "football").toLowerCase();
  const sport: SportKey = raw in SPORTS ? (raw as SportKey) : "football";
  const Page = SPORTS[sport];

  return (
    <Suspense fallback={<div className="text-sm text-muted-foreground">Loading matches...</div>}>
      <Page />
    </Suspense>
  );
}
