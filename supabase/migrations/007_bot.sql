-- ============================================================
-- 007 — the fault bot (applied 2026-09-29 with run_sql.py)
--
-- What it does: for every new report from a site listed in bot_settings.sources it
-- writes the e-mail to the right City department. A person approves it with one tap
-- (mode 'approve') or it is approved by itself (mode 'auto'). A worker sends approved
-- e-mails, reads the City's replies, saves their reference number on the report and
-- writes a chase e-mail when the City goes quiet.
--
-- The database does everything that can be done without the outside world. Only two
-- jobs need a worker: SEND an e-mail and READ the replies. The worker talks to the
-- bot_* functions below and must know the bot code. It never gets a database key.
--
-- Nothing here is readable by visitors: all four tables are locked, like gotv_*.
-- ============================================================
begin;

create table if not exists public.bot_settings (
  id integer primary key default 1 check (id = 1),
  mode text not null default 'approve' check (mode in ('approve', 'auto')),
  paused boolean not null default false,
  sources text[] not null default array['lenzsouth'],
  chase_after_days integer not null default 5,     -- no City reference this long after sending: chase
  chase_every_days integer not null default 7,     -- has a reference but is not fixed: chase this often
  max_per_run integer not null default 10,
  test_to text default '166omar@gmail.com',        -- while tests_left > 0 the e-mail goes here first
  tests_left integer not null default 3,
  code_hash text,
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into public.bot_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.departments (
  id bigint generated always as identity primary key,
  municipality text not null,
  category text not null default 'default',        -- a report category, or 'default'
  email text,                                      -- null = cannot be logged by e-mail
  portal text,                                     -- where a person must log it instead
  name text not null,
  note text,
  unique (municipality, category)
);
insert into public.departments (municipality, category, email, portal, name, note) values
  ('City of Johannesburg', 'default', 'joburgconnect@joburg.org.za', null, 'Joburg Connect', 'verified 10 Sept 2026; replies with a CSDFMC reference'),
  ('City of Johannesburg', 'light',   'joburgconnect@joburg.org.za', null, 'Joburg Connect (City Power faults)', 'verified 10 Sept 2026'),
  ('City of Johannesburg', 'road',    'hotline@jra.org.za', null, 'Johannesburg Roads Agency', 'verified 11 Sept 2026; replies with an SR reference'),
  ('City of Johannesburg', 'drain',   'hotline@jra.org.za', null, 'Johannesburg Roads Agency', 'verified 11 Sept 2026'),
  ('City of Johannesburg', 'dumping', 'illegaldumping@pikitup.co.za', null, 'Pikitup', 'no reply to three faults sent 10 Sept 2026'),
  ('City of Johannesburg', 'water',   null, 'https://customer.forcelink.net/joburg_water/login', 'Johannesburg Water',
     'E-mail to fault@jwater.co.za gives NO reference (learned 16 Sept 2026). Only the portal does, and it needs a login.'),
  ('City of Johannesburg', 'sewer',   null, 'https://customer.forcelink.net/joburg_water/login', 'Johannesburg Water',
     'Same as water: portal only.')
on conflict (municipality, category) do nothing;

create table if not exists public.outbox (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.reports(id),
  kind text not null default 'first' check (kind in ('first', 'chase')),
  department text,
  to_email text,
  subject text not null,
  body text not null,
  state text not null default 'waiting'
    check (state in ('waiting', 'approved', 'sending', 'sent', 'failed', 'rejected', 'needs_person')),
  reason text,
  tries integer not null default 0,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by text,
  sent_at timestamptz,
  message_id text,
  thread_id text
);
create index if not exists outbox_state_idx on public.outbox (state, created_at);
create index if not exists outbox_report_idx on public.outbox (report_id, created_at desc);

create table if not exists public.inbox (
  id bigint generated always as identity primary key,
  report_id uuid references public.reports(id),
  from_email text,
  subject text,
  snippet text,
  city_ref text,
  message_id text unique,
  received_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.bot_settings enable row level security;
alter table public.departments  enable row level security;
alter table public.outbox       enable row level security;
alter table public.inbox        enable row level security;
revoke all on public.bot_settings, public.departments, public.outbox, public.inbox from anon, authenticated;

-- ---------- who signs for which site ----------
create or replace function public.bot_signoff(p_source text) returns text
language sql immutable as $$
  select case p_source
    when 'lenzsouth' then
      'This fault is listed publicly on lenzsouth.co.za, the Lenasia South community website. ' ||
      'Kindly reply with your reference number so that we can publish it for residents.' || E'\n\n' ||
      'Thank you' || E'\n' || 'Omar Khan' || E'\n' || 'Khan''s Butchery, NTN Centre, Lenasia South' || E'\n' || '063 690 7708'
    else
      'This fault is tracked publicly by the Truth and Solidarity community project. ' ||
      'Kindly reply with your reference number so we can publish it for residents.' || E'\n\n' ||
      'Thank you' || E'\n' || 'Truth and Solidarity'
  end
$$;

create or replace function public.bot_category_label(p text) returns text
language sql immutable as $$
  select case p when 'water' then 'Water leak' when 'sewer' then 'Sewer spill' when 'road' then 'Road damage'
    when 'dumping' then 'Illegal dumping' when 'drain' then 'Blocked storm drain' when 'light' then 'Street light out'
    else 'Other problem' end
$$;

-- ---------- write the e-mail for one report ----------
create or replace function public.bot_draft(p_report uuid, p_kind text default 'first') returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reports; s bot_settings; d departments; v_state text; v_reason text; v_subject text; v_body text; v_id bigint; v_sent timestamptz;
begin
  select * into r from reports where id = p_report;
  if not found then return null; end if;
  select * into s from bot_settings where id = 1;
  select * into d from departments where municipality = r.municipality and category = r.category;
  if not found then
    select * into d from departments where municipality = r.municipality and category = 'default';
  end if;

  v_subject := (case when r.escalation_ref is not null then '[' || r.escalation_ref || '] ' else '' end) ||
    (case when p_kind = 'chase' then 'Follow-up: fault report ' else 'Fault report ' end) || r.ref || ': ' ||
    bot_category_label(r.category) || ' - ' || r.area || ', ' || r.municipality;

  if p_kind = 'chase' then
    select max(sent_at) into v_sent from outbox where report_id = r.id and state = 'sent';
    v_body := 'Good day' || E'\n\n' ||
      'We reported the fault below on ' || to_char(coalesce(v_sent, r.created_at) at time zone 'Africa/Johannesburg', 'DD Month YYYY') ||
      (case when r.escalation_ref is not null
            then '. Your reference is ' || r.escalation_ref || '. It has not been fixed yet. Please tell us what the status is.'
            else ' and have not received a reference number. Please log it and send us the reference.' end) || E'\n\n';
  else
    v_body := 'Good day' || E'\n\n' || 'Please log the following fault and provide a reference number.' || E'\n\n';
  end if;

  v_body := v_body ||
    'Type of fault: ' || bot_category_label(r.category) || E'\n' ||
    'Location: ' || r.area || ', ' || r.municipality || E'\n' ||
    'GPS: ' || round(r.lat::numeric, 6) || ', ' || round(r.lng::numeric, 6) || E'\n' ||
    'Map: https://www.google.com/maps?q=' || round(r.lat::numeric, 6) || ',' || round(r.lng::numeric, 6) || E'\n' ||
    'Description: ' || r.description || E'\n' ||
    (case when r.photo_url is not null then 'Photo: ' || r.photo_url || E'\n' else '' end) ||
    'First reported: ' || to_char(r.created_at at time zone 'Africa/Johannesburg', 'DD Month YYYY') || E'\n' ||
    'Community reference: ' || r.ref || E'\n' ||
    (case when r.source = 'lenzsouth' then 'Public record: https://lenzsouth.co.za/report/?ref=' || r.ref || E'\n' else '' end) ||
    E'\n' || bot_signoff(r.source);

  if d.id is null or d.email is null then
    v_state := 'needs_person';
    v_reason := coalesce(d.name, 'This municipality') || ' cannot be reached by e-mail. ' ||
      coalesce('Log it here: ' || d.portal || '. ', '') || 'Then type their reference into the console.';
  elsif s.mode = 'auto' then
    v_state := 'approved'; v_reason := 'approved by the switch (automatic)';
  else
    v_state := 'waiting';
  end if;

  insert into outbox (report_id, kind, department, to_email, subject, body, state, reason, approved_at, approved_by)
  values (r.id, p_kind, d.name, d.email, v_subject, v_body, v_state, v_reason,
          case when v_state = 'approved' then now() end, case when v_state = 'approved' then 'switch' end)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.bot_draft(uuid, text) from public, anon, authenticated;

-- a new report gets its e-mail written straight away; a bot problem must never block a report
create or replace function public.reports_after_insert_bot() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare s bot_settings;
begin
  begin
    select * into s from bot_settings where id = 1;
    if found and not s.paused and new.source = any (s.sources) and not new.hidden then
      perform bot_draft(new.id, 'first');
    end if;
  exception when others then
    null;
  end;
  return new;
end $$;
drop trigger if exists trg_reports_ai_bot on public.reports;
create trigger trg_reports_ai_bot after insert on public.reports
  for each row execute function public.reports_after_insert_bot();

-- ---------- chase e-mails ----------
create or replace function public.bot_tick() returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare s bot_settings; r record; n integer := 0;
begin
  select * into s from bot_settings where id = 1;
  if s.paused then return 0; end if;
  for r in
    select rp.id, max(o.sent_at) as last_sent
      from reports rp join outbox o on o.report_id = rp.id and o.state = 'sent'
     where rp.source = any (s.sources) and not rp.hidden and rp.status not in ('fixed', 'closed')
       and not exists (select 1 from outbox w where w.report_id = rp.id and w.state in ('waiting', 'approved', 'sending'))
     group by rp.id, rp.escalation_ref, rp.updated_at
    having (rp.escalation_ref is null and max(o.sent_at) < now() - make_interval(days => s.chase_after_days))
        or (rp.escalation_ref is not null and greatest(max(o.sent_at), rp.updated_at) < now() - make_interval(days => s.chase_every_days))
  loop
    perform bot_draft(r.id, 'chase'); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.bot_tick() from public, anon, authenticated;

-- ---------- the worker's door ----------
create or replace function public.bot_ok(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare h text;
begin
  if (select count(*) from request_log where kind = 'botfail' and at > now() - interval '10 minutes') >= 20 then
    return false;
  end if;
  select code_hash into h from bot_settings where id = 1;
  if h is null or p_code is null or crypt(p_code, h) <> h then
    insert into request_log (kind, who, target) values ('botfail', coalesce(public.caller_hash(), 'unknown'), null);
    perform pg_sleep(1);
    return false;
  end if;
  return true;
end $$;
revoke all on function public.bot_ok(text) from public, anon, authenticated;

-- what to send now, and which sent e-mails are still waiting for the City's answer
create or replace function public.bot_pull(p_code text) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s bot_settings; v_send json; v_watch json; v_chase integer;
begin
  if not bot_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  select * into s from bot_settings where id = 1;
  if s.paused then return json_build_object('paused', true, 'send', '[]'::json, 'watch', '[]'::json); end if;
  v_chase := bot_tick();
  with pick as (
    select o.id from outbox o where o.state = 'approved' and o.to_email is not null
     order by o.created_at limit s.max_per_run for update skip locked
  ), upd as (
    update outbox o set state = 'sending', tries = tries + 1 from pick where o.id = pick.id
    returning o.id, o.to_email, o.subject, o.body, o.report_id, o.kind
  )
  select coalesce(json_agg(json_build_object(
           'id', u.id, 'ref', r.ref, 'kind', u.kind,
           'test', (s.tests_left > 0 and s.test_to is not null),
           'to', case when s.tests_left > 0 and s.test_to is not null then s.test_to else u.to_email end,
           'real_to', u.to_email,
           'subject', case when s.tests_left > 0 and s.test_to is not null then '[TEST COPY, not sent to the City yet] ' || u.subject else u.subject end,
           'body', u.body)), '[]'::json)
    into v_send from upd u join reports r on r.id = u.report_id;
  select coalesce(json_agg(json_build_object(
           'ref', r.ref, 'to', o.to_email, 'subject', o.subject, 'sent_at', o.sent_at,
           'message_id', o.message_id, 'thread_id', o.thread_id, 'city_ref', r.escalation_ref)), '[]'::json)
    into v_watch
    from outbox o join reports r on r.id = o.report_id
   where o.state = 'sent' and o.sent_at > now() - interval '45 days' and r.status not in ('fixed', 'closed');
  return json_build_object('mode', s.mode, 'paused', false, 'chase_written', v_chase, 'send', v_send, 'watch', v_watch);
end $$;

create or replace function public.bot_sent(p_code text, p_id bigint, p_message_id text, p_thread_id text, p_test boolean default false)
returns json language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o outbox; r reports;
begin
  if not bot_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  select * into o from outbox where id = p_id and state = 'sending';
  if not found then return json_build_object('error', 'not_sending'); end if;
  if p_test then
    -- a copy went to the owner, not to the City: it waits for a second yes
    update outbox set state = 'waiting', approved_at = null, approved_by = null,
           reason = 'Test copy sent to the owner on ' || to_char(now() at time zone 'Africa/Johannesburg', 'DD Mon HH24:MI') ||
                    '. Approve again to send it to the City.'
     where id = p_id;
    update bot_settings set tests_left = greatest(tests_left - 1, 0) where id = 1;
    return json_build_object('ok', true, 'test', true);
  end if;
  update outbox set state = 'sent', sent_at = now(), message_id = p_message_id, thread_id = p_thread_id where id = p_id;
  select * into r from reports where id = o.report_id;
  if r.status in ('new', 'acknowledged') then
    update reports set status = 'escalated',
           status_note = 'Sent to ' || coalesce(o.department, 'the City') || ' by e-mail. Waiting for their reference number.'
     where id = r.id;
  end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.bot_failed(p_code text, p_id bigint, p_error text)
returns json language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not bot_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  update outbox set state = case when tries >= 3 then 'failed' else 'approved' end, reason = left(coalesce(p_error, 'unknown error'), 300)
   where id = p_id and state = 'sending';
  return json_build_object('ok', found);
end $$;

-- a reply from the City. The reference is saved on the report and shows on the public timeline.
create or replace function public.bot_reply(p_code text, p_ref text, p_city_ref text, p_from text, p_subject text,
                                            p_snippet text, p_message_id text, p_received_at timestamptz default now())
returns json language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r reports; v_ref text := nullif(trim(p_city_ref), ''); v_new boolean := false;
begin
  if not bot_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  select * into r from reports where ref = upper(trim(p_ref));
  if not found then return json_build_object('error', 'no_such_report'); end if;
  if v_ref is not null and v_ref !~ '^[A-Za-z0-9][A-Za-z0-9 /_-]{3,39}$' then
    return json_build_object('error', 'bad_reference');
  end if;
  begin
    insert into inbox (report_id, from_email, subject, snippet, city_ref, message_id, received_at)
    values (r.id, left(p_from, 200), left(p_subject, 300), left(p_snippet, 600), v_ref, p_message_id, p_received_at);
  exception when unique_violation then
    return json_build_object('ok', true, 'seen_before', true);
  end;
  if v_ref is not null and r.escalation_ref is null then
    update reports set escalation_ref = v_ref,
           status = case when status in ('new', 'acknowledged') then 'escalated' else status end,
           status_note = 'The City gave reference ' || v_ref || '.'
     where id = r.id;
    v_new := true;
  end if;
  return json_build_object('ok', true, 'reference_saved', v_new);
end $$;

revoke all on function public.bot_pull(text), public.bot_sent(text, bigint, text, text, boolean),
  public.bot_failed(text, bigint, text),
  public.bot_reply(text, text, text, text, text, text, text, timestamptz) from public;
grant execute on function public.bot_pull(text), public.bot_sent(text, bigint, text, text, boolean),
  public.bot_failed(text, bigint, text),
  public.bot_reply(text, text, text, text, text, text, text, timestamptz) to anon, authenticated;

-- ---------- the team's side (console) ----------
create or replace function public.admin_bot() returns json
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare s bot_settings;
begin
  if not is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from bot_settings where id = 1;
  return json_build_object('mode', s.mode, 'paused', s.paused, 'sources', s.sources, 'tests_left', s.tests_left,
    'test_to', s.test_to, 'chase_after_days', s.chase_after_days, 'chase_every_days', s.chase_every_days,
    'worker_ready', s.code_hash is not null,
    'outbox', (select coalesce(json_agg(x order by x.created_at desc), '[]'::json) from (
        select o.id, r.ref, r.source, o.kind, o.department, o.to_email, o.subject, o.body, o.state, o.reason,
               o.created_at, o.sent_at
          from outbox o join reports r on r.id = o.report_id
         where o.state in ('waiting', 'approved', 'sending', 'failed', 'needs_person')
            or o.created_at > now() - interval '14 days' limit 200) x));
end $$;

create or replace function public.admin_bot_mode(p_mode text, p_paused boolean default null) returns json
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_mode is not null and p_mode not in ('approve', 'auto') then raise exception 'mode must be approve or auto'; end if;
  update bot_settings set mode = coalesce(p_mode, mode), paused = coalesce(p_paused, paused),
         updated_at = now(), updated_by = coalesce(auth.jwt() ->> 'email', 'console') where id = 1;
  -- switching to automatic approves what is waiting, except test copies that were never read
  if p_mode = 'auto' then
    update outbox set state = 'approved', approved_at = now(), approved_by = 'switch'
     where state = 'waiting' and to_email is not null;
  end if;
  return admin_bot();
end $$;

create or replace function public.admin_outbox_set(p_id bigint, p_action text) returns json
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_action = 'approve' then
    update outbox set state = 'approved', approved_at = now(), approved_by = coalesce(auth.jwt() ->> 'email', 'console'), reason = null
     where id = p_id and state in ('waiting', 'failed') and to_email is not null;
  elsif p_action = 'reject' then
    update outbox set state = 'rejected', reason = 'rejected by ' || coalesce(auth.jwt() ->> 'email', 'console')
     where id = p_id and state in ('waiting', 'approved', 'failed', 'needs_person');
  elsif p_action = 'done' then                     -- a person logged it on a portal
    update outbox set state = 'sent', sent_at = now(), reason = 'logged by a person' where id = p_id and state = 'needs_person';
  else
    raise exception 'action must be approve, reject or done';
  end if;
  return json_build_object('ok', found);
end $$;

revoke all on function public.admin_bot(), public.admin_bot_mode(text, boolean), public.admin_outbox_set(bigint, text) from public, anon;
grant execute on function public.admin_bot(), public.admin_bot_mode(text, boolean), public.admin_outbox_set(bigint, text) to authenticated;

notify pgrst, 'reload schema';
commit;
