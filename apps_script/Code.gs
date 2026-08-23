/**
 * ابدأ إديو — نظام متابعة الموازنات والعهد
 * الباك-إند: Google Apps Script فوق Google Sheet (قاعدة البيانات المشتركة)
 * ------------------------------------------------------------------
 * التركيب:
 *  1) افتح الشيت → Extensions ‹ Apps Script، الصق هذا الملف كاملاً واحفظ.
 *  2) شغّل الدالة setup مرة واحدة (Run ‹ setup) واقبل الصلاحيات.
 *  3) Deploy ‹ New deployment ‹ Web app ‹ Execute as: Me ‹ Access: Anyone.
 *  4) انسخ Web app URL وضعه فى config.js بالواجهة.
 *  حساب المدير الافتراضى:  المستخدم: admin   كلمة السر (PIN): 1234
 */

var SHEET_ID = '1-iQ_zkmWryCJqL7XC_-NLXzXfh2W_tatvpm-uL7hZNo';

function ss_() {
  try { var a = SpreadsheetApp.getActiveSpreadsheet(); if (a) return a; } catch (e) {}
  return SpreadsheetApp.openById(SHEET_ID);
}

// تعريف الجداول (التبويبات) ورؤوسها
var TABLES = {
  db_users:      ['id','username','pin','name','role','schools','active','email'],
  db_schools:    ['id','name','type','period','students','active'],
  db_lines:      ['id','school_id','section','name','allocated','note'],
  db_custodies:  ['id','label','holder','school_id','note','user'],
  db_tranches:   ['id','custody_id','date','amount','note'],
  db_expenses:   ['id','date','school_id','custody_id','line_id','spend_item','description','amount','approval','approved_by','doc_url','doc_name','review_status','review_note','settled','ref','note','created_by','created_at'],
  db_spend_items:['id','name'],
  db_holders:    ['id','name','title'],
  db_approvers:  ['id','name','email'],
  db_emails:     ['id','email','label']
};

function sheet_(name) {
  var ss = ss_();
  var sh = ss.getSheetByName(name);
  if (!sh) { sh = ss.insertSheet(name); sh.hideSheet(); }
  var headers = TABLES[name];
  var first = sh.getRange(1,1,1,headers.length).getValues()[0];
  var empty = first.join('') === '';
  if (empty) { sh.getRange(1,1,1,headers.length).setValues([headers]); sh.setFrozenRows(1); }
  return sh;
}

function readAll_(name) {
  var sh = sheet_(name), headers = TABLES[name];
  var last = sh.getLastRow();
  if (last < 2) return [];
  var values = sh.getRange(2,1,last-1,headers.length).getValues();
  var out = [];
  for (var i=0;i<values.length;i++){
    var row = values[i]; if (row.join('')==='') continue;
    var o = { _row: i+2 };
    for (var c=0;c<headers.length;c++) o[headers[c]] = row[c];
    out.push(o);
  }
  return out;
}
function insert_(name, obj) {
  var sh = sheet_(name), headers = TABLES[name];
  if (!obj.id) obj.id = uid_();
  var row = headers.map(function(h){ return obj[h]!==undefined? obj[h] : ''; });
  sh.appendRow(row);
  return obj;
}
function updateById_(name, id, patch) {
  var sh = sheet_(name), headers = TABLES[name], rows = readAll_(name);
  for (var i=0;i<rows.length;i++){
    if (String(rows[i].id)===String(id)){
      var r = rows[i]._row;
      headers.forEach(function(h,ci){
        if (patch[h]!==undefined) sh.getRange(r, ci+1).setValue(patch[h]);
      });
      return true;
    }
  }
  return false;
}
function deleteById_(name, id) {
  var sh = sheet_(name), rows = readAll_(name);
  for (var i=0;i<rows.length;i++){
    if (String(rows[i].id)===String(id)){ sh.deleteRow(rows[i]._row); return true; }
  }
  return false;
}
function uid_(){ return 'id' + new Date().getTime().toString(36) + Math.floor(Math.random()*1e4).toString(36); }

