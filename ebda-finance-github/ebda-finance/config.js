/* ============================================================
   إعدادات الربط — الأولوية: Supabase ثم Apps Script ثم وضع تجريبى
   ============================================================ */
window.EBDA_CONFIG = {
  // (١) الأساسى: Supabase (سريع لكميات البيانات الكبيرة)
  SUPABASE_URL: "",        // مثال: "https://xxxx.supabase.co"
  SUPABASE_ANON_KEY: "",   // مفتاح anon العام من Supabase ‹ Settings ‹ API

  // (٢) بديل/سابق: Google Apps Script فوق جوجل شيت
  API_URL: "",             // رابط /exec

  APP_TITLE: "ابدأ إديو — متابعة الموازنات والعهد",
  SHEET_URL: "https://docs.google.com/spreadsheets/d/1-iQ_zkmWryCJqL7XC_-NLXzXfh2W_tatvpm-uL7hZNo/edit"
};
