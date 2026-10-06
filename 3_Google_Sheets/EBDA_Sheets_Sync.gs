/**
 * ابدأ إديو — مزامنة قاعدة البيانات (Supabase) مع شيتات المتابعة على Google Sheets
 * ---------------------------------------------------------------------------------
 * المصدر الرئيسى للبيانات = قاعدة البيانات. الشيتات = نسخة متابعة وتقارير (اتجاه واحد: DB ← Sheets).
 *
 * التركيب (مرة واحدة):
 *  1) افتح شيت متابعة الموازنات ‹ Extensions ‹ Apps Script ‹ ملف جديد، الصق هذا الملف.
 *  2) عدّل الإعدادات بالأسفل: رابط Supabase + مفتاح anon + رمز النسخ السرّى (نفس ebda.config.backup_token).
 *  3) شغّل syncNow مرة واقبل الصلاحيات (يحتاج صلاحية فتح الشيتين).
 *  4) شغّل installSync مرة لجدولة مزامنة تلقائية كل ساعة. (وتظهر قائمة «ابدأ إديو» أعلى الشيت).
 *
 * ما يحدث فى كل مزامنة:
 *  - تُكتب/تُحدَّث تبويبات مُدارة تبدأ بالرمز ⟳ فقط. لا يُلمس أى تبويب آخر من تبويباتك الحالية.
 *  - كل صف له مفتاح ثابت (معرّف السجل فى قاعدة البيانات) فى آخر عمود مُدار ⇒ إعادة المزامنة تحدّث نفس الصف
 *    ولا تكرّره، والسجلات الجديدة تُضاف فى الأسفل.
 *  - السجل المحذوف من النظام لا يُمسح من الشيت؛ يُعلَّم «محذوف من النظام» (لا فقد للبيانات).
 *  - أى أعمدة تضيفها أنت يمين الجدول المُدار (ملاحظات/تحليل) تبقى كما هى ومرتبطة بنفس الصف.
 *  - أنشئ شيتات التحليل والتقارير كما تريد واربطها بالتبويبات المُدارة بالمعادلات (ترتيب الأعمدة ثابت).
 */

var CONFIG = {
  SUPABASE_URL: 'https://xxxx.supabase.co',
  SUPABASE_ANON_KEY: 'ضع مفتاح anon هنا',
  BACKUP_TOKEN: 'ضع رمز النسخ السرّى هنا',
  // الشيتان الحاليان (من الروابط التى أرسلتها)
  BUDGET_SHEET_ID: '1LZBlV8Z6lPE6u61gUop_SY7fyxH1oK-l8G9ezLKHD9o',
  CUSTODY_SHEET_ID: '1e4F3i1cQ0AAJuTlk2Bq0ieQudiYjRoXhpsGadn_5kfs'
};

var MONTHS = ['سبتمبر','أكتوبر','نوفمبر','ديسمبر','يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس'];
var ENTITY_TYPES = { school:'مدرسة', company:'الشركة', training_general:'تدريب عام', training_vocational:'تدريب مهنى',
  training_project:'مشروع تدريب', training_program:'برنامج تدريب', training_course:'دورة تدريبية' };
var CUST_STATUS = { open:'مفتوحة', pending_settlement:'فى انتظار التسوية', settled:'تمت التسوية', closed:'مغلقة', cancelled:'ملغاة' };
var APPROVAL = { pending:'معلق — بانتظار المدير المباشر', approved:'معتمد', rejected:'مرفوض' };
var FIN = { '':'بانتظار الاعتماد المالى', approved:'معتمد مالياً', rejected:'مرفوض مالياً' };
var REQ = { pending_supervisor:'بانتظار المدير المباشر', pending_accountant:'بانتظار الاعتماد المالى', transferred:'معتمد مالياً · تم التحويل للعهدة', rejected:'مرفوض' };
var DELETED = 'محذوف من النظام';

function onOpen() {
  SpreadsheetApp.getUi().createMenu('ابدأ إديو').addItem('مزامنة الآن', 'syncNow').addItem('تفعيل المزامنة كل ساعة', 'installSync').addToUi();
}