// ============ إعداد أولى + بذور ============
function setup(){
  Object.keys(TABLES).forEach(function(t){ sheet_(t); });
  if (readAll_('db_users').length===0){
    insert_('db_users', {username:'admin', pin:'1234', name:'المدير العام', role:'manager', schools:'*', active:'نعم', email:''});
  }
  if (readAll_('db_spend_items').length===0){
    ['أدوات مكتبية ونظافة ومستهلكات وبوفيه','مستهلكات للورش التدريبية','مستهلكات وأدوات دراسية بالفصول',
     'انتقالات وبدلات انتقال','الوجبات بموقع التدريب','صيانة المنشأة والورش','حافز للتحول الثقافى',
     'مصاريف نثرية','إقامة','تجهيزات ورش ومعامل','مرتب مدرسين تابعين للشركة','مصاريف تدريب ميدانى','بوفيه']
      .forEach(function(n){ insert_('db_spend_items',{name:n}); });
  }
  if (readAll_('db_holders').length===0){
    insert_('db_holders',{name:'أحمد سمير', title:'مدير مدرسة بدر'});
    insert_('db_holders',{name:'منى فؤاد', title:'منسق مدرسة دمياط'});
  }
  if (readAll_('db_approvers').length===0){
    insert_('db_approvers',{name:'المدير المالى', email:'finance@ebda.com.eg'});
    insert_('db_approvers',{name:'رئيس العمليات', email:'ops@ebda.com.eg'});
  }
  if (readAll_('db_emails').length===0){
    insert_('db_emails',{email:'ebda.edu@ebda.com.eg', label:'الإدارة'});
  }
  if (readAll_('db_schools').length===0) seedSchools_();
  return 'setup done';
}

