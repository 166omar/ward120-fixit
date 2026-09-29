// Fix Ward 120 — team console
"use strict";

const sb = w120Client();
let all = [];
let vols = [];
let aFilter = "open";
let sFilter = "all";          // which site's reports are shown
let bot = null;               // the fault bot: switch position and its e-mails

/* ============ auth ============ */
document.getElementById("btnLogin").addEventListener("click", login);
document.getElementById("lPass").addEventListener("keydown", function (e) { if (e.key === "Enter") login(); });

async function login() {
  const btn = document.getElementById("btnLogin");
  btn.disabled = true; btn.textContent = "Signing in…";
  const res = await sb.auth.signInWithPassword({
    email: document.getElementById("lEmail").value.trim(),
    password: document.getElementById("lPass").value
  });
  btn.disabled = false; btn.textContent = "Sign in";
  if (res.error) { toast("Sign in failed: " + res.error.message, true); return; }
  enterConsole();
}

document.getElementById("btnLogout").addEventListener("click", async function () {
  await sb.auth.signOut();
  location.reload();
});

async function enterConsole() {
  document.getElementById("loginCard").hidden = true;
  document.getElementById("console").hidden = false;
  await load();
}

/* ============ data ============ */
async function load() {
  // Names and phone numbers come only through this function, which refuses anyone who is
  // not on the team list (migration 005). A plain table read no longer returns them.
  const res = await sb.rpc("admin_reports");
  if (res.error) { toast("Load failed: " + res.error.message, true); return; }
  all = res.data;
  const vres = await sb.from("volunteers").select("*").order("created_at", { ascending: false }).limit(2000);
  vols = vres.error ? [] : vres.data;
  const bres = await sb.rpc("admin_bot");
  bot = bres.error ? null : bres.data;
  const botBtn = document.querySelector('#aFilters [data-f="bot"]');
  if (botBtn && bot) {
    const n = bot.outbox.filter(function (o) { return o.state === "waiting" || o.state === "needs_person" || o.state === "failed"; }).length;
    botBtn.textContent = "🤖 Bot" + (n ? " (" + n + ")" : "");
  }
  document.getElementById("sNew").textContent = all.filter(function (r) { return r.status === "new" || r.status === "acknowledged"; }).length;
  document.getElementById("sBusy").textContent = all.filter(function (r) { return r.status === "in_progress" || r.status === "escalated"; }).length;
  document.getElementById("sFixed").textContent = all.filter(function (r) { return r.status === "fixed"; }).length;
  const attnEl = document.getElementById("sAttn");
  if (attnEl) {
    const n = all.filter(function (r) { return needsAttention(r); }).length;
    attnEl.textContent = n;
    attnEl.style.color = n > 0 ? "#D64545" : "";
  }
  render();
}

document.getElementById("aFilters").addEventListener("click", function (e) {
  const b = e.target.closest("button"); if (!b) return;
  this.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
  b.classList.add("on");
  aFilter = b.dataset.f;
  render();
});

const sFilters = document.getElementById("sFilters");
if (sFilters) sFilters.addEventListener("click", function (e) {
  const b = e.target.closest("button"); if (!b) return;
  this.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
  b.classList.add("on");
  sFilter = b.dataset.s;
  render();
});

function fromSite() {
  return sFilter === "all" ? all : all.filter(function (r) { return (r.source || "ward120") === sFilter; });
}

function rows() {
  const base = fromSite();
  if (aFilter === "all") return base;
  if (aFilter === "open") return base.filter(function (r) { return ["new", "acknowledged", "in_progress", "escalated"].indexOf(r.status) >= 0; });
  if (aFilter === "attention") return base.filter(function (r) { return needsAttention(r); });
  return base.filter(function (r) { return r.status === aFilter; });
}