function installSync() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'syncNow') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('syncNow').timeBased().everyHours(1).create();
}

function fetchExport_() {
  var res = UrlFetchApp.fetch(CONFIG.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/api', {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { apikey: CONFIG.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + CONFIG.SUPABASE_ANON_KEY },
    payload: JSON.stringify({ req: { action: 'syncExport', token: CONFIG.BACKUP_TOKEN } })
  });
  var data = JSON.parse(res.getContentText());
  if (!data || !data.ok) throw new Error((data && data.error) || ('فشل الاتصال بقاعدة البيانات: HTTP ' + res.getResponseCode()));
  return data;
}

function syncNow() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) return;  // مزامنة أخرى تعمل الآن
  var started = new Date(), stats = [];
  try {
    var d = fetchExport_();
    var budget = SpreadsheetApp.openById(CONFIG.BUDGET_SHEET_ID);
    var custody = SpreadsheetApp.openById(CONFIG.CUSTODY_SHEET_ID);

    // ---------------- شيت متابعة الموازنات
    var bHead = ['الجهة','نوع الجهة','السنة المالية','القسم','البند','المخصص السنوى','المخصص الشهرى']
      .concat(MONTHS.map(function (m) { return 'مصروف ' + m; }))
      .concat(['إجمالى المصروف','المتبقى','العجز / التجاوز','نسبة التنفيذ','قيد الاعتماد (غير محتسب)','حالة البند']);
    var bRows = d.budget.map(function (b) {
      var annual = num_(b.annual), spent = num_(b.spent);
      var status = annual === 0 && spent === 0 ? 'لا توجد موازنة' : spent > annual ? 'يوجد عجز' : (annual && spent / annual >= 0.9 ? 'قارب على النفاد' : 'ضمن الموازنة');
      return { key: b.key, values: [b.entity, ENTITY_TYPES[b.entity_type] || b.entity_type, b.fiscal_year, b.section, b.line, annual, num_(b.monthly)]
        .concat((b.months || []).map(num_))
        .concat([spent, Math.max(0, annual - spent), Math.max(0, spent - annual), annual ? spent / annual : 0, num_(b.pending), status]) };
    });
    stats.push(upsert_(budget, '⟳ متابعة الموازنات', bHead, bRows, { money: [6, 7].concat(range_(8, 19)).concat([20, 21, 22, 24]), pct: [23], statusCol: 25 }));

    // ملخص لكل جهة (يُعاد بناؤه بالكامل لأنه تجميعى)
    var ent = {};
    d.budget.forEach(function (b) {
      var k = b.entity_id; if (!ent[k]) ent[k] = { key: k, e: b.entity, t: ENTITY_TYPES[b.entity_type] || b.entity_type, fy: b.fiscal_year, a: 0, s: 0, def: 0, n: 0 };
      var a = num_(b.annual), s = num_(b.spent); ent[k].a += a; ent[k].s += s; if (s > a) { ent[k].def += s - a; ent[k].n++; }
    });
    var sRows = Object.keys(ent).map(function (k) { var x = ent[k];
      return { key: x.key, values: [x.e, x.t, x.fy, x.a, x.s, Math.max(0, x.a - x.s), x.def, x.a ? x.s / x.a : 0, x.n] }; });
    stats.push(upsert_(budget, '⟳ ملخص الجهات', ['الجهة','نوع الجهة','السنة المالية','إجمالى الموازنة','إجمالى المصروف','المتبقى','إجمالى العجز','نسبة التنفيذ','بنود بها عجز'], sRows, { money: [4, 5, 6, 7], pct: [8] }));

    // ---------------- شيت متابعة العهد
    var cRows = d.custodies.map(function (c) {
      var rem = num_(c.received) - num_(c.spent);
      var st = CUST_STATUS[c.status] || c.status;
      if (c.status === 'open' && num_(c.exp_count) > 0) st = 'بها مصروفات';
      return { key: c.key, values: [c.code, c.entity, ENTITY_TYPES[c.entity_type] || c.entity_type, c.holder, date_(c.opened_at), num_(c.received), num_(c.spent),
        num_(c.settled_amount), rem, st, num_(c.exp_count), num_(c.pending_count), num_(c.unsettled_count), date_(c.settled_at), date_(c.closed_at)] };
    });
    stats.push(upsert_(custody, '⟳ متابعة العهد', ['رقم العهدة','الجهة','نوع الجهة','مسئول العهدة','تاريخ العهدة','المبلغ المستلم','المصروف','إجمالى المُسوّى','المتبقى','حالة العهدة',
      'عدد المصروفات','معلق الاعتماد','غير مُسوّى','تاريخ التسوية','تاريخ الإغلاق'], cRows, { money: [6, 7, 8, 9], statusCol: 10 }));

    var eRows = d.expenses.map(function (e) {
      return { key: e.key, values: [e.txn_no, date_(e.date), e.entity, e.custody_code, e.holder, e.section, e.line, e.spend_item, e.description, num_(e.amount),
        APPROVAL[e.approval] || e.approval, FIN[e.fin_approval] !== undefined ? (e.approval === 'approved' ? FIN[e.fin_approval] : '—') : e.fin_approval,
        e.settled === 'نعم' ? 'تمت التسوية' : 'غير مُسوّى', e.in_budget, e.has_doc, e.doc_type, e.doc_name, e.doc_link,
        e.created_by, date_(e.created_at), e.updated_by, date_(e.updated_at), e.note] };
    });
    stats.push(upsert_(custody, '⟳ المصروفات', ['رقم العملية','التاريخ','الجهة','العهدة','مسئول العهدة','القسم','بند الموازنة','نوع المصروف','الوصف','المبلغ',
      'موافقة المدير المباشر','الاعتماد المالى','التسوية مع الحسابات','محتسب فى الموازنة','يوجد مستند','نوع المستند','اسم المستند','رابط المستند',
      'سجّله','تاريخ التسجيل','آخر تعديل بواسطة','آخر تعديل','ملاحظات'], eRows, { money: [10] }));

    var rRows = d.requests.map(function (r) {
      return { key: r.key, values: [r.req_no, date_(r.created_at), r.entity, r.requester, r.items, num_(r.total), r.reason, REQ[r.status] || r.status, r.decided_by, r.fin_by, r.custody_code, r.note] };
    });
    stats.push(upsert_(custody, '⟳ طلبات العهد', ['رقم الطلب','التاريخ','الجهة','مقدم الطلب','البنود والمبالغ','إجمالى الطلب','السبب','الحالة','المدير المباشر','المدير المالى','العهدة','ملاحظات'],
      rRows, { money: [6] }));

    log_(budget, started, 'تمت المزامنة', stats.join(' · '));
    log_(custody, started, 'تمت المزامنة', stats.join(' · '));
  } catch (err) {
    try { log_(SpreadsheetApp.openById(CONFIG.BUDGET_SHEET_ID), started, 'فشل', String(err && err.message || err)); } catch (e) {}
    throw err;
  } finally {
    lock.releaseLock();
  }
}

