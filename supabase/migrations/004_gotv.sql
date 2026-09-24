-- ============================================================
-- 004 — GET OUT THE VOTE tracker (Ward 120, election 4 Nov 2026)
-- Tables are locked (RLS on, no policies). The page talks ONLY to the
-- gotv_* functions below, and every one of them checks the team code.
-- POPIA: a name/phone is stored only when the voter said yes (consent = true
-- is enforced by a CHECK). Delete all gotv_people rows after the election.
-- ============================================================
create extension if not exists pgcrypto;

create table if not exists public.gotv_settings (
  id int primary key default 1 check (id = 1),
  code_hash text not null,
  target int not null default 3200,
  updated_at timestamptz not null default now()
);

create table if not exists public.gotv_failed (
  at timestamptz not null default now()
);

create table if not exists public.gotv_streets (
  id bigint generated always as identity primary key,
  name text not null unique,
  metres int,
  area text,
  vd bigint,
  station text,
  lat double precision,
  lng double precision,
  status text not null default 'todo' check (status in ('todo','started','done')),
  status_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.gotv_doors (
  id bigint generated always as identity primary key,
  street_id bigint not null references public.gotv_streets(id) on delete cascade,
  house_no text,
  result text not null check (result in ('yes','maybe','no','not_home')),
  note text,
  volunteer text,
  created_at timestamptz not null default now()
);
create index if not exists gotv_doors_street on public.gotv_doors(street_id);

create table if not exists public.gotv_people (
  id bigint generated always as identity primary key,
  door_id bigint references public.gotv_doors(id) on delete cascade,
  street_id bigint not null references public.gotv_streets(id) on delete cascade,
  house_no text,
  first_name text not null,
  phone text,
  consent boolean not null check (consent = true),
  needs_lift boolean not null default false,
  special_vote boolean not null default false,
  voted boolean not null default false,
  voted_at timestamptz,
  voted_by text,
  added_by text,
  created_at timestamptz not null default now()
);
create index if not exists gotv_people_street on public.gotv_people(street_id);

alter table public.gotv_settings enable row level security;
alter table public.gotv_failed   enable row level security;
alter table public.gotv_streets  enable row level security;
alter table public.gotv_doors    enable row level security;
alter table public.gotv_people   enable row level security;
revoke all on public.gotv_settings, public.gotv_failed, public.gotv_streets, public.gotv_doors, public.gotv_people from anon, authenticated;

-- ---------- the gate ----------
-- returns false (never raises, so the failed-attempt row is kept) on a wrong code or when locked
create or replace function public.gotv_ok(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if (select count(*) from gotv_failed where at > now() - interval '10 minutes') >= 30 then
    return false;
  end if;
  select code_hash into h from gotv_settings where id = 1;
  if h is null or p_code is null or crypt(upper(trim(p_code)), h) <> h then
    insert into gotv_failed default values;
    perform pg_sleep(1);
    return false;
  end if;
  delete from gotv_failed where at < now() - interval '1 day';
  return true;
end $$;

create or replace function public.gotv_login(p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  return json_build_object('ok', true);
end $$;

-- whole-ward picture: streets with counts + totals
create or replace function public.gotv_state(p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  return json_build_object(
    'target', (select target from gotv_settings where id = 1),
    'totals', (select json_build_object(
        'doors', (select count(*) from gotv_doors),
        'yes', (select count(*) from gotv_doors where result = 'yes'),
        'maybe', (select count(*) from gotv_doors where result = 'maybe'),
        'no', (select count(*) from gotv_doors where result = 'no'),
        'not_home', (select count(*) from gotv_doors where result = 'not_home'),
        'people', (select count(*) from gotv_people),
        'lifts', (select count(*) from gotv_people where needs_lift),
        'special', (select count(*) from gotv_people where special_vote),
        'voted', (select count(*) from gotv_people where voted),
        'streets_done', (select count(*) from gotv_streets where status = 'done'),
        'streets_started', (select count(*) from gotv_streets where status = 'started'),
        'streets', (select count(*) from gotv_streets))),
    'streets', coalesce((select json_agg(s order by s.area, s.name) from (
        select st.id, st.name, st.metres, st.area, st.station, st.lat, st.lng, st.status, st.status_by, st.updated_at,
          (select count(*) from gotv_doors d where d.street_id = st.id) as doors,
          (select count(*) from gotv_doors d where d.street_id = st.id and d.result = 'yes') as yes,
          (select count(*) from gotv_doors d where d.street_id = st.id and d.result = 'maybe') as maybe
        from gotv_streets st) s), '[]'::json));
end $$;

-- one street: its doors and people
create or replace function public.gotv_street(p_code text, p_street bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  return json_build_object(
    'doors', coalesce((select json_agg(d order by d.created_at desc) from gotv_doors d where d.street_id = p_street), '[]'::json),
    'people', coalesce((select json_agg(p order by p.created_at desc) from gotv_people p where p.street_id = p_street), '[]'::json));
end $$;

create or replace function public.gotv_log_door(p_code text, p_street bigint, p_house text, p_result text,
  p_note text, p_volunteer text, p_name text, p_phone text, p_consent boolean, p_lift boolean, p_special boolean) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare d bigint;
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  insert into gotv_doors(street_id, house_no, result, note, volunteer)
    values (p_street, nullif(trim(p_house), ''), p_result, nullif(trim(p_note), ''), nullif(trim(p_volunteer), ''))
    returning id into d;
  if coalesce(p_consent, false) and nullif(trim(p_name), '') is not null then
    insert into gotv_people(door_id, street_id, house_no, first_name, phone, consent, needs_lift, special_vote, added_by)
      values (d, p_street, nullif(trim(p_house), ''), trim(p_name), nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), ''),
              true, coalesce(p_lift, false), coalesce(p_special, false), nullif(trim(p_volunteer), ''));
  end if;
  update gotv_streets set status = 'started', status_by = nullif(trim(p_volunteer), ''), updated_at = now()
    where id = p_street and status = 'todo';
  return json_build_object('ok', true, 'door', d);
end $$;

create or replace function public.gotv_undo_door(p_code text, p_door bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  delete from gotv_doors where id = p_door;
  return json_build_object('ok', true);
end $$;

create or replace function public.gotv_set_street(p_code text, p_street bigint, p_status text, p_volunteer text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  update gotv_streets set status = p_status, status_by = nullif(trim(p_volunteer), ''), updated_at = now() where id = p_street;
  return json_build_object('ok', true);
end $$;

-- election-day list: every supporter with a name
create or replace function public.gotv_people_all(p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  return coalesce((select json_agg(x order by x.voted, x.station, x.street, x.house_no) from (
      select p.id, p.first_name, p.phone, p.house_no, p.needs_lift, p.special_vote, p.voted, p.voted_at, p.voted_by,
             s.name as street, s.area, s.station
      from gotv_people p join gotv_streets s on s.id = p.street_id) x), '[]'::json);
end $$;

create or replace function public.gotv_mark_voted(p_code text, p_person bigint, p_voted boolean, p_volunteer text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  update gotv_people set voted = p_voted, voted_at = case when p_voted then now() end,
         voted_by = case when p_voted then nullif(trim(p_volunteer), '') end where id = p_person;
  return json_build_object('ok', true);
end $$;

create or replace function public.gotv_forget_person(p_code text, p_person bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not gotv_ok(p_code) then return json_build_object('error', 'bad_code'); end if;
  delete from gotv_people where id = p_person;
  return json_build_object('ok', true);
end $$;

revoke all on function public.gotv_ok(text) from public, anon, authenticated;
grant execute on function public.gotv_login(text), public.gotv_state(text), public.gotv_street(text, bigint),
  public.gotv_log_door(text, bigint, text, text, text, text, text, text, boolean, boolean, boolean),
  public.gotv_undo_door(text, bigint), public.gotv_set_street(text, bigint, text, text),
  public.gotv_people_all(text), public.gotv_mark_voted(text, bigint, boolean, text),
  public.gotv_forget_person(text, bigint) to anon, authenticated;