function render() {
  const wrap = document.getElementById("aWrap");
  if (aFilter === "volunteers") { renderVolunteers(wrap); return; }
  if (aFilter === "bot") { renderBot(wrap); return; }
  const list = rows();
  if (!list.length) { wrap.innerHTML = '<div class="card"><p style="text-align:center;color:#66736E">Nothing here.</p></div>'; return; }
  wrap.innerHTML = list.map(function (r) {
    const cat = CATEGORIES[r.category] || CATEGORIES.other;
    const st = STATUSES[r.status] || STATUSES.new;
    const attn = needsAttention(r);
    const phoneDigits = (r.reporter_phone || "").replace(/\D/g, "").replace(/^0/, "27");
    const tellHref = reporterWhatsApp(r);
    const toldDays = r.notified_at
      ? Math.floor((Date.now() - new Date(r.notified_at)) / 86400000) : null;
    const toldLabel = r.notified_at
      ? "✅ reporter told " + (toldDays === 0 ? "today" : toldDays === 1 ? "yesterday" : toldDays + " days ago")
      : (r.reporter_phone ? "🔔 <b>reporter not told yet</b>" : "");
    return '<div class="card acard" style="border-left-color:' + st.color + '" data-id="' + r.id + '">' +
      '<div class="top" style="display:flex;justify-content:space-between;align-items:center">' +
        '<span><b style="color:#0B6E4F">' + esc(r.ref) + "</b> " + sourceBadge(r) +
          (r.hidden ? ' <span class="badge" style="background:#7F8C8D">Hidden from public</span>' : "") +
        "</span> " + statusBadge(r.status) + "</div>" +
      (attn ? '<div class="banner" style="margin:8px 0">' + esc(attn) + "</div>" : "") +
      '<p style="margin:6px 0">' + cat.emoji + " " + esc(r.description) + "</p>" +
      '<div class="hint">' + placeLabel(r) + " · " + fmtDate(r.created_at) + " · 🙋 " + r.supports +
        ' · <a href="https://www.openstreetmap.org/?mlat=' + r.lat + "&mlon=" + r.lng + "#map=18/" + r.lat + "/" + r.lng +
        '" target="_blank" rel="noopener">map 🗺️</a></div>' +
      (r.photo_url ? '<p><a href="' + esc(r.photo_url) + '" target="_blank" rel="noopener"><img class="athumb" src="' + esc(r.photo_url) + '" alt="photo"></a></p>' : "") +
      '<div class="private">🔒 <b>' + esc(r.reporter_name || "No name given") + "</b>" +
        (r.reporter_phone ?
          " · " + esc(r.reporter_phone) +
          ' · <a href="tel:' + esc(r.reporter_phone) + '">call</a>' +
          (phoneDigits ? ' · <a href="https://wa.me/' + phoneDigits + '" target="_blank" rel="noopener">WhatsApp</a>' : "")
          : " · no phone") +
        (toldLabel ? ' <span class="hint" style="display:block;margin-top:4px">' + toldLabel + "</span>" : "") +
        "</div>" +
      '<div class="arow">' +
        '<div><label>Status</label><select class="eStatus">' +
          Object.keys(STATUSES).map(function (k) {
            return '<option value="' + k + '"' + (k === r.status ? " selected" : "") + ">" + STATUSES[k].label + "</option>";
          }).join("") + "</select></div>" +
        '<div><label>Municipal ref <span class="opt">(published)</span></label>' +
          '<input type="text" class="eEsc" value="' + esc(r.escalation_ref || "") + '" placeholder="e.g. JW-123456"></div>' +
      "</div>" +
      '<label>Public note <span class="opt">(shown on the timeline)</span></label>' +
      '<input type="text" class="eNote" maxlength="500" placeholder="e.g. Team visited today, part ordered" value="">' +
      '<label>“Fixed” photo <span class="opt">(after photo for the trust wall)</span></label>' +
      '<input type="file" class="eFixedPhoto" accept="image/*">' +
      '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<button class="btn small eSave">💾 Save update</button>' +
        '<a class="btn small second" href="' + escalationMailto(r) + '">📧 Escalate email' +
          (escalationEmail(r) ? "" : " (add address)") + "</a>" +
        (tellHref
          ? '<a class="btn small second eTell" href="' + tellHref + '" target="_blank" rel="noopener">📲 Tell the reporter</a>'
          : "") +
        '<button class="btn small second eHide">' + (r.hidden ? "👁 Show on the site again" : "🙈 Hide from public") + "</button>" +
        (r.reporter_name || r.reporter_phone
          ? '<button class="btn small second eForget">🧹 Forget reporter’s details</button>'
          : "") +
      "</div>" +
    "</div>";
  }).join("");
}

