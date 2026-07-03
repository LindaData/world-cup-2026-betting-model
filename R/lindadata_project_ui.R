# LindaData project-command UI helpers for the World Cup forecasting site.
# These helpers render public-safe project context and org routing.
# They do not change model outputs, source data, or forecast methodology.

snapshot_label <- function(summary, metric, fallback = "Not available yet") {
  escape_html(summary_value(summary, metric, fallback))
}

render_lindadata_metric_card <- function(label, value, note) {
  paste0(
    '<article class="ld-metric-card">',
    '<span>', escape_html(label), '</span>',
    '<strong>', escape_html(value), '</strong>',
    '<small>', escape_html(note), '</small>',
    '</article>'
  )
}

render_lindadata_route_card <- function(label, title, text, href, action = "Open") {
  paste0(
    '<a class="ld-route-card" href="', escape_html(href), '">',
    '<span>', escape_html(label), '</span>',
    '<strong>', escape_html(title), '</strong>',
    '<p>', escape_html(text), '</p>',
    '<b>', escape_html(action), ' &rarr;</b>',
    '</a>'
  )
}

render_lindadata_org_card <- function(label, title, text) {
  paste0(
    '<article class="ld-org-card">',
    '<span>', escape_html(label), '</span>',
    '<strong>', escape_html(title), '</strong>',
    '<p>', escape_html(text), '</p>',
    '</article>'
  )
}

render_lindadata_flow_step <- function(label, title, text) {
  paste0(
    '<article class="ld-flow-step">',
    '<span>', escape_html(label), '</span>',
    '<strong>', escape_html(title), '</strong>',
    '<p>', escape_html(text), '</p>',
    '</article>'
  )
}

