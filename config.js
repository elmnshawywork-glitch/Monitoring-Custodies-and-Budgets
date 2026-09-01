/* ============================================================
   إعدادات الربط — الأولوية: Supabase ثم Apps Script ثم وضع تجريبى
   ============================================================ */
window.EBDA_CONFIG = {
  // (١) الأساسى: Supabase (سريع لكميات البيانات الكبيرة)
  SUPABASE_URL: "https://awqkgnpvznaznowhoaxy.supabase.co/rest/v1/",        // مثال: "https://xxxx.supabase.co"
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3cWtnbnB2em5hem5vd2hvYXh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyMjIyMzAsImV4cCI6MjEwMzc5ODIzMH0.3CsgQq15MJaAmyQiCv9yDx6ssnpWiZBVCJzSdERbMbQ",   // مفتاح anon العام من Supabase ‹ Settings ‹ API

  // (٢) بديل/سابق: Google Apps Script فوق جوجل شيت
  API_URL: "",             // رابط /exec

  APP_TITLE: "ابدأ إديو — متابعة الموازنات والعهد",
  SHEET_URL: "https://docs.google.com/spreadsheets/d/1-iQ_zkmWryCJqL7XC_-NLXzXfh2W_tatvpm-uL7hZNo/edit"
};
