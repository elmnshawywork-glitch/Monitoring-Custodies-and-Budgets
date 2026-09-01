# ابدأ إديو — التحويل إلى Supabase (قاعدة أساسية) مع جوجل شيت كنسخة احتياطية

لمعالجة ثقل البيانات: تصبح **Supabase (Postgres)** هى القاعدة الأساسية السريعة، و**جوجل شيت نسخة احتياطية** تُحدَّث تلقائياً.

## المكوّنات
- `supabase_setup.sql` — يُنشئ الجداول + دالة `api()` الآمنة + بيانات أولية (يُشغَّل مرة فى Supabase).
- الواجهة تتصل بدالة واحدة فقط (`rpc/api`) فلا تُكشف الجداول للعامة.
- `EBDA_Supabase_Backup.gs` — Apps Script ينسخ من Supabase إلى الشيت يومياً.

## الخطوات
### 1) إنشاء القاعدة على Supabase
1. أنشئ مشروعاً على supabase.com.
2. **SQL Editor ‹ New query**، الصق `supabase_setup.sql` بالكامل ‹ **Run**.
3. من **Settings ‹ API** انسخ: **Project URL** و**anon public key**.
4. (أمان) غيّر رمز النسخ الاحتياطى:
   `update ebda.config set value='رمز_سرّى_قوى' where key='backup_token';`

### 2) ربط الواجهة (GitHub)
فى `config.js`:
```js
SUPABASE_URL: "https://xxxx.supabase.co",
SUPABASE_ANON_KEY: "مفتاح anon",
```
الأولوية: Supabase ‹ Apps Script ‹ وضع تجريبى. ارفع `config.js` و`bundle.js`.
سجّل الدخول: **admin / 1234** ثم غيّر كلمته وأضف المستخدمين.

### 3) النسخ الاحتياطى إلى جوجل شيت
1. افتح شيت النسخ ‹ Apps Script، الصق `EBDA_Supabase_Backup.gs`.
2. عدّل: `SUPABASE_URL`، `SUPABASE_ANON_KEY`، و`BACKUP_TOKEN` (نفس رمز `ebda.config`).
3. شغّل `backupToSheet` مرة (اقبل الصلاحيات)، ثم `installDailyBackup` لجدولة نسخة يومية.
   تُكتب البيانات فى تبويبات `db_users`, `db_schools`, `db_expenses` … مع `_backup_log`.

## ملاحظات
- **الأمان:** الجداول فى مخطط `ebda` غير مكشوفة؛ العامة يستطيعون فقط تنفيذ `api()` التى تتحقق من اسم المستخدم/الـPIN. لا تُستخدم مفاتيح service_role فى الواجهة.
- **المستندات:** فى وضع Supabase تُخزَّن روابط/داتا المستندات فى القاعدة (يمكن لاحقاً استخدام Supabase Storage).
- **الإيميلات:** إشعارات الاعتماد/المراجعة والإرسال بالإيميل تبقى عبر مسار Apps Script أو عبر Supabase Edge Function (غير مفعّلة افتراضياً فى وضع Supabase). عند الحاجة أضيفها كـ Edge Function.
- كل منطق الأدوار والصلاحيات (مدير/محاسب/مدير مباشر/مسئول عهدة) والاستيراد والخصم بعد التسوية منفّذ داخل `api()` تماماً كما فى نسخة جوجل شيت — وتم اختباره على Postgres حقيقى.