/**
 * يكتب جدولاً مُداراً بمفتاح ثابت فى آخر عمود مُدار (مخفى):
 *  - صف موجود ⇒ تحديث قيمه فقط (الأعمدة الإضافية يمين الجدول لا تُلمس)
 *  - صف جديد ⇒ يُضاف فى الأسفل
 *  - صف لم يعد موجوداً فى النظام ⇒ يُعلَّم «محذوف من النظام» ولا يُحذف
 */
function upsert_(ss, name, headers, rows, fmt) {
  var sh = ss.getSheetByName(name) || ss.insertSheet(name);
  var width = headers.length + 1;               // + عمود المفتاح
  var keyCol = width;
  sh.getRange(1, 1, 1, width).setValues([headers.concat(['_key'])])
    .setFontWeight('bold').setBackground('#34495E').setFontColor('#FFFFFF').setWrap(true).setVerticalAlignment('middle');
  sh.setFrozenRows(1); sh.setRightToLeft(true);
  var last = sh.getLastRow();
  var existing = last > 1 ? sh.getRange(2, 1, last - 1, width).getValues() : [];
  var index = {};
  existing.forEach(function (r, i) { if (r[keyCol - 1] !== '') index[String(r[keyCol - 1])] = i; });
  var seen = {}, added = 0, updated = 0, removed = 0;
  rows.forEach(function (r) {
    var line = r.values.concat([r.key]);
    if (index.hasOwnProperty(String(r.key))) { existing[index[String(r.key)]] = line; updated++; }
    else { existing.push(line); added++; }
    seen[String(r.key)] = true;
  });
  existing.forEach(function (r) {
    var k = String(r[keyCol - 1]);
    if (k && !seen[k] && r[0] !== DELETED) {
      // عمود الحالة إن وجد وإلا أول عمود
      var c = (fmt.statusCol || 1) - 1; r[c] = DELETED; removed++;
    }
  });
  if (existing.length) sh.getRange(2, 1, existing.length, width).setValues(existing);
  var n = Math.max(existing.length, 1);
  (fmt.money || []).forEach(function (c) { sh.getRange(2, c, n, 1).setNumberFormat('#,##0;[Red]-#,##0'); });
  (fmt.pct || []).forEach(function (c) { sh.getRange(2, c, n, 1).setNumberFormat('0.0%'); });
  sh.hideColumns(keyCol);
  // حماية تحذيرية للجزء المُدار (يمكن للمستخدم الكتابة يمينه بحرية)
  var prot = sh.getProtections(SpreadsheetApp.ProtectionType.RANGE).filter(function (p) { return p.getDescription() === 'managed'; });
  var pr = prot.length ? prot[0] : sh.getRange(1, 1, 1, width).protect().setDescription('managed');
  pr.setRange(sh.getRange(1, 1, Math.max(sh.getLastRow(), 2), width)).setWarningOnly(true);
  if (fmt.statusCol) colorStatus_(sh, fmt.statusCol, n);
  return name + ': +' + added + ' / ~' + updated + (removed ? ' / حُذف ' + removed : '');
}