function seedSchools_(){
  var badr = uid_(), dam = uid_();
  insert_('db_schools',{id:badr, name:'مدرسة ابدأ للعلوم التقنية — بدر', type:'مدرسة', period:'2026/2027', students:253, active:'نعم'});
  insert_('db_schools',{id:dam,  name:'مدرسة ابدأ للعلوم التقنية — دمياط', type:'مدرسة', period:'2026/2027', students:255, active:'نعم'});
  var B = [
   ['تكلفة التدريس','حافز المدير الأكاديمى',120000],['تكلفة التدريس','حافز المعلمين المنتدبين',84000],
   ['تكلفة التدريس','راتب معلمى التخصص',1440000],['تكلفة التدريس','راتب معلمى المواد الثقافية',1656000],
   ['تكلفة التدريس','تدريب المعلمين',150000],['تكلفة التدريس','انتقالات وبدلات انتقال',28800],
   ['تكلفة التشغيل','معدات الأمن والسلامة',0],['تكلفة التشغيل','الزى المدرسى',350000],
   ['تكلفة التشغيل','الانتقالات إلى الموقع (أول)',27000],['تكلفة التشغيل','الانتقالات إلى الموقع (ثانى)',27000],
   ['تكلفة التشغيل','الانتقالات إلى الموقع (ثالث)',27000],['تكلفة التشغيل','الوجبات بالموقع (أول)',17820],
   ['تكلفة التشغيل','الوجبات بالموقع (ثانى)',10065],['تكلفة التشغيل','الوجبات بالموقع (ثالث)',17160],
   ['تكلفة التشغيل','التأمين على الطلبة والمعلمين',43050],['تكلفة التشغيل','حافز برنامج سمات',100000],
   ['المواد والمستلزمات','مطبوعات',37950],['المواد والمستلزمات','مستهلكات معامل',101200],
   ['المواد والمستلزمات','مستهلكات وأدوات دراسية بالفصول',13200],
   ['تكلفة الإداريين','حافز الإداريين المنتدبين',180000],['تكلفة الإداريين','حافز الأخصائيين',132000],
   ['تكلفة الإداريين','راتب الإداريين',630000],['تكلفة الإداريين','تدريب الإداريين',44000],
   ['تكلفة الإداريين','شركة نظافة',369600],['تكلفة الإداريين','شركة أمن',369600],
   ['إدارية وعمومية','الأدوات المكتبية والضيافة',42000],['إدارية وعمومية','صيانة واجهات وأسوار',18000],
   ['إدارية وعمومية','صيانة أجهزة ومعدات',18000],['إدارية وعمومية','صيانة ملاعب ولاند سكيب',18000],
   ['إدارية وعمومية','تكاليف متنوعة',18000],['إدارية وعمومية','مصاريف امتحان الدبلوم',30000],
   ['إدارية وعمومية','مصاريف تسويق مستمر',24000],
   ['تطوير المناهج','تطوير المناهج بالتخصص',100000],['المنصة','اشتراك وتشغيل المنصة',300000],
   ['الإدارة','أتعاب شركة الإدارة',1800000],['الإدارة','ضريبة القيمة المضافة',252000],
   ['الأصول الثابتة','أصول ثابتة وتجهيزات',0],['الاعتماد الدولى','الاعتماد الدولى والمراجعة',0]
  ];
  var D = [
   ['تكلفة التدريس','حافز المدير الأكاديمى',105600],['تكلفة التدريس','حافز المعلمين المنتدبين',148800],
   ['تكلفة التدريس','راتب معلمى التخصص',1080000],['تكلفة التدريس','راتب معلمى المواد الثقافية',1242000],
   ['تكلفة التدريس','تدريب المعلمين',114000],['تكلفة التدريس','انتقالات وبدلات انتقال',72000],
   ['تكلفة التشغيل','معدات الأمن والسلامة',125000],['تكلفة التشغيل','الزى المدرسى',350000],
   ['تكلفة التشغيل','الانتقالات إلى الموقع (أول)',90000],['تكلفة التشغيل','الانتقالات إلى الموقع (ثانى)',135000],
   ['تكلفة التشغيل','الانتقالات إلى الموقع (ثالث)',135000],['تكلفة التشغيل','الوجبات بالموقع (أول)',59400],
   ['تكلفة التشغيل','الوجبات بالموقع (ثانى)',56100],['تكلفة التشغيل','الوجبات بالموقع (ثالث)',81675],
   ['تكلفة التشغيل','التأمين على الطلبة والمعلمين',42750],['تكلفة التشغيل','حافز برنامج سمات',100000],
   ['المواد والمستلزمات','مطبوعات',38250],['المواد والمستلزمات','مستهلكات ورش ومعامل',102000],
   ['المواد والمستلزمات','مستهلكات وأدوات دراسية بالفصول',13200],
   ['تكلفة الإداريين','حافز الإداريين المنتدبين',300000],['تكلفة الإداريين','حافز الأخصائيين',240000],
   ['تكلفة الإداريين','راتب مسئول سمات',502200],['تكلفة الإداريين','تدريب الإداريين',52000],
   ['تكلفة الإداريين','شركة نظافة',369600],['تكلفة الإداريين','شركة أمن',369600],
   ['إدارية وعمومية','الأدوات المكتبية والضيافة',42000],['إدارية وعمومية','صيانة واجهات وأسوار',18000],
   ['إدارية وعمومية','صيانة أجهزة ومعدات',18000],['إدارية وعمومية','صيانة ملاعب ولاند سكيب',18000],
   ['إدارية وعمومية','تكاليف متنوعة',18000],['إدارية وعمومية','مصاريف امتحان الدبلوم',20000],
   ['إدارية وعمومية','مصاريف تسويق مستمر',24000],
   ['تطوير المناهج','تطوير المناهج بالتخصص',100000],['المنصة','اشتراك وتشغيل المنصة',300000],
   ['الإدارة','أتعاب شركة الإدارة',1800000],['الإدارة','ضريبة القيمة المضافة',252000],
   ['الأصول الثابتة','أصول ثابتة وتجهيزات',0],['الاعتماد الدولى','الاعتماد الدولى والمراجعة',0]
  ];
  B.forEach(function(x){ insert_('db_lines',{school_id:badr, section:x[0], name:x[1], allocated:x[2], note:''}); });
  D.forEach(function(x){ insert_('db_lines',{school_id:dam,  section:x[0], name:x[1], allocated:x[2], note:''}); });
}

