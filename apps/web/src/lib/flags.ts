// Feature flags for the consolidated app.
//
// The betting desk (staking, edge pricing, portfolio, bankroll ledger) is a
// private workspace: it only renders when VITE_ENABLE_BETTING_DESK=true is set
// at build time, or during local development. Public deploys stay
// prediction/data only.
export const BETTING_DESK_ENABLED =
  import.meta.env.VITE_ENABLE_BETTING_DESK === "true" || import.meta.env.DEV;

// NBA/MLB have no model coverage yet, and the model is the product: their
// tabs stay hidden on public builds (same private-flag pattern as the desk)
// until each sport ships with predictions.
export const EXTRA_SPORTS_ENABLED =
  import.meta.env.VITE_ENABLE_EXTRA_SPORTS === "true" || import.meta.env.DEV;