function colorStatus_(sh, col, n) {
  var rng = sh.getRange(2, col, n, 1);
  var rules = sh.getConditionalFormatRules().filter(function (r) {
    return !r.getRanges().some(function (x) { return x.getColumn() === col; });
  });
  var add = function (txt, bg, fg) {
    rules.push(SpreadsheetApp.newConditionalFormatRule().whenTextContains(txt).setBackground(bg).setFontColor(fg).setRanges([rng]).build());
  };
  add('عجز', '#FBE3E3', '#9C0006'); add('محذوف', '#EDEDED', '#7F7F7F'); add('قارب', '#FFF2CC', '#7F6000');
  add('انتظار', '#FFF2CC', '#7F6000'); add('تمت التسوية', '#E2F0D9', '#375623'); add('ضمن', '#E2F0D9', '#375623');
  add('مفتوحة', '#DDEBF7', '#1F3864'); add('بها مصروفات', '#DDEFF4', '#1E7E9C');
  sh.setConditionalFormatRules(rules);
}

function log_(ss, started, status, details) {
  var sh = ss.getSheetByName('⟳ سجل المزامنة') || ss.insertSheet('⟳ سجل المزامنة');
  if (sh.getLastRow() === 0) sh.appendRow(['الوقت', 'الحالة', 'المدة (ث)', 'التفاصيل']);
  sh.appendRow([new Date(), status, Math.round((new Date() - started) / 1000), details]);
}

function num_(v) { var n = Number(v); return isFinite(n) ? n : 0; }
function range_(a, b) { var r = []; for (var i = a; i <= b; i++) r.push(i); return r; }
function date_(v) { if (!v) return ''; var s = String(v); return s.length >= 10 ? s.slice(0, 10) : s; }
