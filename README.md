# Fix Ward 120 🛠️

**A Truth and Solidarity community project** — residents of Ward 120 (Lenasia South,
Hospital Hills, Vlakfontein) and nearby Region G areas report water leaks, sewer spills
and broken roads. Every report is public, numbered, and tracked on a visible timeline
until it is fixed. Inspired by the Roshnee community's fix-it-ourselves spirit.

| | |
|---|---|
| **Public site** | https://166omar.github.io/ward120-fixit/ (live, deployed 29 Aug 2026) |
| **Team console** | https://166omar.github.io/ward120-fixit/admin.html |
| **Code** | https://github.com/166omar/ward120-fixit (push to `main` redeploys automatically) |
| **Backend** | Supabase project `ward120-fixit` (`vzwkelixolmexgfkwoif`, eu-west-1, free tier) |

Sharing the site link on the community WhatsApp groups *is* the launch. A custom
domain (e.g. `fixward120.co.za`) can be pointed at it later in the repo's Pages settings.

## Team sign-in

- Email: `166omar@gmail.com`
- Temporary password: `W120-Truth!2026` — **change this after your first login**
  (Supabase dashboard → Authentication → Users → your user → Reset password,
  or use "Forgot password" flows once SMTP is set up).

### Add more team members
1. Supabase dashboard → Authentication → Users → *Add user* (email + password, auto-confirm).
2. Run in the SQL editor: `insert into admin_emails values ('their@email.com');`

Only emails in `admin_emails` can update reports — anyone else who signs in can do nothing.

## Before you launch (5 minutes)

1. **Set the WhatsApp number** in `config.js` → `WHATSAPP_NUMBER: "27XXXXXXXXX"`.
   This turns on: the volunteer button, and the WhatsApp fallback for reporting.
2. Change the admin password (above).
3. Share the link on the community WhatsApp groups. That *is* the launch.

## How it protects people (POPIA)

- Reporter **name and phone are never public** — blocked at database level
  (column grants), not just hidden in the page. Only signed-in team members see them.
- Everything else (description, photo, pin, status timeline) is deliberately public —
  that transparency is the whole point.
- Reports can never be deleted, by anyone, through the site — the ledger is permanent.
  Mark junk reports as **Closed** with a note instead.

## Day-to-day playbook (this is what builds trust)

1. Open the console every morning. Every **New** report → set **Team notified** same day.
2. Go see it. Update to **Being fixed** with an honest public note.
3. Fix what volunteers can fix. Upload the **after photo** — it feeds the Fixed wall.
4. What needs the municipality: report it to Joburg Water (0860 562 874) / JRA,
   set status **Escalated**, and paste their reference number — it is published on
   the report's page so residents can see you actually did it.
5. Never delete, never hide. Slow progress with honest notes beats silence.

## Changing things

- **Areas list, map centre, keys**: `config.js` (no other file needs edits).
- **Categories/status labels**: `js/common.js` (`CATEGORIES` / `STATUSES`) — categories
  must match the database check constraint in `supabase/migrations/001_schema.sql`.
- **Wording/promises**: `index.html` (About tab).
- **Deploy a change**: commit and `git push` — GitHub Pages redeploys automatically.

## Architecture (for future developers)

Static HTML/CSS/JS (no build step) + Supabase (Postgres/Auth/Storage) + Leaflet/OSM.
Security lives entirely in the database: RLS policies, column-level grants, a
`SECURITY DEFINER` trigger writes the public status timeline, and `is_admin()`
gates updates to the `admin_emails` allow-list. See `supabase/migrations/001_schema.sql`
and `docs/superpowers/specs/` for the full design.

## Costs

R0. GitHub Pages is free; Supabase free tier covers this scale (500 MB database,
1 GB file storage — thousands of reports). If photos ever fill storage, old ones
can be archived.
