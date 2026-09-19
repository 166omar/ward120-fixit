-- ============================================================
-- 004 — "Tell the reporter"
--
-- Residents were reporting faults and never hearing back. This records when we
-- last told the person who reported it what was happening with their fault.
--
-- PRIVACY: notified_at is deliberately NOT added to the anon select grant in
-- 001_schema.sql. That grant is an explicit column whitelist, so a new column is
-- invisible to the public by default — the same protection that keeps
-- reporter_name and reporter_phone off the public page. Do not add it to the
-- anon grant. Anyone adding a future column must follow this same pattern.
-- ============================================================

alter table public.reports
  add column if not exists notified_at timestamptz;

comment on column public.reports.notified_at is
  'When the reporter was last told the status of their own report (team-only, never public). Set by the "Tell the reporter" button in admin.html.';

-- The team already has table-wide SELECT (001_schema.sql line 117), so they can
-- read it. They also need to be able to stamp it. This grant is additive and is
-- still gated by the reports_update policy, which requires is_admin().
grant update (notified_at) on public.reports to authenticated;

-- Deliberately NOT granted to anon, for either select or update.
