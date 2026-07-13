import { lazy, Suspense } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes, Navigate } from "react-router-dom";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { DataProvider } from "@/context/DataContext";
import Layout from "@/components/Layout";
import GlobalReviewWorkspace from "@/components/GlobalReviewWorkspace";
import { BETTING_DESK_ENABLED } from "@/lib/flags";

// Primary tabs
const Today = lazy(() => import("./pages/Today"));
const Matches = lazy(() => import("./pages/Matches"));
const MatchDetail = lazy(() => import("./pages/MatchDetail"));
const Research = lazy(() => import("./pages/Research"));

// Research sub-pages (keep their routes)
const Approval = lazy(() => import("./pages/Approval"));
const Datasets = lazy(() => import("./pages/Datasets"));
const ModelAudit = lazy(() => import("./pages/ModelAudit"));
const Coverage = lazy(() => import("./pages/Coverage"));
const Dictionary = lazy(() => import("./pages/Dictionary"));
const Quality = lazy(() => import("./pages/Quality"));
const ReviewBasket = lazy(() => import("./pages/ReviewBasket"));
const Signals = lazy(() => import("./pages/Signals"));
const Status = lazy(() => import("./pages/Status"));
const RawDataLab = lazy(() => import("./pages/RawDataLab"));

// Private betting desk (flag-gated)
const BettingDesk = lazy(() => import("./pages/BettingDesk"));
const EdgeLab = lazy(() => import("./pages/EdgeLab"));
const Portfolio = lazy(() => import("./pages/Portfolio"));
const Bankroll = lazy(() => import("./pages/Bankroll"));

const NotFound = lazy(() => import("./pages/NotFound"));

const queryClient = new QueryClient();
const basename = import.meta.env.BASE_URL.replace(/\/$/, "");

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <DataProvider>
        <BrowserRouter basename={basename || "/"}>
          <Suspense fallback={<RouteFallback />}>
            <Routes>
              <Route element={<Layout />}>
                <Route path="/" element={<Today />} />
                <Route path="/matches" element={<Matches />} />
                <Route path="/match/:id" element={<MatchDetail />} />
                <Route path="/research" element={<Research />} />

                {/* Legacy sport routes redirect into the Matches tab */}
                <Route path="/football" element={<Navigate to="/matches" replace />} />
                <Route path="/nba" element={<Navigate to="/matches?sport=nba" replace />} />
                <Route path="/mlb" element={<Navigate to="/matches?sport=mlb" replace />} />

                {/* Research sub-pages keep their routes */}
                <Route path="/approval" element={<Approval />} />
                <Route path="/datasets" element={<Datasets />} />
                <Route path="/model" element={<ModelAudit />} />
                <Route path="/signals" element={<Signals />} />
                <Route path="/coverage" element={<Coverage />} />
                <Route path="/dictionary" element={<Dictionary />} />
                <Route path="/quality" element={<Quality />} />
                <Route path="/basket" element={<ReviewBasket />} />
                <Route path="/explore" element={<RawDataLab />} />
                <Route path="/raw" element={<Navigate to="/explore" replace />} />
                <Route path="/status" element={<Status />} />

                {BETTING_DESK_ENABLED && (
                  <>
                    <Route path="/desk" element={<BettingDesk />} />
                    <Route path="/edge" element={<EdgeLab />} />
                    <Route path="/portfolio" element={<Portfolio />} />
                    <Route path="/bankroll" element={<Bankroll />} />
                  </>
                )}
                <Route path="*" element={<NotFound />} />
              </Route>
            </Routes>
          </Suspense>
          <GlobalReviewWorkspace />
        </BrowserRouter>
      </DataProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;

function RouteFallback() {
  return (
    <div className="min-h-screen bg-background p-4 text-foreground">
      <div className="surface-card mx-auto mt-8 max-w-md p-4 text-sm text-muted-foreground">
        Loading...
      </div>
    </div>
  );
}
