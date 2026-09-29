-- 008: the console and Babe must say honestly whether a sending worker is running.
-- Until now "worker_ready" only meant "a code has been set". Now it means "a worker asked for work
-- in the last 3 hours". bot_pull stamps the time of every valid call.
-- Adds one column and replaces two functions. Changes no report and no e-mail.

alter table public.bot_settings add column if not exists last_pull_at timestamptz;

create or replace function public.bot_pull(p_code text) returns json
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s bot_settings; v_send json; v_watch json; v_chase integer;
begin
  if not bot_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  update bot_settings set last_pull_at = now() where id = 1;
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

create or replace function public.admin_bot() returns json
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare s bot_settings;
begin
  if not is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from bot_settings where id = 1;
  return json_build_object('mode', s.mode, 'paused', s.paused, 'sources', s.sources, 'tests_left', s.tests_left,
    'test_to', s.test_to, 'chase_after_days', s.chase_after_days, 'chase_every_days', s.chase_every_days,
    'worker_ready', coalesce(s.last_pull_at > now() - interval '3 hours', false),
    'worker_seen', s.last_pull_at,
    'outbox', (select coalesce(json_agg(x order by x.created_at desc), '[]'::json) from (
        select o.id, r.ref, r.source, o.kind, o.department, o.to_email, o.subject, o.body, o.state, o.reason,
               o.created_at, o.sent_at
          from outbox o join reports r on r.id = o.report_id
         where o.state in ('waiting', 'approved', 'sending', 'failed', 'needs_person')
            or o.created_at > now() - interval '14 days' limit 200) x));
end $$;

-- same rights as before (create or replace keeps them; stated again so this file stands alone)
revoke all on function public.bot_pull(text) from public;
grant execute on function public.bot_pull(text) to anon, authenticated;
revoke all on function public.admin_bot() from public, anon;
grant execute on function public.admin_bot() to authenticated;

select json_build_object('last_pull_at', (select last_pull_at from public.bot_settings where id = 1)) as j;
