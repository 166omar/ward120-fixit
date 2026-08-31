// Fix Ward 120 — public page logic
"use strict";

const sb = w120Client();

const state = {
  reports: [],
  filter: "all",
  category: null,
  locationSet: false,
  photoBlob: null,
  bigMap: null,
  pickMap: null,
  pin: null,
  markersLayer: null,
  supported: JSON.parse(localStorage.getItem("w120_supported") || "[]")
};

/* ================= tabs ================= */
document.querySelectorAll(".tabs button").forEach(function (btn) {
  btn.addEventListener("click", function () {
    document.querySelectorAll(".tabs button").forEach(function (b) { b.classList.remove("on"); });
    document.querySelectorAll("section.tabpage").forEach(function (s) { s.classList.remove("on"); });
    btn.classList.add("on");
    document.getElementById("page-" + btn.dataset.tab).classList.add("on");
    if (btn.dataset.tab === "map") { initBigMap(); setTimeout(function () { state.bigMap.invalidateSize(); }, 60); }
    if (btn.dataset.tab === "report" && state.pickMap) setTimeout(function () { state.pickMap.invalidateSize(); }, 60);
    window.scrollTo(0, 0);
  });
});

/* ================= report form ================= */
function buildCategoryChips() {
  const wrap = document.getElementById("catChips");
  wrap.innerHTML = Object.keys(CATEGORIES).map(function (k) {
    return '<button type="button" class="chip" data-cat="' + k + '">' +
      '<span class="ico">' + CATEGORIES[k].emoji + "</span>" + esc(CATEGORIES[k].label) + "</button>";
  }).join("");
  wrap.querySelectorAll(".chip").forEach(function (c) {
    c.addEventListener("click", function () {
      wrap.querySelectorAll(".chip").forEach(function (x) { x.classList.remove("on"); });
      c.classList.add("on");
      state.category = c.dataset.cat;
    });
  });
}

function buildAreas() {
  const areaEl = document.getElementById("fArea");
  if (areaEl.tagName === "SELECT") {
    areaEl.innerHTML =
      W120.AREAS.map(function (a) { return "<option>" + esc(a) + "</option>"; }).join("");
  }
  const muniEl = document.getElementById("fMuni"); // Gauteng-wide site only
  if (muniEl && W120.MUNICIPALITIES) {
    muniEl.innerHTML =
      W120.MUNICIPALITIES.map(function (m) { return "<option>" + esc(m) + "</option>"; }).join("");
  }
}

function initPickMap() {
  state.pickMap = L.map("pickMap").setView(W120.MAP_CENTER, W120.MAP_ZOOM);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap", maxZoom: 19
  }).addTo(state.pickMap);
  state.pin = L.marker(W120.MAP_CENTER, { draggable: true }).addTo(state.pickMap);
  state.pin.on("dragend", markLocated);
  state.pickMap.on("click", function (e) {
    state.pin.setLatLng(e.latlng);
    markLocated();
  });
}

function markLocated() {
  state.locationSet = true;
  const h = document.getElementById("locHint");
  h.textContent = "✔ Location set. You can still drag the pin to adjust.";
  h.style.color = "#0B6E4F";
}

document.getElementById("btnLocate").addEventListener("click", function () {
  if (!navigator.geolocation) { toast("Your phone doesn't share location — tap the map instead", true); return; }
  const btn = this;
  btn.disabled = true; btn.textContent = "Finding you…";
  navigator.geolocation.getCurrentPosition(function (pos) {
    const ll = [pos.coords.latitude, pos.coords.longitude];
    state.pin.setLatLng(ll);
    state.pickMap.setView(ll, 17);
    markLocated();
    btn.disabled = false; btn.textContent = "📍 Use my location";
  }, function () {
    toast("Couldn't get your location — tap the exact spot on the map instead", true);
    btn.disabled = false; btn.textContent = "📍 Use my location";
  }, { enableHighAccuracy: true, timeout: 12000 });
});

document.getElementById("fPhoto").addEventListener("change", async function () {
  const f = this.files[0];
  const hint = document.getElementById("photoHint");
  state.photoBlob = null;
  if (!f) { hint.textContent = ""; return; }
  try {
    state.photoBlob = await compressImage(f);
    hint.textContent = "✔ Photo ready (" + Math.round(state.photoBlob.size / 1024) + " KB after shrinking)";
  } catch (e) {
    hint.textContent = "That file isn't a photo we can use.";
    this.value = "";
  }
});

