-- ============================================================
-- 005 — source of each report, team-only reads through functions, limits
-- (applied 2026-09-29 with run_sql.py)
--
-- WHY: until today every signed-in account could read reporter_name and
-- reporter_phone (001_schema.sql line 117 grants table-wide SELECT to
-- "authenticated", and the select policy is "true"). Public sign-up was also on.
-- Sign-up was switched off on 2026-09-29 through the Management API. This file
-- adds what the consoles need so that 006 can take the table-wide grant away.
--
-- This file only ADDS. Nothing that works today stops working.
-- ============================================================

-- ---------- "Tell the reporter" (004_notified.sql was never applied) ----------
alter table public.reports add column if not exists notified_at timestamptz;
comment on column public.reports.notified_at is
  'When the reporter was last told the status of their own report (team-only, never public).';
grant update (notified_at) on public.reports to authenticated;

-- ---------- where a report came from ----------
-- ward120   = Fix Ward 120 page
-- gauteng   = Truth and Solidarity Gauteng page
-- lenzsouth = lenzsouth.co.za, the neutral town site. Shown publicly ONLY there.
alter table public.reports
  add column if not exists source text not null default 'ward120',
  add column if not exists hidden boolean not null default false,
  add column if not exists client_id uuid;
alter table public.reports drop constraint if exists reports_source_check;
alter table public.reports add constraint reports_source_check
  check (source in ('ward120', 'gauteng', 'lenzsouth'));
comment on column public.reports.hidden is
  'Team switch: takes an abusive or test report off every public page without deleting it.';
comment on column public.reports.client_id is
  'Made on the reporter''s phone. A report that is re-sent after a lost reply cannot arrive twice.';
create unique index if not exists reports_client_id_key on public.reports (client_id);
create index if not exists reports_source_created_idx on public.reports (source, created_at desc);

grant select (source, client_id) on public.reports to anon, authenticated;
grant insert (source, client_id) on public.reports to anon, authenticated;
grant update (hidden) on public.reports to authenticated;          -- still gated by is_admin()

-- ---------- reference numbers: LS- for the town site, TS- for the rest ----------
-- PostgreSQL 17 can change the expression in place, so the column and its grants survive.
alter table public.reports alter column ref set expression as (
  (case source when 'lenzsouth' then 'LS-' else 'TS-' end) || lpad(seq::text, 4, '0'));
grant select (ref, municipality) on public.reports to anon, authenticated;
create unique index if not exists reports_ref_key on public.reports (ref);

-- ---------- team-only reads ----------
create or replace function public.admin_reports() returns setof public.reports
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query select * from public.reports order by created_at desc limit 1000;
end $$;
revoke all on function public.admin_reports() from public, anon, authenticated;
grant execute on function public.admin_reports() to authenticated;

-- A reporter may ask for their name and number to be removed. The report itself stays.
create or replace function public.admin_forget_reporter(p_report uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.reports set reporter_name = null, reporter_phone = null where id = p_report;
  return found;
end $$;
revoke all on function public.admin_forget_reporter(uuid) from public, anon, authenticated;
grant execute on function public.admin_forget_reporter(uuid) to authenticated;

-- ---------- counters for a public page ----------
create or replace function public.report_counts(p_source text) returns json
language sql stable security invoker set search_path = public, pg_temp as $$
  select json_build_object(
    'open',  count(*) filter (where status in ('new', 'acknowledged')),
    'busy',  count(*) filter (where status in ('in_progress', 'escalated')),
    'fixed', count(*) filter (where status = 'fixed'))
  from public.reports where source = p_source
$$;
revoke all on function public.report_counts(text) from public;
grant execute on function public.report_counts(text) to anon, authenticated;

-- ---------- hidden reports leave every public page ----------
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports for select
  using (not hidden or (select public.is_admin()));
drop policy if exists history_select on public.status_history;
create policy history_select on public.status_history for select
  using (exists (select 1 from public.reports r where r.id = status_history.report_id));

-- ---------- what a report may contain ----------
alter table public.reports drop constraint if exists reports_ls_box;
alter table public.reports add constraint reports_ls_box
  check (source <> 'lenzsouth' or (lat between -26.44 and -26.34 and lng between 27.80 and 27.905)) not valid;
alter table public.reports validate constraint reports_ls_box;

alter table public.reports drop constraint if exists reports_ls_text;
alter table public.reports add constraint reports_ls_text
  check (source <> 'lenzsouth'
         or (char_length(description) between 10 and 600 and description !~* '(https?://|www\.)')) not valid;
alter table public.reports validate constraint reports_ls_text;

-- a report may only point at a photo in our own bucket
alter table public.reports drop constraint if exists reports_photo_own;
alter table public.reports add constraint reports_photo_own check (
  (photo_url is null or photo_url like 'https://vzwkelixolmexgfkwoif.supabase.co/storage/v1/object/public/report-photos/%')
  and (fixed_photo_url is null or fixed_photo_url like 'https://vzwkelixolmexgfkwoif.supabase.co/storage/v1/object/public/report-photos/%')
) not valid;
alter table public.reports validate constraint reports_photo_own;

alter table public.reports drop constraint if exists reports_contact_len;
alter table public.reports add constraint reports_contact_len check (
  char_length(coalesce(reporter_name, '')) <= 120 and char_length(coalesce(reporter_phone, '')) <= 20) not valid;
alter table public.reports validate constraint reports_contact_len;

-- ---------- limits (free tier, no captcha) ----------
-- One locked table. "who" is a salted hash of the caller's address, kept two days.
create table if not exists public.request_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  kind text not null,
  who text not null,
  target text
);
create index if not exists request_log_idx on public.request_log (kind, who, at desc);
create table if not exists public.app_secrets (key text primary key, value text not null);
insert into public.app_secrets (key, value)
  values ('log_salt', encode(extensions.gen_random_bytes(16), 'hex'))
  on conflict (key) do nothing;