/* ============ the fault bot ============
   The bot writes the e-mail to the City for every new report from the sites it looks after.
   Switch on "One tap": nothing leaves until someone here presses Approve.
   Switch on "Automatic": e-mails are approved by themselves.
   A worker sends what is approved, reads the City's replies and saves their reference. */
const OUT_STATES = {
  waiting:      { label: "Waiting for a yes", color: "#E67E22" },
  approved:     { label: "Approved, will be sent", color: "#1B5E8C" },
  sending:      { label: "Being sent", color: "#1B5E8C" },
  sent:         { label: "Sent", color: "#0B6E4F" },
  failed:       { label: "Failed", color: "#D64545" },
  rejected:     { label: "Rejected", color: "#7F8C8D" },
  needs_person: { label: "Needs a person", color: "#8E44AD" }
};

function renderBot(wrap) {
  if (!bot) { wrap.innerHTML = '<div class="card"><p>The bot panel could not load.</p></div>'; return; }
  const auto = bot.mode === "auto";
  const head =
    '<div class="card"><h2 style="margin-top:0">🤖 Fault bot</h2>' +
    '<p>Looks after reports from: <b>' + esc((bot.sources || []).join(", ")) + "</b></p>" +
    '<div class="filters" style="margin:10px 0">' +
      '<button class="bMode' + (auto ? "" : " on") + '" data-m="approve">One tap: I approve each e-mail</button>' +
      '<button class="bMode' + (auto ? " on" : "") + '" data-m="auto">Automatic</button>' +
    "</div>" +
    '<p class="hint">' + (auto
      ? "Automatic: every new report is e-mailed to the City by itself."
      : "One tap: nothing goes to the City until you press Approve below.") + "</p>" +
    (bot.tests_left > 0 ? '<div class="banner" style="margin:8px 0">The next ' + bot.tests_left +
      " approved e-mail" + (bot.tests_left === 1 ? "" : "s") + " go to <b>" + esc(bot.test_to) +
      "</b> first as a test copy. Read it, then approve again to send it to the City.</div>" : "") +
    '<button class="btn small second bPause">' + (bot.paused ? "▶ Start the bot again" : "⏸ Pause the bot") + "</button>" +
    (bot.paused ? ' <b style="color:#D64545">The bot is paused.</b>' : "") +
    (bot.worker_ready ? "" : '<div class="banner" style="margin:8px 0"><b>The sender is not switched on.</b> Approved e-mails wait here and nothing goes out by itself.' +
      (bot.worker_seen ? " It last ran " + fmtDate(bot.worker_seen) + "." : "") + "</div>") +
    "</div>";
  const list = (bot.outbox || []).map(function (o) {
    const st = OUT_STATES[o.state] || OUT_STATES.waiting;
    const portal = (o.reason || "").match(/https?:\/\/\S+/);
    return '<div class="card acard" style="border-left-color:' + st.color + '" data-out="' + o.id + '">' +
      '<div class="top" style="display:flex;justify-content:space-between;align-items:center">' +
        "<span><b>" + esc(o.ref) + "</b> " + sourceBadge(o) + (o.kind === "chase" ? ' <span class="badge" style="background:#7F8C8D">Follow-up</span>' : "") + "</span>" +
        '<span class="badge" style="background:' + st.color + '">' + esc(st.label) + "</span></div>" +
      '<p style="margin:6px 0"><b>To:</b> ' + esc(o.department || "") + (o.to_email ? " · " + esc(o.to_email) : "") + "</p>" +
      '<p style="margin:6px 0"><b>Subject:</b> ' + esc(o.subject) + "</p>" +
      (o.reason ? '<div class="banner" style="margin:8px 0">' + esc(o.reason) + "</div>" : "") +
      '<details><summary>Read the e-mail</summary><pre style="white-space:pre-wrap;font:inherit;margin:8px 0">' + esc(o.body) + "</pre></details>" +
      '<div class="hint">Written ' + fmtDate(o.created_at) + (o.sent_at ? " · sent " + fmtDate(o.sent_at) : "") + "</div>" +
      '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
        (o.to_email && (o.state === "waiting" || o.state === "failed") ? '<button class="btn small bAct" data-a="approve">✅ Approve and send</button>' : "") +
        (o.state === "needs_person" && portal ? '<a class="btn small second" href="' + esc(portal[0].replace(/[.,]$/, "")) + '" target="_blank" rel="noopener">Open the portal</a>' : "") +
        (o.state === "needs_person" ? '<button class="btn small bAct" data-a="done">✔ I logged it myself</button>' : "") +
        (["waiting", "approved", "failed", "needs_person"].indexOf(o.state) >= 0 ? '<button class="btn small second bAct" data-a="reject">✖ Do not send</button>' : "") +
      "</div></div>";
  }).join("");
  wrap.innerHTML = head + (list || '<div class="card"><p style="text-align:center;color:#66736E">No e-mails yet. The first report from the site will show here.</p></div>');
}

