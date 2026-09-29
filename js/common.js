// Shared helpers for Fix Ward 120 (public + admin pages)
"use strict";

/* Supabase client — created once per page */
function w120Client() {
  return window.supabase.createClient(W120.SUPABASE_URL, W120.SUPABASE_ANON_KEY);
}

/* Anon role may only read these columns (reporter name/phone are blocked by the DB).
   Never use select('*') on the public page. */
const PUBLIC_COLUMNS =
  "id,ref,source,category,description,area,municipality,lat,lng,photo_url,status,status_note," +
  "escalation_ref,fixed_photo_url,fixed_at,supports,created_at,updated_at";

/* "Vlakfontein · City of Johannesburg" — used on cards and detail views */
function placeLabel(r) {
  return esc(r.area) + (r.municipality ? " · " + esc(r.municipality) : "");
}

const CATEGORIES = {
  water:   { label: "Water leak", emoji: "\u{1F4A7}" },
  sewer:   { label: "Sewer spill", emoji: "\u{1F6BD}" },
  road:    { label: "Road damage", emoji: "\u{1F6E3}️" },
  dumping: { label: "Dumping / dirty area", emoji: "\u{1F5D1}️" },
  drain:   { label: "Blocked storm drain", emoji: "\u{1F327}️" },
  light:   { label: "Street light out", emoji: "\u{1F4A1}" },
  other:   { label: "Other problem", emoji: "⚠️" }
};

const STATUSES = {
  new:          { label: "Reported",       color: "#D64545", public: "Reported — waiting for the team" },
  acknowledged: { label: "Team notified",  color: "#E67E22", public: "Seen by the team" },
  in_progress:  { label: "Being fixed",    color: "#F5A623", public: "Team is working on it" },
  escalated:    { label: "Escalated",      color: "#8E44AD", public: "Escalated to the municipality" },
  fixed:        { label: "Fixed",          color: "#0B6E4F", public: "Fixed ✔" },
  closed:       { label: "Closed",         color: "#7F8C8D", public: "Closed" }
};

/* Where a report came from (column "source").
   lenzsouth.co.za is the town's neutral website: nothing that leaves the console for one
   of ITS reports may carry a party name, and its reporters' numbers are never mixed with
   party contacts. */
const SOURCES = {
  ward120: {
    label: "Fix Ward 120", color: "#0B6E4F",
    link: function () { return "https://166omar.github.io/ward120-fixit/"; },
    tracked: "This fault is tracked publicly by the Truth and Solidarity community project.",
    signoff: "Truth and Solidarity", waSign: "Truth and Solidarity — Ward 120"
  },
  gauteng: {
    label: "Gauteng", color: "#1B5E8C",
    link: function () { return "https://166omar.github.io/truth-gauteng/"; },
    tracked: "This fault is tracked publicly by the Truth and Solidarity community project.",
    signoff: "Truth and Solidarity", waSign: "Truth and Solidarity — Gauteng"
  },
  lenzsouth: {
    label: "lenzsouth.co.za", color: "#B45309",
    link: function (r) { return "https://lenzsouth.co.za/report/?ref=" + encodeURIComponent(r.ref); },
    tracked: "This fault is listed publicly on lenzsouth.co.za, the Lenasia South community website.",
    signoff: "Omar Khan\r\nKhan's Butchery, Lenasia South", waSign: "Omar Khan, Khan's Butchery"
  }
};

function sourceOf(r) { return SOURCES[r.source] || SOURCES.ward120; }

function sourceBadge(r) {
  const s = sourceOf(r);
  return '<span class="badge" style="background:' + s.color + '">' + esc(s.label) + "</span>";
}

/* Escape everything that came from users before putting it in HTML */
function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function timeAgo(iso) {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  const m = Math.floor(s / 60); if (m < 60) return m + " min ago";
  const h = Math.floor(m / 60); if (h < 24) return h + (h === 1 ? " hour ago" : " hours ago");
  const d = Math.floor(h / 24); if (d < 31) return d + (d === 1 ? " day ago" : " days ago");
  return new Date(iso).toLocaleDateString("en-ZA", { day: "numeric", month: "short", year: "numeric" });
}

function fmtDate(iso) {
  return new Date(iso).toLocaleString("en-ZA", {
    day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit"
  });
}

function daysBetween(a, b) {
  return Math.max(0, Math.round((new Date(b) - new Date(a)) / 86400000));
}

function statusBadge(status) {
  const st = STATUSES[status] || STATUSES.new;
  return '<span class="badge" style="background:' + st.color + '">' + esc(st.label) + "</span>";
}

/* Compress a photo on the phone before upload: max 1280px, JPEG q0.72.
   Saves the reporter's data and our storage. Returns a Blob. */
function compressImage(file) {
  return new Promise(function (resolve, reject) {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = function () {
      URL.revokeObjectURL(url);
      const max = 1280;
      let w = img.naturalWidth, h = img.naturalHeight;
      if (w > max || h > max) {
        const k = Math.min(max / w, max / h);
        w = Math.round(w * k); h = Math.round(h * k);
      }
      const c = document.createElement("canvas");
      c.width = w; c.height = h;
      c.getContext("2d").drawImage(img, 0, 0, w, h);
      c.toBlob(function (b) { b ? resolve(b) : reject(new Error("compress failed")); }, "image/jpeg", 0.72);
    };
    img.onerror = function () { URL.revokeObjectURL(url); reject(new Error("not an image")); };
    img.src = url;
  });
}

