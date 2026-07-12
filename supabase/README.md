# Supabase setup (private desk persistence)

One-time setup, ~10 minutes:

1. In [Supabase](https://supabase.com/dashboard) create a project (free tier)
   named e.g. `lindadata-sports`.
2. SQL Editor → paste and run `schema.sql` from this directory.
3. Authentication → Providers → enable **Email** (magic link / OTP). Disable
   sign-ups after your first login (Auth → Settings → "Allow new users to
   sign up" off) — RLS already restricts data to the allowlisted email, this
   just keeps strangers from creating empty accounts.
4. Project Settings → API: copy the **Project URL** and **anon public key**.
5. Add to the Vercel project (and `.env.local` for dev):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`

The anon key is safe to expose in the frontend — RLS means it grants nothing
unless the signed-in email matches the allowlist in `schema.sql`.

Migrating the old ledger: the bankroll page's CSV export from the deployed
game-stat-pulse app imports into `wagers` (the desk will grow an import
button; until then the SQL editor's CSV import works against the same
columns).