document.getElementById("btnSubmit").addEventListener("click", async function () {
  const desc = document.getElementById("fDesc").value.trim();
  const areaEl = document.getElementById("fArea");
  if (!state.category) { toast("Please choose what the problem is", true); return; }
  if (desc.length < 5) { toast("Please describe the problem in a few words", true); return; }
  if (areaEl.tagName === "INPUT" && areaEl.value.trim().length < 2) {
    toast("Please type your suburb or area", true); return;
  }
  if (!state.locationSet) {
    toast("Please set the location — tap the map or use 📍 My location", true);
    document.getElementById("pickMap").scrollIntoView({ behavior: "smooth", block: "center" });
    return;
  }
  const btn = this;
  btn.disabled = true; btn.textContent = "Sending…";
  try {
    let photo_url = null;
    if (state.photoBlob) photo_url = await uploadPhoto(sb, state.photoBlob);
    const ll = state.pin.getLatLng();
    const row = {
      category: state.category,
      description: desc,
      area: areaEl.value.trim() || "Other",
      lat: ll.lat, lng: ll.lng,
      photo_url: photo_url,
      reporter_name: document.getElementById("fName").value.trim() || null,
      reporter_phone: document.getElementById("fPhone").value.trim() || null
    };
    const muniEl = document.getElementById("fMuni"); // Gauteng-wide site only
    if (muniEl) row.municipality = muniEl.value;
    const res = await sb.from("reports").insert(row).select("ref").single();
    if (res.error) throw res.error;
    showSuccess(res.data.ref);
    loadReports();
  } catch (e) {
    console.error(e);
    document.getElementById("offlineBanner").hidden = false;
    toast("Sending failed — please check your signal and try again", true);
  } finally {
    btn.disabled = false; btn.textContent = "Send report";
  }
});

function showSuccess(ref) {
  document.getElementById("reportCard").hidden = true;
  const card = document.getElementById("successCard");
  card.hidden = false;
  document.getElementById("successRef").textContent = ref;
  const share = document.getElementById("btnShareWA");
  const msg = "I just reported a problem in Ward 120 — ref " + ref +
    ". Track it here: " + location.origin + location.pathname;
  share.href = "https://wa.me/?text=" + encodeURIComponent(msg);
  share.hidden = false;
  window.scrollTo(0, 0);
}

document.getElementById("btnAnother").addEventListener("click", function () {
  document.getElementById("successCard").hidden = true;
  document.getElementById("reportCard").hidden = false;
  document.getElementById("fDesc").value = "";
  document.getElementById("fPhoto").value = "";
  document.getElementById("photoHint").textContent = "";
  state.photoBlob = null;
});

/* ================= data ================= */
async function loadReports() {
  try {
    const res = await sb.from("reports")
      .select(PUBLIC_COLUMNS)
      .order("created_at", { ascending: false })
      .limit(500);
    if (res.error) throw res.error;
    state.reports = res.data;
    document.getElementById("offlineBanner").hidden = true;
    renderCounters(); renderList(); renderFixed(); renderMarkers();
  } catch (e) {
    console.error(e);
    document.getElementById("offlineBanner").hidden = false;
  }
}

function renderCounters() {
  const open = state.reports.filter(function (r) { return r.status === "new" || r.status === "acknowledged"; }).length;
  const busy = state.reports.filter(function (r) { return r.status === "in_progress" || r.status === "escalated"; }).length;
  const fixed = state.reports.filter(function (r) { return r.status === "fixed"; }).length;
  document.getElementById("cOpen").textContent = open;
  document.getElementById("cBusy").textContent = busy;
  document.getElementById("cFixed").textContent = fixed;
}

/* ================= list ================= */
document.getElementById("listFilters").addEventListener("click", function (e) {
  const b = e.target.closest("button"); if (!b) return;
  this.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
  b.classList.add("on");
  state.filter = b.dataset.f;
  renderList();
});

function filtered() {
  return state.reports.filter(function (r) {
    if (state.filter === "all") return true;
    if (state.filter === "open") return ["new", "acknowledged", "in_progress", "escalated"].indexOf(r.status) >= 0;
    if (state.filter === "fixed") return r.status === "fixed";
    return r.category === state.filter;
  });
}