async function uploadPhoto(sb, blob) {
  const name = crypto.randomUUID() + ".jpg";
  const up = await sb.storage.from("report-photos").upload(name, blob, { contentType: "image/jpeg" });
  if (up.error) throw up.error;
  return sb.storage.from("report-photos").getPublicUrl(name).data.publicUrl;
}

/* Small toast messages */
function toast(msg, isError) {
  let t = document.getElementById("w120-toast");
  if (!t) {
    t = document.createElement("div");
    t.id = "w120-toast";
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.className = isError ? "toast err show" : "toast show";
  clearTimeout(t._h);
  t._h = setTimeout(function () { t.className = t.className.replace(" show", ""); }, 3500);
}

function waLink(number, text) {
  return "https://wa.me/" + number + "?text=" + encodeURIComponent(text);
}

/* ---- Escalation email (admin console) ---- */
function escalationEmail(r) {
  const m = (W120.ESCALATION_EMAILS || {})[r.municipality] || {};
  return m[r.category] || m.default || "";
}

function escalationMailto(r) {
  const to = escalationEmail(r);
  const cat = (CATEGORIES[r.category] || CATEGORIES.other).label;
  // Once the City has given us a reference, every follow-up must carry it in square
  // brackets in the subject line — that is how their systems (Joburg Water's Forcelink
  // especially) attach the mail to the open ticket. Without it, a follow-up is treated
  // as a brand-new query and goes to the back of the queue.
  const subject = (r.escalation_ref ? "[" + r.escalation_ref + "] " : "") +
    "Fault report " + r.ref + ": " + cat + " — " + r.area +
    (r.municipality ? ", " + r.municipality : "");
  const body =
    "Good day\r\n\r\n" +
    "Please log the following fault and provide a reference number.\r\n\r\n" +
    "Type of fault: " + cat + "\r\n" +
    "Location: " + r.area + (r.municipality ? ", " + r.municipality : "") + "\r\n" +
    "GPS: " + r.lat.toFixed(6) + ", " + r.lng.toFixed(6) + "\r\n" +
    "Map: https://www.openstreetmap.org/?mlat=" + r.lat + "&mlon=" + r.lng +
      "#map=18/" + r.lat + "/" + r.lng + "\r\n" +
    "Description: " + r.description + "\r\n" +
    (r.photo_url ? "Photo: " + r.photo_url + "\r\n" : "") +
    "First reported: " + new Date(r.created_at).toLocaleDateString("en-ZA") + "\r\n" +
    "Community reference: " + r.ref + "\r\n\r\n" +
    sourceOf(r).tracked + " " +
    "Kindly reply with your reference number so we can publish it for residents.\r\n\r\n" +
    "Thank you\r\n" + sourceOf(r).signoff;
  return "mailto:" + encodeURIComponent(to) +
    "?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(body);
}

/* ---- Telling the reporter what happened (admin console) ----
   A resident gave us their number so that we could come back to them about THEIR
   OWN fault. That is the only thing it may ever be used for: it is never published,
   never pasted into a WhatsApp group, and never exported into campaign material.
   Returns "" when we have no number, so the button can hide itself. */
function reporterWhatsApp(r) {
  const digits = (r.reporter_phone || "").replace(/\D/g, "").replace(/^0/, "27");
  if (!digits) return "";

  const st = STATUSES[r.status] || STATUSES.new;
  const cat = (CATEGORIES[r.category] || CATEGORIES.other).label.toLowerCase();
  const firstName = (r.reporter_name || "").trim().split(/\s+/)[0];

  // Each report links back to the site it was made on.
  const site = sourceOf(r).link(r);

  const lines = [
    "Good day" + (firstName ? " " + firstName : "") + ",",
    "",
    "An update on the " + cat + " you reported in " + r.area + ":",
    "",
    "Your reference: " + r.ref,
    "Status: " + st.public
  ];
  if (r.escalation_ref) lines.push("City reference: " + r.escalation_ref);
  if (r.status_note) lines.push("", r.status_note);
  lines.push(
    "",
    "Follow your report here, with the City's reference number: " + site,
    "",
    sourceOf(r).waSign
  );

  return "https://wa.me/" + digits + "?text=" + encodeURIComponent(lines.join("\n"));
}

/* ---- Follow-up alarms (admin console) ----
   Returns a reason string if the report needs attention, else null. */
function needsAttention(r) {
  const dayMs = 86400000;
  const sinceCreated = Math.floor((Date.now() - new Date(r.created_at)) / dayMs);
  const sinceUpdate = Math.floor((Date.now() - new Date(r.updated_at || r.created_at)) / dayMs);
  if (r.status === "new" && sinceCreated >= 1)
    return "⏰ New for " + sinceCreated + (sinceCreated === 1 ? " day" : " days") + " — respond today!";
  // A resident who reports a fault and never hears back is the whole reason people
  // stopped believing anyone. If we have their number, they get told.
  if (r.reporter_phone && !r.notified_at && r.status !== "new" && sinceCreated >= 1)
    return "🔔 The reporter has never been told anything — send them their reference";
  if ((r.status === "acknowledged" || r.status === "in_progress") && sinceUpdate >= 7)
    return "⏰ No update for " + sinceUpdate + " days — post a progress note";
  if (r.status === "escalated" && sinceUpdate >= 7)
    return "⏰ Escalated " + sinceUpdate + " days ago — chase the municipality" +
      (r.escalation_ref ? " (ref " + r.escalation_ref + ")" : "");
  return null;
}