// ============ نقطة الدخول ============
function doGet(e){ return json_({ok:true, service:'EBDA Finance API', ver:1}); }

function doPost(e){
  try {
    var req = JSON.parse(e.postData.contents || '{}');
    var action = req.action;
    if (action === 'login') return json_(login_(req));
    var user = auth_(req);              // يتحقق من كل الطلبات التالية
    var res = route_(action, req, user);
    return json_(res);
  } catch (err) {
    return json_({error: String(err && err.message || err)});
  }
}

function json_(obj){
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function login_(req){
  setup();
  var u = readAll_('db_users').filter(function(x){
    return String(x.username).trim()===String(req.username).trim() &&
           String(x.pin).trim()===String(req.pin).trim() &&
           String(x.active).indexOf('نعم')>=0;
  })[0];
  if (!u) return {error:'بيانات الدخول غير صحيحة'};
  return {ok:true, user:{id:u.id, username:u.username, name:u.name, role:u.role, schools:u.schools}};
}
function auth_(req){
  var a = req.auth || {};
  var u = readAll_('db_users').filter(function(x){
    return String(x.username).trim()===String(a.username).trim() &&
           String(x.pin).trim()===String(a.pin).trim();
  })[0];
  if (!u) throw new Error('انتهت الجلسة — سجّل الدخول من جديد');
  return {id:u.id, username:u.username, name:u.name, role:u.role, schools:String(u.schools)};
}
function canSchool_(user, schoolId){
  if (user.role==='manager' || user.schools==='*') return true;
  return user.schools.split(',').map(function(s){return s.trim();}).indexOf(String(schoolId))>=0;
}
function requireManager_(user){ if (user.role!=='manager') throw new Error('صلاحية المدير مطلوبة'); }
function canApprove_(user){ return user.role==='manager' || user.role==='supervisor'; }
function canReview_(user){ return user.role==='manager' || user.role==='accountant'; }
function seesBudgets_(user){ return user.role==='manager' || user.role==='accountant' || user.role==='supervisor'; }
function expById_(id){ return readAll_('db_expenses').filter(function(x){return String(x.id)===String(id);})[0]; }
function custById_(id){ return readAll_('db_custodies').filter(function(c){return String(c.id)===String(id);})[0]; }

function route_(action, req, user){
  switch(action){
    case 'bootstrap': return bootstrap_(user);
    case 'addExpense': {
      var cust = custById_(req.expense.custody_id);
      if (!cust) throw new Error('العهدة غير موجودة');
      if (user.role!=='manager' && String(cust.user||'')!==String(user.username)) throw new Error('لا صلاحية على هذه العهدة');
      var e = req.expense; e.approval='pending'; e.settled=''; e.approved_by=''; e.review_status=''; e.review_note='';
      e.doc_url = e.doc_url||''; e.doc_name = e.doc_name||'';
      e.created_by=user.name; e.created_at=new Date();
      return {ok:true, item: insert_('db_expenses', e)};
    }
    case 'updateExpense': {
      var exU = expById_(req.id);
      if (req.patch.approval!==undefined){ if(!canApprove_(user)) throw new Error('صلاحية الاعتماد مطلوبة'); }
      else if (user.role==='manager'){ /* allow */ }
      else {
        var custU = exU ? custById_(exU.custody_id) : null;
        var ownerU = custU && String(custU.user||'')===String(user.username);
        if (!(ownerU && String(exU.approval)==='pending')) throw new Error('لا يمكن التعديل بعد اعتماد الصرف');
        var allowed=['date','line_id','amount','description'];
        for (var k in req.patch){ if (allowed.indexOf(k)<0) throw new Error('حقل غير مسموح بتعديله'); }
      }
      updateById_('db_expenses', req.id, req.patch);
      var mailA='';
      if (req.patch.approval==='approved') mailA=sendApprovalMail_(req.id);
      return {ok:true, mail:mailA};
    }
    case 'addCentral': {
      if(!(user.role==='manager'||user.role==='accountant')) throw new Error('صلاحية المحاسب مطلوبة');
      var ce = req.expense; ce.custody_id=''; ce.spend_item=''; ce.approval='approved'; ce.approved_by=user.name;
      ce.review_status='مستوفى'; ce.settled='نعم'; ce.review_note=''; ce.doc_url=ce.doc_url||''; ce.doc_name=ce.doc_name||'';
      ce.created_by=user.name; ce.created_at=new Date();
      var citem = insert_('db_expenses', ce);
      if (req.dataBase64){ try{ var curl=saveDoc_(req.filename, req.mimeType, req.dataBase64); updateById_('db_expenses', citem.id, {doc_url:curl, doc_name:req.filename}); }catch(e2){} }
      return {ok:true, item:citem};
    }
    case 'reviewExpense': {
      if(!canReview_(user)) throw new Error('صلاحية المراجعة مطلوبة');
      updateById_('db_expenses', req.id, req.patch);
      var mailR=sendReviewMail_(req.id, req.patch);
      return {ok:true, mail:mailR};
    }
    case 'uploadDoc': {
      var ex = expById_(req.id); if(!ex) throw new Error('المصروف غير موجود');
      var c2 = custById_(ex.custody_id);
      var ownerOk = c2 && String(c2.user||'')===String(user.username);
      var centralOk = String(ex.custody_id)==='' && canReview_(user);
      if (user.role!=='manager' && !ownerOk && !centralOk) throw new Error('لا صلاحية لرفع مستند لهذا المصروف');
      var url = saveDoc_(req.filename, req.mimeType, req.dataBase64);
      updateById_('db_expenses', req.id, {doc_url:url, doc_name:req.filename});
      return {ok:true, url:url};
    }
    case 'emailReport': {
      if(!seesBudgets_(user)) throw new Error('لا صلاحية');
      var recips=(req.recipients||[]).filter(function(e){return e && String(e).indexOf('@')>0;});
      if(!recips.length) throw new Error('لا يوجد مستلمون بإيميلات صحيحة');
      var opts={htmlBody:req.html||'تقرير مرفق.'};
      if(req.attachment){
        var att=req.attachment, blob=null;
        try{
          if(att.mimeType==='application/pdf' && att.html){ blob=Utilities.newBlob(att.html,'text/html',(att.filename||'report').replace(/\.pdf$/,'')+'.html').getAs('application/pdf'); blob.setName(att.filename||'report.pdf'); }
          else if(att.dataBase64){ blob=Utilities.newBlob(Utilities.base64Decode(att.dataBase64), att.mimeType||'application/octet-stream', att.filename||'report'); }
        }catch(e3){}
        if(blob) opts.attachments=[blob];
      }
      try{ MailApp.sendEmail(recips.join(','), req.subject||'تقرير — ابدأ إديو', 'تقرير مرفق من نظام ابدأ إديو.', opts); }
      catch(err){ throw new Error('تعذّر الإرسال: '+err.message); }
      return {ok:true, sent:recips.length};
    }
    case 'ping': return {ok:true, connected:true, sheet: ss_().getName(), users: readAll_('db_users').length, schools: readAll_('db_schools').length};
    case 'deleteExpense': {
      var exD = expById_(req.id);
      if (user.role!=='manager'){
        var custD = exD ? custById_(exD.custody_id) : null;
        var ownerD = custD && String(custD.user||'')===String(user.username);
        if (!(ownerD && String(exD.approval)==='pending')) throw new Error('لا يمكن الحذف بعد اعتماد الصرف');
      }
      deleteById_('db_expenses', req.id); return {ok:true};
    }
    case 'addTranche': { requireManager_(user); return {ok:true, item: insert_('db_tranches', req.tranche)}; }
    case 'addCustody': { requireManager_(user); return {ok:true, item: insert_('db_custodies', req.custody)}; }
    case 'updateCustody': { requireManager_(user); updateById_('db_custodies', req.id, req.patch); return {ok:true}; }
    case 'deleteCustody': {
      requireManager_(user);
      readAll_('db_expenses').forEach(function(x){ if(String(x.custody_id)===String(req.id)) deleteById_('db_expenses', x.id); });
      readAll_('db_tranches').forEach(function(t){ if(String(t.custody_id)===String(req.id)) deleteById_('db_tranches', t.id); });
      deleteById_('db_custodies', req.id); return {ok:true};
    }
    // إدارة (المدير فقط)
    case 'addSchool': { requireManager_(user); if(!req.school.active)req.school.active='نعم'; return {ok:true, item: insert_('db_schools', req.school)}; }
    case 'updateSchool': { requireManager_(user); updateById_('db_schools', req.id, req.patch); return {ok:true}; }
    case 'deleteSchool': { requireManager_(user); deleteById_('db_schools', req.id); return {ok:true}; }
    case 'addLine': { requireManager_(user); return {ok:true, item: insert_('db_lines', req.line)}; }
    case 'updateLine': { requireManager_(user); updateById_('db_lines', req.id, req.patch); return {ok:true}; }
    case 'deleteLine': { requireManager_(user); deleteById_('db_lines', req.id); return {ok:true}; }
    case 'addSpendItem': { requireManager_(user); return {ok:true, item: insert_('db_spend_items', req.item)}; }
    case 'deleteSpendItem': { requireManager_(user); deleteById_('db_spend_items', req.id); return {ok:true}; }
    case 'addHolder': { requireManager_(user); return {ok:true, item: insert_('db_holders', req.item)}; }
    case 'deleteHolder': { requireManager_(user); deleteById_('db_holders', req.id); return {ok:true}; }
    case 'addUser': { requireManager_(user); if(!req.user.active)req.user.active='نعم'; return {ok:true, item: insert_('db_users', req.user)}; }
    case 'updateUser': { requireManager_(user); updateById_('db_users', req.id, req.patch); return {ok:true}; }
    case 'deleteUser': { requireManager_(user); deleteById_('db_users', req.id); return {ok:true}; }
    default: throw new Error('إجراء غير معروف: ' + action);
  }
}

function bootstrap_(user){
  var isMgr = user.role==='manager';
  var schools = readAll_('db_schools').filter(function(s){ return String(s.active).indexOf('نعم')>=0 && canSchool_(user, s.id); });
  var ids = schools.map(function(s){ return String(s.id); });
  var custodies = readAll_('db_custodies').filter(function(c){
    if (user.role==='custody') return String(c.user||'')===String(user.username);
    return ids.indexOf(String(c.school_id))>=0 || c.school_id==='';
  });
  var cids = custodies.map(function(c){ return String(c.id); });
  var lines;
  if (seesBudgets_(user)) lines = readAll_('db_lines').filter(function(l){ return ids.indexOf(String(l.school_id))>=0; });
  else if (user.role==='custody') lines = readAll_('db_lines').filter(function(l){ return ids.indexOf(String(l.school_id))>=0; }).map(function(l){ return {id:l.id, school_id:l.school_id, section:l.section, name:l.name}; });
  else lines = [];
  var tranches = readAll_('db_tranches').filter(function(t){ return cids.indexOf(String(t.custody_id))>=0; });
  var expenses = readAll_('db_expenses').filter(function(x){
    if (user.role==='custody') return cids.indexOf(String(x.custody_id))>=0;
    return cids.indexOf(String(x.custody_id))>=0 || ids.indexOf(String(x.school_id))>=0;
  });
  var out = {
    ok:true, me:user,
    schools: strip_(schools), lines: strip_(lines), custodies: strip_(custodies),
    tranches: strip_(tranches), expenses: strip_(expenses),
    spendItems: strip_(readAll_('db_spend_items')),
    holders: strip_(readAll_('db_holders')),
    approvers: strip_(readAll_('db_approvers')),
    emails: strip_(readAll_('db_emails'))
  };
  if (isMgr) out.users = strip_(readAll_('db_users'));
  return out;
}

// ============ Drive (المستندات) + Mail (الإشعارات) ============
function getFolder_(){
  var it = DriveApp.getFoldersByName('EBDA_Documents');
  return it.hasNext() ? it.next() : DriveApp.createFolder('EBDA_Documents');
}
function saveDoc_(name, mime, b64){
  var bytes = Utilities.base64Decode(b64);
  var blob = Utilities.newBlob(bytes, mime || 'application/octet-stream', name || 'document');
  var file = getFolder_().createFile(blob);
  try { file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch(e){}
  return file.getUrl();
}
function dedupe_(a){ var s={},o=[]; a.forEach(function(x){ if(x && !s[x]){s[x]=1;o.push(x);} }); return o; }
function ownerEmail_(cust){ if(!cust) return null; var u=readAll_('db_users').filter(function(u){return String(u.username)===String(cust.user);})[0]; return u&&u.email?u.email:null; }
function roleEmails_(role){ return readAll_('db_users').filter(function(u){return u.role===role && String(u.active).indexOf('نعم')>=0;}).map(function(u){return u.email;}).filter(function(e){return e && String(e).indexOf('@')>0;}); }
function sendApprovalMail_(expId){
  try{
    var ex=expById_(expId); if(!ex) return '';
    var cust=custById_(ex.custody_id);
    var recips = dedupe_([ownerEmail_(cust)].concat(roleEmails_('accountant')).concat(roleEmails_('manager')).filter(Boolean));
    if(!recips.length) return 'لم يُرسل إيميل (لا إيميلات مسجّلة)';
    var body='<div dir="rtl" style="font-family:Arial">تمت الموافقة على مصروف:<br><b>'+ex.amount+' ج.م</b> — '+ex.description+
      '<br>العهدة: '+(cust?cust.label:'')+' | التاريخ: '+ex.date+'<br>برجاء رفع/مراجعة المستندات.</div>';
    MailApp.sendEmail(recips.join(','), 'اعتماد مصروف — ابدأ إديو', '', {htmlBody:body});
    return 'أُرسل إشعار الموافقة إلى '+recips.length+' مستلم';
  }catch(e){ return 'فشل إرسال الإيميل: '+(e && e.message||e); }
}
function sendReviewMail_(expId, patch){
  try{
    var ex=expById_(expId); if(!ex) return '';
    var cust=custById_(ex.custody_id);
    var recips = dedupe_([ownerEmail_(cust)].concat(roleEmails_('supervisor')).concat(roleEmails_('manager')).filter(Boolean));
    if(!recips.length) return 'لم يُرسل إيميل (لا إيميلات مسجّلة)';
    var st = (patch&&patch.review_status)|| ex.review_status || '';
    var subj = st==='مستوفى' ? 'تسوية معتمدة — ابدأ إديو' : 'ملاحظات على مستند — ابدأ إديو';
    var body='<div dir="rtl" style="font-family:Arial">نتيجة مراجعة المستندات لمصروف <b>'+ex.amount+' ج.م</b> — '+ex.description+
      '<br>الحالة: <b>'+st+'</b>'+((patch&&patch.review_note)?('<br>ملاحظة: '+patch.review_note):'')+'</div>';
    MailApp.sendEmail(recips.join(','), subj, '', {htmlBody:body});
    return (st==='مستوفى'?'أُرسل إشعار التسوية إلى ':'أُرسلت الملاحظة إلى ')+recips.length+' مستلم';
  }catch(e){ return 'فشل إرسال الإيميل: '+(e && e.message||e); }
}
function strip_(rows){ return rows.map(function(r){ var o={}; for (var k in r) if (k!=='_row') o[k]=r[k]; return o; }); }
