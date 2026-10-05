-- 010: follow-ups that get faults FIXED, not just reported (Omar, 5 Oct 2026).
--   1. Escalation ladder: when a fault is still open N days after the first e-mail, the bot writes to the
--      next level up (table escalation_steps). Only rows with active = true are used, and only addresses
--      someone has checked go in. The first desk is chased at most twice (Joburg Connect asked us not to
--      repeat the same e-mail), then the ladder takes over.
--   2. "Is it fixed?" on the tracking page: residents tap Fixed / Still broken (fix_vote). Two different
--      callers saying fixed marks it fixed; two saying still broken re-opens a fixed one. One vote per caller
--      per report per day. Nobody is messaged, no names or numbers are collected.
--   3. Numbers for the weekly scorecard: report_counts gains the average days to fix.
-- Changes no existing report or e-mail.

-- ---------- 1. the ladder ----------
create table if not exists public.escalation_steps (
  id           serial primary key,
  municipality text not null default 'City of Johannesburg',
  category     text not null default 'default',   -- a report category, or 'default' for all
  level        integer not null check (level between 1 and 5),
  after_days   integer not null check (after_days between 7 and 180),
  name         text not null,
  to_email     text,
  note         text,
  source_url   text,
  needs_ref    boolean not null default false,  -- e.g. the Ombudsman only takes a fault that has a City reference
  active       boolean not null default false,
  created_at   timestamptz not null default now(),
  unique (municipality, category, level)
);
alter table public.escalation_steps enable row level security;   -- service role only, no policies

alter table public.outbox add column if not exists level integer not null default 0;
alter table public.outbox add column if not exists step_id integer references public.escalation_steps(id);
alter table public.outbox drop constraint if exists outbox_kind_check;
alter table public.outbox add constraint outbox_kind_check check (kind in ('first', 'chase', 'escalate'));

alter table public.bot_settings add column if not exists max_chases integer not null default 2;

-- ---------- 2. residents say fixed / still broken ----------
create table if not exists public.fix_votes (
  id         bigserial primary key,
  report_id  uuid not null references public.reports(id) on delete cascade,
  fixed      boolean not null,
  who        text not null,
  at         timestamptz not null default now()
);
create index if not exists fix_votes_report on public.fix_votes (report_id, at);
alter table public.fix_votes enable row level security;          -- service role only, no policies

alter table public.reports add column if not exists fixed_votes integer not null default 0;
alter table public.reports add column if not exists broken_votes integer not null default 0;
alter table public.reports add column if not exists last_broken_at timestamptz;
grant select (fixed_votes, broken_votes, last_broken_at) on public.reports to anon, authenticated;

create or replace function public.fix_vote(p_report uuid, p_fixed boolean) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r reports; v_who text := public.caller_hash(); v_since timestamptz; v_n integer; v_flip text := null;
begin
  if v_who is null then return json_build_object('error', 'no_caller'); end if;
  select * into r from reports where id = p_report and not hidden;
  if not found or r.status = 'closed' then return json_build_object('error', 'not_open'); end if;
  if (select count(*) from request_log where kind = 'fixvote' and who = v_who and at > now() - interval '1 hour') >= 20 then
    return json_build_object('error', 'too_many');
  end if;
  if exists (select 1 from fix_votes where report_id = r.id and who = v_who and at > now() - interval '1 day') then
    return json_build_object('error', 'already', 'fixed_votes', r.fixed_votes, 'broken_votes', r.broken_votes, 'status', r.status);
  end if;
  insert into request_log (kind, who, target) values ('fixvote', v_who, r.id::text);
  insert into fix_votes (report_id, fixed, who) values (r.id, p_fixed, v_who);

  if p_fixed and r.status <> 'fixed' then
    -- fixed votes that came after the last "still broken" vote, from different callers
    select max(at) into v_since from fix_votes where report_id = r.id and not fixed;
    select count(distinct who) into v_n from fix_votes
     where report_id = r.id and fixed and at > coalesce(v_since, '-infinity') and at > now() - interval '30 days';
    if v_n >= 2 then
      update reports set status = 'fixed', status_note = 'Two residents confirmed on the website that it is fixed.' where id = r.id;
      v_flip := 'fixed';
    end if;
  elsif not p_fixed and r.status = 'fixed' then
    select count(distinct who) into v_n from fix_votes
     where report_id = r.id and not fixed and at >= coalesce(r.fixed_at, '-infinity');
    if v_n >= 2 then
      update reports set status = 'escalated', fixed_at = null,
             status_note = 'Residents say it is broken again. The follow-ups start again.' where id = r.id;
      v_flip := 'reopened';
    end if;
  end if;

  update reports set
    fixed_votes  = (select count(distinct who) from fix_votes where report_id = r.id and fixed and at > now() - interval '30 days'),
    broken_votes = (select count(distinct who) from fix_votes where report_id = r.id and not fixed and at > now() - interval '30 days'),
    last_broken_at = case when p_fixed then last_broken_at else now() end
   where id = r.id
   returning * into r;
  return json_build_object('ok', true, 'status', r.status, 'fixed_votes', r.fixed_votes,
                           'broken_votes', r.broken_votes, 'changed', v_flip);
