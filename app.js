const { useState, useEffect, useMemo, useRef } = React;
const CFG = window.EBDA_CONFIG || {};
const fmt = (n) => (Number(n) || 0).toLocaleString("en-US", { maximumFractionDigits: 0 });
const uid = () => "id" + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36);
const today = () => new Date().toISOString().slice(0, 10);
const yes = (v) => String(v).indexOf("نعم") >= 0 || v === true || v === "true";
function toCSV(header, rows) { const esc = v => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`; return "\uFEFF" + [header, ...rows].map(r => r.map(esc).join(",")).join("\n"); }
function download(name, content) { const b = new Blob([content], { type: "text/csv;charset=utf-8" }); const u = URL.createObjectURL(b); const a = document.createElement("a"); a.href = u; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(u), 1500); }
function daysSince(d) { if (!d) return 0; return Math.max(0, Math.floor((Date.now() - new Date(d).getTime()) / 86400000)); }
function b64utf8(str) { return btoa(unescape(encodeURIComponent(str))); }
function numAr(v) { if (v == null) return NaN; if (typeof v === "number") return v; const s = String(v).replace(/[,\u066c\s]/g, ""); const n = parseFloat(s); return isNaN(n) ? NaN : n; }
function parseBudgetRows(rows) {
  const norm = s => String(s == null ? "" : s).trim();
  let hr = -1, nameCol = -1;
  for (let i = 0; i < Math.min(rows.length, 40); i++) { for (let j = 0; j < (rows[i] || []).length; j++) { if (norm(rows[i][j]) === "البند") { hr = i; nameCol = j; break; } } if (hr >= 0) break; }
  if (hr < 0) { for (let i = 0; i < Math.min(rows.length, 10); i++) { const r = (rows[i] || []).map(norm); let bi = r.indexOf("البند"); if (bi < 0) bi = r.indexOf("الاسم"); if (bi >= 0) { hr = i; nameCol = bi; break; } } }
  if (hr < 0) { hr = 0; nameCol = 0; }
  const findCol = (labels) => { for (let i = Math.max(0, hr - 1); i < Math.min(rows.length, hr + 4); i++) { const r = rows[i] || []; for (let j = 0; j < r.length; j++) { const c = norm(r[j]); for (const lb of labels) if (c.indexOf(lb) >= 0) return j; } } return -1; };
  let allocCol = findCol(["الأجمالى", "الإجمالى", "الاجمالى", "الموازنة", "القيمة"]);
  const costCol = findCol(["التكلفة"]), countCol = findCol(["العدد"]), durCol = findCol(["المدة"]);
  if (allocCol < 0) allocCol = nameCol + (costCol >= 0 ? 4 : 1);
  let section = "عام"; const lines = [];
  for (let i = hr + 1; i < rows.length; i++) {
    const r = rows[i] || []; const name = norm(r[nameCol]); if (!name) continue;
    if (/^إجمال/.test(name)) continue;
    let alloc = numAr(r[allocCol]);
    const cost = costCol >= 0 ? numAr(r[costCol]) : NaN, cnt = countCol >= 0 ? numAr(r[countCol]) : NaN, dur = durCol >= 0 ? numAr(r[durCol]) : NaN;
    if (!isFinite(alloc) && isFinite(cost) && isFinite(cnt) && isFinite(dur)) alloc = cost * cnt * dur;
    const isItem = isFinite(alloc) && (costCol < 0 || isFinite(cost));
    if (isItem) lines.push({ section, name, allocated: Math.round(alloc) });
    else section = name;
  }
  return { lines, total: lines.reduce((a, l) => a + l.allocated, 0) };
}
function parseCSV(text) {
  const out = []; let row = [], cur = "", q = false;
  for (let i = 0; i < text.length; i++) { const ch = text[i];
    if (q) { if (ch === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += ch; }
    else { if (ch === '"') q = true; else if (ch === ",") { row.push(cur); cur = ""; } else if (ch === "\n" || ch === "\r") { if (ch === "\r" && text[i + 1] === "\n") i++; row.push(cur); out.push(row); row = []; cur = ""; } else cur += ch; }
  }
  if (cur !== "" || row.length) { row.push(cur); out.push(row); }
  return out;
}
function loadXLSX() { return new Promise((res, rej) => { if (window.XLSX) return res(window.XLSX); const s = document.createElement("script"); s.src = "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"; s.onload = () => res(window.XLSX); s.onerror = () => rej(new Error("تعذّر تحميل مكتبة Excel — استخدم ملف CSV بدلاً منه")); document.head.appendChild(s); }); }
async function readBudgetFile(file) {
  if (/\.csv$/i.test(file.name)) { const text = await file.text(); return parseBudgetRows(parseCSV(text)); }
  const XLSX = await loadXLSX();
  const buf = await file.arrayBuffer();
  const wb = XLSX.read(buf, { type: "array" });
  const ws = wb.Sheets["الموازنة المقترحة"] || wb.Sheets[wb.SheetNames[0]];
  return parseBudgetRows(XLSX.utils.sheet_to_json(ws, { header: 1 }));
}
function reportHTML(title, header, rows, meta) {
  const th = header.map(h => `<th style="background:#123C5A;color:#fff;padding:7px 9px;border:1px solid #bbb;text-align:right">${h}</th>`).join("");
  const tb = rows.map(r => `<tr>${r.map(c => `<td style="padding:6px 9px;border:1px solid #ccc;text-align:right">${c == null ? "" : String(c)}</td>`).join("")}</tr>`).join("");
  return `<html dir="rtl"><head><meta charset="utf-8"><title>${title}</title></head><body style="font-family:Arial,sans-serif;color:#16232F">
  <h2 style="color:#123C5A">${title}</h2>${meta ? `<p style="color:#555">${meta}</p>` : ""}
  <table style="border-collapse:collapse;width:100%;font-size:13px"><thead><tr>${th}</tr></thead><tbody>${tb}</tbody></table>
  <p style="color:#888;font-size:11px;margin-top:14px">ابدأ إديو — نظام متابعة الموازنات والعهد</p></body></html>`;
}
function dlBlob(name, mime, content) { const b = new Blob([content], { type: mime }); const u = URL.createObjectURL(b); const a = document.createElement("a"); a.href = u; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(u), 1500); }
function exportAs(format, title, header, rows, meta) {
  if (format === "csv") return dlBlob(title + ".csv", "text/csv;charset=utf-8", toCSV(header, rows));
  if (format === "excel") return dlBlob(title + ".xls", "application/vnd.ms-excel", "\uFEFF" + reportHTML(title, header, rows, meta));
  if (format === "word") return dlBlob(title + ".doc", "application/msword", "\uFEFF" + reportHTML(title, header, rows, meta));
  if (format === "pdf") { const w = window.open("", "_blank"); if (!w) { alert("اسمح بالنوافذ المنبثقة للطباعة كـ PDF"); return; } w.document.write(reportHTML(title, header, rows, meta) + "<script>setTimeout(function(){window.print();},350);<\/script>"); w.document.close(); }
}

/* ============================================================
   طبقة البيانات: عن بُعد (Apps Script) أو تجريبى محلى
   ============================================================ */
const SUPA = !!(CFG.SUPABASE_URL && CFG.SUPABASE_ANON_KEY);
const GAS = !!(CFG.API_URL && CFG.API_URL.trim());
const REMOTE = SUPA || GAS;

async function supabaseCall(action, payload, session) {
  const req = Object.assign({ action }, payload, session ? { auth: { username: session.username, pin: session.pin } } : {});
  const res = await fetch(CFG.SUPABASE_URL.replace(/\/+$/, "") + "/rest/v1/rpc/api", {
    method: "POST",
    headers: { "Content-Type": "application/json", "apikey": CFG.SUPABASE_ANON_KEY, "Authorization": "Bearer " + CFG.SUPABASE_ANON_KEY },
    body: JSON.stringify({ req })
  });
  let data; try { data = await res.json(); } catch { throw new Error("تعذّر الاتصال بـ Supabase (تحقق من الرابط والمفتاح)"); }
  if (data && data.error) throw new Error(data.error);
  return data;
}

async function remoteCall(action, payload, session) {
  const body = JSON.stringify(Object.assign({ action }, payload,
    session ? { auth: { username: session.username, pin: session.pin } } : {}));
  const res = await fetch(CFG.API_URL, { method: "POST", body });
  const data = await res.json();
  if (data && data.error) throw new Error(data.error);
  return data;
}

/* ---- باك-إند تجريبى محلى (localStorage) ---- */
const LS_KEY = "ebda_db_v1";
function seedDB() {
  const badr = uid(), dam = uid();
  const mkLines = (sid, arr) => arr.map(([section, name, allocated]) => ({ id: uid(), school_id: sid, section, name, allocated, note: "" }));
  const B = [["تكلفة التدريس","حافز المدير الأكاديمى",120000],["تكلفة التدريس","حافز المعلمين المنتدبين",84000],["تكلفة التدريس","راتب معلمى التخصص",1440000],["تكلفة التدريس","راتب معلمى المواد الثقافية",1656000],["تكلفة التدريس","تدريب المعلمين",150000],["تكلفة التدريس","انتقالات وبدلات انتقال",28800],["تكلفة التشغيل","الزى المدرسى",350000],["تكلفة التشغيل","الانتقالات إلى الموقع (أول)",27000],["تكلفة التشغيل","الوجبات بالموقع (أول)",17820],["تكلفة التشغيل","التأمين على الطلبة والمعلمين",43050],["تكلفة التشغيل","حافز برنامج سمات",100000],["المواد والمستلزمات","مطبوعات",37950],["المواد والمستلزمات","مستهلكات معامل",101200],["تكلفة الإداريين","راتب الإداريين",630000],["تكلفة الإداريين","شركة نظافة",369600],["تكلفة الإداريين","شركة أمن",369600],["إدارية وعمومية","الأدوات المكتبية والضيافة",42000],["إدارية وعمومية","مصاريف امتحان الدبلوم",30000],["الإدارة","أتعاب شركة الإدارة",1800000],["الإدارة","ضريبة القيمة المضافة",252000]];
  const D = [["تكلفة التدريس","حافز المدير الأكاديمى",105600],["تكلفة التدريس","راتب معلمى التخصص",1080000],["تكلفة التدريس","راتب معلمى المواد الثقافية",1242000],["تكلفة التدريس","تدريب المعلمين",114000],["تكلفة التشغيل","معدات الأمن والسلامة",125000],["تكلفة التشغيل","الزى المدرسى",350000],["تكلفة التشغيل","التأمين على الطلبة والمعلمين",42750],["تكلفة التشغيل","حافز برنامج سمات",100000],["المواد والمستلزمات","مطبوعات",38250],["المواد والمستلزمات","مستهلكات ورش ومعامل",102000],["تكلفة الإداريين","راتب مسئول سمات",502200],["تكلفة الإداريين","شركة نظافة",369600],["تكلفة الإداريين","شركة أمن",369600],["إدارية وعمومية","الأدوات المكتبية والضيافة",42000],["الإدارة","أتعاب شركة الإدارة",1800000],["الإدارة","ضريبة القيمة المضافة",252000]];
  const c1 = uid();
  const comp = uid(), trg = uid(), trv = uid();
  const badrLines = mkLines(badr, B), damLines = mkLines(dam, D);
  const COMP = [["مصاريف إدارية", "أدوات مكتبية ومستهلكات", 0], ["مصاريف إدارية", "ضيافة وبوفيه", 0], ["مصاريف إدارية", "صيانة وأجهزة", 0], ["مصاريف إدارية", "انتقالات ونثريات", 0], ["مصاريف إدارية", "تسويق", 0]];
  const TR = [["تكلفة التدريب", "أجور المدربين", 0], ["تكلفة التدريب", "قاعات وتجهيزات", 0], ["تكلفة التدريب", "مواد ومستلزمات تدريبية", 0], ["تكلفة التدريب", "ضيافة وبوفيه", 0], ["تكلفة التدريب", "انتقالات", 0], ["تكلفة التدريب", "شهادات واعتماد", 0]];
  const compLines = mkLines(comp, COMP), trgLines = mkLines(trg, TR), trvLines = mkLines(trv, TR);
  const zLine = badrLines.find(l => l.name === "الزى المدرسى");
  const cComp = uid(), cTrg = uid();
  const db = {
    db_users: [{ id: uid(), username: "admin", pin: "1234", name: "المدير العام", role: "manager", schools: "*", active: "نعم", email: "" },
               { id: uid(), username: "custody1", pin: "1111", name: "أحمد (مسئول عهدة بدر)", role: "custody", schools: badr, active: "نعم", email: "custody@ebda.com.eg" },
               { id: uid(), username: "acc1", pin: "2222", name: "سارة (محاسب المتابعة)", role: "accountant", schools: badr, active: "نعم", email: "acc@ebda.com.eg" },
               { id: uid(), username: "sup1", pin: "3333", name: "خالد (مدير مباشر)", role: "supervisor", schools: badr, active: "نعم", email: "sup@ebda.com.eg" }],
    db_schools: [{ id: badr, name: "مدرسة ابدأ للعلوم التقنية — بدر", type: "مدرسة", period: "2026/2027", students: 253, active: "نعم", category: "school" },
                 { id: dam, name: "مدرسة ابدأ للعلوم التقنية — دمياط", type: "مدرسة", period: "2026/2027", students: 255, active: "نعم", category: "school" },
                 { id: comp, name: "الشركة — العهدة الداخلية", type: "الشركة", period: "2026/2027", students: 0, active: "نعم", category: "company" },
                 { id: trg, name: "التدريب العام", type: "تدريب", period: "2026/2027", students: 0, active: "نعم", category: "training_general" },
                 { id: trv, name: "التدريب المهنى", type: "تدريب", period: "2026/2027", students: 0, active: "نعم", category: "training_vocational" }],
    db_lines: [...badrLines, ...damLines, ...compLines, ...trgLines, ...trvLines],
    db_custodies: [{ id: c1, label: "عهدة مدير بدر", holder: "أحمد سمير", school_id: badr, note: "عهدة الفصل الأول", user: "custody1" },
                   { id: cComp, label: "عهدة الشركة الداخلية", holder: "منى فؤاد", school_id: comp, note: "نثريات المقر", user: "" },
                   { id: cTrg, label: "عهدة تدريب عام — دورة أغسطس", holder: "منى فؤاد", school_id: trg, note: "", user: "" }],
    db_tranches: [{ id: uid(), custody_id: c1, date: "2026-08-05", amount: 200000, note: "الدفعة الأولى" },
                  { id: uid(), custody_id: cComp, date: "2026-08-03", amount: 50000, note: "عهدة داخلية" },
                  { id: uid(), custody_id: cTrg, date: "2026-08-10", amount: 30000, note: "عهدة الدورة" }],
    db_expenses: [{ id: uid(), date: "2026-08-12", school_id: badr, custody_id: c1, line_id: zLine ? zLine.id : "", spend_item: "", description: "دفعة أولى زى مدرسى", amount: 120000, approval: "approved", approved_by: "خالد", doc_url: "", doc_name: "", review_status: "مستوفى", review_note: "", settled: "نعم", ref: "فاتورة 4402", note: "", created_by: "أحمد", created_at: "" }],
    db_spend_items: ["أدوات مكتبية وضيافة","مستهلكات للورش","انتقالات","صيانة المنشأة والورش","مصاريف نثرية","بوفيه"].map(n => ({ id: uid(), name: n })),
    db_holders: [{ id: uid(), name: "أحمد سمير", title: "مدير مدرسة بدر" }, { id: uid(), name: "منى فؤاد", title: "منسق" }],
    db_approvers: [{ id: uid(), name: "المدير المالى", email: "finance@ebda.com.eg" }, { id: uid(), name: "رئيس العمليات", email: "ops@ebda.com.eg" }],
    db_emails: [{ id: uid(), email: "ebda.edu@ebda.com.eg", label: "الإدارة" }],
  };
  localStorage.setItem(LS_KEY, JSON.stringify(db));
  return db;
}
function getDB() { try { return JSON.parse(localStorage.getItem(LS_KEY)) || seedDB(); } catch { return seedDB(); } }
function saveDB(db) { localStorage.setItem(LS_KEY, JSON.stringify(db)); }

function localCall(action, payload, session) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      try { resolve(localRoute(action, payload, session)); }
      catch (e) { reject(e); }
    }, 120);
  });
}
function canSchool(user, sid) { return user.role === "manager" || user.schools === "*" || String(user.schools).split(",").map(s => s.trim()).indexOf(String(sid)) >= 0; }
function reqMgr(user) { if (user.role !== "manager") throw new Error("صلاحية المدير مطلوبة"); }
function localRoute(action, p, session) {
  const db = getDB();
  const ins = (t, o) => { o.id = o.id || uid(); db[t].push(o); saveDB(db); return o; };
  const upd = (t, id, patch) => { db[t] = db[t].map(x => String(x.id) === String(id) ? Object.assign({}, x, patch) : x); saveDB(db); };
  const del = (t, id) => { db[t] = db[t].filter(x => String(x.id) !== String(id)); saveDB(db); };
  if (action === "login") {
    const u = db.db_users.find(x => String(x.username).trim() === String(p.username).trim() && String(x.pin) === String(p.pin) && yes(x.active));
    if (!u) return { error: "بيانات الدخول غير صحيحة" };
    return { ok: true, user: { id: u.id, username: u.username, name: u.name, role: u.role, schools: String(u.schools) } };
  }
  const user = session && session.user;
  if (!user) throw new Error("انتهت الجلسة");
  switch (action) {
    case "bootstrap": {
      const isMgr = user.role === "manager";
      const seesBudgets = isMgr || user.role === "accountant" || user.role === "supervisor";
      const schools = db.db_schools.filter(s => yes(s.active) && canSchool(user, s.id));
      const ids = schools.map(s => String(s.id));
      const custodies = db.db_custodies.filter(c => user.role === "custody" ? String(c.user || "") === String(user.username) : (ids.indexOf(String(c.school_id)) >= 0 || c.school_id === ""));
      const cids = custodies.map(c => String(c.id));
      const lines = seesBudgets ? db.db_lines.filter(l => ids.indexOf(String(l.school_id)) >= 0)
        : (user.role === "custody" ? db.db_lines.filter(l => ids.indexOf(String(l.school_id)) >= 0).map(l => ({ id: l.id, school_id: l.school_id, section: l.section, name: l.name })) : []);
      const tranches = db.db_tranches.filter(t => cids.indexOf(String(t.custody_id)) >= 0);
      const expenses = db.db_expenses.filter(x => user.role === "custody" ? cids.indexOf(String(x.custody_id)) >= 0 : (cids.indexOf(String(x.custody_id)) >= 0 || ids.indexOf(String(x.school_id)) >= 0));
      const out = { ok: true, me: user, schools, lines, custodies, tranches, expenses, spendItems: db.db_spend_items, holders: db.db_holders, approvers: db.db_approvers, emails: db.db_emails };
      if (isMgr) out.users = db.db_users;
      return out;
    }
    case "addExpense": {
      const cust = db.db_custodies.find(c => String(c.id) === String(p.expense.custody_id));
      if (!cust) throw new Error("العهدة غير موجودة");
      if (user.role !== "manager" && String(cust.user || "") !== String(user.username)) throw new Error("لا صلاحية على هذه العهدة");
      const e = Object.assign({ doc_url: "", doc_name: "", review_status: "", review_note: "" }, p.expense, { approval: "pending", settled: "", approved_by: "", created_by: user.name, created_at: new Date().toISOString() }); return { ok: true, item: ins("db_expenses", e) };
    }
    case "addCentral": {
      if (!(user.role === "manager" || user.role === "accountant")) throw new Error("صلاحية المحاسب مطلوبة");
      const ce = Object.assign({ custody_id: "", spend_item: "", doc_url: p.dataUrl || "", doc_name: p.filename || "" }, p.expense, { approval: "approved", approved_by: user.name, review_status: "مستوفى", settled: "نعم", review_note: "", created_by: user.name, created_at: new Date().toISOString() });
      return { ok: true, item: ins("db_expenses", ce) };
    }
    case "updateExpense": {
      const exU = db.db_expenses.find(x => String(x.id) === String(p.id));
      if (p.patch.approval !== undefined) { if (!(user.role === "manager" || user.role === "supervisor")) throw new Error("صلاحية الاعتماد مطلوبة"); }
      else if (user.role === "manager") { /* allow */ }
      else {
        const custU = exU && db.db_custodies.find(c => String(c.id) === String(exU.custody_id));
        const ownerU = custU && String(custU.user || "") === String(user.username);
        if (!(ownerU && String(exU.approval) === "pending")) throw new Error("لا يمكن التعديل بعد اعتماد الصرف");
        const allowed = ["date", "line_id", "amount", "description"];
        for (const k in p.patch) if (allowed.indexOf(k) < 0) throw new Error("حقل غير مسموح بتعديله");
      }
      upd("db_expenses", p.id, p.patch); return { ok: true };
    }
    case "reviewExpense": { if (!(user.role === "manager" || user.role === "accountant")) throw new Error("صلاحية المراجعة مطلوبة"); upd("db_expenses", p.id, p.patch); return { ok: true }; }
    case "deleteExpense": {
      const exD = db.db_expenses.find(x => String(x.id) === String(p.id));
      if (user.role !== "manager") {
        const custD = exD && db.db_custodies.find(c => String(c.id) === String(exD.custody_id));
        const ownerD = custD && String(custD.user || "") === String(user.username);
        if (!(ownerD && String(exD.approval) === "pending")) throw new Error("لا يمكن الحذف بعد اعتماد الصرف");
      }
      del("db_expenses", p.id); return { ok: true };
    }
    case "uploadDoc": {
      const ex = db.db_expenses.find(x => String(x.id) === String(p.id)); if (!ex) throw new Error("المصروف غير موجود");
      const c3 = db.db_custodies.find(c => String(c.id) === String(ex.custody_id));
      const ownerOk = c3 && String(c3.user || "") === String(user.username);
      const centralOk = String(ex.custody_id) === "" && (user.role === "manager" || user.role === "accountant");
      if (user.role !== "manager" && !ownerOk && !centralOk) throw new Error("لا صلاحية لرفع مستند");
      upd("db_expenses", p.id, { doc_url: p.dataUrl || "", doc_name: p.filename }); return { ok: true, url: p.dataUrl };
    }
    case "emailReport": { return { ok: true, demo: true }; }
    case "ping": { return { ok: true, demo: true, users: getDB().db_users.length, schools: getDB().db_schools.length }; }
    case "addTranche": { reqMgr(user); return { ok: true, item: ins("db_tranches", p.tranche) }; }
    case "addCustody": { reqMgr(user); return { ok: true, item: ins("db_custodies", p.custody) }; }
    case "updateCustody": { reqMgr(user); upd("db_custodies", p.id, p.patch); return { ok: true }; }
    case "deleteCustody": {
      reqMgr(user);
      db.db_expenses = db.db_expenses.filter(x => String(x.custody_id) !== String(p.id));
      db.db_tranches = db.db_tranches.filter(t => String(t.custody_id) !== String(p.id));
      db.db_custodies = db.db_custodies.filter(c => String(c.id) !== String(p.id));
      saveDB(db); return { ok: true };
    }
    case "importBudget": {
      reqMgr(user);
      let sid = p.school_id;
      if (p.newSchool) { const s = ins("db_schools", Object.assign({ active: "نعم", category: "school" }, p.newSchool)); sid = s.id; }
      db.db_lines = db.db_lines.filter(l => String(l.school_id) !== String(sid));
      (p.lines || []).forEach(x => db.db_lines.push({ id: uid(), school_id: sid, section: x.section || "", name: x.name || "", allocated: Number(x.allocated) || 0, note: "" }));
      saveDB(db); return { ok: true, school_id: sid, count: (p.lines || []).length };
    }
    case "addSchool": { reqMgr(user); return { ok: true, item: ins("db_schools", Object.assign({ active: "نعم" }, p.school)) }; }
    case "updateSchool": { reqMgr(user); upd("db_schools", p.id, p.patch); return { ok: true }; }
    case "deleteSchool": { reqMgr(user); del("db_schools", p.id); return { ok: true }; }
    case "addLine": { reqMgr(user); return { ok: true, item: ins("db_lines", p.line) }; }
    case "updateLine": { reqMgr(user); upd("db_lines", p.id, p.patch); return { ok: true }; }
    case "deleteLine": { reqMgr(user); del("db_lines", p.id); return { ok: true }; }
    case "addSpendItem": { reqMgr(user); return { ok: true, item: ins("db_spend_items", p.item) }; }
    case "deleteSpendItem": { reqMgr(user); del("db_spend_items", p.id); return { ok: true }; }
    case "addHolder": { reqMgr(user); return { ok: true, item: ins("db_holders", p.item) }; }
    case "deleteHolder": { reqMgr(user); del("db_holders", p.id); return { ok: true }; }
    case "addUser": { reqMgr(user); return { ok: true, item: ins("db_users", Object.assign({ active: "نعم" }, p.user)) }; }
    case "updateUser": { reqMgr(user); upd("db_users", p.id, p.patch); return { ok: true }; }
    case "deleteUser": { reqMgr(user); del("db_users", p.id); return { ok: true }; }
    default: throw new Error("إجراء غير معروف: " + action);
  }
}
function call(action, payload, session) { return SUPA ? supabaseCall(action, payload, session) : (GAS ? remoteCall(action, payload, session) : localCall(action, payload, session)); }

/* ============================================================ التطبيق ============================================================ */
function applyLocal(data, action, payload, result) {
  if (!data) return null;
  const clone = { ...data, expenses: [...(data.expenses || [])], tranches: [...(data.tranches || [])], custodies: [...(data.custodies || [])] };
  const item = result && result.item;
  switch (action) {
    case "addExpense": case "addCentral": if (item) { clone.expenses.push(item); return clone; } return null;
    case "addTranche": if (item) { clone.tranches.push(item); return clone; } return null;
    case "updateExpense": case "reviewExpense": clone.expenses = clone.expenses.map(e => String(e.id) === String(payload.id) ? { ...e, ...payload.patch } : e); return clone;
    case "deleteExpense": clone.expenses = clone.expenses.filter(e => String(e.id) !== String(payload.id)); return clone;
    case "uploadDoc": { const url = (result && result.url) || payload.dataUrl || ""; clone.expenses = clone.expenses.map(e => String(e.id) === String(payload.id) ? { ...e, doc_url: url, doc_name: payload.filename } : e); return clone; }
    case "deleteCustody": clone.custodies = clone.custodies.filter(c => String(c.id) !== String(payload.id)); clone.expenses = clone.expenses.filter(e => String(e.custody_id) !== String(payload.id)); clone.tranches = clone.tranches.filter(t => String(t.custody_id) !== String(payload.id)); return clone;
    default: return null; // مدارس/بنود/مستخدمين/استيراد → إعادة تحميل كاملة (نادرة)
  }
}
function App() {
  const [session, setSession] = useState(() => { try { return JSON.parse(localStorage.getItem("ebda_session")); } catch { return null; } });
  const [data, setData] = useState(null);
  const [tab, setTab] = useState("dashboard");
  const [toast, setToast] = useState(null);
  const [modal, setModal] = useState(null);
  const [loading, setLoading] = useState(false);

  const showToast = (msg, kind = "ok") => { setToast({ msg, kind }); setTimeout(() => setToast(null), 2800); };
  const boot = async (sess) => {
    setLoading(true);
    try { const d = await call("bootstrap", {}, sess); setData(d); }
    catch (e) { showToast(e.message, "err"); if (String(e.message).indexOf("الجلسة") >= 0) logout(); }
    setLoading(false);
  };
  useEffect(() => { if (session) boot(session); }, []);
  const login = async (username, pin) => {
    setLoading(true);
    try {
      const r = await call("login", { username, pin });
      if (r.error) { showToast(r.error, "err"); setLoading(false); return; }
      const sess = { username, pin, user: r.user };
      localStorage.setItem("ebda_session", JSON.stringify(sess));
      setSession(sess); await boot(sess);
    } catch (e) { showToast(e.message, "err"); }
    setLoading(false);
  };
  const logout = () => { localStorage.removeItem("ebda_session"); setSession(null); setData(null); setTab("dashboard"); };

  const act = async (action, payload) => {
    try {
      const r = await call(action, payload, session);
      const patched = applyLocal(data, action, payload, r);
      if (patched) setData(patched); else await boot(session);
      return r;
    }
    catch (e) { showToast(e.message, "err"); throw e; }
  };
  const probe = (action, payload) => call(action, payload, session);

  if (!session) return <><Login onLogin={login} loading={loading} /><Toast toast={toast} /></>;
  if (!data) return <div className="loading"><div className="spinner" /><p>جارٍ تحميل البيانات…</p></div>;

  const role = data.me.role;
  const isMgr = role === "manager", isAcc = role === "accountant", isSup = role === "supervisor", isCust = role === "custody";
  const seesBudgets = isMgr || isAcc || isSup;
  const canApprove = isMgr || isSup;
  const canReview = isMgr || isAcc;
  const canRecord = isMgr || isCust;
  const seesReports = isMgr || isAcc || isSup;
  const roleLabel = { manager: "مدير البرنامج", accountant: "محاسب المتابعة", supervisor: "مدير مباشر", custody: "مسئول عهدة" }[role] || role;
  const tabs = [["dashboard", "لوحة المتابعة"]];
  if (seesBudgets) tabs.push(["budgets", "الموازنات"]);
  tabs.push(["custodies", "العهد"], ["approvals", "المصروفات"]);
  if (seesReports) tabs.push(["reports", "التقارير"]);
  if (isMgr) tabs.push(["admin", "الإدارة"]);

  return (
    <div>
      <div className="topbar">
        <div className="brand"><Logo /><div><div className="brand-title">ابدأ إديو</div><div className="brand-sub">متابعة الموازنات والعهد</div></div></div>
        <div className="user-box">
          {!REMOTE && <span className="chip amber" title="غير متصل بجوجل شيت — البيانات على المتصفح فقط">وضع تجريبى · غير متصل</span>}
          {REMOTE && <span className="chip green" title="متصل بجوجل شيت">متصل</span>}
          <span className="user-chip">{data.me.name}{String(data.me.name).trim() !== roleLabel && <span className={"role-tag " + (isMgr ? "" : "acc")}>{roleLabel}</span>}</span>
          <button className="btn ghost sm" onClick={logout}>خروج</button>
        </div>
      </div>
      <div className="tabs">{tabs.map(([k, l]) => <button key={k} className={"tab " + (tab === k ? "active" : "")} onClick={() => setTab(k)}>{l}</button>)}</div>
      {isCust && <PettyBar data={data} />}
      <div className="content">
        {tab === "dashboard" && <Dashboard data={data} onGo={setTab} />}
        {tab === "budgets" && seesBudgets && <Budgets data={data} canCentral={isMgr || isAcc} setModal={setModal} />}
        {tab === "custodies" && <Custodies data={data} isMgr={isMgr} canRecord={canRecord} act={act} showToast={showToast} setModal={setModal} />}
        {tab === "approvals" && <Approvals data={data} isMgr={isMgr} canApprove={canApprove} canReview={canReview} act={act} setModal={setModal} showToast={showToast} />}
        {tab === "reports" && seesReports && <Reports data={data} act={act} showToast={showToast} />}
        {tab === "admin" && isMgr && <Admin data={data} act={act} probe={probe} showToast={showToast} setModal={setModal} />}
      </div>
      {modal && <Modals modal={modal} data={data} act={act} close={() => setModal(null)} showToast={showToast} />}
      <Toast toast={toast} />
    </div>
  );
}

/* ---- حسابات مشتركة ---- */
function useCalc(data) {
  return useMemo(() => {
    const spentByLine = {}, spentBySchool = {}, spentByCustody = {}, pendingByCustody = {};
    (data.expenses || []).forEach(e => {
      const amt = Number(e.amount || 0);
      const active = e.approval !== "rejected";
      const settled = yes(e.settled);
      // نقدية العهدة: يُخصم فور الصرف (غير المرفوض)
      if (active && e.custody_id) spentByCustody[e.custody_id] = (spentByCustody[e.custody_id] || 0) + amt;
      if (e.approval === "pending" && e.custody_id) pendingByCustody[e.custody_id] = (pendingByCustody[e.custody_id] || 0) + amt;
      // الموازنة: تُخصم فقط بعد التسوية (موافقة المحاسب) أو الشراء المركزى
      if (settled) {
        if (e.line_id) spentByLine[e.line_id] = (spentByLine[e.line_id] || 0) + amt;
        spentBySchool[e.school_id] = (spentBySchool[e.school_id] || 0) + amt;
      }
    });
    return { spentByLine, spentBySchool, spentByCustody, pendingByCustody };
  }, [data]);
}
const custIssued = (data, c) => (data.tranches || []).filter(t => String(t.custody_id) === String(c.id)).reduce((s, t) => s + Number(t.amount || 0), 0);
const CAT_LABEL = { school: "مدرسة", company: "الشركة الداخلية", training_general: "تدريب عام", training_vocational: "تدريب مهنى" };
const CAT_OPTIONS = [["school", "مدرسة (عهد وموازنات)"], ["company", "الشركة الداخلية"], ["training_general", "تدريب عام"], ["training_vocational", "تدريب مهنى"]];
const CAT_FILTER = [["all", "كل الأنواع"], ["school", "المدارس"], ["company", "الشركة الداخلية"], ["training_general", "تدريب عام"], ["training_vocational", "تدريب مهنى"]];
const unitCat = (data, sid) => { const u = (data.schools || []).find(s => String(s.id) === String(sid)); return (u && u.category) || "school"; };

/* ============================================================ الشاشات ============================================================ */
function Login({ onLogin, loading }) {
  const [u, setU] = useState(""); const [p, setP] = useState("");
  const go = () => { if (u && p) onLogin(u.trim(), p.trim()); };
  return (
    <div className="login-wrap">
      <div className="login-card">
        <Logo big />
        <h1>ابدأ إديو</h1>
        <p>نظام متابعة الموازنات والعهد المالية</p>
        <label className="field"><span>اسم المستخدم</span><input value={u} onChange={e => setU(e.target.value)} onKeyDown={e => e.key === "Enter" && go()} /></label>
        <label className="field"><span>كلمة السر (PIN)</span><input type="password" value={p} onChange={e => setP(e.target.value)} onKeyDown={e => e.key === "Enter" && go()} /></label>
        <button className="btn primary" style={{ width: "100%" }} disabled={loading} onClick={go}>{loading ? "جارٍ الدخول…" : "دخول"}</button>
        {!REMOTE && <div className="demo-note">وضع تجريبى — جرّب: <b>admin / 1234</b> (مدير) أو <b>hasan / 1111</b> (محاسب). لتفعيل الوضع المشترك ضع رابط Apps Script فى config.js</div>}
      </div>
    </div>
  );
}

function PettyBar({ data }) {
  let received = 0, spent = 0;
  (data.tranches || []).forEach(t => received += Number(t.amount || 0));
  (data.expenses || []).forEach(e => { if (e.approval !== "rejected" && e.custody_id) spent += Number(e.amount || 0); });
  const rem = received - spent;
  return (
    <div className="petty-bar">
      <div className="pb-item"><span>إجمالى العهد المستلمة</span><b>{fmt(received)} <i>ج.م</i></b></div>
      <div className="pb-sep" />
      <div className="pb-item"><span>المصروف</span><b className="amber">{fmt(spent)} <i>ج.م</i></b></div>
      <div className="pb-sep" />
      <div className="pb-item"><span>المتبقى · Petty Cash</span><b className={rem >= 0 ? "green" : "red"}>{fmt(rem)} <i>ج.م</i></b></div>
    </div>
  );
}
function Dashboard({ data, onGo }) {
  const calc = useCalc(data);
  if (data.me.role !== "manager") return <AccountantHome data={data} calc={calc} onGo={onGo} />;
  const schoolTotals = (sid) => {
    const allocated = data.lines.filter(l => String(l.school_id) === String(sid)).reduce((s, l) => s + Number(l.allocated || 0), 0);
    const spent = calc.spentBySchool[sid] || 0;
    return { allocated, spent, remaining: allocated - spent };
  };
  const totalAlloc = data.schools.reduce((s, sc) => s + schoolTotals(sc.id).allocated, 0);
  const totalSpent = data.schools.reduce((s, sc) => s + schoolTotals(sc.id).spent, 0);
  const pending = data.expenses.filter(e => e.approval === "pending").length;
  const unsettled = data.expenses.filter(e => e.approval === "approved" && !yes(e.settled)).length;
  const custAvail = data.custodies.reduce((s, c) => s + (custIssued(data, c) - (calc.spentByCustody[c.id] || 0)), 0);
  return (
    <div className="stack">
      <div className="kpi-row">
        <Kpi label="إجمالى الموازنات" v={fmt(totalAlloc)} u="ج.م" tone="navy" />
        <Kpi label="إجمالى المصروف" v={fmt(totalSpent)} u="ج.م" tone="teal" />
        <Kpi label="المتبقى" v={fmt(totalAlloc - totalSpent)} u="ج.م" tone="green" />
        <Kpi label="رصيد العهد المتاح" v={fmt(custAvail)} u="ج.م" tone="amber" />
      </div>
      <div className="kpi-row">
        <div className="kpi red" style={{ cursor: "pointer" }} onClick={() => onGo("approvals")}><div className="kpi-label">بنود بانتظار الاعتماد</div><div className="kpi-value">{pending}</div></div>
        <div className="kpi teal" style={{ cursor: "pointer" }} onClick={() => onGo("approvals")}><div className="kpi-label">مصروفات لم تُسوَّ</div><div className="kpi-value">{unsettled}</div></div>
      </div>
      <PettyByType data={data} calc={calc} onGo={onGo} />
      <div className="panel">
        <h3 className="panel-title">حالة الموازنات</h3>
        <div className="table-wrap"><table className="tbl">
          <thead><tr><th>المدرسة / الجهة</th><th>الموازنة</th><th>المصروف</th><th>المتبقى</th><th>التنفيذ</th></tr></thead>
          <tbody>{data.schools.map(sc => { const t = schoolTotals(sc.id); const pct = t.allocated ? Math.round((t.spent / t.allocated) * 100) : 0; return (
            <tr key={sc.id}><td style={{ fontWeight: 600 }}>{sc.name}</td><td className="num">{fmt(t.allocated)}</td><td className="num teal">{fmt(t.spent)}</td><td className="num green">{fmt(t.remaining)}</td>
              <td style={{ minWidth: 120 }}><div className="bar"><div className="bar-fill" style={{ width: pct + "%", background: pct > 90 ? "var(--red)" : "var(--teal)" }} /></div><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>{pct}%</span></td></tr>); })}
          </tbody>
        </table></div>
      </div>
    </div>
  );
}

function PettyByType({ data, calc, onGo }) {
  const cats = [["school", "المدارس", "navy"], ["company", "الشركة الداخلية", "teal"], ["training_general", "تدريب عام", "green"], ["training_vocational", "تدريب مهنى", "amber"]];
  const agg = {};
  data.custodies.forEach(c => { const k = unitCat(data, c.school_id); const rem = custIssued(data, c) - (calc.spentByCustody[c.id] || 0); (agg[k] = agg[k] || { rem: 0, n: 0 }).rem += rem; agg[k].n += 1; });
  const shown = cats.filter(([k]) => agg[k]);
  if (shown.length === 0) return null;
  return (
    <div className="panel">
      <h3 className="panel-title">النقدية المتاحة بالعهد حسب النوع · Petty Cash</h3>
      <div className="kpi-row" style={{ cursor: "pointer" }} onClick={() => onGo("custodies")}>
        {shown.map(([k, label, tone]) => <div key={k} className={"kpi " + tone}><div className="kpi-label">{label} <span style={{ opacity: .7 }}>({agg[k].n} عهدة)</span></div><div className="kpi-value">{fmt(agg[k].rem)} <span className="kpi-unit">ج.م</span></div></div>)}
      </div>
    </div>
  );
}
function AccountantHome({ data, calc, onGo }) {
  const rows = data.custodies.map(c => { const issued = custIssued(data, c); const spent = calc.spentByCustody[c.id] || 0; return { c, issued, spent, rem: issued - spent }; });
  const tot = rows.reduce((a, r) => ({ issued: a.issued + r.issued, spent: a.spent + r.spent }), { issued: 0, spent: 0 });
  const pending = data.expenses.filter(e => e.approval === "pending").length;
  return (
    <div className="stack">
      <div className="kpi-row">
        <Kpi label="عدد عهدى" v={rows.length} u="" tone="navy" />
        <Kpi label="إجمالى العهد المستلمة" v={fmt(tot.issued)} u="ج.م" tone="teal" />
        <Kpi label="المصروف" v={fmt(tot.spent)} u="ج.م" tone="amber" />
        <Kpi label="المتبقى" v={fmt(tot.issued - tot.spent)} u="ج.م" tone="green" />
      </div>
      <div className="kpi-row">
        <div className="kpi red" style={{ cursor: "pointer" }} onClick={() => onGo("approvals")}><div className="kpi-label">بنودى بانتظار الاعتماد</div><div className="kpi-value">{pending}</div></div>
        <div className="kpi teal" style={{ cursor: "pointer" }} onClick={() => onGo("custodies")}><div className="kpi-label">تسجيل صرف من العهدة</div><div className="kpi-value" style={{ fontSize: 15 }}>افتح تبويب العهد ‹</div></div>
      </div>
      <div className="panel">
        <h3 className="panel-title">عهدى</h3>
        {rows.length === 0 ? <div className="empty">لا توجد عهد مسندة إليك بعد — تواصل مع مدير البرنامج.</div> :
          <div className="table-wrap"><table className="tbl">
            <thead><tr><th>العهدة</th><th>المستلمة</th><th>المصروف</th><th>المتبقى</th><th>الاستهلاك</th></tr></thead>
            <tbody>{rows.map(r => { const pct = r.issued ? Math.min(100, Math.round(r.spent / r.issued * 100)) : 0; return (
              <tr key={r.c.id} style={{ cursor: "pointer" }} onClick={() => onGo("custodies")}>
                <td style={{ fontWeight: 600 }}>{r.c.label}</td><td className="num">{fmt(r.issued)}</td><td className="num amber">{fmt(r.spent)}</td>
                <td className={"num " + (r.rem >= 0 ? "green" : "red")}>{fmt(r.rem)}</td>
                <td style={{ minWidth: 110 }}><div className="bar"><div className="bar-fill" style={{ width: pct + "%", background: pct > 90 ? "var(--red)" : "var(--navy)" }} /></div></td>
              </tr>); })}</tbody>
          </table></div>}
      </div>
    </div>
  );
}

function Budgets({ data, canCentral, setModal }) {
  const calc = useCalc(data);
  const [catF, setCatF] = useState("all");
  const units = data.schools.filter(s => catF === "all" || (s.category || "school") === catF);
  const [sid, setSid] = useState(units[0] ? units[0].id : "");
  useEffect(() => { if (!units.find(u => String(u.id) === String(sid))) setSid(units[0] ? units[0].id : ""); }, [catF]);
  const school = data.schools.find(s => String(s.id) === String(sid));
  const lines = data.lines.filter(l => String(l.school_id) === String(sid));
  const sections = [];
  lines.forEach(l => { let s = sections.find(x => x.name === l.section); if (!s) { s = { name: l.section, items: [] }; sections.push(s); } s.items.push(l); });
  const grand = lines.reduce((a, l) => a + Number(l.allocated || 0), 0);
  const grandSpent = lines.reduce((a, l) => a + (calc.spentByLine[l.id] || 0), 0);
  return (
    <div className="stack">
      <div className="toolbar">
        <h3 className="section-h">الموازنة السنوية <span style={{ fontSize: 12, color: "var(--ink-soft)", fontWeight: 400 }}>(الفعلى = المصروف المُسوّى فقط)</span></h3>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <select value={catF} onChange={e => setCatF(e.target.value)}>{CAT_FILTER.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          <select value={sid} onChange={e => setSid(e.target.value)}>{units.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category || "school"]} · {s.name}</option>)}</select>
          {canCentral && <button className="btn ghost sm" onClick={() => setModal({ type: "import", payload: { school_id: sid } })}>استيراد موازنة</button>}
          {canCentral && sid && <button className="btn primary sm" onClick={() => setModal({ type: "central", payload: { school_id: sid } })}>+ شراء مركزى</button>}
        </div>
      </div>
      {!sid ? <div className="empty">لا توجد جهات فى هذا التصنيف.</div> :
      <div className="panel">
        <div className="mini-kpis">
          <div><span>الموازنة</span><b>{fmt(grand)}</b></div>
          <div><span>المصروف</span><b className="teal">{fmt(grandSpent)}</b></div>
          <div><span>المتبقى</span><b className={grand - grandSpent >= 0 ? "green" : "red"}>{fmt(grand - grandSpent)}</b></div>
          <div><span>التنفيذ</span><b>{grand ? Math.round((grandSpent / grand) * 100) : 0}%</b></div>
        </div>
        <div className="table-wrap"><table className="tbl">
          <thead><tr><th>البند</th><th>الموازنة</th><th>ما تم صرفه</th><th>المتبقى</th><th>الحالة</th><th>النسبة</th></tr></thead>
          <tbody>
            {sections.map(sec => { const sa = sec.items.reduce((a, l) => a + Number(l.allocated || 0), 0); const ss = sec.items.reduce((a, l) => a + (calc.spentByLine[l.id] || 0), 0); return (
              <React.Fragment key={sec.name}>
                <tr className="sec"><td>{sec.name}</td><td className="num">{fmt(sa)}</td><td className="num">{fmt(ss)}</td><td className="num">{fmt(sa - ss)}</td><td></td><td className="num">{sa ? Math.round(ss / sa * 100) : 0}%</td></tr>
                {sec.items.map(l => { const a = Number(l.allocated || 0); const sp = calc.spentByLine[l.id] || 0; const rem = a - sp; const def = rem < 0; const pct = a ? Math.abs(Math.round(rem / a * 100)) : (sp > 0 ? 100 : 0); return (
                  <tr key={l.id} className={def ? "def" : ""}><td>{l.name}</td><td className="num">{fmt(a)}</td><td className="num teal">{fmt(sp)}</td><td className={"num " + (def ? "red" : "green")}>{fmt(rem)}</td>
                    <td><span className={"chip " + (def ? "red" : "green")}>{def ? "عجز" : rem === 0 ? "مطابق" : "وفر"}</span></td><td className={"num " + (def ? "red" : "green")}>{pct}%</td></tr>); })}
              </React.Fragment>); })}
            <tr className="tot"><td>الإجمالى العام</td><td className="num">{fmt(grand)}</td><td className="num teal">{fmt(grandSpent)}</td><td className="num green">{fmt(grand - grandSpent)}</td><td></td><td className="num">{grand ? Math.round(grandSpent / grand * 100) : 0}%</td></tr>
          </tbody>
        </table></div>
      </div>}
    </div>
  );
}

function Custodies({ data, isMgr, canRecord, act, showToast, setModal }) {
  const calc = useCalc(data);
  const [open, setOpen] = useState(data.custodies[0] ? data.custodies[0].id : null);
  const inCat = (cats) => data.custodies.filter(c => cats.indexOf(unitCat(data, c.school_id)) >= 0);
  const groups = [
    { key: "school", label: "عهد وموازنات المدارس", subs: [{ cat: "school" }] },
    { key: "company", label: "عهدة الشركة الداخلية", subs: [{ cat: "company" }] },
    { key: "training", label: "عهد التدريب", subs: [{ cat: "training_general", label: "عام" }, { cat: "training_vocational", label: "مهنى" }] },
  ];
  const props = { data, calc, isMgr, canRecord, act, showToast, setModal, open, setOpen };
  return (
    <div className="stack">
      <div className="toolbar"><h3 className="section-h">العهد المالية</h3>{isMgr && <button className="btn primary" onClick={() => setModal({ type: "custody" })}>+ عهدة جديدة</button>}</div>
      {data.custodies.length === 0 && <div className="empty">لا توجد عهد.</div>}
      {groups.map(g => {
        const all = inCat(g.subs.map(s => s.cat));
        if (all.length === 0) return null;
        return (
          <div key={g.key} className="cust-group">
            <div className="cust-group-h">{g.label} <span className="cust-group-n">{all.length}</span></div>
            {g.subs.map(sub => {
              const list = inCat([sub.cat]);
              if (list.length === 0) return null;
              return (
                <div key={sub.cat}>
                  {sub.label && <div className="cust-sub-h">تدريب {sub.label}</div>}
                  {list.map(c => <CustodyBlock key={c.id} c={c} {...props} />)}
                </div>);
            })}
          </div>);
      })}
    </div>
  );
}
function CustodyBlock({ c, data, calc, isMgr, canRecord, act, showToast, setModal, open, setOpen }) {
  const issued = custIssued(data, c); const spent = calc.spentByCustody[c.id] || 0; const pending = calc.pendingByCustody[c.id] || 0; const rem = issued - spent;
  const isOpen = open === c.id; const pct = issued ? Math.min(100, spent / issued * 100) : 0;
  const school = data.schools.find(s => String(s.id) === String(c.school_id));
  const ledger = [];
  (data.tranches || []).filter(t => String(t.custody_id) === String(c.id)).forEach(t => ledger.push({ date: t.date, kind: "in", item: "عهدة مستلمة" + (t.note ? " — " + t.note : ""), amount: Number(t.amount || 0) }));
  (data.expenses || []).filter(e => String(e.custody_id) === String(c.id) && e.approval !== "rejected").forEach(e => ledger.push({ date: e.date, kind: "out", item: lineName(data, e.line_id) || e.spend_item || "صرف", desc: e.description, amount: Number(e.amount || 0), approval: e.approval, settled: yes(e.settled) }));
  ledger.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.kind === "in" ? -1 : 1));
  let bal = 0; ledger.forEach(r => { bal += r.kind === "in" ? r.amount : -r.amount; r.balance = bal; });
  return (
    <div className="cust-block">
      <div className="cust-head" onClick={() => setOpen(isOpen ? null : c.id)}>
        <div><b>{c.label}</b><span className="cust-sub">{c.holder}{school ? " · " + school.name : ""}</span></div>
        <div className="cust-bal"><span className="n">{fmt(rem)}</span><span className="u">ج.م متبقّى</span></div>
      </div>
      {isOpen && <div className="cust-body">
        <div className="mini-kpis">
          <div><span>المستلمة</span><b>{fmt(issued)}</b></div>
          <div><span>المصروف</span><b className="teal">{fmt(spent)}</b></div>
          <div><span>المتبقى</span><b className={rem >= 0 ? "green" : "red"}>{fmt(rem)}</b></div>
          <div><span>قيد الاعتماد</span><b className="amber">{fmt(pending)}</b></div>
        </div>
        <div className="bar" style={{ height: 11, marginBottom: 12 }}><div className="bar-fill" style={{ width: pct + "%", background: pct > 90 ? "var(--red)" : "var(--navy)" }} /></div>
        {rem <= 0 && <div className="warn-banner">انتهت العهدة — أضف عهدة جديدة لمواصلة الصرف.</div>}
        {canRecord && <QuickAdd data={data} custody={c} act={act} showToast={showToast} />}
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "10px 0" }}>
          {isMgr && <button className="btn teal sm" onClick={() => setModal({ type: "tranche", payload: c })}>+ إضافة عهدة</button>}
          {isMgr && <button className="btn ghost sm" onClick={() => setModal({ type: "custody", payload: c })}>تعديل</button>}
          {isMgr && <button className="btn danger-ghost sm" onClick={() => { if (typeof window === "undefined" || window.confirm("حذف هذه العهدة وكل حركاتها ومستنداتها نهائياً؟")) act("deleteCustody", { id: c.id }); }}>حذف العهدة</button>}
        </div>
        <div className="table-wrap"><table className="tbl">
          <thead><tr><th>التاريخ</th><th>البند / الحركة</th><th>البيان</th><th>وارد</th><th>منصرف</th><th>الرصيد</th><th>الحالة</th></tr></thead>
          <tbody>{ledger.map((r, i) => (
            <tr key={i} className={r.kind === "in" ? "in" : ""}>
              <td style={{ whiteSpace: "nowrap", color: "var(--ink-soft)" }}>{r.date}</td>
              <td style={{ fontWeight: 600 }}>{r.item}</td><td style={{ color: "var(--ink-soft)", fontSize: 12 }}>{r.desc || "—"}</td>
              <td className="num green">{r.kind === "in" ? fmt(r.amount) : "—"}</td>
              <td className="num red">{r.kind === "out" ? fmt(r.amount) : "—"}</td>
              <td className={"num " + (r.balance < 0 ? "red" : "")}><b>{fmt(r.balance)}</b></td>
              <td>{r.kind === "out" ? <ApprovalChip s={r.approval} sett={r.settled} /> : <span className="chip green">إيداع</span>}</td>
            </tr>))}
            {ledger.length === 0 && <tr><td colSpan="7"><div className="empty">لا توجد حركات.</div></td></tr>}
          </tbody>
        </table></div>
      </div>}
    </div>
  );
}

function QuickAdd({ data, custody, act, showToast }) {
  const lines = data.lines.filter(l => String(l.school_id) === String(custody.school_id));
  const [lineId, setLineId] = useState(lines[0] ? lines[0].id : "");
  const [amount, setAmount] = useState(""); const [date, setDate] = useState(today()); const [desc, setDesc] = useState(""); const [busy, setBusy] = useState(false);
  if (lines.length === 0) return <div className="warn-banner">لا توجد بنود موازنة لهذه المدرسة — أبلغ مدير البرنامج لإضافتها قبل تسجيل الصرف.</div>;
  const save = async () => {
    if (!amount || !lineId) return;
    setBusy(true);
    const exp = { date, school_id: custody.school_id, custody_id: custody.id, line_id: lineId, spend_item: "", description: desc.trim(), amount: Number(amount) || 0, doc_url: "", doc_name: "", ref: "", note: "" };
    try { await act("addExpense", { expense: exp }); setAmount(""); setDesc(""); showToast("تم تسجيل الصرف — بانتظار الاعتماد"); } catch {}
    setBusy(false);
  };
  return (
    <div className="quick-row">
      <div className="qf"><span>بند الموازنة</span><select value={lineId} onChange={e => setLineId(e.target.value)}>{lines.map(l => <option key={l.id} value={l.id}>{l.section ? l.section + " — " : ""}{l.name}</option>)}</select></div>
      <div className="qf"><span>المبلغ</span><input type="number" value={amount} onChange={e => setAmount(e.target.value)} onKeyDown={e => e.key === "Enter" && save()} style={{ width: 100 }} /></div>
      <div className="qf"><span>التاريخ</span><input type="date" value={date} onChange={e => setDate(e.target.value)} /></div>
      <div className="qf" style={{ flex: 1, minWidth: 150 }}><span>البيان</span><input value={desc} onChange={e => setDesc(e.target.value)} onKeyDown={e => e.key === "Enter" && save()} placeholder="ماذا صُرف؟" /></div>
      <button className="btn primary sm" disabled={busy} onClick={save}>{busy ? "…" : "+ صرف"}</button>
    </div>
  );
}

function Approvals({ data, isMgr, canApprove, canReview, act, setModal, showToast }) {
  const [fSchool, setFSchool] = useState("all"); const [fc, setFc] = useState("all"); const [fs, setFs] = useState("all");
  const [from, setFrom] = useState(""); const [to, setTo] = useState("");
  const myCustody = (e) => { const c = data.custodies.find(x => String(x.id) === String(e.custody_id)); return c && String(c.user || "") === String(data.me.username); };
  const canUpload = (e) => isMgr || myCustody(e);
  const custodiesForSchool = fSchool === "all" ? data.custodies : data.custodies.filter(c => String(c.school_id) === fSchool);
  const rows = data.expenses.filter(e => {
    if (fSchool !== "all" && String(e.school_id) !== fSchool) return false;
    if (fc !== "all" && String(e.custody_id) !== fc) return false;
    if (from && e.date < from) return false;
    if (to && e.date > to) return false;
    if (fs === "pending" && e.approval !== "pending") return false;
    if (fs === "approved" && e.approval !== "approved") return false;
    if (fs === "needdoc" && !(e.approval === "approved" && !e.doc_url)) return false;
    if (fs === "review" && !(e.approval === "approved" && e.doc_url && !yes(e.settled) && e.review_status !== "ناقص")) return false;
    if (fs === "settled" && !yes(e.settled)) return false;
    if (fs === "incomplete" && e.review_status !== "ناقص") return false;
    return true;
  }).slice().reverse();
  const totalShown = rows.reduce((a, e) => a + (e.approval !== "rejected" ? Number(e.amount || 0) : 0), 0);
  const upload = async (e, file) => {
    if (!file) return;
    if (file.size > 4.5 * 1024 * 1024) { showToast("حجم الملف أكبر من 4.5 ميجا", "err"); return; }
    const fr = new FileReader();
    fr.onload = async () => {
      const dataUrl = fr.result; const base64 = String(dataUrl).split(",")[1];
      try { await act("uploadDoc", { id: e.id, filename: file.name, mimeType: file.type, dataBase64: base64, dataUrl }); showToast("تم رفع المستند"); } catch {}
    };
    fr.readAsDataURL(file);
  };
  return (
    <div className="stack">
      <div className="panel" style={{ padding: 12 }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "end" }}>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>المدرسة / الجهة</span>
            <select value={fSchool} onChange={e => { setFSchool(e.target.value); setFc("all"); }}><option value="all">كل الجهات</option>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category || "school"]} · {s.name}</option>)}</select></div>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>العهدة</span>
            <select value={fc} onChange={e => setFc(e.target.value)}><option value="all">كل العهد</option>{custodiesForSchool.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}</select></div>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>من</span><input type="date" value={from} onChange={e => setFrom(e.target.value)} style={{ padding: "8px 10px", border: "1px solid var(--line)", borderRadius: 8 }} /></div>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>إلى</span><input type="date" value={to} onChange={e => setTo(e.target.value)} style={{ padding: "8px 10px", border: "1px solid var(--line)", borderRadius: 8 }} /></div>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>الحالة</span>
            <select value={fs} onChange={e => setFs(e.target.value)}>
              <option value="all">كل الحالات</option><option value="pending">بانتظار الاعتماد</option><option value="approved">معتمد</option>
              <option value="needdoc">معتمد بلا مستند</option><option value="review">بانتظار مراجعة المحاسب</option>
              <option value="incomplete">مستندات ناقصة</option><option value="settled">تمت التسوية</option>
            </select></div>
        </div>
        <div style={{ marginTop: 10, fontSize: 13, color: "var(--navy)", fontWeight: 700 }}>عدد المصروفات: {rows.length} · الإجمالى المعروض: {fmt(totalShown)} ج.م</div>
      </div>
      {rows.map(e => {
        const cust = data.custodies.find(c => String(c.id) === String(e.custody_id));
        return (
          <div key={e.id} className="exp-card">
            <div className="exp-main">
              <div className="exp-top">
                <span className="exp-amount">{fmt(e.amount)} <i>ج.م</i></span>
                <ApprovalChip s={e.approval} sett={yes(e.settled)} />
                {e.review_status === "ناقص" && <span className="chip red">مستندات ناقصة</span>}
                {e.doc_url ? <a className="chip navy" href={e.doc_url} target="_blank" rel="noreferrer" style={{ textDecoration: "none" }}>📎 {e.doc_name || "مستند"}</a> : (e.approval === "approved" && <span className="chip amber">بلا مستند</span>)}
              </div>
              <div className="exp-desc">{e.description || "—"}</div>
              <div className="exp-meta"><span>البند: <b>{lineName(data, e.line_id) || e.spend_item || "—"}</b></span><span>العهدة: {cust ? cust.label : "شراء مركزى"}</span><span>{e.date}</span><span>أدخله: {e.created_by}</span>{e.approved_by && <span>اعتمده: {e.approved_by}</span>}</div>
              {e.review_note && <div style={{ fontSize: 12.5, color: "var(--red)", marginTop: 6, background: "#FDF2F2", padding: "6px 10px", borderRadius: 8 }}>ملاحظة المحاسب: {e.review_note}</div>}
            </div>
            <div className="exp-actions">
              {canApprove && e.approval === "pending" && <button className="btn primary sm" onClick={() => setModal({ type: "approve", payload: e })}>مراجعة واعتماد</button>}
              {myCustody(e) && e.approval === "pending" && <button className="btn ghost sm" onClick={() => setModal({ type: "editExpense", payload: e })}>تعديل</button>}
              {myCustody(e) && e.approval === "pending" && <button className="btn danger-ghost sm" onClick={() => { if (typeof window === "undefined" || window.confirm("حذف هذا الصرف؟")) act("deleteExpense", { id: e.id }); }}>حذف</button>}
              {canUpload(e) && e.approval === "approved" && <label className="btn ghost sm" style={{ cursor: "pointer" }}>{e.doc_url ? "تغيير المستند" : "رفع مستند"}<input type="file" hidden accept="image/*,application/pdf" onChange={ev => upload(e, ev.target.files[0])} /></label>}
              {canReview && e.approval === "approved" && e.doc_url && !yes(e.settled) && <button className="btn teal sm" onClick={() => setModal({ type: "review", payload: e })}>مراجعة المستند</button>}
              {canReview && yes(e.settled) && <button className="btn ghost sm" onClick={() => setModal({ type: "review", payload: e })}>تعديل المراجعة</button>}
              {isMgr && <button className="btn danger-ghost sm" onClick={() => act("deleteExpense", { id: e.id })}>حذف</button>}
            </div>
          </div>);
      })}
      {rows.length === 0 && <div className="empty">لا توجد مصروفات مطابقة.</div>}
    </div>
  );
}

function Admin({ data, act, probe, showToast, setModal }) {
  const [sub, setSub] = useState("schools");
  const [conn, setConn] = useState(null); const [testing, setTesting] = useState(false);
  const test = async () => {
    setTesting(true); setConn(null);
    try { const r = await probe("ping", {}); setConn(r && r.demo ? { ok: true, demo: true } : { ok: true, remote: true, r }); }
    catch (e) { setConn({ ok: false, msg: e.message }); }
    setTesting(false);
  };
  const subs = [["schools", "المدارس والبنود"], ["custodyItems", "بنود ومسئولو العهد"], ["users", "المستخدمون"]];
  return (
    <div className="stack">
      <div className="panel">
        <div className="toolbar"><h3 className="panel-title" style={{ margin: 0 }}>الاتصال بجوجل شيت</h3><button className="btn ghost sm" onClick={test} disabled={testing}>{testing ? "جارٍ الفحص…" : "اختبار الاتصال"}</button></div>
        <div style={{ fontSize: 13, color: "var(--ink-soft)", marginTop: 8 }}>
          {conn == null && <span>اضغط «اختبار الاتصال» للتأكد من الربط مع جوجل شيت.</span>}
          {conn && conn.ok && conn.demo && <span style={{ color: "var(--amber)" }}>⚠ وضع تجريبى — التطبيق غير مربوط بجوجل شيت. البيانات تُحفظ على متصفحك فقط. ضع رابط Apps Script فى config.js لتفعيل الحفظ المشترك.</span>}
          {conn && conn.ok && conn.remote && <span style={{ color: "var(--green)" }}>✅ متصل بنجاح — عدد المستخدمين: {conn.r.users} · المدارس: {conn.r.schools}. الحفظ يتم على جوجل شيت.</span>}
          {conn && !conn.ok && <span style={{ color: "var(--red)" }}>✗ فشل الاتصال: {conn.msg} — تأكد أن رابط Apps Script صحيح (ينتهى بـ /exec) وأن النشر بصلاحية Anyone وأعِد النشر بإصدار جديد.</span>}
        </div>
      </div>
      <div className="tabs" style={{ position: "static", borderRadius: 12, border: "1px solid var(--line)" }}>
        {subs.map(([k, l]) => <button key={k} className={"tab " + (sub === k ? "active" : "")} onClick={() => setSub(k)}>{l}</button>)}
      </div>
      {sub === "schools" && <AdminSchools data={data} act={act} setModal={setModal} />}
      {sub === "custodyItems" && <AdminCustodyItems data={data} act={act} />}
      {sub === "users" && <AdminUsers data={data} act={act} setModal={setModal} />}
    </div>
  );
}

function AdminSchools({ data, act, setModal }) {
  const [sid, setSid] = useState(data.schools[0] ? data.schools[0].id : "");
  const lines = data.lines.filter(l => String(l.school_id) === String(sid));
  return (
    <div className="stack">
      <div className="panel">
        <div className="toolbar"><h3 className="panel-title" style={{ margin: 0 }}>الجهات / الوحدات</h3><button className="btn primary sm" onClick={() => setModal({ type: "school" })}>+ جهة</button></div>
        <div className="chips-list" style={{ marginTop: 12 }}>{data.schools.map(s => <span key={s.id} className="cat-chip">{s.name} <span className="chip navy" style={{ marginInlineStart: 4 }}>{CAT_LABEL[s.category || "school"]}</span><button className="icon-btn" style={{ width: 24, height: 24 }} onClick={() => setModal({ type: "school", payload: s })}>✎</button></span>)}</div>
      </div>
      <div className="panel">
        <div className="toolbar"><div style={{ display: "flex", gap: 8, alignItems: "center" }}><span style={{ fontWeight: 700, color: "var(--navy)" }}>بنود موازنة:</span><select value={sid} onChange={e => setSid(e.target.value)}>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category||"school"]} · {s.name}</option>)}</select></div><button className="btn primary sm" onClick={() => setModal({ type: "line", payload: { school_id: sid } })}>+ بند</button></div>
        <div className="table-wrap" style={{ marginTop: 12 }}><table className="tbl">
          <thead><tr><th>القسم</th><th>البند</th><th>الموازنة</th><th></th></tr></thead>
          <tbody>{lines.map(l => <tr key={l.id}><td>{l.section}</td><td>{l.name}</td><td className="num">{fmt(l.allocated)}</td>
            <td style={{ display: "flex", gap: 6 }}><button className="icon-btn" onClick={() => setModal({ type: "line", payload: l })}>✎</button><button className="icon-btn" onClick={() => act("deleteLine", { id: l.id })}>×</button></td></tr>)}
            {lines.length === 0 && <tr><td colSpan="4"><div className="empty">لا توجد بنود.</div></td></tr>}
          </tbody></table></div>
      </div>
    </div>
  );
}

function AdminCustodyItems({ data, act }) {
  return (
    <div className="admin-grid">
      <Catalog title="بنود صرف العهدة" items={data.spendItems} cols={["name"]} labels={["اسم البند"]} onAdd={v => act("addSpendItem", { item: { name: v.name } })} onDel={id => act("deleteSpendItem", { id })} />
      <Catalog title="مسئولو العهد" items={data.holders} cols={["name", "title"]} labels={["الاسم", "الوظيفة"]} onAdd={v => act("addHolder", { item: { name: v.name, title: v.title } })} onDel={id => act("deleteHolder", { id })} />
    </div>
  );
}

function AdminUsers({ data, act, setModal }) {
  return (
    <div className="panel">
      <div className="toolbar"><h3 className="panel-title" style={{ margin: 0 }}>المستخدمون</h3><button className="btn primary sm" onClick={() => setModal({ type: "user" })}>+ مستخدم</button></div>
      <div className="table-wrap" style={{ marginTop: 12 }}><table className="tbl">
        <thead><tr><th>الاسم</th><th>المستخدم</th><th>الدور</th><th>المدارس</th><th>الحالة</th><th></th></tr></thead>
        <tbody>{(data.users || []).map(u => {
          const sc = u.schools === "*" ? "كل المدارس" : String(u.schools).split(",").map(id => { const s = data.schools.find(x => String(x.id) === String(id.trim())); return s ? s.name : id; }).join("، ");
          return <tr key={u.id}><td style={{ fontWeight: 600 }}>{u.name}</td><td>{u.username}</td><td><span className={"chip " + (u.role === "manager" ? "navy" : "green")}>{u.role === "manager" ? "مدير" : "محاسب"}</span></td><td style={{ fontSize: 12 }}>{sc}</td><td>{yes(u.active) ? "مفعّل" : "موقوف"}</td>
            <td style={{ display: "flex", gap: 6 }}><button className="icon-btn" onClick={() => setModal({ type: "user", payload: u })}>✎</button><button className="icon-btn" onClick={() => act("deleteUser", { id: u.id })}>×</button></td></tr>;
        })}</tbody>
      </table></div>
    </div>
  );
}

function Catalog({ title, items, cols, labels, onAdd, onDel }) {
  const [v, setV] = useState({});
  const add = () => { if (!(v[cols[0]] || "").trim()) return; onAdd(v); setV({}); };
  return (
    <div className="panel">
      <h3 className="panel-title">{title}</h3>
      <div className="catalog-add">{cols.map((c, i) => <input key={c} placeholder={labels[i]} value={v[c] || ""} onChange={e => setV(x => Object.assign({}, x, { [c]: e.target.value }))} onKeyDown={e => e.key === "Enter" && add()} />)}<button className="btn primary sm" onClick={add}>إضافة</button></div>
      <div className="chips-list">{items.map(it => <span key={it.id} className="cat-chip">{cols.map(c => it[c]).filter(Boolean).join(" — ")}<button className="chip-x" onClick={() => onDel(it.id)}>×</button></span>)}{items.length === 0 && <span style={{ color: "var(--ink-soft)", fontSize: 13 }}>لا توجد عناصر.</span>}</div>
    </div>
  );
}

/* ============================================================ التقارير ============================================================ */
function Reports({ data, act, showToast }) {
  const calc = useCalc(data);
  const [view, setView] = useState("tx");
  const [from, setFrom] = useState(""); const [to, setTo] = useState("");
  const [school, setSchool] = useState("all"); const [cust, setCust] = useState("all");
  const [cat, setCat] = useState("all"); const [status, setStatus] = useState("all");
  const [typeF, setTypeF] = useState("all");
  const [email, setEmail] = useState(null);
  const catName = (e) => e.spend_item || lineName(data, e.line_id) || "غير مصنّف";
  const custName = id => { const c = data.custodies.find(x => String(x.id) === String(id)); return c ? c.label : "—"; };
  const schoolName = id => { const s = data.schools.find(x => String(x.id) === String(id)); return s ? s.name : "—"; };
  const inRange = d => (!from || d >= from) && (!to || d <= to);
  const flt = data.expenses.filter(e => {
    if (e.approval === "rejected") return false;
    if (!inRange(e.date)) return false;
    if (typeF !== "all" && unitCat(data, e.school_id) !== typeF) return false;
    if (school !== "all" && String(e.school_id) !== school) return false;
    if (cust !== "all" && String(e.custody_id) !== cust) return false;
    if (cat !== "all" && catName(e) !== cat) return false;
    if (status === "pending" && e.approval !== "pending") return false;
    if (status === "approved" && e.approval !== "approved") return false;
    if (status === "settled" && !yes(e.settled)) return false;
    if (status === "unsettled" && !(e.approval === "approved" && !yes(e.settled))) return false;
    return true;
  });
  const cats = Array.from(new Set(data.expenses.map(catName)));
  const total = flt.reduce((a, e) => a + Number(e.amount || 0), 0);

  const periodTxt = `الفترة: ${from || "البداية"} إلى ${to || "الآن"}`;
  const getExport = () => {
    if (view === "byItem") {
      const map = {}; flt.forEach(e => { const k = catName(e); map[k] = (map[k] || 0) + Number(e.amount || 0); });
      const rows = Object.entries(map).sort((a, b) => b[1] - a[1]).map(([n, v]) => [n, Math.round(v), (total ? Math.round(v / total * 100) : 0) + "%"]);
      return { title: "تقرير المصروف حسب البند", header: ["البند", "المبلغ", "النسبة"], rows, meta: periodTxt };
    }
    if (view === "balances") {
      const custs = data.custodies.filter(c => (cust === "all" || String(c.id) === cust) && (school === "all" || String(c.school_id) === school));
      const rows = custs.map(c => { const iss = custIssued(data, c); const sp = calc.spentByCustody[c.id] || 0; return [c.label, c.holder, iss, sp, iss - sp, iss ? Math.round((iss - sp) / iss * 100) + "%" : "-"]; });
      return { title: "تقرير أرصدة العهد", header: ["العهدة", "المسئول", "المستلمة", "المصروف", "المتبقى", "نسبة المتبقى"], rows, meta: periodTxt };
    }
    if (view === "budget") {
      const actual = {}; flt.forEach(e => { if (e.line_id && yes(e.settled)) actual[e.line_id] = (actual[e.line_id] || 0) + Number(e.amount || 0); });
      const scs = school === "all" ? data.schools : data.schools.filter(s => String(s.id) === school);
      const rows = [];
      scs.forEach(sc => data.lines.filter(l => String(l.school_id) === String(sc.id)).forEach(l => { const a = Number(l.allocated || 0), sp = actual[l.id] || 0; rows.push([sc.name, l.section, l.name, a, sp, a - sp, a ? Math.round(sp / a * 100) + "%" : "-"]); }));
      return { title: "تقرير تحليل الموازنة", header: ["المدرسة", "القسم", "البند", "الموازنة", "الفعلى المُسوّى", "المتبقى", "التنفيذ"], rows, meta: periodTxt };
    }
    if (view === "docs") {
      const rows = flt.filter(e => e.approval === "approved" && !yes(e.settled)).sort((a, b) => daysSince(b.date) - daysSince(a.date)).map(e => [e.date, custName(e.custody_id), catName(e), e.amount, daysSince(e.date) + " يوم", e.doc_url ? "مرفوع" : "بلا مستند", e.review_status === "ناقص" ? "ناقص" : "بانتظار المراجعة"]);
      return { title: "تقرير متابعة المستندات", header: ["التاريخ", "العهدة", "البند", "المبلغ", "العمر", "المستند", "المراجعة"], rows, meta: periodTxt };
    }
    if (view === "pettySchool") {
      const agg = {}; data.custodies.filter(c => (school === "all" || String(c.school_id) === school) && (typeF === "all" || unitCat(data, c.school_id) === typeF)).forEach(c => { const k = c.school_id; const iss = custIssued(data, c); const sp = calc.spentByCustody[c.id] || 0; (agg[k] = agg[k] || { iss: 0, sp: 0, n: 0 }); agg[k].iss += iss; agg[k].sp += sp; agg[k].n += 1; });
      const rows = Object.entries(agg).map(([k, v]) => [schoolName(k), CAT_LABEL[unitCat(data, k)], v.n, v.iss, v.sp, v.iss - v.sp]);
      return { title: "تقرير Petty Cash — السيولة لكل مدرسة", header: ["المدرسة / الجهة", "النوع", "عدد العهد", "إجمالى المستلم", "المصروف", "المتبقى (السيولة)"], rows, meta: periodTxt };
    }
    if (view === "officer") {
      const agg = {}; data.custodies.forEach(c => { const key = c.holder || (c.user || "—"); const iss = custIssued(data, c); const sp = calc.spentByCustody[c.id] || 0; (agg[key] = agg[key] || { iss: 0, sp: 0, n: 0 }); agg[key].iss += iss; agg[key].sp += sp; agg[key].n += 1; });
      const rows = Object.entries(agg).sort((a, b) => (b[1].iss - b[1].sp) - (a[1].iss - a[1].sp)).map(([k, v]) => [k, v.n, v.iss, v.sp, v.iss - v.sp]);
      return { title: "تقرير لكل مسئول عهدة", header: ["المسئول", "عدد العهد", "إجمالى المستلم", "المصروف", "المتبقى"], rows, meta: periodTxt };
    }
    const rows = flt.map(e => [e.date, schoolName(e.school_id), custName(e.custody_id), catName(e), e.description, e.amount, e.approval === "approved" ? "معتمد" : e.approval === "pending" ? "بانتظار" : "-", yes(e.settled) ? "مسوّى" : "-", e.doc_url ? "نعم" : "لا"]);
    return { title: "تقرير حركات المصروفات", header: ["التاريخ", "المدرسة", "العهدة", "البند", "البيان", "المبلغ", "الاعتماد", "التسوية", "مستند"], rows, meta: `${periodTxt} · الإجمالى ${fmt(total)} ج.م · عدد ${flt.length}` };
  };
  const [fmtSel, setFmtSel] = useState("excel");
  const doExport = () => { const x = getExport(); exportAs(fmtSel, x.title, x.header, x.rows, x.meta); };

  const views = [["tx", "الحركات"], ["byItem", "حسب البند"], ["balances", "أرصدة العهد"], ["pettySchool", "سيولة المدارس"], ["officer", "لكل مسئول"], ["budget", "تحليل الموازنة"], ["docs", "متابعة المستندات"]];
  return (
    <div className="stack">
      <div className="panel">
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "end" }}>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>من</span><input type="date" value={from} onChange={e => setFrom(e.target.value)} style={{ padding: "8px 10px", border: "1px solid var(--line)", borderRadius: 8 }} /></div>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>إلى</span><input type="date" value={to} onChange={e => setTo(e.target.value)} style={{ padding: "8px 10px", border: "1px solid var(--line)", borderRadius: 8 }} /></div>
          <select value={typeF} onChange={e => setTypeF(e.target.value)}>{CAT_FILTER.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
          <select value={school} onChange={e => setSchool(e.target.value)}><option value="all">كل المدارس</option>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category||"school"]} · {s.name}</option>)}</select>
          <select value={cust} onChange={e => setCust(e.target.value)}><option value="all">كل العهد</option>{data.custodies.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}</select>
          <select value={cat} onChange={e => setCat(e.target.value)}><option value="all">كل البنود</option>{cats.map(c => <option key={c} value={c}>{c}</option>)}</select>
          <select value={status} onChange={e => setStatus(e.target.value)}><option value="all">كل الحالات</option><option value="approved">معتمد</option><option value="pending">بانتظار الاعتماد</option><option value="settled">مسوّى</option><option value="unsettled">معتمد غير مسوّى</option></select>
          <div className="qf" style={{ display: "flex", flexDirection: "column", gap: 4 }}><span style={{ fontSize: 11, color: "var(--ink-soft)" }}>صيغة</span><select value={fmtSel} onChange={e => setFmtSel(e.target.value)}><option value="excel">Excel</option><option value="word">Word</option><option value="pdf">PDF</option><option value="csv">CSV</option></select></div>
          <button className="btn ghost sm" onClick={doExport}>تصدير</button>
          <button className="btn teal sm" onClick={() => setEmail(getExport())}>إرسال بالإيميل</button>
        </div>
        <div className="tabs" style={{ position: "static", borderRadius: 10, border: "1px solid var(--line)", marginTop: 12 }}>
          {views.map(([k, l]) => <button key={k} className={"tab " + (view === k ? "active" : "")} onClick={() => setView(k)}>{l}</button>)}
        </div>
      </div>

      {view === "tx" && <RepTx flt={flt} total={total} custName={custName} catName={catName} />}
      {view === "byItem" && <RepByItem flt={flt} catName={catName} total={total} />}
      {view === "balances" && <RepBalances data={data} calc={calc} flt={flt} cust={cust} school={school} typeF={typeF} />}
      {view === "pettySchool" && <RepPettySchool data={data} calc={calc} school={school} typeF={typeF} />}
      {view === "officer" && <RepOfficer data={data} calc={calc} />}
      {view === "budget" && <RepBudget data={data} flt={flt} school={school} typeF={typeF} />}
      {view === "docs" && <RepDocs flt={flt} custName={custName} catName={catName} />}
      {email && <EmailModal data={data} report={email} act={act} showToast={showToast} close={() => setEmail(null)} />}
    </div>
  );
}
function EmailModal({ data, report, act, showToast, close }) {
  const pool = dedupeEmails([...(data.users || []).map(u => ({ email: u.email, label: u.name })), ...(data.approvers || []).map(a => ({ email: a.email, label: a.name })), ...(data.emails || []).map(x => ({ email: x.email, label: x.label || x.email }))]);
  const [sel, setSel] = useState(pool.map(p => p.email));
  const [extra, setExtra] = useState("");
  const [format, setFormat] = useState("pdf");
  const [busy, setBusy] = useState(false);
  const toggle = (e) => setSel(s => s.indexOf(e) >= 0 ? s.filter(x => x !== e) : [...s, e]);
  const send = async () => {
    const recipients = dedupe([...sel, ...extra.split(/[,;\s]+/).filter(x => x.indexOf("@") > 0)]);
    if (!recipients.length) { alert("اختر مستلماً واحداً على الأقل"); return; }
    setBusy(true);
    const html = reportHTML(report.title, report.header, report.rows, report.meta);
    const payload = { recipients, subject: report.title + " — ابدأ إديو", html };
    if (format === "excel") payload.attachment = { filename: report.title + ".xls", mimeType: "application/vnd.ms-excel", dataBase64: b64utf8("\uFEFF" + html) };
    else if (format === "word") payload.attachment = { filename: report.title + ".doc", mimeType: "application/msword", dataBase64: b64utf8("\uFEFF" + html) };
    else if (format === "pdf") payload.attachment = { filename: report.title + ".pdf", mimeType: "application/pdf", html };
    // format === "summary" → لا مرفق
    try { const r = await act("emailReport", payload); showToast(r && r.demo ? "وضع تجريبى: لا يُرسل إيميل فعلى — يعمل بعد ربط جوجل شيت" : ("تم الإرسال إلى " + recipients.length + " مستلم")); close(); } catch { setBusy(false); }
  };
  return <Modal title="إرسال التقرير بالإيميل" close={close} wide>
    <div style={{ marginBottom: 12, fontSize: 13, color: "var(--ink-soft)" }}>{report.title} · {report.meta}</div>
    <F label="ما الذى يُرسل؟"><select value={format} onChange={e => setFormat(e.target.value)}><option value="pdf">التقرير كـ PDF</option><option value="excel">التقرير كـ Excel</option><option value="word">التقرير كـ Word</option><option value="summary">ملخص فى نص الرسالة فقط</option></select></F>
    <div className="field"><span>المستلمون (من إيميلات المستخدمين المسجّلة)</span>
      <div className="chips-list">{pool.length === 0 ? <span style={{ fontSize: 12, color: "var(--ink-soft)" }}>لا إيميلات مسجّلة — أضف إيميلات المستخدمين من الإدارة.</span> : pool.map(p => <label key={p.email} className="cat-chip" style={{ cursor: "pointer" }}><input type="checkbox" checked={sel.indexOf(p.email) >= 0} onChange={() => toggle(p.email)} /> {p.label} <span style={{ color: "var(--ink-soft)" }}>({p.email})</span></label>)}</div>
    </div>
    <F label="إيميلات إضافية (اختيارى، بفاصلة)"><input value={extra} onChange={e => setExtra(e.target.value)} placeholder="name@example.com, ..." /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" disabled={busy} onClick={send}>{busy ? "جارٍ الإرسال…" : "إرسال"}</button></div>
  </Modal>;
}
function dedupe(a) { const s = {}, o = []; a.forEach(x => { if (x && !s[x]) { s[x] = 1; o.push(x); } }); return o; }
function dedupeEmails(a) { const s = {}, o = []; a.forEach(x => { if (x.email && x.email.indexOf("@") > 0 && !s[x.email]) { s[x.email] = 1; o.push(x); } }); return o; }
function RepTx({ flt, total, custName, catName }) {
  const avg = flt.length ? Math.round(total / flt.length) : 0;
  return (<div className="stack">
    <div className="kpi-row"><Kpi label="عدد الحركات" v={flt.length} u="" tone="navy" /><Kpi label="إجمالى المصروف" v={fmt(total)} u="ج.م" tone="teal" /><Kpi label="متوسط الحركة" v={fmt(avg)} u="ج.م" tone="amber" /></div>
    <div className="panel"><div className="table-wrap"><table className="tbl">
      <thead><tr><th>التاريخ</th><th>العهدة</th><th>البند</th><th>البيان</th><th>المبلغ</th><th>الحالة</th></tr></thead>
      <tbody>{flt.slice().reverse().map(e => <tr key={e.id}><td style={{ whiteSpace: "nowrap", color: "var(--ink-soft)" }}>{e.date}</td><td>{custName(e.custody_id)}</td><td>{catName(e)}</td><td style={{ color: "var(--ink-soft)", fontSize: 12.5 }}>{e.description}</td><td className="num">{fmt(e.amount)}</td><td><ApprovalChip s={e.approval} sett={yes(e.settled)} /></td></tr>)}
        {flt.length === 0 && <tr><td colSpan="6"><div className="empty">لا توجد حركات مطابقة.</div></td></tr>}</tbody>
    </table></div></div>
  </div>);
}
function RepByItem({ flt, catName, total }) {
  const map = {}; flt.forEach(e => { const k = catName(e); map[k] = (map[k] || 0) + Number(e.amount || 0); });
  const rows = Object.entries(map).map(([name, v]) => ({ name, v })).sort((a, b) => b.v - a.v);
  const max = rows.length ? rows[0].v : 1;
  return (<div className="panel"><h3 className="panel-title">المصروف حسب البند {rows[0] && <span style={{ fontSize: 12, color: "var(--ink-soft)" }}>· أعلى بند: {rows[0].name}</span>}</h3>
    {rows.length === 0 ? <div className="empty">لا توجد بيانات.</div> : <div className="table-wrap"><table className="tbl">
      <thead><tr><th>البند</th><th>المبلغ</th><th>النسبة</th><th>التوزيع</th></tr></thead>
      <tbody>{rows.map((r, i) => <tr key={i}><td style={{ fontWeight: 600 }}>{r.name}</td><td className="num">{fmt(r.v)}</td><td className="num">{total ? Math.round(r.v / total * 100) : 0}%</td>
        <td style={{ minWidth: 160 }}><div className="bar"><div className="bar-fill" style={{ width: (r.v / max * 100) + "%", background: i === 0 ? "var(--red)" : "var(--teal)" }} /></div></td></tr>)}
        <tr className="tot"><td>الإجمالى</td><td className="num">{fmt(total)}</td><td>100%</td><td></td></tr></tbody>
    </table></div>}
  </div>);
}
function RepPettySchool({ data, calc, school, typeF }) {
  const custs = data.custodies.filter(c => (school === "all" || String(c.school_id) === school) && (typeF === "all" || unitCat(data, c.school_id) === typeF));
  const agg = {};
  custs.forEach(c => { const k = c.school_id; (agg[k] = agg[k] || { iss: 0, sp: 0, n: 0 }); agg[k].iss += custIssued(data, c); agg[k].sp += (calc.spentByCustody[c.id] || 0); agg[k].n += 1; });
  const rows = Object.entries(agg).map(([k, v]) => ({ k, ...v, rem: v.iss - v.sp, name: (data.schools.find(s => String(s.id) === String(k)) || {}).name || "—", cat: unitCat(data, k) }));
  const totRem = rows.reduce((a, r) => a + r.rem, 0);
  return (<div className="panel"><h3 className="panel-title">Petty Cash — السيولة المتاحة لكل مدرسة/جهة <span style={{ fontSize: 12, color: "var(--ink-soft)" }}>· الإجمالى {fmt(totRem)} ج.م</span></h3>
    {rows.length === 0 ? <div className="empty">لا توجد عهد.</div> : <div className="table-wrap"><table className="tbl">
      <thead><tr><th>المدرسة / الجهة</th><th>النوع</th><th>عدد العهد</th><th>المستلم</th><th>المصروف</th><th>المتبقى (السيولة)</th></tr></thead>
      <tbody>{rows.map(r => <tr key={r.k}><td style={{ fontWeight: 600 }}>{r.name}</td><td><span className="chip navy">{CAT_LABEL[r.cat]}</span></td><td className="num">{r.n}</td><td className="num">{fmt(r.iss)}</td><td className="num amber">{fmt(r.sp)}</td><td className={"num " + (r.rem >= 0 ? "green" : "red")}><b>{fmt(r.rem)}</b></td></tr>)}
        <tr className="tot"><td>الإجمالى</td><td></td><td></td><td className="num">{fmt(rows.reduce((a, r) => a + r.iss, 0))}</td><td className="num">{fmt(rows.reduce((a, r) => a + r.sp, 0))}</td><td className="num green">{fmt(totRem)}</td></tr>
      </tbody></table></div>}
  </div>);
}
function RepOfficer({ data, calc }) {
  const agg = {};
  data.custodies.forEach(c => { const key = c.holder || c.user || "—"; (agg[key] = agg[key] || { iss: 0, sp: 0, n: 0, custodies: [] }); agg[key].iss += custIssued(data, c); agg[key].sp += (calc.spentByCustody[c.id] || 0); agg[key].n += 1; agg[key].custodies.push(c.label); });
  const rows = Object.entries(agg).map(([k, v]) => ({ k, ...v, rem: v.iss - v.sp })).sort((a, b) => b.rem - a.rem);
  return (<div className="panel"><h3 className="panel-title">ملخص لكل مسئول عهدة</h3>
    {rows.length === 0 ? <div className="empty">لا توجد عهد.</div> : <div className="table-wrap"><table className="tbl">
      <thead><tr><th>المسئول</th><th>العهد</th><th>عددها</th><th>المستلم</th><th>المصروف</th><th>المتبقى</th></tr></thead>
      <tbody>{rows.map(r => <tr key={r.k}><td style={{ fontWeight: 600 }}>{r.k}</td><td style={{ fontSize: 12, color: "var(--ink-soft)" }}>{r.custodies.join("، ")}</td><td className="num">{r.n}</td><td className="num">{fmt(r.iss)}</td><td className="num amber">{fmt(r.sp)}</td><td className={"num " + (r.rem >= 0 ? "green" : "red")}><b>{fmt(r.rem)}</b></td></tr>)}</tbody>
    </table></div>}
  </div>);
}
function RepBalances({ data, calc, flt, cust, school, typeF }) {
  const custodies = data.custodies.filter(c => (cust === "all" || String(c.id) === cust) && (school === "all" || String(c.school_id) === school) && (!typeF || typeF === "all" || unitCat(data, c.school_id) === typeF));
  const spentInPeriod = {}; flt.forEach(e => { spentInPeriod[e.custody_id] = (spentInPeriod[e.custody_id] || 0) + Number(e.amount || 0); });
  return (<div className="panel"><h3 className="panel-title">أرصدة العهد المتبقية</h3>
    <div className="table-wrap"><table className="tbl">
      <thead><tr><th>العهدة</th><th>المسئول</th><th>المستلمة</th><th>المصروف الكلى</th><th>المتبقى</th><th>مصروف الفترة</th><th>الحالة</th></tr></thead>
      <tbody>{custodies.map(c => { const issued = custIssued(data, c); const spent = calc.spentByCustody[c.id] || 0; const rem = issued - spent; const pct = issued ? rem / issued * 100 : 0; const low = pct <= 10; return (
        <tr key={c.id} className={low ? "def" : ""}><td style={{ fontWeight: 600 }}>{c.label}</td><td>{c.holder}</td><td className="num">{fmt(issued)}</td><td className="num amber">{fmt(spent)}</td>
          <td className={"num " + (rem <= 0 ? "red" : "green")}><b>{fmt(rem)}</b></td><td className="num">{fmt(spentInPeriod[c.id] || 0)}</td>
          <td>{rem <= 0 ? <span className="chip red">نفدت</span> : low ? <span className="chip amber">أوشكت</span> : <span className="chip green">جيدة</span>}</td></tr>); })}
        {custodies.length === 0 && <tr><td colSpan="7"><div className="empty">لا توجد عهد.</div></td></tr>}</tbody>
    </table></div>
  </div>);
}
function RepBudget({ data, flt, school, typeF }) {
  if (!data.lines || data.lines.length === 0) return <div className="panel"><div className="empty">تحليل الموازنة متاح للأدوار التى ترى الموازنات.</div></div>;
  const schools = data.schools.filter(s => (school === "all" || String(s.id) === school) && (!typeF || typeF === "all" || (s.category || "school") === typeF));
  const actualByLine = {}; flt.forEach(e => { if (e.line_id && yes(e.settled)) actualByLine[e.line_id] = (actualByLine[e.line_id] || 0) + Number(e.amount || 0); });
  return (<div className="stack">{schools.map(sc => {
    const lines = data.lines.filter(l => String(l.school_id) === String(sc.id));
    const secs = {}; lines.forEach(l => { (secs[l.section] = secs[l.section] || []).push(l); });
    const grandA = lines.reduce((a, l) => a + Number(l.allocated || 0), 0);
    const grandSp = lines.reduce((a, l) => a + (actualByLine[l.id] || 0), 0);
    return (<div className="panel" key={sc.id}>
      <h3 className="panel-title">{sc.name} — تنفيذ الموازنة <span style={{ fontSize: 12, color: "var(--ink-soft)" }}>({grandA ? Math.round(grandSp / grandA * 100) : 0}% منفّذ)</span></h3>
      <div className="table-wrap"><table className="tbl">
        <thead><tr><th>البند</th><th>الموازنة</th><th>الفعلى (الفترة)</th><th>المتبقى</th><th>%</th><th>التنفيذ</th></tr></thead>
        <tbody>{Object.entries(secs).map(([secName, its]) => {
          const sa = its.reduce((a, l) => a + Number(l.allocated || 0), 0); const ss = its.reduce((a, l) => a + (actualByLine[l.id] || 0), 0);
          return (<React.Fragment key={secName}>
            <tr className="sec"><td>{secName}</td><td className="num">{fmt(sa)}</td><td className="num">{fmt(ss)}</td><td className="num">{fmt(sa - ss)}</td><td className="num">{sa ? Math.round(ss / sa * 100) : 0}%</td><td></td></tr>
            {its.map(l => { const a = Number(l.allocated || 0); const sp = actualByLine[l.id] || 0; const pct = a ? Math.min(100, Math.round(sp / a * 100)) : 0; return (
              <tr key={l.id}><td>{l.name}</td><td className="num">{fmt(a)}</td><td className="num teal">{fmt(sp)}</td><td className={"num " + (a - sp < 0 ? "red" : "green")}>{fmt(a - sp)}</td><td className="num">{pct}%</td>
                <td style={{ minWidth: 120 }}><div className="bar"><div className="bar-fill" style={{ width: pct + "%", background: pct > 90 ? "var(--red)" : "var(--teal)" }} /></div></td></tr>); })}
          </React.Fragment>);
        })}
          <tr className="tot"><td>الإجمالى</td><td className="num">{fmt(grandA)}</td><td className="num teal">{fmt(grandSp)}</td><td className="num green">{fmt(grandA - grandSp)}</td><td className="num">{grandA ? Math.round(grandSp / grandA * 100) : 0}%</td><td></td></tr>
        </tbody>
      </table></div>
    </div>);
  })}</div>);
}
function RepDocs({ flt, custName, catName }) {
  const rows = flt.filter(e => e.approval === "approved" && !yes(e.settled)).map(e => ({ e, age: daysSince(e.date), miss: !e.doc_url })).sort((a, b) => b.age - a.age);
  return (<div className="panel"><h3 className="panel-title">متابعة المستندات (معتمد وغير مُسوّى)</h3>
    {rows.length === 0 ? <div className="empty">لا توجد بنود معلّقة — كل شىء مُسوّى ✅</div> : <div className="table-wrap"><table className="tbl">
      <thead><tr><th>التاريخ</th><th>العهدة</th><th>البند</th><th>المبلغ</th><th>عمر البند</th><th>المستند</th><th>المراجعة</th></tr></thead>
      <tbody>{rows.map(({ e, age, miss }) => <tr key={e.id} className={age > 14 ? "def" : ""}><td style={{ whiteSpace: "nowrap", color: "var(--ink-soft)" }}>{e.date}</td><td>{custName(e.custody_id)}</td><td>{catName(e)}</td><td className="num">{fmt(e.amount)}</td>
        <td className="num">{age} يوم</td><td>{miss ? <span className="chip amber">بلا مستند</span> : <span className="chip navy">مرفوع</span>}</td><td>{e.review_status === "ناقص" ? <span className="chip red">ناقص</span> : <span className="chip gray">بانتظار المراجعة</span>}</td></tr>)}</tbody>
    </table></div>}
  </div>);
}

/* ============================================================ النوافذ ============================================================ */
function Modals({ modal, data, act, close, showToast }) {
  const done = async (action, payload, msg) => { try { const r = await act(action, payload); showToast((msg || "تم الحفظ") + (r && r.mail ? " · " + r.mail : "")); close(); } catch {} };
  if (modal.type === "custody") return <CustodyModal data={data} initial={modal.payload} onSave={(c, isNew) => done(isNew ? "addCustody" : "updateCustody", isNew ? { custody: c } : { id: c.id, patch: c }, "تم حفظ العهدة")} close={close} />;
  if (modal.type === "tranche") return <TrancheModal custody={modal.payload} onSave={t => done("addTranche", { tranche: t }, "تمت إضافة العهدة")} close={close} />;
  if (modal.type === "approve") return <ApproveModal e={modal.payload} data={data} onDecide={(dec, by, note) => done("updateExpense", { id: modal.payload.id, patch: { approval: dec, approved_by: by, note } }, dec === "approved" ? "تم الاعتماد" : "تم الرفض")} close={close} />;
  if (modal.type === "import") return <ImportModal data={data} school_id={modal.payload && modal.payload.school_id} act={act} onDone={(msg) => { showToast(msg); close(); }} close={close} />;
  if (modal.type === "editExpense") return <EditExpenseModal data={data} e={modal.payload} onSave={patch => done("updateExpense", { id: modal.payload.id, patch }, "تم تعديل الصرف")} close={close} />;
  if (modal.type === "central") return <CentralModal data={data} school_id={modal.payload.school_id} act={act} onDone={(msg) => { showToast(msg || "تم تسجيل الشراء المركزى"); close(); }} close={close} />;
  if (modal.type === "review") return <ReviewModal e={modal.payload} onSave={patch => done("reviewExpense", { id: modal.payload.id, patch }, patch.settled ? "تمت التسوية والخصم من الموازنة" : "تم إرسال الملاحظة لصاحب التسوية")} close={close} />;
  if (modal.type === "school") return <SchoolModal initial={modal.payload} onSave={(s, isNew) => done(isNew ? "addSchool" : "updateSchool", isNew ? { school: s } : { id: s.id, patch: s }, "تم حفظ المدرسة")} close={close} />;
  if (modal.type === "line") return <LineModal initial={modal.payload} onSave={(l, isNew) => done(isNew ? "addLine" : "updateLine", isNew ? { line: l } : { id: l.id, patch: l }, "تم حفظ البند")} close={close} />;
  if (modal.type === "user") return <UserModal initial={modal.payload} data={data} onSave={(u, isNew) => done(isNew ? "addUser" : "updateUser", isNew ? { user: u } : { id: u.id, patch: u }, "تم حفظ المستخدم")} close={close} />;
  return null;
}
function Modal({ title, children, close, wide }) {
  return <div className="overlay" onMouseDown={close}><div className={"modal " + (wide ? "wide" : "")} onMouseDown={e => e.stopPropagation()}>
    <div className="modal-head"><h3>{title}</h3><button className="close" onClick={close}>×</button></div><div className="modal-body">{children}</div></div></div>;
}
function F({ label, children }) { return <label className="field"><span>{label}</span>{children}</label>; }

function CustodyModal({ data, initial, onSave, close }) {
  const [label, setLabel] = useState(initial ? initial.label : "");
  const [holder, setHolder] = useState(initial ? initial.holder : (data.holders[0] ? data.holders[0].name : ""));
  const [school_id, setSchool] = useState(initial ? initial.school_id : (data.schools[0] ? data.schools[0].id : ""));
  const [userName, setUserName] = useState(initial ? (initial.user || "") : "");
  const [note, setNote] = useState(initial ? initial.note : "");
  const accountants = (data.users || []).filter(u => u.role !== "manager");
  const save = () => { if (!label.trim()) return; const c = { label: label.trim(), holder, school_id, note, user: userName }; if (initial) { c.id = initial.id; onSave(c, false); } else { onSave(c, true); } };
  return <Modal title={initial ? "تعديل العهدة" : "عهدة جديدة"} close={close}>
    <F label="مسمّى العهدة"><input value={label} onChange={e => setLabel(e.target.value)} /></F>
    <F label="اسم المسئول (للعرض)"><select value={holder} onChange={e => setHolder(e.target.value)}>{data.holders.map(h => <option key={h.id} value={h.name}>{h.name} — {h.title}</option>)}</select></F>
    <F label="المستخدم المسئول (يرى هذه العهدة فقط)">
      <select value={userName} onChange={e => setUserName(e.target.value)}>
        <option value="">— بدون ربط —</option>
        {accountants.map(u => <option key={u.id} value={u.username}>{u.name} ({u.username})</option>)}
      </select>
    </F>
    <F label="المدرسة"><select value={school_id} onChange={e => setSchool(e.target.value)}>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category||"school"]} · {s.name}</option>)}</select></F>
    <F label="ملاحظات"><input value={note} onChange={e => setNote(e.target.value)} /></F>
    {!initial && <div style={{ fontSize: 12, color: "var(--ink-soft)" }}>ملاحظة: أضف قيمة العهدة من زر «إضافة عهدة» بعد الحفظ.</div>}
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={save}>حفظ</button></div>
  </Modal>;
}
function TrancheModal({ custody, onSave, close }) {
  const [amount, setAmount] = useState(""); const [date, setDate] = useState(today()); const [note, setNote] = useState("");
  return <Modal title={"إضافة عهدة — " + custody.label} close={close}>
    <div className="grid2"><F label="القيمة (ج.م)"><input type="number" value={amount} onChange={e => setAmount(e.target.value)} /></F><F label="التاريخ"><input type="date" value={date} onChange={e => setDate(e.target.value)} /></F></div>
    <F label="ملاحظة"><input value={note} onChange={e => setNote(e.target.value)} placeholder="تعزيز / دفعة ثانية…" /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn teal" onClick={() => amount && onSave({ custody_id: custody.id, amount: Number(amount), date, note })}>إضافة</button></div>
  </Modal>;
}
function ApproveModal({ e, data, onDecide, close }) {
  const [by, setBy] = useState(data.approvers[0] ? data.approvers[0].name : ""); const [note, setNote] = useState("");
  return <Modal title="مراجعة واعتماد المصروف" close={close}>
    <div style={{ background: "#F6F9FB", border: "1px solid var(--line)", borderRadius: 12, padding: 14, marginBottom: 14 }}>
      <div style={{ fontFamily: "Cairo", fontWeight: 800, fontSize: 22, color: "var(--navy)" }}>{fmt(e.amount)} ج.م</div>
      <div style={{ margin: "6px 0" }}>{e.description}</div><div style={{ fontSize: 12, color: "var(--ink-soft)" }}>البند: {e.spend_item || lineName(data, e.line_id)} · {e.date} · أدخله: {e.created_by}</div>
    </div>
    <F label="المعتمِد"><select value={by} onChange={e2 => setBy(e2.target.value)}>{data.approvers.map(a => <option key={a.id} value={a.name}>{a.name}</option>)}</select></F>
    <F label="ملاحظة"><input value={note} onChange={e2 => setNote(e2.target.value)} /></F>
    <div className="modal-actions"><button className="btn danger-ghost" onClick={() => onDecide("rejected", by, note)}>رفض</button><span className="spacer" /><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={() => onDecide("approved", by, note)}>اعتماد</button></div>
  </Modal>;
}
function ImportModal({ data, school_id, act, onDone, close }) {
  const [mode, setMode] = useState(school_id ? "existing" : "new");
  const [sid, setSid] = useState(school_id || (data.schools[0] ? data.schools[0].id : ""));
  const [newName, setNewName] = useState(""); const [newCat, setNewCat] = useState("school");
  const [parsed, setParsed] = useState(null); const [err, setErr] = useState(""); const [busy, setBusy] = useState(false); const fileRef = useRef();
  const onFile = async (f) => {
    if (!f) return; setErr(""); setParsed(null);
    try { const res = await readBudgetFile(f); if (!res.lines.length) { setErr("لم يتم العثور على بنود — تأكد من أن الملف يحتوى عمود «البند» وعمود القيمة."); return; } setParsed(Object.assign({ fileName: f.name }, res)); }
    catch (e) { setErr(e.message || "تعذّر قراءة الملف"); }
  };
  const doImport = async () => {
    if (!parsed) return;
    if (mode === "new" && !newName.trim()) { setErr("اكتب اسم الجهة الجديدة"); return; }
    setBusy(true);
    const payload = { lines: parsed.lines };
    if (mode === "new") payload.newSchool = { name: newName.trim(), category: newCat, type: CAT_LABEL[newCat], period: "2026/2027", students: 0 };
    else payload.school_id = sid;
    try { const r = await act("importBudget", payload); onDone(`تم استيراد ${r && r.count || parsed.lines.length} بنداً بنجاح`); }
    catch { setBusy(false); }
  };
  return <Modal title="استيراد موازنة من Excel / CSV" close={close} wide>
    <div style={{ fontSize: 12.5, color: "var(--ink-soft)", marginBottom: 12, lineHeight: 1.7 }}>
      يقرأ النظام ملفات الموازنة بنفس تنسيق موازنات بدر ودمياط (عمود «البند» و«الأجمالى» مع الأقسام)، أو أى ملف بأعمدة: القسم / البند / الموازنة. تُستبدل بنود الجهة المختارة بالبنود المستوردة.
    </div>
    <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
      <button className={"btn sm " + (mode === "existing" ? "primary" : "ghost")} onClick={() => setMode("existing")}>جهة موجودة</button>
      <button className={"btn sm " + (mode === "new" ? "primary" : "ghost")} onClick={() => setMode("new")}>جهة جديدة</button>
    </div>
    {mode === "existing"
      ? <F label="الجهة المستهدفة (ستُستبدل موازنتها)"><select value={sid} onChange={e => setSid(e.target.value)}>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category || "school"]} · {s.name}</option>)}</select></F>
      : <div className="grid2"><F label="اسم الجهة الجديدة"><input value={newName} onChange={e => setNewName(e.target.value)} placeholder="مثال: مدرسة ابدأ — القاهرة" /></F><F label="النوع"><select value={newCat} onChange={e => setNewCat(e.target.value)}>{CAT_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></F></div>}
    <F label="ملف الموازنة (.xlsx أو .csv)"><div className="file-row"><button className="btn ghost sm" onClick={() => fileRef.current && fileRef.current.click()}>اختيار ملف</button><input ref={fileRef} type="file" hidden accept=".xlsx,.xls,.csv" onChange={e => onFile(e.target.files[0])} />{parsed && <span className="file-name">📎 {parsed.fileName}</span>}</div></F>
    {err && <div className="warn-banner" style={{ background: "#FBE1E2", color: "#A31820" }}>{err}</div>}
    {parsed && <div style={{ background: "#F4FBF7", border: "1px solid var(--line)", borderRadius: 10, padding: 12, marginBottom: 12 }}>
      <div style={{ fontWeight: 700, color: "var(--green)" }}>تمت القراءة: {parsed.lines.length} بند · إجمالى {fmt(parsed.total)} ج.م</div>
      <div style={{ fontSize: 12, color: "var(--ink-soft)", marginTop: 6, maxHeight: 120, overflow: "auto" }}>{parsed.lines.slice(0, 6).map((l, i) => <div key={i}>• {l.section} — {l.name}: {fmt(l.allocated)}</div>)}{parsed.lines.length > 6 && <div>… و{parsed.lines.length - 6} بند آخر</div>}</div>
    </div>}
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" disabled={!parsed || busy} onClick={doImport}>{busy ? "جارٍ الاستيراد…" : "استيراد وحفظ"}</button></div>
  </Modal>;
}

function EditExpenseModal({ data, e, onSave, close }) {
  const lines = data.lines.filter(l => String(l.school_id) === String(e.school_id));
  const [lineId, setLineId] = useState(e.line_id || (lines[0] ? lines[0].id : ""));
  const [amount, setAmount] = useState(e.amount); const [date, setDate] = useState(e.date || today()); const [desc, setDesc] = useState(e.description || "");
  const save = () => { if (!amount) return; onSave({ date, line_id: lineId, amount: Number(amount) || 0, description: desc.trim() }); };
  return <Modal title="تعديل الصرف" close={close}>
    <div style={{ fontSize: 12, color: "var(--ink-soft)", marginBottom: 10 }}>يمكن التعديل طالما لم يُعتمد الصرف بعد.</div>
    {lines.length > 0 && <F label="بند الموازنة"><select value={lineId} onChange={ev => setLineId(ev.target.value)}>{lines.map(l => <option key={l.id} value={l.id}>{l.section ? l.section + " — " : ""}{l.name}</option>)}</select></F>}
    <div className="grid2"><F label="المبلغ (ج.م)"><input type="number" value={amount} onChange={ev => setAmount(ev.target.value)} /></F><F label="التاريخ"><input type="date" value={date} onChange={ev => setDate(ev.target.value)} /></F></div>
    <F label="البيان"><input value={desc} onChange={ev => setDesc(ev.target.value)} /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={save}>حفظ</button></div>
  </Modal>;
}
function CentralModal({ data, school_id, act, onDone, close }) {
  const [sid, setSid] = useState(school_id || (data.schools[0] ? data.schools[0].id : ""));
  const lines = data.lines.filter(l => String(l.school_id) === String(sid));
  const [lineId, setLineId] = useState(lines[0] ? lines[0].id : "");
  const [amount, setAmount] = useState(""); const [date, setDate] = useState(today()); const [desc, setDesc] = useState("");
  const [file, setFile] = useState(null); const fileRef = useRef(); const [busy, setBusy] = useState(false);
  useEffect(() => { const ls = data.lines.filter(l => String(l.school_id) === String(sid)); setLineId(ls[0] ? ls[0].id : ""); }, [sid]);
  const pick = (f) => { if (!f) return; if (f.size > 4.5 * 1024 * 1024) { alert("حجم الملف أكبر من 4.5 ميجا"); return; } const fr = new FileReader(); fr.onload = () => setFile({ name: f.name, type: f.type, dataUrl: fr.result }); fr.readAsDataURL(f); };
  const save = async () => {
    if (!amount || !lineId) return; setBusy(true);
    const payload = { expense: { school_id: sid, line_id: lineId, amount: Number(amount) || 0, date, description: desc.trim() } };
    if (file) { payload.dataUrl = file.dataUrl; payload.dataBase64 = String(file.dataUrl).split(",")[1]; payload.mimeType = file.type; payload.filename = file.name; }
    try { await act("addCentral", payload); onDone("تم تسجيل الشراء المركزى وخصمه من الموازنة"); } catch { setBusy(false); }
  };
  return <Modal title="تسجيل شراء مركزى (يُخصم من الموازنة مباشرة)" close={close}>
    <F label="المدرسة"><select value={sid} onChange={e => setSid(e.target.value)}>{data.schools.map(s => <option key={s.id} value={s.id}>{CAT_LABEL[s.category||"school"]} · {s.name}</option>)}</select></F>
    <F label="بند الموازنة"><select value={lineId} onChange={e => setLineId(e.target.value)}>{lines.map(l => <option key={l.id} value={l.id}>{l.section ? l.section + " — " : ""}{l.name}</option>)}</select></F>
    <div className="grid2"><F label="المبلغ (ج.م)"><input type="number" value={amount} onChange={e => setAmount(e.target.value)} /></F><F label="التاريخ"><input type="date" value={date} onChange={e => setDate(e.target.value)} /></F></div>
    <F label="البيان"><input value={desc} onChange={e => setDesc(e.target.value)} placeholder="ما تم شراؤه مركزياً" /></F>
    <F label="مستند الشراء (اختيارى)"><div className="file-row"><button className="btn ghost sm" onClick={() => fileRef.current && fileRef.current.click()}>{file ? "تغيير الملف" : "رفع ملف"}</button><input ref={fileRef} type="file" hidden accept="image/*,application/pdf" onChange={e => pick(e.target.files[0])} />{file && <span className="file-name">📎 {file.name}</span>}</div></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" disabled={busy} onClick={save}>{busy ? "…" : "تسجيل الشراء"}</button></div>
  </Modal>;
}

function ReviewModal({ e, onSave, close }) {
  const [status, setStatus] = useState(e.review_status || "مستوفى");
  const [note, setNote] = useState(e.review_note || "");
  const save = () => {
    if (status === "مستوفى") onSave({ review_status: "مستوفى", settled: "نعم", review_note: note.trim() });
    else { if (!note.trim()) { alert("اكتب ملاحظة توضّح النقص المطلوب استيفاؤه"); return; } onSave({ review_status: "ناقص", settled: "", review_note: note.trim() }); }
  };
  return <Modal title="مراجعة المستند" close={close}>
    <div style={{ marginBottom: 10 }}>{fmt(e.amount)} ج.م — {e.description}</div>
    {e.doc_url && <a className="btn ghost sm" href={e.doc_url} target="_blank" rel="noreferrer" style={{ marginBottom: 12, display: "inline-block" }}>📎 فتح المستند المرفوع</a>}
    <F label="نتيجة المراجعة">
      <select value={status} onChange={ev => setStatus(ev.target.value)}>
        <option value="مستوفى">المستند مستوفٍ — تمت التسوية</option>
        <option value="ناقص">المستند ناقص — إرسال ملاحظة لمسئول العهدة</option>
      </select>
    </F>
    <F label="ملاحظة"><input value={note} onChange={ev => setNote(ev.target.value)} placeholder={status === "ناقص" ? "سبب عدم الاستيفاء المطلوب" : "اختيارى"} /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className={"btn " + (status === "مستوفى" ? "teal" : "primary")} onClick={save}>{status === "مستوفى" ? "تأكيد التسوية" : "إرسال الملاحظة"}</button></div>
  </Modal>;
}
function SchoolModal({ initial, onSave, close }) {
  const [name, setName] = useState(initial ? initial.name : ""); const [category, setCategory] = useState(initial ? (initial.category || "school") : "school"); const [period, setPeriod] = useState(initial ? initial.period : "2026/2027"); const [students, setStudents] = useState(initial ? initial.students : "");
  const save = () => { if (!name.trim()) return; const s = { name: name.trim(), category, type: CAT_LABEL[category] || "جهة", period, students: Number(students) || 0 }; if (initial) { s.id = initial.id; s.active = initial.active; onSave(s, false); } else onSave(s, true); };
  return <Modal title={initial ? "تعديل الجهة" : "جهة / وحدة جديدة"} close={close}>
    <F label="الاسم"><input value={name} onChange={e => setName(e.target.value)} placeholder="اسم المدرسة / الشركة / الدورة" /></F>
    <div className="grid2"><F label="النوع (التصنيف)"><select value={category} onChange={e => setCategory(e.target.value)}>{CAT_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></F><F label="عدد الطلاب/المتدربين"><input type="number" value={students} onChange={e => setStudents(e.target.value)} /></F></div>
    <F label="الفترة"><input value={period} onChange={e => setPeriod(e.target.value)} /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={save}>حفظ</button></div>
  </Modal>;
}
function LineModal({ initial, onSave, close }) {
  const [name, setName] = useState(initial && initial.name ? initial.name : ""); const [section, setSection] = useState(initial && initial.section ? initial.section : "تكلفة التشغيل"); const [allocated, setAllocated] = useState(initial && initial.allocated !== undefined ? initial.allocated : ""); const [note, setNote] = useState(initial && initial.note ? initial.note : "");
  const editing = initial && initial.id;
  const save = () => { if (!name.trim()) return; const l = { school_id: initial.school_id, section: section.trim(), name: name.trim(), allocated: Number(allocated) || 0, note }; if (editing) { l.id = initial.id; onSave(l, false); } else onSave(l, true); };
  return <Modal title={editing ? "تعديل البند" : "إضافة بند"} close={close}>
    <F label="القسم"><input value={section} onChange={e => setSection(e.target.value)} placeholder="تكلفة التدريس / التشغيل / إدارية…" /></F>
    <F label="اسم البند"><input value={name} onChange={e => setName(e.target.value)} /></F>
    <F label="الموازنة السنوية (ج.م)"><input type="number" value={allocated} onChange={e => setAllocated(e.target.value)} /></F>
    <F label="ملاحظات"><input value={note} onChange={e => setNote(e.target.value)} /></F>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={save}>حفظ</button></div>
  </Modal>;
}
function UserModal({ initial, data, onSave, close }) {
  const [name, setName] = useState(initial ? initial.name : ""); const [username, setUsername] = useState(initial ? initial.username : ""); const [pin, setPin] = useState(initial ? initial.pin : "");
  const [email, setEmail] = useState(initial ? (initial.email || "") : "");
  const [role, setRole] = useState(initial ? initial.role : "custody");
  const [allSchools, setAllSchools] = useState(initial ? initial.schools === "*" : false);
  const [schools, setSchools] = useState(initial && initial.schools !== "*" ? String(initial.schools).split(",").map(s => s.trim()).filter(Boolean) : []);
  const [active, setActive] = useState(initial ? yes(initial.active) : true);
  const toggle = (id) => setSchools(s => s.indexOf(id) >= 0 ? s.filter(x => x !== id) : [...s, id]);
  const save = () => {
    if (!name.trim() || !username.trim() || !pin) return;
    const u = { name: name.trim(), username: username.trim(), pin: String(pin), email: email.trim(), role, schools: (role === "manager" || allSchools) ? "*" : schools.join(","), active: active ? "نعم" : "لا" };
    if (initial) { u.id = initial.id; onSave(u, false); } else onSave(u, true);
  };
  return <Modal title={initial ? "تعديل مستخدم" : "مستخدم جديد"} close={close}>
    <div className="grid2"><F label="الاسم"><input value={name} onChange={e => setName(e.target.value)} /></F><F label="الإيميل (للإشعارات)"><input value={email} onChange={e => setEmail(e.target.value)} placeholder="name@ebda.com.eg" /></F></div>
    <div className="grid2"><F label="اسم المستخدم"><input value={username} onChange={e => setUsername(e.target.value)} /></F><F label="كلمة السر (PIN)"><input value={pin} onChange={e => setPin(e.target.value)} /></F></div>
    <F label="الدور">
      <select value={role} onChange={e => setRole(e.target.value)}>
        <option value="manager">مدير البرنامج (كل شىء)</option>
        <option value="accountant">محاسب المتابعة (موازنات بلا تعديل + مراجعة المستندات)</option>
        <option value="supervisor">مدير مباشر (موازنات بلا تعديل + اعتماد)</option>
        <option value="custody">مسئول عهدة (تسجيل الصرف ورفع المستندات)</option>
      </select>
    </F>
    {role !== "manager" && <div style={{ marginBottom: 12 }}>
      <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13, marginBottom: 8 }}><input type="checkbox" checked={allSchools} onChange={e => setAllSchools(e.target.checked)} /> كل المدارس</label>
      {!allSchools && <div className="chips-list">{data.schools.map(s => <label key={s.id} className="cat-chip" style={{ cursor: "pointer" }}><input type="checkbox" checked={schools.indexOf(s.id) >= 0} onChange={() => toggle(s.id)} /> {s.name}</label>)}</div>}
      {role === "custody" && <div style={{ fontSize: 12, color: "var(--ink-soft)", marginTop: 6 }}>اربط هذا المستخدم بعهدته من تبويب «العهد ‹ المستخدم المسئول».</div>}
    </div>}
    <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}><input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} /> الحساب مفعّل</label>
    <div className="modal-actions"><button className="btn ghost" onClick={close}>إلغاء</button><button className="btn primary" onClick={save}>حفظ</button></div>
  </Modal>;
}

/* ---- صغائر ---- */
function Kpi({ label, v, u, tone }) { return <div className={"kpi " + tone}><div className="kpi-label">{label}</div><div className="kpi-value">{v} <span className="kpi-unit">{u}</span></div></div>; }
function ApprovalChip({ s, sett }) {
  const map = { pending: ["بانتظار الاعتماد", "amber"], approved: ["معتمد", "green"], rejected: ["مرفوض", "red"] };
  const [t, c] = map[s] || ["—", "gray"];
  return <span><span className={"chip " + c}>{t}</span>{s === "approved" && (sett ? <span className="chip navy"> مُسوّى</span> : <span className="chip gray"> لم يُسوّ</span>)}</span>;
}
function lineName(data, id) { const l = (data.lines || []).find(x => String(x.id) === String(id)); return l ? l.name : null; }
function Toast({ toast }) { return toast ? <div className={"toast " + toast.kind}>{toast.msg}</div> : null; }
function Logo({ big }) {
  return <img src="logo.png" alt="ابدأ إديو" style={{ height: big ? 66 : 40, width: "auto", display: "block" }} onError={(e) => { e.target.style.display = "none"; }} />;
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
