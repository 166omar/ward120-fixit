# Joburg Water — getting a real reference number

**Why this file exists.** E-mailing Johannesburg Water does **not** create a reference number.
`customer@jwater.co.za` is dead and bounces ("no longer valid"). `fault@jwater.co.za` is the
live address, but it only auto-replies telling you to log the fault on their portal. **The
portal is the only thing that issues a `JWCC-` reference**, and a fault without a reference is
a fault we cannot prove we reported.

This is currently blocking **TS-0009** and **TS-0010**, our two water faults — nine days with
nothing to show. Water is the biggest issue in the ward.

---

## Part 1 — Use the link Joburg Water already sent us

**You do not have to register first.** We assumed you did; their own reply proves otherwise.

On **15 September at 20:08**, `fault@jwater.co.za` replied to our water e-mails with the
subject *"Action Required: Please Provide Details to complete the logging of your Johannesburg
Water Technical Fault."* It contains a **LOG A TECHNICAL FAULT** button. That button is the
thing that issues a reference number — and it opens the form in **anonymous mode**, so it can
be completed without an account. Registration is offered *afterwards*, not before.

That e-mail sat unread in the inbox from 15 to 19 September. It is the whole reason TS-0009 and
TS-0010 still have no reference.

1. Open that e-mail in Gmail (search: `from:fault@jwater.co.za "Action Required"`).
2. Click **LOG A TECHNICAL FAULT**. It goes to
   `customer.forcelink.net/joburg_water/logFaultOtherAddress` — verified genuine, it is the
   City's Forcelink system. The link carries a token tied to `166omar@gmail.com`, so treat it
   as personal: do not post it in a group.
3. Complete **every** required field — their notice says a fault is only logged, and a
   reference only issued, if all required details are submitted. Account and meter numbers are
   *not* required, only recommended.
4. Write down the reference it gives you (`JWCC-4…`, `JWAPP-4…` or `COJ-8…`) and send it to me.
5. Registering afterwards is worth doing — it gives 24/7 logging and faster follow-ups — but it
   is **not** a blocker for these two faults.

> If the form refuses to submit or the site is down, phone **0860 562 874**, ask them to log the
> fault, and get the reference read out to you. A reference from the phone is worth exactly as
> much as one from the portal.

---

## Part 2 — The two faults to lodge first

Log these exactly as written — street names only, never a resident's name.

**TS-0009 — recurring early-morning water outages**
> No water in Annapurna Place, Mount Logan Street and Witwatersrand Street, Lenasia South,
> from about 04:00 on 7 September 2026, restored about 05:00. This is recurring. Residents
> want the cause and the current supply-management schedule for the Lenasia High Level
> Reservoir zone.

**TS-0010 — informal settlement, no tanker deliveries**
> Informal settlement on the western side of the railway line opposite Lenasia South: no
> municipal water tanker delivery for about three weeks in August/September 2026. Residents
> are carrying borehole water from the BP garage across a live railway line. Request the
> tanker delivery schedule for this settlement.

---

## Part 3 — What to capture (this is the whole point)

For each fault, write down the **`JWCC-` reference** the portal gives you and send it to me.
I put it into `escalation_ref`, set the status to `escalated` with a public note, and it
appears on the public report page at https://166omar.github.io/ward120-fixit/ — which is the
proof no rival in this ward can produce.

## Part 4 — Chasing an existing ticket

Reply to the thread with the reference in the subject line **in square brackets** — this is
quoted directly from their 15 September notice:

```
Subject: I have no water [JWCC-412345678]
```

Valid reference shapes: `[JWCC-4xxxxxxxx]`, `[JWAPP-4xxxxxxxx]` or `[COJ-800000000]`.

That is how their system links a follow-up to the open ticket. Without the brackets it is
treated as a brand-new query and goes to the back of the queue. The **📧 Escalate email**
button in the console now adds the brackets automatically once `escalation_ref` is filled in.

Do not expect a human reply to `fault@jwater.co.za` — it states plainly that it is automated
and cannot respond to replies. The portal and the phone line are the only two routes that
produce a reference.

## Also open with Joburg Water

- **Reservoir letter, project 23759** — went to four named JW officials on 16 September
  (feziwe.mbube, tsakani.ngobeni, bongani.miya, sizwe.kunene @jwater.co.za) after PRASA
  forwarded Omar's wayleave request. A 14-working-day clock restarted, so a reply is due
  **around 6 October 2026**. If nothing arrives, that silence is itself the Friday post.
- **PRASA wayleave** — PRASA answered on 11 September: they agree in principle, but
  **Joburg Water** must lodge the wayleave for the water pipe. That request is with them.