end $$;
revoke all on function public.fix_vote(uuid, boolean) from public;
grant execute on function public.fix_vote(uuid, boolean) to anon, authenticated;

-- ---------- the e-mails ----------
drop function if exists public.bot_draft(uuid, text);
create or replace function public.bot_draft(p_report uuid, p_kind text default 'first', p_step integer default null)
returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare r reports; s bot_settings; d departments; st escalation_steps; v_state text; v_reason text; v_subject text;
        v_body text; v_id bigint; v_sent timestamptz; v_first timestamptz; v_to text; v_dep text; v_level integer := 0;
        v_days integer; v_history text := '';
begin
  select * into r from reports where id = p_report;
  if not found then return null; end if;
  select * into s from bot_settings where id = 1;
  select * into d from departments where municipality = r.municipality and category = r.category;
  if not found then
    select * into d from departments where municipality = r.municipality and category = 'default';
  end if;
  v_to := d.email; v_dep := d.name;
  select min(sent_at), max(sent_at) into v_first, v_sent from outbox where report_id = r.id and state = 'sent';
  v_days := greatest(0, extract(day from now() - coalesce(v_first, r.created_at))::integer);

  if p_kind = 'escalate' then
    select * into st from escalation_steps where id = p_step and active;
    if not found then return null; end if;
    v_to := st.to_email; v_dep := st.name; v_level := st.level;
    select string_agg('- ' || to_char(o.sent_at at time zone 'Africa/Johannesburg', 'DD Mon YYYY') || ': ' ||
                      case o.kind when 'first' then 'reported to ' when 'chase' then 'followed up with ' else 'escalated to ' end ||
                      coalesce(o.department, o.to_email), E'\n' order by o.sent_at)
      into v_history from outbox o where o.report_id = r.id and o.state = 'sent';
  end if;

  v_subject := (case when r.escalation_ref is not null then '[' || r.escalation_ref || '] ' else '' end) ||
    (case p_kind when 'chase' then 'Follow-up: fault report '
                 when 'escalate' then 'Escalation: unresolved fault ' else 'Fault report ' end) || r.ref || ': ' ||
    bot_category_label(r.category) || ' - ' || r.area || ', ' || r.municipality;

  if p_kind = 'chase' then
    v_body := 'Good day' || E'\n\n' ||
      'We reported the fault below on ' || to_char(coalesce(v_sent, r.created_at) at time zone 'Africa/Johannesburg', 'DD Month YYYY') ||
      (case when r.escalation_ref is not null
            then '. Your reference is ' || r.escalation_ref || '. It has not been fixed yet. Please tell us what the status is.'
            else ' and have not received a reference number. Please log it and send us the reference.' end) || E'\n\n';
  elsif p_kind = 'escalate' then
    v_body := 'Good day' || E'\n\n' ||
      'We ask for your help with a fault that is still not fixed ' || v_days || ' days after it was first reported. ' ||
      (case when r.escalation_ref is not null then 'The City''s reference is ' || r.escalation_ref || '. '
            else 'The City has not given us a reference number. ' end) ||
      'What has been done so far:' || E'\n' || coalesce(v_history, '') || E'\n' ||
      (case when r.supports > 0 then E'\n' || r.supports || ' other resident(s) reported the same fault on the website.' else '' end) ||
      (case when r.last_broken_at is not null then E'\n' || 'Residents confirmed it was still broken on ' ||
            to_char(r.last_broken_at at time zone 'Africa/Johannesburg', 'DD Month YYYY') || '.' else '' end) ||
      E'\n\nPlease see that it is attended to, and tell us the reference and the expected date.' || E'\n\n';
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

  if v_to is null then
    v_state := 'needs_person';
    v_reason := coalesce(v_dep, 'This municipality') || ' cannot be reached by e-mail. ' ||
      coalesce('Log it here: ' || d.portal || '. ', '') || 'Then type their reference into the console.';
  elsif s.mode = 'auto' then
    v_state := 'approved'; v_reason := 'approved by the switch (automatic)';
  else
    v_state := 'waiting';
  end if;

  insert into outbox (report_id, kind, department, to_email, subject, body, state, reason, approved_at, approved_by, level, step_id)
  values (r.id, p_kind, v_dep, v_to, v_subject, v_body, v_state, v_reason,
          case when v_state = 'approved' then now() end, case when v_state = 'approved' then 'switch' end,
          v_level, case when p_kind = 'escalate' then p_step end)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.bot_draft(uuid, text, integer) from public, anon, authenticated;

