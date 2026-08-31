-- Truth and Solidarity — Gauteng expansion (applied 2026-08-31 via Supabase MCP as gauteng_v3)
-- One shared ledger for the whole province; refs become movement-wide TS-XXXX.
alter table public.reports add column municipality text not null default 'City of Johannesburg';
alter table public.reports drop column ref;
alter table public.reports add column ref text generated always as ('TS-' || lpad(seq::text, 4, '0')) stored;
grant select (ref, municipality) on public.reports to anon;
grant insert (municipality) on public.reports to anon, authenticated;
