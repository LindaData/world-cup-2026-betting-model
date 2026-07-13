-- LindaData Sports — private desk persistence.
-- Run once in the Supabase SQL editor (or `supabase db push`).
-- Access model: single-owner. Every table is RLS-locked to the allowlisted
-- email; the anon key alone reads nothing.

create table if not exists wagers (
  id uuid primary key default gen_random_uuid(),
  placed_at timestamptz not null default now(),
  sport text not null,
  event text not null,
  market text not null,               -- h2h | spread | total | outright
  selection text not null,
  book text,
  odds_decimal numeric not null check (odds_decimal > 1),
  stake numeric not null check (stake >= 0),
  model_probability numeric check (model_probability > 0 and model_probability < 1),
  closing_odds_decimal numeric,
  result text not null default 'open' check (result in ('open','won','lost','push','void')),
  settled_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists edge_snapshots (
  id uuid primary key default gen_random_uuid(),
  captured_at timestamptz not null default now(),
  event_id text not null,
  sport text not null,
  commence_time timestamptz,
  market text not null,
  outcome text not null,
  model_probability numeric not null,
  best_odds numeric not null,
  best_book text,
  novig_consensus_probability numeric,
  edge_pct numeric not null,
  kelly_fraction numeric
);

create table if not exists approvals (
  dataset_id text primary key,
  decision text not null check (decision in ('pending','approved','changes_requested')),
  notes text,
  reviewed_at timestamptz not null default now()
);

alter table wagers enable row level security;
alter table edge_snapshots enable row level security;
alter table approvals enable row level security;

-- Single-owner allowlist. Change the email here if the account ever changes.
create or replace function is_owner() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'sergio.mora@lindadata.com'
$$;

create policy owner_all_wagers on wagers
  for all using (is_owner()) with check (is_owner());
create policy owner_all_edges on edge_snapshots
  for all using (is_owner()) with check (is_owner());
create policy owner_all_approvals on approvals
  for all using (is_owner()) with check (is_owner());