function renderList() {
  const wrap = document.getElementById("listWrap");
  const rows = filtered();
  if (!rows.length) {
    wrap.innerHTML = '<div class="card"><p style="text-align:center;color:#66736E">No reports here yet.</p></div>';
    return;
  }
  wrap.innerHTML = rows.map(function (r) {
    const cat = CATEGORIES[r.category] || CATEGORIES.other;
    const done = state.supported.indexOf(r.id) >= 0;
    return '<div class="card rcard" data-id="' + r.id + '">' +
      '<div class="ico">' + cat.emoji + "</div>" +
      '<div class="body">' +
        '<div class="top"><span class="ref">' + esc(r.ref) + "</span>" + statusBadge(r.status) + "</div>" +
        '<div class="desc">' + esc(r.description) + "</div>" +
        '<div class="meta">' + placeLabel(r) + " · " + timeAgo(r.created_at) + "</div>" +
        '<button type="button" class="support' + (done ? " done" : "") + '" data-sup="' + r.id + '">' +
          "🙋 Me too" + (r.supports > 0 ? " · " + r.supports : "") + "</button>" +
      "</div></div>";
  }).join("");
}

document.getElementById("listWrap").addEventListener("click", async function (e) {
  const sup = e.target.closest("[data-sup]");
  if (sup) {
    e.stopPropagation();
    const id = sup.dataset.sup;
    if (state.supported.indexOf(id) >= 0) { toast("You already supported this one 👍"); return; }
    const res = await sb.rpc("add_support", { p_report: id });
    if (!res.error) {
      state.supported.push(id);
      localStorage.setItem("w120_supported", JSON.stringify(state.supported));
      const r = state.reports.find(function (x) { return x.id === id; });
      if (r) r.supports = res.data;
      sup.classList.add("done");
      sup.textContent = "🙋 Me too · " + res.data;
      toast("Thanks — that helps us prioritise");
    }
    return;
  }
  const card = e.target.closest(".rcard");
  if (card) openDetail(card.dataset.id);
});

/* ================= detail modal ================= */
async function openDetail(id) {
  const r = state.reports.find(function (x) { return x.id === id; });
  if (!r) return;
  const cat = CATEGORIES[r.category] || CATEGORIES.other;
  const body = document.getElementById("modalBody");
  body.innerHTML =
    '<button type="button" class="close" id="modalClose">✕</button>' +
    '<div class="top" style="display:flex;gap:10px;align-items:center">' +
      '<span style="font-size:28px">' + cat.emoji + "</span>" +
      '<div><div class="ref" style="font-weight:800;color:#0B6E4F">' + esc(r.ref) + "</div>" +
      statusBadge(r.status) + "</div></div>" +
    (r.photo_url ? '<p><img src="' + esc(r.photo_url) + '" alt="report photo" style="border-radius:10px"></p>' : "") +
    "<p>" + esc(r.description) + "</p>" +
    '<p class="hint">' + placeLabel(r) + " · reported " + fmtDate(r.created_at) + " · 🙋 " + r.supports + " affected</p>" +
    (r.escalation_ref ?
      '<div class="banner">🏛️ Escalated to the municipality — reference <b>' + esc(r.escalation_ref) + "</b></div>" : "") +
    (r.fixed_photo_url ?
      '<div class="beforeafter"><div><div class="lbl">Before</div>' +
      (r.photo_url ? '<img src="' + esc(r.photo_url) + '" alt="before">' : '<p class="hint">no photo</p>') +
      '</div><div><div class="lbl">After</div><img src="' + esc(r.fixed_photo_url) + '" alt="after"></div></div>' : "") +
    "<h3>Progress — public record</h3>" +
    '<ul class="timeline" id="modalTimeline"><li>Loading…</li></ul>';
  document.getElementById("modalBack").classList.add("on");
  document.getElementById("modalClose").addEventListener("click", closeModal);

  const hist = await sb.from("status_history")
    .select("status,note,created_at")
    .eq("report_id", id)
    .order("created_at", { ascending: true });
  const ul = document.getElementById("modalTimeline");
  if (hist.error || !hist.data.length) { ul.innerHTML = "<li>No timeline yet.</li>"; return; }
  ul.innerHTML = hist.data.map(function (h) {
    const st = STATUSES[h.status] || { public: h.status };
    return "<li><b>" + esc(st.public) + '</b><div class="when">' + fmtDate(h.created_at) + "</div>" +
      (h.note ? '<div class="note">💬 ' + esc(h.note) + "</div>" : "") + "</li>";
  }).join("");
}

