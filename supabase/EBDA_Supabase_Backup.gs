/**
 * ابدأ إديو — نسخ احتياطى من Supabase إلى Google Sheet
 * ------------------------------------------------------------
 * الاستخدام:
 *  1) افتح شيت النسخ الاحتياطى ‹ Extensions ‹ Apps Script، الصق هذا الملف.
 *  2) عدّل القيم الثلاث بالأسفل (الرابط + مفتاح anon + رمز النسخ السرّى).
 *     رمز النسخ يجب أن يطابق ما فى جدول ebda.config (backup_token) داخل Supabase.
 *  3) شغّل الدالة backupToSheet مرة واقبل الصلاحيات للتأكد.
 *  4) شغّل installDailyBackup مرة واحدة لجدولة نسخة يومية تلقائية.
 */

var SUPABASE_URL = 'https://xxxx.supabase.co';
var SUPABASE_ANON_KEY = 'ضع مفتاح anon هنا';
var BACKUP_TOKEN = 'CHANGE_ME_TO_A_SECRET';

function backupToSheet() {
  var res = UrlFetchApp.fetch(SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/api', {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + SUPABASE_ANON_KEY },
    payload: JSON.stringify({ req: { action: 'dumpAll', token: BACKUP_TOKEN } }),
    muteHttpExceptions: true
  });
  var data = JSON.parse(res.getContentText());
  if (!data || !data.ok) throw new Error((data && data.error) || 'فشل النسخ الاحتياطى');
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var map = {
    db_users: data.users, db_schools: data.schools, db_lines: data.lines,
    db_custodies: data.custodies, db_tranches: data.tranches, db_expenses: data.expenses,
    db_spend_items: data.spend_items, db_holders: data.holders, db_approvers: data.approvers, db_emails: data.emails
  };
  Object.keys(map).forEach(function (name) { writeTable_(ss, name, map[name] || []); });
  var log = ss.getSheetByName('_backup_log') || ss.insertSheet('_backup_log');
  log.appendRow([new Date(), 'تم النسخ الاحتياطى بنجاح']);
}

function writeTable_(ss, name, rows) {
  var sh = ss.getSheetByName(name) || ss.insertSheet(name);
  sh.clearContents();
  if (!rows.length) return;
  var headers = Object.keys(rows[0]);
  var out = [headers];
  for (var i = 0; i < rows.length; i++) {
    out.push(headers.map(function (h) { var v = rows[i][h]; return v == null ? '' : v; }));
  }
  sh.getRange(1, 1, out.length, headers.length).setValues(out);
  sh.setFrozenRows(1);
}

function installDailyBackup() {
  // يحذف أى مؤقّت سابق لنفس الدالة ثم ينشئ نسخة يومية 2 صباحاً
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'backupToSheet') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('backupToSheet').timeBased().everyDays(1).atHour(2).create();
}