render_lindadata_project_shell <- function(summary, board) {
  completed <- snapshot_label(summary, "completed_matches", "0")
  tracked <- snapshot_label(summary, "matches_on_board", "0")
  today <- snapshot_label(summary, "matches_today", "0")
  upcoming <- snapshot_label(summary, "upcoming_matches", "0")
  generated <- snapshot_label(summary, "last_refreshed_local", "Not available yet")
  phase <- escape_html(tournament_phase(summary))

  latest_completed <- if (nrow(board) > 0 && any(board$match_timing == "Completed", na.rm = TRUE)) {
    completed_dates <- suppressWarnings(as.Date(board$date[board$match_timing == "Completed"]))
    if (any(!is.na(completed_dates))) {
      format(max(completed_dates, na.rm = TRUE), "%b %d, %Y")
    } else {
      "Latest scored match"
    }
  } else {
    "Latest refresh"
  }

  metrics <- paste0(
    render_lindadata_metric_card("Matches tracked", tracked, "full fixture board"),
    render_lindadata_metric_card("Today", today, "current slate"),
    render_lindadata_metric_card("Upcoming", upcoming, "future forecasts"),
    render_lindadata_metric_card("Completed", completed, "graded results")
  )

  routes <- paste0(
    render_lindadata_route_card("Forecast board", "Today's predictions", "Match cards, model pick, win/draw/loss or advance probabilities, expected score, and details.", "reports/08_matchday_predictions.html", "Open predictions"),
    render_lindadata_route_card("Tournament path", "Bracket and champion outlook", "Projected bracket flow and title probability view from the tournament simulation layer.", "reports/08_matchday_predictions.html#bracket", "Open bracket"),
    render_lindadata_route_card("Model trust", "Post-match review", "Completed-match grading, hit/miss patterns, score miss, and calibration watch areas.", "reports/08_matchday_predictions.html#model-review", "Open review"),
    render_lindadata_route_card("Coverage", "Data source overview", "Public-safe summary of fixture coverage, model-ready files, and what is intentionally excluded.", "reports/00_data_overview.html", "Open coverage"),
    render_lindadata_route_card("Model lab", "Challenger bench", "Expanded comparison bench for goals, result, and tree-based challengers before promotion.", "reports/10_model_challengers.html", "Open model lab"),
    render_lindadata_route_card("Execution", "Repository", "Source, project docs, issues, pull requests, security policy, and generated GitHub Pages output.", "https://github.com/LindaData/world-cup-2026-betting-model", "Open GitHub")
  )

  org <- paste0(
    render_lindadata_org_card("CEO / Owner", "ChefHands / Sergio Mora", "Final decision maker. Reviews the public output, model direction, and what should be promoted next."),
    render_lindadata_org_card("Chief of Staff", "Priority routing", "Turns morning review into focused tasks and keeps this project aligned under the LindaData HQ."),
    render_lindadata_org_card("CDO + data pod", "Inputs and features", "Owns source refreshes, DuckDB/model-ready tables, feature quality, and data freshness notes."),
    render_lindadata_org_card("CTO + engineering pod", "Site and pipeline", "Owns Quarto, GitHub Pages, static rendering, links, performance, and mobile-first UX."),
    render_lindadata_org_card("CSO / CIO", "Public-safe controls", "Keeps raw data, credentials, private feeds, and operational secrets out of the public site."),
    render_lindadata_org_card("CMO / PRO", "Clear public story", "Explains the model as research and forecasting. No betting-edge or profit claims without complete inputs.")
  )

  flow <- paste0(
    render_lindadata_flow_step("1 / CDO", "Ingest", "Fixtures, results, team strength, form, weather, and available provider metadata."),
    render_lindadata_flow_step("2 / CDO", "Model", "Result probabilities, score grid, challenger models, and historical validation."),
    render_lindadata_flow_step("3 / CDO", "Simulate", "Bracket path and champion outlook from the current forecast state."),
    render_lindadata_flow_step("4 / COO", "Review", "Post-match grading, failure modes, tuning priorities, and promotion checks."),
    render_lindadata_flow_step("5 / CTO", "Publish", "Static GitHub Pages output with clean links, public-safe copy, and fast mobile UX.")
  )

  paste0(
    '<section class="ld-project-hero page-columns page-full">',
    '<div class="ld-hero-copy">',
    '<div class="ld-chip-row">',
    '<span class="ld-chip ld-chip-gold">LindaData Project</span>',
    '<span class="ld-chip">Active research</span>',
    '<span class="ld-chip">', phase, '</span>',
    '</div>',
    '<h1>World Cup Forecasting Hub</h1>',
    '<p><strong>One clean command center</strong> for the World Cup model: match probabilities, bracket path, champion outlook, post-match model review, and the project operating layer.</p>',
    '<div class="ld-hero-actions">',
    '<a class="button-primary" href="reports/08_matchday_predictions.html">Open predictions</a>',
    '<a class="button-secondary" href="reports/08_matchday_predictions.html#bracket">Open bracket</a>',
    '<a class="button-secondary" href="reports/08_matchday_predictions.html#model-review">Review model</a>',
    '</div>',
    '</div>',
    '<aside class="ld-snapshot-card" aria-label="Current published forecast snapshot">',
    '<span class="section-kicker">Snapshot</span>',
    '<h2>Current published model output</h2>',
    '<div class="ld-snapshot-grid">',
    '<div><span>Last generated</span><strong>', generated, '</strong></div>',
    '<div><span>Data current through</span><strong>', escape_html(latest_completed), '</strong></div>',
    '<div><span>Public mode</span><strong>Read-only static</strong></div>',
    '<div><span>Use case</span><strong>Research forecast</strong></div>',
    '</div>',
    '</aside>',
    '</section>',
    '<section class="ld-metric-strip" aria-label="Forecast board metrics">', metrics, '</section>',
    '<section class="page-section ld-command-section" id="go-to-work">',
    '<div class="section-heading"><span class="section-kicker">Start here</span><h2>Project Dashboard</h2><p>Every primary task has a one-tap path. Forecasts stay first; diagnostics and repo work are secondary.</p></div>',
    '<div class="ld-route-grid">', routes, '</div>',
    '</section>',
    '<section class="page-section ld-command-section" id="lindadata-org">',
    '<div class="section-heading"><span class="section-kicker">Follow org</span><h2>LindaData Operating Layer</h2><p>The project shows who owns the work, how decisions flow, and which agents should handle each part.</p></div>',
    '<div class="ld-org-grid">', org, '</div>',
    '</section>',
    '<section class="page-section ld-command-section" id="workflow">',
    '<div class="section-heading"><span class="section-kicker">Workflow</span><h2>How This Project Moves</h2><p>Simple flow from data to public review. Each stage has a responsible executive lane.</p></div>',
    '<div class="ld-flow-grid">', flow, '</div>',
    '<div class="ld-responsible-card"><strong>Responsible use:</strong> This is an educational forecasting and model-review project. Verify official match information before making decisions; the site does not provide financial advice.</div>',
    '</section>'
  )
}
