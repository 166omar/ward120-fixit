-- ============================================================
-- 006 — the lock (applied 2026-09-29 with run_sql.py, after both consoles were
-- reading through admin_reports())
--
-- Until now "authenticated" had table-wide SELECT on reports, so ANY signed-in
-- account could read reporter_name and reporter_phone. From here on a signed-in
-- account reads exactly the public columns, the same as a visitor. The team gets
-- names and numbers only through admin_reports(), which checks the team list.
--
-- Adding a column later? It is invisible to everyone until you grant it here.
-- Never grant reporter_name, reporter_phone, notified_at or hidden.
-- ============================================================
begin;

revoke select on public.reports from authenticated;
grant select (id, seq, ref, source, client_id, category, description, area, municipality, lat, lng,
              photo_url, status, status_note, escalation_ref, fixed_photo_url, fixed_at,
              supports, created_at, updated_at)
  on public.reports to anon, authenticated;

-- volunteers: rows were already limited to the team by policy vol_select_admin.
-- Nothing to change; recorded in 003b_volunteers_v4_recovered.sql.

notify pgrst, 'reload schema';
commit;
