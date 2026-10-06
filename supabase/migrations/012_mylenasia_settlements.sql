-- 012: My Lenasia also covers the informal settlements around Lenasia in wards 8 and 9 (Omar, 6 Oct 2026):
-- Thembelihle, Nana's Farm, Patsing, Lawley informal settlement and Lakeview.
-- Boxes from mylenasia/tools/make_coverage.py (outline from OpenStreetMap + 200 m). The Lenasia proper box stays as in 011.
alter table public.reports drop constraint if exists reports_ml_box;
alter table public.reports add constraint reports_ml_box check (source <> 'mylenasia' or (
     (lat between -26.352  and -26.298  and lng between 27.815  and 27.890)    -- Lenasia proper (011)
  or (lat between -26.3437 and -26.3294 and lng between 27.8553 and 27.8777)   -- Thembelihle
  or (lat between -26.3102 and -26.2979 and lng between 27.8468 and 27.8743)   -- Nana's Farm
  or (lat between -26.3324 and -26.3233 and lng between 27.8745 and 27.8864)   -- Patsing
  or (lat between -26.3602 and -26.3487 and lng between 27.8284 and 27.8421)   -- Lawley informal settlement
  or (lat between -26.4041 and -26.3736 and lng between 27.8151 and 27.8438)   -- Lakeview
));
