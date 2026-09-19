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
- Password: set privately (to change it: Supabase dashboard → Authentication →
  Users → your user → Reset password).

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
5. **Tell the person who reported it.** Hit **📲 Tell the reporter** on the card — it opens
   WhatsApp with their reference, the City's reference and the current status already
   written. The card then shows when they were last told, and the **Attention** filter
   lists anyone who has never been told. A resident who reports a fault and hears nothing
   back is exactly why people stopped believing anyone.
6. Never delete, never hide. Slow progress with honest notes beats silence.

## When the site says "we can't reach the server"

The Supabase free tier **pauses a project that sits idle** — it happened on 10 September 2026
and the public page went blank. `.github/workflows/keepalive.yml` now pings the database every
3 days to stop that, and fails loudly in the Actions tab if the database is unreachable.

If it is already paused, wake it up:

```bash
curl -X POST -H "Authorization: Bearer $(cat ~/.supabase/access-token)" \
  https://api.supabase.com/v1/projects/vzwkelixolmexgfkwoif/restore
```

It goes `COMING_UP` → `ACTIVE_HEALTHY` in 1–2 minutes. Then re-run the keep-alive workflow
from the Actions tab to confirm.

> One trap: a tool that cannot run JavaScript (curl, a link preview, most "fetch this page"
> tools) will report the site as broken even when it is perfectly healthy, because it exposes
> the hidden `#offlineBanner`. **Always check in a real browser before panicking.**

## Joburg Water is a special case

E-mail alone gets you **no reference number** — see `docs/JW_PORTAL_STEPS.md`. `customer@jwater.co.za`
is dead; use `fault@jwater.co.za`, and log the fault on the Forcelink portal to get a `JWCC-`
reference. Follow-ups must carry the reference in square brackets in the subject line — the
Escalate button now does this automatically once `escalation_ref` is filled in.

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
