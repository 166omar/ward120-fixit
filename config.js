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
  WHATSAPP_NUMBER: "",

  // Map defaults (Lenasia South / Vlakfontein, Ward 120)
  MAP_CENTER: [-26.392, 27.870],
  MAP_ZOOM: 13,

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
