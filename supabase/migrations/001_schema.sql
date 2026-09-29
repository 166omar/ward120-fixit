-- Fix Ward 120 — schema, security, seed (applied 2026-08-29 via Supabase MCP)
-- Project: ward120-fixit (vzwkelixolmexgfkwoif)

-- ============ TABLES ============
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity,
  ref text generated always as ('W120-' || lpad(seq::text, 4, '0')) stored,
  category text not null check (category in ('water','sewer','road','other')),
  description text not null check (char_length(description) between 3 and 2000),
  area text not null default 'Other',
  lat double precision not null check (lat between -35 and -20),
  lng double precision not null check (lng between 20 and 35),
  photo_url text,
  reporter_name text,
  reporter_phone text,
  status text not null default 'new'
    check (status in ('new','acknowledged','in_progress','escalated','fixed','closed')),
  status_note text,
  escalation_ref text,
  fixed_photo_url text,
  fixed_at timestamptz,
  supports integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index reports_status_idx on public.reports (status);
create index reports_created_idx on public.reports (created_at desc);

create table public.status_history (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.reports(id),
  status text not null,
  note text,
  created_at timestamptz not null default now()
);
create index history_report_idx on public.status_history (report_id);

create table public.admin_emails (email text primary key);
insert into public.admin_emails values ('166omar@gmail.com');

-- ============ FUNCTIONS ============
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from admin_emails
    where lower(email) = lower(coalesce(auth.jwt()->>'email',''))
  );
$$;

-- Timeline is written ONLY by triggers (security definer bypasses RLS).
create or replace function public.reports_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into status_history (report_id, status) values (new.id, 'new');
  return new;
end $$;

create or replace function public.reports_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if new.status = 'fixed' and new.fixed_at is null then
    new.fixed_at := now();
  end if;
  return new;
end $$;

create or replace function public.reports_after_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into status_history (report_id, status, note)
    values (new.id, new.status, new.status_note);
  end if;
  return new;
end $$;

create trigger trg_reports_ai after insert on public.reports
  for each row execute function public.reports_after_insert();
create trigger trg_reports_bu before update on public.reports
  for each row execute function public.reports_before_update();
create trigger trg_reports_au after update on public.reports
  for each row execute function public.reports_after_update();

-- "This affects me too"
create or replace function public.add_support(p_report uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  update reports set supports = supports + 1 where id = p_report returning supports into v;
  return v;
end $$;

-- ============ RLS + COLUMN GRANTS ============
alter table public.reports enable row level security;
alter table public.status_history enable row level security;
alter table public.admin_emails enable row level security;

create policy reports_select on public.reports for select using (true);
create policy reports_insert on public.reports for insert with check (true);
create policy reports_update on public.reports for update
  using (public.is_admin()) with check (public.is_admin());
-- no delete policy: the ledger is permanent

create policy history_select on public.status_history for select using (true);
-- admin_emails: no policies -> unreachable through the API

revoke all on public.reports from anon, authenticated;
grant select (id, seq, ref, category, description, area, lat, lng, photo_url,
              status, status_note, escalation_ref, fixed_photo_url, fixed_at,
              supports, created_at, updated_at)
  on public.reports to anon;
grant insert (category, description, area, lat, lng, photo_url,
              reporter_name, reporter_phone)
  on public.reports to anon, authenticated;
grant select on public.reports to authenticated; -- team sees name/phone
grant update (status, status_note, escalation_ref, fixed_photo_url, fixed_at)
  on public.reports to authenticated;            -- gated by is_admin() policy

revoke all on public.status_history from anon, authenticated;
grant select on public.status_history to anon, authenticated;
revoke all on public.admin_emails from anon, authenticated;

grant usage, select on all sequences in schema public to anon, authenticated;

revoke all on function public.add_support(uuid) from public;
grant execute on function public.add_support(uuid) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- ============ STORAGE ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-photos','report-photos', true, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "w120 upload photos" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'report-photos');
create policy "w120 read photos" on storage.objects
  for select to anon, authenticated using (bucket_id = 'report-photos');

-- ============ SEED ADMIN USER ============
-- Temp password recorded in README; owner must change after first login.
do $$
declare uid uuid := gen_random_uuid();
begin
  if not exists (select 1 from auth.users where email = '166omar@gmail.com') then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      '166omar@gmail.com',
      -- The first password that stood here was published with this repo, so it was
      -- retired on 2026-09-29. Set a password in the Supabase dashboard instead.
      extensions.crypt('<SET-A-PASSWORD-IN-THE-DASHBOARD>', extensions.gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      '', '', '', '', now(), now());
    insert into auth.identities (id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', '166omar@gmail.com', 'email_verified', true),
      'email', now(), now(), now());
  end if;
end $$;
