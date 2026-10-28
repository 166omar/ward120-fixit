-- 009: faults spotted in a WhatsApp group (LS Service Delivery), waiting for Omar's yes on Babe.
-- Filled by community-help/tools/fault_scan.py on the shop PC (Management API, service level).
-- PRIVATE: holds the group member's words and label. RLS on with no policies, so the public
-- (anon) key can neither read nor write it. Nothing here is ever shown on the website:
-- a yes creates a normal lenzsouth report with a neutral description and no reporter details.
create table if not exists public.group_candidates (
  id          bigserial primary key,
  seen_key    text not null unique,            -- hash of group + day + time + sender + text
  group_name  text not null,
  msg_time    text,                            -- as WhatsApp shows it, e.g. "14:05"
  msg_day     text,
  sender      text,                            -- private: never copied into reports
  text        text not null,                   -- private: never copied into reports
  category    text not null check (category in ('water', 'sewer', 'road', 'dumping', 'drain', 'light', 'other')),
  street      text,
  lat         double precision,
  lng         double precision,
  dup_ref     text,                            -- an open report nearby with the same category
  status      text not null default 'new' check (status in ('new', 'asked', 'reported', 'dropped')),
  report_ref  text,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
alter table public.group_candidates enable row level security;
revoke all on public.group_candidates from anon, authenticated;
create index if not exists group_candidates_status on public.group_candidates (status);
