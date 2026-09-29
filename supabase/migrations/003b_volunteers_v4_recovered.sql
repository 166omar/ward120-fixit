-- ============================================================
-- 003b — volunteers (RECORD ONLY, do not run)
--
-- The live database lists a migration "volunteers_v4" (applied 2026-08-31 through
-- the Supabase MCP) but no file for it was ever saved. This file was rebuilt on
-- 2026-09-29 from what is live (information_schema, pg_policies, pg_constraint),
-- so the repo describes the database again.
-- ============================================================

create table public.volunteers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  phone text not null check (char_length(phone) between 7 and 20),
  area text,
  municipality text,
  skills text check (skills is null or char_length(skills) <= 500),
  created_at timestamptz not null default now()
);

alter table public.volunteers enable row level security;

-- anyone may sign up; only the team may read
create policy vol_insert on public.volunteers for insert with check (true);
create policy vol_select_admin on public.volunteers for select using (public.is_admin());

revoke all on public.volunteers from anon, authenticated;
grant insert (name, phone, area, municipality, skills) on public.volunteers to anon, authenticated;
grant select on public.volunteers to authenticated;   -- rows still gated by vol_select_admin
