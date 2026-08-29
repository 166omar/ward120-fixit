# Fix Ward 120 — Design Spec
**Date:** 2026-08-29 · **Owner:** Omar (Truth and Solidarity) · **Status:** Approved (autonomous build per owner's delegation)

## 1. Purpose

Residents of Ward 120, City of Johannesburg (Hospital Hills, Lenasia South Ext 1/4/28, Vlakfontein) and neighbouring Region G areas (Lawley, Ennerdale, Orange Farm — wards 7–10, 121) report **water leaks, sewer spills and broken rural roads** with a pinned location and photo. The Truth and Solidarity team sees every report, responds, fixes what volunteers can fix (the **Roshnee model** — Roshnee Neighbourhood Watch famously repairs its own town's leaks and roads), and escalates the rest to Joburg Water / JRA **with the municipal reference number published**.

**The product goal is trust through radical transparency.** Every report is public, permanent, numbered, and tracked on a visible timeline from "reported" to "fixed", with before/after photos and live counters.

## 2. Why a website (not a native app)

- Zero install: shared as a WhatsApp link, opens on any phone.
- No app-store account, no review delays, free hosting (GitHub Pages, HTTPS → geolocation works).
- Low data: no frameworks, no web fonts, photos compressed on-device before upload.
- Can be "installed" via Add to Home Screen (PWA manifest).

Alternatives considered: Flutter app (install friction kills adoption in this audience), Claude Artifact (CSP blocks external API calls — can't reach a database), Google Forms (no map, no public status ledger — fails the trust objective).

## 3. Architecture

```
┌─ Phone browser ────────────────┐      ┌─ Supabase (ward120-fixit) ─────────┐
│ index.html  (public: report,   │──────│ Postgres: reports, status_history, │
│   map, list, fixed wall, about)│ anon │   admin_emails, add_support() RPC  │
│ admin.html  (T&S team console) │──────│ Auth: email/password (allow-list)  │
│ Leaflet + OSM tiles            │ auth │ Storage: report-photos (public)    │
└────────────────────────────────┘      └────────────────────────────────────┘
        hosted on GitHub Pages (https://166omar.github.io/ward120-fixit/)
```

- Frontend: framework-free HTML/CSS/JS. `config.js` holds the Supabase URL, anon key, WhatsApp number, map center.
- Supabase project ref: `vzwkelixolmexgfkwoif` (eu-west-1, free tier).

## 4. Data model

**reports**
| column | type | notes |
|---|---|---|
| id | uuid pk | gen_random_uuid() |
| seq | bigint identity | drives the ref |
| ref | text generated | `'W120-' || lpad(seq, 4, '0')` |
| category | text | `water` · `sewer` · `road` · `other` |
| description | text | required |
| area | text | suburb dropdown value |
| lat, lng | double | required (pin) |
| photo_url | text | optional |
| reporter_name | text | **private** (column-level grants) |
| reporter_phone | text | **private** (column-level grants) |
| status | text | `new → acknowledged → in_progress → escalated → fixed → closed` |
| status_note, escalation_ref | text | escalation_ref = Joburg Water/JRA ref, published |
| fixed_photo_url, fixed_at | | before/after wall |
| supports | int | "This affects me too" count |
| created_at, updated_at | timestamptz | |

**status_history** (public timeline): report_id, status, note, created_at. Filled by SECURITY DEFINER trigger on insert + status change. No one can write it directly.

**admin_emails**: allow-list. RLS on `reports` UPDATE checks `is_admin()` (SECURITY DEFINER fn) — so random sign-ups get no power.

### Security (POPIA-aware)
- Anon may INSERT reports (only the citizen-facing columns) and SELECT everything **except** `reporter_name`/`reporter_phone` (column-level grants).
- Only admins UPDATE. **Nobody deletes** — the ledger is permanent by design.
- `add_support(report_id)` RPC increments the counter (client localStorage prevents casual double-taps).
- Storage bucket `report-photos`: public read, anon upload, images only, 5 MB cap; photos compressed client-side to ≤1280px JPEG first.

## 5. Public UI (index.html) — mobile-first, bottom tab nav

1. **Report** (default): category chips (💧 Water leak · 🚽 Sewer · 🛣️ Road · ⚠️ Other) → description → area dropdown → location ("Use my location" + draggable pin on mini-map) → optional photo (camera) → optional name/phone ("kept private — only so we can tell you when it's fixed") → submit → success screen with big **W120-XXXX** ref + WhatsApp share button.
2. **Map**: all reports; pin colour = status (red new, amber in-progress/escalated, green fixed).
3. **Reports**: filterable cards; "Me too 🙋" support button; tap → detail with photo, timeline, escalation ref.
4. **Fixed** — the trust wall: before/after photos, "Fixed in N days".
5. **About**: Our Promise (see it same day → visit → fix what we can ourselves → escalate the rest and publish the ref → nothing is ever deleted), how it works, get involved via WhatsApp, privacy note, "A Truth and Solidarity community project".

Header carries live counters: **Reported · In progress · Fixed**.

Design: single light theme, deep green `#0B6E4F` + amber `#F5A623`, system fonts, large touch targets, plain English at ~grade-6 reading level. WhatsApp report fallback button (hidden until number configured).

## 6. Admin console (admin.html)

Email/password login → report queue (filter by status; private name/phone visible; `wa.me`/`tel:` links to reporter) → per-report editor: status, public note, escalation ref, "fixed" photo upload → save. CSV export. Admin user seeded for `166omar@gmail.com` with a temporary password (in README; change after first login).

## 7. Error handling

- No GPS permission → drag the pin instead (map defaults to Lenasia South `-26.392, 27.853`).
- Offline/failed submit → clear retry message; form values preserved.
- Photo too large/wrong type → compressed client-side; bucket rules as backstop.
- Supabase unreachable → banner with the WhatsApp fallback.

## 8. Testing

- RLS proven in SQL (`set local role anon` — private columns must error, updates must fail).
- Playwright end-to-end on a local server: submit report (map-click location), verify DB row, public list/map/timeline render, "Me too", admin login, status change → public timeline updates, fixed photo → trust wall. Mobile viewport screenshots.
- Live smoke test after GitHub Pages deploy.

## 9. Out of scope (v1)

Donations/payments, multi-language UI, push notifications, service-worker offline cache, moderation queue (reports publish immediately — transparency over gatekeeping; admin can mark `closed` with a note for junk).