function closeModal() { document.getElementById("modalBack").classList.remove("on"); }
document.getElementById("modalBack").addEventListener("click", function (e) {
  if (e.target === this) closeModal();
});

/* ================= fixed wall ================= */
function renderFixed() {
  const wrap = document.getElementById("fixedWrap");
  const rows = state.reports.filter(function (r) { return r.status === "fixed"; });
  if (!rows.length) {
    wrap.innerHTML = '<div class="card"><p style="text-align:center;color:#66736E">' +
      "The first fix will appear here — with before &amp; after photos. Watch this space. 💪</p></div>";
    return;
  }
  wrap.innerHTML = rows.map(function (r) {
    const cat = CATEGORIES[r.category] || CATEGORIES.other;
    const days = r.fixed_at ? daysBetween(r.created_at, r.fixed_at) : null;
    return '<div class="card fixgrid rcard" data-id="' + r.id + '"><div class="body">' +
      '<div class="top"><span class="ref">' + cat.emoji + " " + esc(r.ref) + "</span>" +
      (days !== null ? '<span class="fixdays">Fixed in ' + days + (days === 1 ? " day" : " days") + "</span>" : statusBadge("fixed")) +
      "</div>" +
      '<div class="desc">' + esc(r.description) + "</div>" +
      '<div class="meta">' + placeLabel(r) + "</div>" +
      ((r.photo_url || r.fixed_photo_url) ?
        '<div class="beforeafter"><div><div class="lbl">Before</div>' +
        (r.photo_url ? '<img src="' + esc(r.photo_url) + '" alt="before">' : '<p class="hint">no photo</p>') +
        '</div><div><div class="lbl">After</div>' +
        (r.fixed_photo_url ? '<img src="' + esc(r.fixed_photo_url) + '" alt="after">' : '<p class="hint">no photo</p>') +
        "</div></div>" : "") +
      "</div></div>";
  }).join("");
}
document.getElementById("fixedWrap").addEventListener("click", function (e) {
  const card = e.target.closest(".rcard");
  if (card) openDetail(card.dataset.id);
});

/* ================= big map ================= */
function statusColor(s) {
  if (s === "fixed") return "#0B6E4F";
  if (s === "in_progress" || s === "escalated") return "#F5A623";
  if (s === "closed") return "#7F8C8D";
  return "#D64545";
}

function initBigMap() {
  if (state.bigMap) return;
  state.bigMap = L.map("bigMap").setView(W120.MAP_CENTER, W120.MAP_ZOOM);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap", maxZoom: 19
  }).addTo(state.bigMap);
  state.markersLayer = L.layerGroup().addTo(state.bigMap);
  renderMarkers();
}

function renderMarkers() {
  if (!state.markersLayer) return;
  state.markersLayer.clearLayers();
  state.reports.forEach(function (r) {
    const cat = CATEGORIES[r.category] || CATEGORIES.other;
    const m = L.circleMarker([r.lat, r.lng], {
      radius: 9, weight: 2, color: "#fff",
      fillColor: statusColor(r.status), fillOpacity: 0.92
    });
    m.bindPopup(
      '<b>' + esc(r.ref) + "</b> " + cat.emoji + "<br>" +
      esc(r.description.slice(0, 90)) + (r.description.length > 90 ? "…" : "") + "<br>" +
      '<small>' + esc((STATUSES[r.status] || {}).public || r.status) + "</small><br>" +
      '<a href="#" data-detail="' + r.id + '">Full details ›</a>'
    );
    state.markersLayer.addLayer(m);
  });
}

document.addEventListener("click", function (e) {
  const a = e.target.closest("[data-detail]");
  if (a) { e.preventDefault(); openDetail(a.dataset.detail); }
});

/* ================= WhatsApp config ================= */
function initWhatsApp() {
  if (!W120.WHATSAPP_NUMBER) return;
  document.getElementById("waFallback").innerHTML =
    ', or <a href="' + waLink(W120.WHATSAPP_NUMBER, "Hi, I want to report a problem in Ward 120:") +
    '" target="_blank" rel="noopener">report it on WhatsApp</a>';
  const v = document.getElementById("volunteerCard");
  v.hidden = false;
  document.getElementById("btnVolunteer").href =
    waLink(W120.WHATSAPP_NUMBER, "Hi Truth and Solidarity — I want to volunteer for Ward 120 fixes!");
}

/* ================= boot ================= */
buildCategoryChips();
buildAreas();
initPickMap();
initWhatsApp();
loadReports();
