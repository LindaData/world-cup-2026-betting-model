# Codex / ChatGPT Project Instructions

## Prime rule: Lovable baseline architecture

For any app project that began in Lovable, treat the initial Lovable build as the approved architecture and scaffold unless the user explicitly says to replace it.

Preserve:

- existing routing
- mobile-first layout
- app shell
- page names and user flows
- shadcn/ui component pattern
- Tailwind design tokens
- demo data contracts
- localStorage/demo state behavior
- working controls and navigation

Do not redesign or rebuild the app from scratch just because Codex is now doing the engineering work.

## Preferred workflow

1. Start with a Lovable or Lovable-style mobile-first scaffold.
2. Freeze the shell: routes, layout, design tokens, components, and demo flows.
3. Let Codex harden the app with data, tests, security, persistence, GitHub Actions, iOS/Capacitor, AWS, and production cleanup.
4. Keep PRs small and reviewable.
5. Run lint, tests, TypeScript checks, and production build before reporting completion.

## Game Stat Pulse priority

Game Stat Pulse is data-pipeline heavy. Preserve the review UI shell while Codex focuses on API-Football ingestion, Parquet/catalog generation, GitHub Actions, browser-safe review flows, and model-prep documentation.

## Security rules

- Do not expose API keys or secrets in frontend code, logs, commits, `.env` files, or browser requests.
- Use GitHub Actions secrets or server-side/cloud runtime secrets only.
- Prefer free/local-first proof of concept work before paid infrastructure.

## Mobile-first rule

The user is usually on iPhone. Make review links, instructions, and UI flows mobile-friendly and copy-pasteable.

## Codex behavior

Before changing code:

1. Inspect the current repo structure.
2. Identify the Lovable-generated scaffold and preserve it.
3. Make the smallest useful change.
4. Add or update tests/docs when useful.
5. Report what changed, what passed, and what still needs review.