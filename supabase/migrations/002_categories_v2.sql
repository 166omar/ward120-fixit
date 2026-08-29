-- Fix Ward 120 — add dumping / storm drain / street light categories
-- (applied 2026-08-29 via Supabase MCP as migration categories_v2)
alter table public.reports drop constraint reports_category_check;
alter table public.reports add constraint reports_category_check
  check (category in ('water','sewer','road','dumping','drain','light','other'));
