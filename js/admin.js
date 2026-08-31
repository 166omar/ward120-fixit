// Fix Ward 120 — team console
"use strict";

const sb = w120Client();
let all = [];
let aFilter = "open";

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
  const res = await sb.from("reports").select("*").order("created_at", { ascending: false }).limit(1000);
  if (res.error) { toast("Load failed: " + res.error.message, true); return; }
  all = res.data;
  document.getElementById("sNew").textContent = all.filter(function (r) { return r.status === "new" || r.status === "acknowledged"; }).length;
  document.getElementById("sBusy").textContent = all.filter(function (r) { return r.status === "in_progress" || r.status === "escalated"; }).length;
  document.getElementById("sFixed").textContent = all.filter(function (r) { return r.status === "fixed"; }).length;
  render();
}

document.getElementById("aFilters").addEventListener("click", function (e) {
  const b = e.target.closest("button"); if (!b) return;
  this.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
  b.classList.add("on");
  aFilter = b.dataset.f;
  render();
});

function rows() {
  if (aFilter === "all") return all;
  if (aFilter === "open") return all.filter(function (r) { return ["new", "acknowledged", "in_progress", "escalated"].indexOf(r.status) >= 0; });
  return all.filter(function (r) { return r.status === aFilter; });
}

function render() {
  const wrap = document.getElementById("aWrap");
  const list = rows();
  if (!list.length) { wrap.innerHTML = '<div class="card"><p style="text-align:center;color:#66736E">Nothing here.</p></div>'; return; }
  wrap.innerHTML = list.map(function (r) {
    const cat = CATEGORIES[r.category] || CATEGORIES.other;
    const st = STATUSES[r.status] || STATUSES.new;
    const phoneDigits = (r.reporter_phone || "").replace(/\D/g, "").replace(/^0/, "27");
    return '<div class="card acard" style="border-left-color:' + st.color + '" data-id="' + r.id + '">' +
      '<div class="top" style="display:flex;justify-content:space-between;align-items:center">' +
        '<b style="color:#0B6E4F">' + esc(r.ref) + "</b> " + statusBadge(r.status) + "</div>" +
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
          : " · no phone") + "</div>" +
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
      '<div style="margin-top:10px"><button class="btn small eSave">💾 Save update</button></div>' +
    "</div>";
  }).join("");
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

/* ============ CSV export ============ */
document.getElementById("btnCsv").addEventListener("click", function () {
  const cols = ["ref", "category", "status", "description", "area", "municipality", "lat", "lng",
    "reporter_name", "reporter_phone", "escalation_ref", "supports", "created_at", "fixed_at"];
  const lines = [cols.join(",")].concat(all.map(function (r) {
    return cols.map(function (c) {
      return '"' + String(r[c] == null ? "" : r[c]).replace(/"/g, '""') + '"';
    }).join(",");
  }));
  const blob = new Blob([lines.join("\r\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "ward120-reports-" + new Date().toISOString().slice(0, 10) + ".csv";
  a.click();
  URL.revokeObjectURL(a.href);
});

/* ============ boot: restore session ============ */
sb.auth.getSession().then(function (s) {
  if (s.data.session) enterConsole();
});
