-- 011: a second town site, mylenasia.co.za (Lenasia proper and its extensions), Omar 5 Oct 2026.
-- Its reports carry source 'mylenasia' and numbers ML-0031 etc. (one shared counter with LS-/TS-).
-- They show publicly ONLY on mylenasia; lenzsouth reports stay on lenzsouth.
-- The bot does NOT pick them up yet: 'mylenasia' is added to bot_settings.sources only at go-live,
-- so test reports never reach the City.

alter table public.reports drop constraint if exists reports_source_check;
alter table public.reports add constraint reports_source_check check (source in ('ward120', 'gauteng', 'lenzsouth', 'mylenasia'));

-- spot inside the Lenasia proper box, same text rules as lenzsouth
alter table public.reports drop constraint if exists reports_ml_box;
alter table public.reports add constraint reports_ml_box check (source <> 'mylenasia' or (
  lat between -26.352 and -26.298 and lng between 27.815 and 27.890));
alter table public.reports drop constraint if exists reports_ml_text;
alter table public.reports add constraint reports_ml_text check (source <> 'mylenasia' or (
  char_length(description) between 10 and 600 and description !~* '(https?://|www\.)'));

alter table public.reports alter column ref set expression as (
  (case source when 'lenzsouth' then 'LS-' when 'mylenasia' then 'ML-' else 'TS-' end) || lpad(seq::text, 4, '0'));

-- the e-mails to the City stay plain community wording (no party name)
create or replace function public.bot_signoff(p_source text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select case p_source
    when 'lenzsouth' then
      'This fault is listed publicly on lenzsouth.co.za, the Lenasia South community website. ' ||
      'Kindly reply with your reference number so that we can publish it for residents.' || E'\n\n' ||
      'Thank you' || E'\n' || 'Omar Khan' || E'\n' || 'Khan''s Butchery, NTN Centre, Lenasia South' || E'\n' || '063 690 7708'
    when 'mylenasia' then
      'This fault is listed publicly on mylenasia.co.za, the Lenasia community website. ' ||
      'Kindly reply with your reference number so that we can publish it for residents.' || E'\n\n' ||
      'Thank you' || E'\n' || 'Omar Khan' || E'\n' || 'My Lenasia community website' || E'\n' || '083 343 5786'
    else
      'This fault is tracked publicly by the Truth and Solidarity community project. ' ||
      'Kindly reply with your reference number so we can publish it for residents.' || E'\n\n' ||
      'Thank you' || E'\n' || 'Truth and Solidarity'
  end
$$;

-- the "Public record" link in every e-mail points at the right site
do $$
declare d text := pg_get_functiondef('public.bot_draft(uuid, text, integer)'::regprocedure);
begin
  if position('mylenasia.co.za' in d) = 0 then
    d := replace(d,
      $q$(case when r.source = 'lenzsouth' then 'Public record: https://lenzsouth.co.za/report/?ref=' || r.ref || E'\n' else '' end)$q$,
      $q$(case r.source when 'lenzsouth' then 'Public record: https://lenzsouth.co.za/report/?ref=' || r.ref || E'\n'
                         when 'mylenasia' then 'Public record: https://mylenasia.co.za/report/?ref=' || r.ref || E'\n' else '' end)$q$);
    if position('mylenasia.co.za' in d) = 0 then raise exception 'bot_draft text not found'; end if;
    execute d;
  end if;
end $$;