-- Runs on every worker pull. One new e-mail per report per tick at most.
create or replace function public.bot_tick() returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare s bot_settings; r record; n integer := 0; v_step integer;
begin
  select * into s from bot_settings where id = 1;
  if s.paused then return 0; end if;
  for r in
    select rp.id, rp.category, rp.municipality, rp.escalation_ref, rp.updated_at, rp.last_broken_at,
           min(o.sent_at) filter (where o.kind = 'first') as first_sent,
           max(o.sent_at) as last_sent,
           count(*) filter (where o.kind = 'chase') as chases,
           coalesce(max(o.level), 0) as level,
           max(o.sent_at) filter (where o.kind = 'escalate') as last_escalated
      from reports rp join outbox o on o.report_id = rp.id and o.state = 'sent'
     where rp.source = any (s.sources) and not rp.hidden and rp.status not in ('fixed', 'closed')
       and not exists (select 1 from outbox w where w.report_id = rp.id and w.state in ('waiting', 'approved', 'sending', 'needs_person'))
     group by rp.id
  loop
    -- next rung of the ladder that is due (category-specific beats 'default'), at most one rung a week
    select e.id into v_step from escalation_steps e
     where e.active and e.to_email is not null and e.municipality = r.municipality
       and e.category in (r.category, 'default') and e.level > r.level
       and r.first_sent < now() - make_interval(days => e.after_days)
       and (r.last_escalated is null or r.last_escalated < now() - interval '7 days')
       and (not e.needs_ref or r.escalation_ref is not null)
       and not exists (select 1 from escalation_steps e2 where e2.active and e2.municipality = e.municipality
                         and e2.level = e.level and e2.category = r.category and e.category = 'default')
     order by e.level limit 1;
    if v_step is not null then
      perform bot_draft(r.id, 'escalate', v_step); n := n + 1;
    elsif r.level = 0 and r.chases < s.max_chases and (
          (r.escalation_ref is null and r.last_sent < now() - make_interval(days => s.chase_after_days))
       or (r.escalation_ref is not null and greatest(r.last_sent, r.updated_at) < now() - make_interval(days => s.chase_every_days))
       or (r.last_broken_at > r.last_sent and r.last_sent < now() - interval '3 days')) then
      perform bot_draft(r.id, 'chase'); n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.bot_tick() from public, anon, authenticated;

-- ---------- 3. numbers ----------
create or replace function public.report_counts(p_source text) returns json
language sql stable security definer set search_path = public, pg_temp as $$
  -- security definer: it reads the private column "hidden", which visitors may not read themselves
  select json_build_object(
    'open',  count(*) filter (where status in ('new', 'acknowledged')),
    'busy',  count(*) filter (where status in ('in_progress', 'escalated')),
    'fixed', count(*) filter (where status = 'fixed'),
    'with_ref', count(*) filter (where escalation_ref is not null),
    'avg_fix_days', round(avg(extract(epoch from fixed_at - created_at) / 86400) filter (where status = 'fixed' and fixed_at is not null), 1))
  from public.reports where source = p_source and not hidden
$$;

-- ---------- the rungs (all OFF until Omar switches each one on: Babe "ladder on 1") ----------
-- Found 5 Oct 2026; every address from a published source. Never add a guessed address.
insert into public.escalation_steps (category, level, after_days, name, to_email, note, source_url, needs_ref) values
 ('light',   1, 14, 'City Power customer service', 'customerservice@citypower.co.za',
  'Only e-mail City Power publishes. High confidence.', 'https://www.joburg.org.za/services_/electricity/Pages/contacting-City-Power.aspx', false),
 ('dumping', 1, 14, 'Pikitup', 'info@pikitup.co.za',
  'Pikitup general address (contacts page + City X account Feb 2025). High confidence.', 'https://www.pikitup.co.za/contacts/', false),
 ('default', 2, 21, 'Region G Regional Director (Mickey Padayachee)', 'mickeyp@joburg.org.za',
  'From the Region G page, undated; director list from 2019. Medium confidence: may be out of date.', 'https://www.joburg.org.za', false),
 ('default', 3, 28, 'Ward 120 councillor (Puseletso Nzimande)', 'nomumelelophoomy@gmail.com',
  'From the City councillor list 2022 (personal Gmail). Medium confidence. Political: Omar decides.', 'https://www.joburg.org.za', false),
 ('default', 4, 35, 'Office of the City Ombudsman', 'complaints@joburgombudsman.org.za',
  'Ombudsman contact page (2026). High confidence. Only takes a fault that has a City reference.', 'https://joburgombudsman.org.za/contact-us/', true)
on conflict (municipality, category, level) do nothing;