alter table public.request_log enable row level security;
alter table public.app_secrets enable row level security;
revoke all on public.request_log, public.app_secrets from anon, authenticated;

-- null when the call did not come through the API (seed scripts, the dashboard)
create or replace function public.caller_hash() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare h json; ip text; salt text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    return null;
  end;
  if h is null then return null; end if;
  ip := trim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1));
  if ip = '' then return null; end if;
  select value into salt from app_secrets where key = 'log_salt';
  return encode(digest(coalesce(salt, '') || ip, 'sha256'), 'hex');
end $$;
revoke all on function public.caller_hash() from public, anon, authenticated;

create or replace function public.reports_before_insert() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_who text := public.caller_hash();
begin
  if v_who is null then return new; end if;
  if (select count(*) from request_log where kind = 'report' and who = v_who
        and at > now() - interval '1 hour') >= 5
     or (select count(*) from request_log where kind = 'report' and who = v_who
        and at > now() - interval '1 day') >= 12
     or (select count(*) from request_log where kind = 'report' and target = new.source
        and at > now() - interval '1 hour') >= 60 then
    raise sqlstate 'PGRST' using
      message = '{"code":"LIMIT","message":"Too many reports from this connection. Please try again in an hour.","details":null,"hint":null}',
      detail  = '{"status":429,"headers":{}}';
  end if;
  insert into request_log (kind, who, target) values ('report', v_who, new.source);
  delete from request_log where at < now() - interval '2 days';
  return new;
end $$;
drop trigger if exists trg_reports_bi on public.reports;
create trigger trg_reports_bi before insert on public.reports
  for each row execute function public.reports_before_insert();

-- "This affects me too": a few per caller, and only on reports that are still open and visible
create or replace function public.add_support(p_report uuid) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v integer; v_who text := public.caller_hash();
begin
  if v_who is not null then
    if (select count(*) from request_log where kind = 'support' and who = v_who
          and target = p_report::text and at > now() - interval '1 day') >= 3
       or (select count(*) from request_log where kind = 'support' and who = v_who
          and at > now() - interval '1 hour') >= 30 then
      select supports into v from reports where id = p_report and not hidden;
      return v;
    end if;
    insert into request_log (kind, who, target) values ('support', v_who, p_report::text);
  end if;
  update reports set supports = supports + 1
   where id = p_report and not hidden and status not in ('fixed', 'closed')
   returning supports into v;
  if v is null then
    select supports into v from reports where id = p_report and not hidden;
  end if;
  return v;
end $$;
revoke all on function public.add_support(uuid) from public;
grant execute on function public.add_support(uuid) to anon, authenticated;

-- a "me too" must not reset the console's "no update for 7 days" alarm
create or replace function public.reports_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status
     or new.status_note is distinct from old.status_note
     or new.escalation_ref is distinct from old.escalation_ref
     or new.fixed_photo_url is distinct from old.fixed_photo_url then
    new.updated_at := now();
  end if;
  if new.status = 'fixed' and new.fixed_at is null then
    new.fixed_at := now();
  end if;
  return new;
end $$;

-- ---------- photos ----------
-- phones shrink photos to 1280 px JPEG before upload (common.js compressImage), so 1 MB is generous
update storage.buckets
   set file_size_limit = 1048576, allowed_mime_types = array['image/jpeg']
 where id = 'report-photos';
drop policy if exists "w120 upload photos" on storage.objects;
create policy "w120 upload photos" on storage.objects
  for insert to anon, authenticated with check (
    bucket_id = 'report-photos'
    and name ~ '^(ls/)?[0-9a-f-]{36}\.jpg$'
    and (select count(*) from storage.objects o
          where o.bucket_id = 'report-photos' and o.created_at > now() - interval '1 hour') < 40
    and (select count(*) from storage.objects o
          where o.bucket_id = 'report-photos' and o.created_at > now() - interval '1 day') < 200
  );

notify pgrst, 'reload schema';