document.getElementById("aWrap").addEventListener("click", async function (e) {
  const mode = e.target.closest(".bMode"), pause = e.target.closest(".bPause"), act = e.target.closest(".bAct");
  if (!mode && !pause && !act) return;
  try {
    let res;
    if (mode) {
      if (mode.dataset.m === "auto" && !confirm("Switch to Automatic? Every new report will be e-mailed to the City without anyone reading it first, and everything that is waiting now will be sent.")) return;
      res = await sb.rpc("admin_bot_mode", { p_mode: mode.dataset.m, p_paused: null });
    } else if (pause) {
      res = await sb.rpc("admin_bot_mode", { p_mode: null, p_paused: !bot.paused });
    } else {
      res = await sb.rpc("admin_outbox_set", { p_id: Number(act.closest("[data-out]").dataset.out), p_action: act.dataset.a });
    }
    if (res.error) throw res.error;
    toast(mode ? "Switch changed" : pause ? "Done" : act.dataset.a === "approve" ? (bot.worker_ready ? "Approved. It goes out with the next run." : "Approved. It waits until the sender is switched on.") : "Done");
    await load();
  } catch (err) {
    console.error(err);
    toast("That did not work: " + (err.message || err), true);
  }
});

/* ============ volunteers ============ */
function renderVolunteers(wrap) {
  if (!vols.length) {
    wrap.innerHTML = '<div class="card"><p style="text-align:center;color:#66736E">No volunteer sign-ups yet — share the site!</p></div>';
    return;
  }
  wrap.innerHTML =
    '<div class="card"><b>👥 ' + vols.length + " volunteer" + (vols.length === 1 ? "" : "s") +
    '</b> · newest first · <a href="#" id="volCsv">⬇ download CSV</a></div>' +
    vols.map(function (v) {
      const digits = (v.phone || "").replace(/\D/g, "").replace(/^0/, "27");
      return '<div class="card"><b>' + esc(v.name) + "</b> · " + esc(v.phone) +
        (digits ? ' · <a href="https://wa.me/' + digits + '" target="_blank" rel="noopener">WhatsApp</a>' : "") +
        ' · <a href="tel:' + esc(v.phone) + '">call</a>' +
        '<div class="hint">' + esc(v.area || "") +
          (v.municipality ? " · " + esc(v.municipality) : "") + " · joined " + fmtDate(v.created_at) + "</div>" +
        (v.skills ? '<div style="margin-top:4px">🛠️ ' + esc(v.skills) + "</div>" : "") +
      "</div>";
    }).join("");
  document.getElementById("volCsv").addEventListener("click", function (e) {
    e.preventDefault();
    const cols = ["name", "phone", "area", "municipality", "skills", "created_at"];
    const lines = [cols.join(",")].concat(vols.map(function (v) {
      return cols.map(function (c) {
        return '"' + String(v[c] == null ? "" : v[c]).replace(/"/g, '""') + '"';
      }).join(",");
    }));
    const blob = new Blob([lines.join("\r\n")], { type: "text/csv" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "ts-volunteers-" + new Date().toISOString().slice(0, 10) + ".csv";
    a.click();
    URL.revokeObjectURL(a.href);
  });
}

/* ============ save ============ */
document.getElementById("aWrap").addEventListener("click", async function (e) {
  const btn = e.target.closest(".eSave"); if (!btn) return;
  const card = btn.closest(".acard");
  const id = card.dataset.id;
  const status = card.querySelector(".eStatus").value;
  const note = card.querySelector(".eNote").value.trim() || null;
  const escRef = card.querySelector(".eEsc").value.trim() || null;
  const file = card.querySelector(".eFixedPhoto").files[0];

  btn.disabled = true; btn.textContent = "Saving…";
  try {
    const upd = { status: status, status_note: note, escalation_ref: escRef };
    if (file) upd.fixed_photo_url = await uploadPhoto(sb, await compressImage(file));
    const res = await sb.from("reports").update(upd).eq("id", id).select("ref,status").single();
    if (res.error) throw res.error;
    toast(res.data.ref + " → " + (STATUSES[res.data.status] || {}).label);
    await load();
  } catch (err) {
    console.error(err);
    toast("Save failed: " + (err.message || err), true);
    btn.disabled = false; btn.textContent = "💾 Save update";
  }
});

/* ============ tell the reporter ============
   Records that we came back to the person who reported the fault. Note what this
   actually measures: that the WhatsApp chat was opened with the message ready, not
   that it was definitely sent. It is a prompt so nobody is forgotten, not proof. */
document.getElementById("aWrap").addEventListener("click", async function (e) {
  const link = e.target.closest(".eTell"); if (!link) return;
  // Deliberately no preventDefault — WhatsApp must still open in its own tab.
  const id = link.closest(".acard").dataset.id;
  try {
    const res = await sb.from("reports")
      .update({ notified_at: new Date().toISOString() })
      .eq("id", id).select("ref").single();
    if (res.error) throw res.error;
    toast(res.data.ref + " → reporter told");
    await load();
  } catch (err) {
    console.error(err);
    toast("Could not record that the reporter was told: " + (err.message || err), true);
  }
});

/* ============ hide / forget ============ */
document.getElementById("aWrap").addEventListener("click", async function (e) {
  const hide = e.target.closest(".eHide"), forget = e.target.closest(".eForget");
  if (!hide && !forget) return;
  const id = (hide || forget).closest(".acard").dataset.id;
  const r = all.filter(function (x) { return x.id === id; })[0]; if (!r) return;
  try {
    if (hide) {
      const res = await sb.from("reports").update({ hidden: !r.hidden }).eq("id", id).select("ref").single();
      if (res.error) throw res.error;
      toast(res.data.ref + (r.hidden ? " is public again" : " is hidden from the public"));
    } else {
      if (!confirm("Remove the name and phone number from " + r.ref + "? This cannot be undone.")) return;
      const res = await sb.rpc("admin_forget_reporter", { p_report: id });
      if (res.error) throw res.error;
      toast(r.ref + " → reporter’s details removed");
    }
    await load();
  } catch (err) {
    console.error(err);
    toast("That did not work: " + (err.message || err), true);
  }
});

/* ============ CSV export ============
   One site at a time, so the numbers of people who reported on the neutral town site
   never end up in the same sheet as party contacts. */
document.getElementById("btnCsv").addEventListener("click", function () {
  if (sFilter === "all") { toast("Choose one site first (the row of site buttons), then export", true); return; }
  const cols = ["ref", "source", "category", "status", "description", "area", "municipality", "lat", "lng",
    "reporter_name", "reporter_phone", "escalation_ref", "supports", "created_at", "fixed_at"];
  const lines = [cols.join(",")].concat(fromSite().map(function (r) {
    return cols.map(function (c) {
      return '"' + String(r[c] == null ? "" : r[c]).replace(/"/g, '""') + '"';
    }).join(",");
  }));
  const blob = new Blob([lines.join("\r\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = sFilter + "-reports-" + new Date().toISOString().slice(0, 10) + ".csv";
  a.click();
  URL.revokeObjectURL(a.href);
});

/* ============ boot: restore session ============ */
sb.auth.getSession().then(function (s) {
  if (s.data.session) enterConsole();
});
