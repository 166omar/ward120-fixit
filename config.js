// ============================================================
// Fix Ward 120 — site configuration
// Edit this file to change settings. No other file needs edits.
// ============================================================
window.W120 = {
  // Supabase backend (anon key is safe to publish — security lives in the database rules)
  SUPABASE_URL: "https://vzwkelixolmexgfkwoif.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6d2tlbGl4b2xtZXhnZmt3b2lmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMTgyMjQsImV4cCI6MjEwMzU5NDIyNH0.6h8RIjnh2FIK1XVvuUYh9yOAIj-ffv9vCJKQIZZREXA",

  // Truth and Solidarity WhatsApp number in international format, digits only,
  // e.g. "27731234567". Leave "" to hide all WhatsApp buttons until ready.
  WHATSAPP_NUMBER: "27833435786",

  // Map defaults (Lenasia South / Vlakfontein, Ward 120)
  MAP_CENTER: [-26.392, 27.870],
  MAP_ZOOM: 13,

  // Department emails used by the admin "Escalate" button, per municipality.
  // These are publicly listed addresses — VERIFY them before first use and fill
  // in the blanks (your ward councillor's office will know the right ones).
  // Per-category overrides: water, sewer, drain, road, light. "default" is the fallback.
  ESCALATION_EMAILS: {
    "City of Johannesburg": {
      default: "joburgconnect@joburg.org.za",     // Joburg Connect, 0860 562 874 (verified 10 Sept 2026)
      // ⚠️ customer@jwater.co.za is DEAD — it auto-replies "no longer valid" and the fault is lost.
      // Rule (learned 15–16 Sept 2026): Joburg Water = fault@jwater.co.za until they name another
      // address. E-mail alone does NOT issue a reference number: it auto-replies telling you to log
      // the fault on the Forcelink portal (see docs/JW_PORTAL_STEPS.md). The portal is what gives a
      // JWCC- reference. Follow up on an existing ticket by replying with the ref in the subject in
      // square brackets, e.g. [JWCC-412345678].
      water: "fault@jwater.co.za",                 // Johannesburg Water faults (verified 16 Sept 2026)
      sewer: "fault@jwater.co.za",
      drain: "hotline@jra.org.za",                 // JRA hotline (verified)
      road:  "hotline@jra.org.za",
      light: "joburgconnect@joburg.org.za",        // City Power faults go via Joburg Connect / 0860 562 874 opt 2
      dumping: "illegaldumping@pikitup.co.za"      // Pikitup illegal dumping (verified), 011 688 1500
    },
    "City of Tshwane":   { default: "customercare@tshwane.gov.za" },
    "City of Ekurhuleni": { default: "" },
    "Emfuleni":          { default: "" },
    "Midvaal":           { default: "" },
    "Lesedi":            { default: "" },
    "Mogale City":       { default: "" },
    "Rand West City":    { default: "" },
    "Merafong City":     { default: "" }
  },

  // Donations. Fill either (or both) to show them on the Support card:
  // DONATE_URL: a payment link (PayFast / BackaBuddy / SnapScan / Yoco page)
  // DONATE_BANK: bank/EFT details, use \n for new lines
  DONATE_URL: "",
  DONATE_BANK: "",

  // Areas offered in the report form (edit freely)
  AREAS: [
    "Lenasia South",
    "Lenasia South Ext 1",
    "Lenasia South Ext 4",
    "Hospital Hills (Ext 28)",
    "Vlakfontein",
    "Lawley",
    "Ennerdale",
    "Orange Farm",
    "Other / nearby"
  ]
};
