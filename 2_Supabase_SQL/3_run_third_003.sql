-- ============================================================================
--  ابدأ إديو — Migration 003: استيراد الموازنة (دمج آمن) + تتبع التعديلات + العهد والمصروفات
--  يُشغَّل بعد 001 و 002 (Supabase ‹ SQL Editor ‹ New query ‹ الصق ‹ Run). آمن لإعادة التشغيل.
--
--  ما يفعله (إضافات فقط، لا حذف ولا إعادة إنشاء لأى بيانات):
--   • أعمدة جديدة: custodies.kind / purpose · expenses.pay_method · audit_log.txid
--   • جدول جديد ebda.audit_changes: القيمة القديمة والجديدة لكل إضافة/تعديل/حذف (يُملأ تلقائياً بـ Triggers)
--   • importBudget بوضع «دمج» (mode='merge'): يحدّث البنود المطابقة ويضيف الجديدة فقط — لا يحذف أى بند
--   • منع تكرار البند (نفس الجهة + نفس القسم + نفس الاسم) فى الإضافة والتعديل والاستيراد
--   • إنشاء عهدة بقيمتها الأساسية فى خطوة واحدة · طريقة الدفع للمصروف · تسجيل التصدير فى تتبع التعديلات
--  ⚠ بعد هذا الملف لا تُعِد تشغيل 002 (يعيد الإصدار السابق من الدالة). أعد تشغيل 003 فقط إن لزم.
-- ============================================================================

-- ---------------------------------------------------------------- أعمدة جديدة (لا تغيّر الموجود)
alter table ebda.custodies add column if not exists kind text default '';
alter table ebda.custodies add column if not exists purpose text default '';
alter table ebda.expenses  add column if not exists pay_method text default '';
alter table ebda.audit_log add column if not exists txid bigint;
alter table ebda.audit_log alter column txid set default txid_current();

insert into ebda.config(key,value) values ('custody_overdue_days','30') on conflict (key) do nothing;

-- ---------------------------------------------------------------- تطبيع النصوص العربية (للمطابقة ومنع التكرار)
-- نفس القواعد مطبقة فى الواجهة (frontend/src/lib/budget.js → normAr)
create or replace function ebda.norm_txt(t text) returns text language sql immutable as $$
  select btrim(regexp_replace(
           regexp_replace(
             btrim(regexp_replace(
               translate(lower(coalesce(t,'')), 'أإآٱىةـًٌٍَُِّْ', 'اااايه'),
             '[^0-9a-zء-ي]+', ' ', 'g')),
           '^(اولا|ثانيا|ثالثا|رابعا|خامسا|سادسا|سابعا|ثامنا|تاسعا|عاشرا)( |$)', ''),
         ' +', ' ', 'g'))
$$;

-- ---------------------------------------------------------------- تتبع التعديلات: القيمة القديمة والجديدة
create table if not exists ebda.audit_changes(
  id bigserial primary key,
  txid bigint default txid_current(),
  ts timestamptz default now(),
  actor_id text default '',
  tbl text, row_id text, op text,
  school_id text default '',
  old_v jsonb, new_v jsonb);
create index if not exists ix_auditch_tx on ebda.audit_changes(txid);
create index if not exists ix_audit_tx on ebda.audit_log(txid);

create or replace function ebda.track_change() returns trigger
language plpgsql security definer set search_path = ebda as $tc$
declare
  o jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  nw jsonb := case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end;
  k text; od jsonb := '{}'::jsonb; nd jsonb := '{}'::jsonb; sid text;
  hide text[] := array['pin','updated_at','updated_by','last_login'];
begin
  -- لا تُسجَّل كلمات السر ولا محتوى الملفات
  if o  is not null then o  := o  - 'pin'; if coalesce(o->>'doc_url','')  like 'data:%' then o  := o  || '{"doc_url":"[ملف مرفق]"}'; end if; end if;
  if nw is not null then nw := nw - 'pin'; if coalesce(nw->>'doc_url','') like 'data:%' then nw := nw || '{"doc_url":"[ملف مرفق]"}'; end if; end if;
  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(nw) loop
      if k = any(hide) then continue; end if;
      if (o->k) is distinct from (nw->k) then od := od || jsonb_build_object(k, o->k); nd := nd || jsonb_build_object(k, nw->k); end if;
    end loop;
    if (to_jsonb(old)->>'pin') is distinct from (to_jsonb(new)->>'pin') then nd := nd || '{"pin":"(تم تغيير كلمة السر)"}'; end if;
    if nd = '{}'::jsonb then return null; end if;
  else
    od := o; nd := nw;
  end if;
  sid := coalesce(nw->>'school_id', o->>'school_id', '');
  if tg_table_name = 'tranches' then
    sid := coalesce((select c.school_id from ebda.custodies c where c.id = coalesce(nw->>'custody_id', o->>'custody_id')), '');
  end if;
  insert into ebda.audit_changes(actor_id, tbl, row_id, op, school_id, old_v, new_v)
  values (coalesce(current_setting('ebda.auth_uid', true),''), tg_table_name, coalesce(nw->>'id', o->>'id', ''), lower(tg_op), sid,
          case when tg_op='INSERT' then null else od end, case when tg_op='DELETE' then null else nd end);
  return null;
end $tc$;

do $tr$
declare t text;
begin
  foreach t in array array['schools','lines','custodies','tranches','expenses','requests','users','temp_budgets'] loop
    execute format('drop trigger if exists trg_track_%1$s on ebda.%1$I', t);
    execute format('create trigger trg_track_%1$s after insert or update or delete on ebda.%1$I for each row execute function ebda.track_change()', t);
  end loop;
end $tr$;

-- ============================================================================
--  الدالة الأساسية (نفس قواعد 001 و 002 + الإضافات أعلاه)
-- ============================================================================
create or replace function ebda.api_core(req jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ebda
as $fn$
declare
  action text := req->>'action';
  a_user text := req#>>'{auth,username}';
  a_pin  text := req#>>'{auth,pin}';
  u ebda.users;
  xu ebda.users;
  cust ebda.custodies;
  ex ebda.expenses;
  rq ebda.requests;
  sid text;
  newid text;
  patch jsonb;
  ln jsonb;
  res jsonb;
  catv text;
  dj jsonb;
  urole text;
  n numeric;
  tok text;
  n_new int := 0;
  n_upd int := 0;
  n_same int := 0;
  lrow ebda.lines;
  lid text;
begin
  -- ------------------------------------------------------------ النسخ الاحتياطى (برمز سرّى)
  if action in ('dumpAll','syncExport') then
    tok := coalesce((select value from ebda.config where key='backup_token'),'');
    if tok = '' or tok = 'CHANGE_ME_TO_A_SECRET' then
      return ebda.err('غيّر رمز النسخ الاحتياطى أولاً: update ebda.config set value=''<رمز سرى طويل>'' where key=''backup_token''');
    end if;
    if coalesce(req->>'token','') <> tok then return ebda.err('رمز النسخ الاحتياطى غير صحيح'); end if;
    if action = 'dumpAll' then
      return jsonb_build_object('ok',true,
        'users',(select coalesce(jsonb_agg(ebda.user_public(x)),'[]') from ebda.users x),
        'schools',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.schools x),
        'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.lines x),
        'custodies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.custodies x),
        'tranches',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.tranches x),
        'expenses',(select coalesce(jsonb_agg(to_jsonb(x) - 'doc_url' || jsonb_build_object('doc_url', case when x.doc_is_link like '%نعم%' then x.doc_url else '' end)),'[]') from ebda.expenses x),
        'spend_items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.spend_items x),
        'holders',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.holders x),
        'approvers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.approvers x),
        'emails',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.emails x),
        'salaries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.salaries x),
        'employees',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.employees x),
        'payslips',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.payslips x),
        'temp_budgets',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.temp_budgets x),
        'requests',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.requests x),
        'request_items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.request_items x),
        'audit_log',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.audit_log x));
    end if;
    return ebda.sync_export();
  end if;

  -- ------------------------------------------------------------ تسجيل الدخول
  if action = 'login' then
    select * into u from ebda.users
      where username = (req->>'username') and coalesce(active,'') like '%نعم%' order by id limit 1;
    if not found or not ebda.pin_ok(u.pin, req->>'pin') then
      perform ebda.audit(jsonb_populate_record(null::ebda.users, jsonb_build_object('username', req->>'username', 'name', coalesce(req->>'username',''))),
                         'loginFailed', '', jsonb_build_object('username', req->>'username'));
      return ebda.err('بيانات الدخول غير صحيحة');
    end if;
    if u.pin not like '$2%' then update ebda.users set pin = ebda.pin_hash(req->>'pin') where id=u.id; end if;
    update ebda.users set last_login = now()::text where id=u.id;
    perform ebda.audit(u, 'login', u.id, '{}'::jsonb);
    return jsonb_build_object('ok',true,'user',jsonb_build_object('id',u.id,'username',u.username,'name',u.name,
      'role',coalesce(ebda.role_legacy(u.role),u.role),'role_key',ebda.role_key(u.role),'role_label',ebda.role_label(u.role),
      'schools',u.schools,'perms',coalesce(u.perms,''),'must_reset',coalesce(u.must_reset,'لا')));
  end if;

  -- ------------------------------------------------------------ التحقق لبقية الإجراءات (كل طلب)
  if coalesce(current_setting('ebda.auth_uid', true),'') <> '' then
    select * into u from ebda.users where id=current_setting('ebda.auth_uid', true) and coalesce(active,'') like '%نعم%';
    if not found then return ebda.err('انتهت الجلسة — سجّل الدخول من جديد'); end if;
  else
    if coalesce((select value from ebda.config where key='allow_pin_auth'),'yes') = 'no' then
      return ebda.err('انتهت الجلسة — سجّل الدخول من جديد'); end if;
    select * into u from ebda.users where username=a_user and coalesce(active,'') like '%نعم%' order by id limit 1;
    if not found or not ebda.pin_ok(u.pin, a_pin) then return ebda.err('انتهت الجلسة — سجّل الدخول من جديد'); end if;
  end if;
  urole := ebda.rk(u);
  if urole = '' then return ebda.err('دور المستخدم غير معروف — راجع الأدمن'); end if;

  -- سجل التدقيق لكل إجراء تعديلى
  if action not in ('bootstrap','ping','lineStatus','notifyInfo','docAuth') then
    dj := req - 'auth' - 'pin' - 'dataBase64' - 'dataUrl' - 'html' - 'attachment';
    if dj ? 'user' then dj := dj #- '{user,pin}'; end if;
    if dj ? 'patch' then dj := dj #- '{patch,pin}'; end if;
    -- لقطة من السجل قبل الحذف
    if action = 'deleteExpense' then dj := dj || jsonb_build_object('before', (select to_jsonb(e) - 'doc_url' from ebda.expenses e where e.id=req->>'id')); end if;
    if action = 'deleteCustody' then dj := dj || jsonb_build_object('before', (select to_jsonb(c) from ebda.custodies c where c.id=req->>'id')); end if;
    if action in ('deleteLine','updateLine') then dj := dj || jsonb_build_object('before', (select to_jsonb(l) from ebda.lines l where l.id=req->>'id')); end if;
    if action in ('updateUser','deleteUser') then dj := dj || jsonb_build_object('before', (select ebda.user_public(z) from ebda.users z where z.id=req->>'id')); end if;
    perform ebda.audit(u, action, coalesce(req->>'id',''), dj);
  end if;

  if action = 'setPassword' then
    if length(coalesce(req->>'pin',''))<4 then return ebda.err('كلمة السر 4 خانات على الأقل'); end if;
    update ebda.users set pin=ebda.pin_hash(req->>'pin'), must_reset='لا' where id=u.id;
    delete from ebda.sessions where user_id=u.id and token_hash <> coalesce(current_setting('ebda.session_hash', true),'');
    return jsonb_build_object('ok',true);
  end if;

  if action = 'logExport' then  -- تسجيل عملية تصدير تقرير فى «تتبع التعديلات»
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ مساعدات القراءة (بدون سجل تدقيق)
  if action = 'lineStatus' then   -- تنبيه تجاوز البند قبل/بعد التسجيل
    return ebda.line_status(u, req->>'line_id', coalesce((req->>'amount')::numeric,0), coalesce(req->>'exclude_id',''));
  end if;
  if action = 'notifyInfo' then   -- يستدعيه Edge Function «notify» بتوكن المستخدم نفسه
    return ebda.notify_info(u, req->>'event', req->>'id');
  end if;
  if action = 'docAuth' then      -- يستدعيه Edge Function «docs» للتحقق قبل رفع/قراءة مستند من Storage
    select * into ex from ebda.expenses where id=(req->>'expense_id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    select * into cust from ebda.custodies where id=ex.custody_id;
    if (req->>'mode')='upload' then
      if not (urole='admin' or (cust.id is not null and coalesce(cust."user",'')=u.username)
              or (urole='finance_manager' and ebda.can_expense(u, ex))) then return ebda.err('لا صلاحية لرفع مستند'); end if;
    elsif not ebda.can_expense(u, ex) then return ebda.err('لا صلاحية على هذا المستند');
    end if;
    return jsonb_build_object('ok',true,'path', coalesce(nullif(ex.school_id,''),'central')||'/'||ex.id||'/',
      'current', case when ex.doc_url like 'storage:%' then substr(ex.doc_url, 9) else '' end);
  end if;

  -- ================================================================ طلبات العهد
  if action = 'addRequest' then
    if urole not in ('custody_officer','admin') then return ebda.err('طلب العهدة خاص بمسئول العهدة'); end if;
    sid := req#>>'{request,school_id}';
    if not ebda.can_school(u, sid) then return ebda.err('لا صلاحية على هذه الجهة'); end if;
    if exists(select 1 from jsonb_array_elements(coalesce(req#>'{request,items}','[]'::jsonb)) it
              where coalesce(it->>'line_id','')<>'' and not exists(select 1 from ebda.lines l where l.id=it->>'line_id' and l.school_id=sid)) then
      return ebda.err('بند غير تابع لهذه الجهة'); end if;
    newid := ebda.uid();
    insert into ebda.requests(id,school_id,requester,requester_name,status,note,total,created_at,req_no,reason)
    values(newid, sid, u.username, u.name, 'pending_supervisor', coalesce(req#>>'{request,note}',''),
      coalesce((select sum((it->>'amount')::numeric) from jsonb_array_elements(coalesce(req#>'{request,items}','[]'::jsonb)) it),0), now()::text,
      'REQ-'||lpad(nextval('ebda.seq_req')::text,4,'0'), coalesce(req#>>'{request,reason}',''));
    for ln in select * from jsonb_array_elements(coalesce(req#>'{request,items}','[]'::jsonb)) loop
      insert into ebda.request_items(id,request_id,line_id,name,amount,sup_note,decision)
      values(ebda.uid(), newid, ln->>'line_id', coalesce(ln->>'name',''), coalesce((ln->>'amount')::numeric,0), '', 'approved');
    end loop;
    return jsonb_build_object('ok',true,'id',newid);
  end if;

  if action in ('updateRequestItem','deleteRequestItem') then
    if urole not in ('direct_manager','admin') then return ebda.err('صلاحية المدير المباشر مطلوبة'); end if;
    select r.* into rq from ebda.requests r join ebda.request_items it on it.request_id=r.id where it.id=(req->>'id');
    if not found then return ebda.err('البند غير موجود'); end if;
    if not ebda.can_school(u, rq.school_id) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if rq.status <> 'pending_supervisor' and urole<>'admin' then return ebda.err('لا يمكن التعديل بعد اتخاذ القرار'); end if;
    if action = 'updateRequestItem' then
      patch := req->'patch';
      update ebda.request_items set line_id=coalesce(patch->>'line_id',line_id), name=coalesce(patch->>'name',name),
        amount=coalesce((patch->>'amount')::numeric,amount), sup_note=coalesce(patch->>'sup_note',sup_note), decision=coalesce(patch->>'decision',decision)
      where id=(req->>'id');
    else
      delete from ebda.request_items where id=(req->>'id');
    end if;
    update ebda.requests set total=coalesce((select sum(amount) from ebda.request_items where request_id=rq.id and decision<>'rejected'),0) where id=rq.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'decideRequest' then
    if urole not in ('direct_manager','admin') then return ebda.err('صلاحية المدير المباشر مطلوبة'); end if;
    select * into rq from ebda.requests where id=(req->>'id');
    if not found then return ebda.err('الطلب غير موجود'); end if;
    if not ebda.can_school(u, rq.school_id) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if rq.requester = u.username and urole<>'admin' then return ebda.err('لا يمكنك اعتماد طلبك بنفسك'); end if;
    if rq.status <> 'pending_supervisor' then return ebda.err('الطلب ليس فى مرحلة اعتماد المدير المباشر'); end if;
    update ebda.requests set status = case when (req->>'decision')='approve' then 'pending_accountant' else 'rejected' end,
      decided_by=u.name, decided_at=now()::text, note=coalesce(req->>'note',note) where id=rq.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'transferRequest' then
    if urole not in ('finance_manager','admin') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    select * into rq from ebda.requests where id=(req->>'id');
    if not found then return ebda.err('الطلب غير موجود'); end if;
    if not ebda.can_school(u, rq.school_id) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if rq.status <> 'pending_accountant' then return ebda.err('الطلب ليس فى مرحلة الاعتماد المالى'); end if;
    if rq.requester = u.username and urole<>'admin' then return ebda.err('لا يمكنك اعتماد طلبك بنفسك'); end if;
    if (req->>'decision')<>'approve' then
      update ebda.requests set status='rejected', acc_by=u.name, fin_at=now()::text where id=rq.id;
      return jsonb_build_object('ok',true);
    end if;
    n := coalesce((select sum(amount) from ebda.request_items where request_id=rq.id and decision<>'rejected'),0);
    -- عهدة مفتوحة لنفس المسئول والجهة، وإلا عهدة جديدة (بعد تسوية/إغلاق السابقة)
    select * into cust from ebda.custodies where school_id=rq.school_id and "user"=rq.requester
      and coalesce(status,'open') in ('open','') order by code desc limit 1;
    if not found then
      newid := ebda.uid();
      insert into ebda.custodies(id,label,holder,school_id,note,"user",code,status,opened_at)
      values(newid, 'عهدة '||rq.requester_name, rq.requester_name, rq.school_id, 'من طلب عهدة '||coalesce(rq.req_no,''), rq.requester,
             'CUST-'||lpad(nextval('ebda.seq_cust')::text,3,'0'), 'open', now()::text);
      select * into cust from ebda.custodies where id=newid;
    end if;
    insert into ebda.tranches(id,custody_id,date,amount,note)
    values(ebda.uid(), cust.id, to_char(now(),'YYYY-MM-DD'), n, 'تحويل طلب عهدة '||coalesce(rq.req_no,''));
    update ebda.requests set status='transferred', acc_by=u.name, fin_at=now()::text, custody_id=cust.id, total=n where id=rq.id;
    return jsonb_build_object('ok',true,'custody_id',cust.id,'custody_code',cust.code);
  end if;

  if action = 'ping' then
    return jsonb_build_object('ok',true,'connected',true,'db','supabase','schema_version',1,
      'users',(select count(*) from ebda.users),'schools',(select count(*) from ebda.schools));
  end if;

  -- ================================================================ bootstrap (كل البيانات المسموح بها فقط)
  if action = 'bootstrap' then
    res := jsonb_build_object('ok',true,'schema_version',1,'me',
      jsonb_build_object('id',u.id,'username',u.username,'name',u.name,'role',coalesce(ebda.role_legacy(u.role),u.role),
        'role_key',urole,'role_label',ebda.role_label(u.role),'schools',u.schools,'perms',coalesce(u.perms,''),
        'must_reset',coalesce(u.must_reset,'لا')));
    res := res || jsonb_build_object('settings', jsonb_build_object(
        'custody_overdue_days', coalesce(nullif((select value from ebda.config where key='custody_overdue_days'),'')::int, 30)));
    res := res || jsonb_build_object('schools', coalesce((select jsonb_agg(to_jsonb(s)) from ebda.schools s
        where coalesce(s.active,'') like '%نعم%' and ebda.can_school(u, s.id)),'[]'::jsonb));
    res := res || jsonb_build_object('custodies', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object(
          'received',(select coalesce(sum(t.amount),0) from ebda.tranches t where t.custody_id=c.id),
          'spent',(select coalesce(sum(e.amount),0) from ebda.expenses e where e.custody_id=c.id and e.approval<>'rejected' and coalesce(e.fin_approval,'')<>'rejected'),
          'exp_count',(select count(*) from ebda.expenses e where e.custody_id=c.id)))
        from ebda.custodies c where ebda.can_custody(u, c)),'[]'::jsonb));
    if urole in ('admin','finance_manager','direct_manager') then
      res := res || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l)) from ebda.lines l
          where ebda.can_school(u, l.school_id)),'[]'::jsonb));
    else  -- مسئول العهدة: أسماء البنود فقط بدون المبالغ
      res := res || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'school_id',l.school_id,'section',l.section,'name',l.name)) from ebda.lines l
          where ebda.can_school(u, l.school_id)),'[]'::jsonb));
    end if;
    res := res || jsonb_build_object('tranches', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.tranches t
        join ebda.custodies c on c.id=t.custody_id where ebda.can_custody(u, c)),'[]'::jsonb));
    res := res || jsonb_build_object('expenses', coalesce((select jsonb_agg(to_jsonb(e)) from ebda.expenses e
        where ebda.can_expense(u, e)),'[]'::jsonb));
    res := res
      || jsonb_build_object('spendItems', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.spend_items z),'[]'::jsonb))
      || jsonb_build_object('holders', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.holders z),'[]'::jsonb))
      || jsonb_build_object('approvers', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.approvers z),'[]'::jsonb))
      || jsonb_build_object('emails', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.emails z),'[]'::jsonb));
    if ebda.sees_budgets(u) then
      res := res || jsonb_build_object('salaries', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.salaries z where ebda.can_school(u, z.school_id)),'[]'::jsonb));
      res := res || jsonb_build_object('employees', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.employees z where ebda.can_school(u, z.school_id)),'[]'::jsonb));
      res := res || jsonb_build_object('payslips', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.payslips z where ebda.can_school(u, z.school_id)),'[]'::jsonb));
    end if;
    res := res || jsonb_build_object('requests', coalesce((
      select jsonb_agg(to_jsonb(r) || jsonb_build_object(
        'stage', case when r.status='transferred' and exists(select 1 from ebda.custodies c where c.id=r.custody_id and c.status in ('settled','closed')) then 'settled'
                      when r.status='transferred' and exists(select 1 from ebda.expenses e where e.custody_id=r.custody_id and e.created_at>=r.fin_at) then 'spent'
                      else r.status end,
        'items', coalesce((select jsonb_agg(to_jsonb(it)) from ebda.request_items it where it.request_id=r.id),'[]'::jsonb)))
      from ebda.requests r
      where (urole='custody_officer' and r.requester=u.username)
         or (urole<>'custody_officer' and ebda.can_school(u, r.school_id))
    ),'[]'::jsonb));
    if urole='admin' then
      res := res || jsonb_build_object('tempBudgets', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.temp_budgets z),'[]'::jsonb));
      res := res || jsonb_build_object('audit', coalesce((select jsonb_agg(to_jsonb(a)) from (select * from ebda.audit_log order by ts desc limit 1000) a),'[]'::jsonb));
      res := res || jsonb_build_object('audit_changes', coalesce((select jsonb_agg(to_jsonb(c)) from ebda.audit_changes c
          where c.txid in (select q.txid from (select txid from ebda.audit_log where txid is not null order by ts desc limit 1000) q)),'[]'::jsonb));
    end if;
    if ebda.can_manage_users(u) then
      res := res || jsonb_build_object('users', coalesce((select jsonb_agg(ebda.user_public(z)) from ebda.users z),'[]'::jsonb));
    elsif urole='finance_manager' then
      res := res || jsonb_build_object('users', coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'username',z.username,'name',z.name,'role',z.role,'role_label',ebda.role_label(z.role))) from ebda.users z),'[]'::jsonb));
    end if;
    return res;
  end if;

  -- ================================================================ المصروفات
  if action = 'addExpense' then
    select * into cust from ebda.custodies where id = (req#>>'{expense,custody_id}');
    if not found then return ebda.err('العهدة غير موجودة'); end if;
    if not (urole='admin' or coalesce(cust."user",'')=u.username) then return ebda.err('لا صلاحية على هذه العهدة'); end if;
    if coalesce(cust.status,'open') in ('settled','closed') then return ebda.err('العهدة '||coalesce(cust.code,'')||' مسوّاة/مغلقة — اطلب عهدة جديدة'); end if;
    if coalesce((req#>>'{expense,amount}')::numeric,0) <= 0 then return ebda.err('قيمة المصروف يجب أن تكون أكبر من صفر'); end if;
    if coalesce(req#>>'{expense,line_id}','')<>'' and not exists(select 1 from ebda.lines l where l.id=req#>>'{expense,line_id}' and l.school_id=cust.school_id) then
      return ebda.err('بند الموازنة غير تابع لجهة هذه العهدة'); end if;
    newid := ebda.uid();
    insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,
       approval,approved_by,doc_url,doc_name,review_status,review_note,settled,ref,note,created_by,created_at,txn_no)
    values(newid, req#>>'{expense,date}', cust.school_id, cust.id,
       req#>>'{expense,line_id}', coalesce(req#>>'{expense,spend_item}',''), coalesce(req#>>'{expense,description}',''),
       (req#>>'{expense,amount}')::numeric,'pending','', '','','','','','',coalesce(req#>>'{expense,note}',''), u.name, now()::text,
       'EXP-'||lpad(nextval('ebda.seq_exp')::text,5,'0'));
    update ebda.expenses set pay_method=coalesce(req#>>'{expense,pay_method}','') where id=newid;
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid))
           || ebda.over_warning(u, req#>>'{expense,line_id}');
  end if;

  if action = 'addCentral' then  -- شراء مركزى: يُخصم من الموازنة مباشرة
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    sid := req#>>'{expense,school_id}';
    if not ebda.can_school(u, sid) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if coalesce(req#>>'{expense,line_id}','')<>'' and not exists(select 1 from ebda.lines l where l.id=req#>>'{expense,line_id}' and l.school_id=sid) then
      return ebda.err('بند الموازنة غير تابع لهذه الجهة'); end if;
    newid := ebda.uid();
    insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,
       approval,approved_by,approved_at,doc_url,doc_name,review_status,review_note,settled,settled_at,ref,note,created_by,created_at,
       fin_approval,fin_by,fin_at,txn_no,doc_type)
    values(newid, req#>>'{expense,date}', sid, '', req#>>'{expense,line_id}', '',
       coalesce(req#>>'{expense,description}',''), coalesce((req#>>'{expense,amount}')::numeric,0),
       'approved', u.name, now()::text, coalesce(req->>'dataUrl',''), coalesce(req->>'filename',''),
       'مستوفى','', 'نعم', now()::text, '','', u.name, now()::text, 'approved', u.name, now()::text,
       'EXP-'||lpad(nextval('ebda.seq_exp')::text,5,'0'), coalesce(req->>'doc_type',''));
    update ebda.expenses set pay_method=coalesce(req#>>'{expense,pay_method}','') where id=newid;
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid))
           || ebda.over_warning(u, req#>>'{expense,line_id}');
  end if;

  if action = 'updateExpense' then
    select * into ex from ebda.expenses where id = (req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if not ebda.can_expense(u, ex) then return ebda.err('لا صلاحية على هذا المصروف'); end if;
    select * into cust from ebda.custodies where id = ex.custody_id;
    patch := req->'patch';
    if patch ? 'approval' then
      -- اعتماد المدير المباشر: يغيّر حالة الاعتماد فقط (لا يُسمح بتعديل المبلغ أثناء الاعتماد)
      if urole not in ('admin','direct_manager') then return ebda.err('صلاحية المدير المباشر مطلوبة'); end if;
      if urole<>'admin' and coalesce(cust."user",'')=u.username then return ebda.err('لا يمكنك اعتماد مصروفك بنفسك'); end if;
      if urole<>'admin' and ex.approval<>'pending' then return ebda.err('تم اتخاذ القرار على هذا المصروف من قبل'); end if;
      if patch->>'approval' not in ('approved','rejected','pending') then return ebda.err('قيمة اعتماد غير صحيحة'); end if;
      update ebda.expenses set approval=patch->>'approval', approved_by=u.name, approved_at=now()::text,
        note=coalesce(patch->>'note', note), updated_by=u.name, updated_at=now()::text
      where id=ex.id;
      return jsonb_build_object('ok',true,'mail','');
    end if;
    -- تعديل بيانات المصروف: الأدمن دائماً، أو صاحب العهدة قبل الاعتماد فقط
    if not (urole='admin' or (coalesce(cust."user",'')=u.username and ex.approval='pending')) then
      return ebda.err('لا يمكن التعديل بعد اعتماد الصرف'); end if;
    if patch ? 'line_id' and coalesce(patch->>'line_id','')<>'' and not exists(select 1 from ebda.lines l where l.id=patch->>'line_id' and l.school_id=ex.school_id) then
      return ebda.err('بند الموازنة غير تابع لجهة المصروف'); end if;
    if patch ? 'amount' and coalesce((patch->>'amount')::numeric,0) <= 0 then return ebda.err('قيمة المصروف يجب أن تكون أكبر من صفر'); end if;
    update ebda.expenses set
      date = coalesce(patch->>'date', date), line_id = coalesce(patch->>'line_id', line_id),
      amount = coalesce((patch->>'amount')::numeric, amount), description = coalesce(patch->>'description', description),
      spend_item = coalesce(patch->>'spend_item', spend_item), note = coalesce(patch->>'note', note),
      pay_method = coalesce(patch->>'pay_method', pay_method),
      settled = case when urole='admin' then coalesce(patch->>'settled', settled) else settled end,
      updated_by=u.name, updated_at=now()::text
    where id = ex.id;
    return jsonb_build_object('ok',true,'mail','');
  end if;

  -- المراجعة المالية: اعتماد مالى + مراجعة المستند + التسوية مع الحسابات
  if action = 'reviewExpense' then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if not ebda.can_expense(u, ex) then return ebda.err('هذا المصروف ليس ضمن نطاقك'); end if;
    select * into cust from ebda.custodies where id = ex.custody_id;
    if urole<>'admin' and cust.id is not null and coalesce(cust."user",'')=u.username then return ebda.err('لا يمكنك اعتماد مصروفك بنفسك'); end if;
    patch := req->'patch';
    if (patch ? 'fin_approval' or coalesce(patch->>'settled','') like '%نعم%') and ex.approval<>'approved' and urole<>'admin' then
      return ebda.err('يجب اعتماد المدير المباشر أولاً'); end if;
    if patch ? 'fin_approval' and coalesce(patch->>'fin_approval','') not in ('','approved','rejected') then return ebda.err('قيمة اعتماد مالى غير صحيحة'); end if;
    if coalesce(patch->>'settled','') like '%نعم%' and coalesce(patch->>'fin_approval', ex.fin_approval)='rejected' then
      return ebda.err('لا يمكن تسوية مصروف مرفوض مالياً'); end if;
    update ebda.expenses set
      fin_approval = case when patch ? 'fin_approval' then patch->>'fin_approval'
                          when coalesce(patch->>'settled','') like '%نعم%' and coalesce(fin_approval,'')='' then 'approved'   -- التسوية تتضمن الاعتماد المالى
                          else fin_approval end,
      fin_by = case when patch ? 'fin_approval' or (coalesce(patch->>'settled','') like '%نعم%' and coalesce(fin_approval,'')='') then u.name else fin_by end,
      fin_at = case when patch ? 'fin_approval' or (coalesce(patch->>'settled','') like '%نعم%' and coalesce(fin_approval,'')='') then now()::text else fin_at end,
      fin_note = coalesce(patch->>'fin_note', fin_note),
      review_status = coalesce(patch->>'review_status', review_status),
      review_note = coalesce(patch->>'review_note', review_note),
      settled = coalesce(patch->>'settled', settled),
      settled_at = case when patch ? 'settled' then case when coalesce(patch->>'settled','') like '%نعم%' then now()::text else '' end else settled_at end,
      updated_by=u.name, updated_at=now()::text
    where id = ex.id;
    return jsonb_build_object('ok',true,'mail','') || case when patch->>'fin_approval'='approved' then ebda.over_warning(u, ex.line_id) else '{}'::jsonb end;
  end if;

  if action = 'uploadDoc' then
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    select * into cust from ebda.custodies where id=ex.custody_id;
    if not (urole='admin'
            or (cust.id is not null and coalesce(cust."user",'')=u.username)
            or (urole='finance_manager' and ebda.can_expense(u, ex)))
    then return ebda.err('لا صلاحية لرفع مستند'); end if;
    if coalesce(req->>'link','')<>'' then
      update ebda.expenses set doc_url=req->>'link', doc_name=coalesce(req->>'filename','رابط مستند'), doc_type=coalesce(req->>'doc_type', doc_type), doc_is_link='نعم',
        updated_by=u.name, updated_at=now()::text where id=ex.id;
      return jsonb_build_object('ok',true,'url',req->>'link');
    end if;
    update ebda.expenses set doc_url=coalesce(req->>'dataUrl',''), doc_name=coalesce(req->>'filename',''), doc_type=coalesce(req->>'doc_type', doc_type), doc_is_link='لا',
      updated_by=u.name, updated_at=now()::text where id=ex.id;
    return jsonb_build_object('ok',true,'url',coalesce(req->>'dataUrl',''));
  end if;

  if action = 'deleteExpense' then
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if urole<>'admin' then
      select * into cust from ebda.custodies where id=ex.custody_id;
      if not (coalesce(cust."user",'')=u.username and ex.approval='pending') then
        return ebda.err('لا يمكن الحذف بعد اعتماد الصرف'); end if;
    end if;
    delete from ebda.expenses where id=ex.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'emailReport' then
    if not ebda.sees_budgets(u) then return ebda.err('لا صلاحية'); end if;
    return jsonb_build_object('ok',true,'note','الإرسال بالإيميل يتم عبر Apps Script أو Edge Function');
  end if;

  -- ================================================================ العهد والدفعات
  if action = 'addTranche' then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    select * into cust from ebda.custodies where id=req#>>'{tranche,custody_id}';
    if not ebda.can_custody(u, cust) then return ebda.err('هذه العهدة ليست ضمن نطاقك'); end if;
    if coalesce(cust.status,'open') in ('settled','closed') then return ebda.err('العهدة مسوّاة/مغلقة — أنشئ عهدة جديدة'); end if;
    newid := ebda.uid();
    insert into ebda.tranches(id,custody_id,date,amount,note)
    values(newid, cust.id, req#>>'{tranche,date}', coalesce((req#>>'{tranche,amount}')::numeric,0), coalesce(req#>>'{tranche,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(t) from ebda.tranches t where t.id=newid));
  end if;

  if action = 'addCustody' then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    if not ebda.can_school(u, req#>>'{custody,school_id}') then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    newid := ebda.uid();
    if coalesce(req#>>'{custody,amount}','') !~ '^\s*[0-9]*\.?[0-9]*\s*$' or coalesce((nullif(btrim(req#>>'{custody,amount}'),''))::numeric,0) < 0 then
      return ebda.err('قيمة العهدة غير صحيحة'); end if;
    if coalesce(btrim(req#>>'{custody,holder}'),'')='' and coalesce(btrim(req#>>'{custody,label}'),'')='' then
      return ebda.err('اكتب اسم مسئول العهدة'); end if;
    insert into ebda.custodies(id,label,holder,school_id,note,"user",code,status,opened_at,kind,purpose)
    values(newid, coalesce(nullif(req#>>'{custody,label}',''), 'عهدة '||coalesce(req#>>'{custody,holder}','')), req#>>'{custody,holder}', req#>>'{custody,school_id}', coalesce(req#>>'{custody,note}',''),
           coalesce(req#>>'{custody,user}',''), 'CUST-'||lpad(nextval('ebda.seq_cust')::text,3,'0'), 'open',
           coalesce(nullif(req#>>'{custody,date}',''), now()::text), coalesce(req#>>'{custody,kind}',''), coalesce(req#>>'{custody,purpose}',''));
    if coalesce((nullif(btrim(req#>>'{custody,amount}'),''))::numeric,0) > 0 then
      insert into ebda.tranches(id,custody_id,date,amount,note)
      values(ebda.uid(), newid, coalesce(nullif(req#>>'{custody,date}',''), to_char(now(),'YYYY-MM-DD')),
             (req#>>'{custody,amount}')::numeric, 'القيمة الأساسية للعهدة');
    end if;
    return jsonb_build_object('ok',true,'item',(select to_jsonb(c) || jsonb_build_object(
        'received',(select coalesce(sum(t.amount),0) from ebda.tranches t where t.custody_id=c.id),'spent',0,'exp_count',0)
      from ebda.custodies c where c.id=newid),
      'tranches', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.tranches t where t.custody_id=newid),'[]'::jsonb));
  end if;

  if action = 'updateCustody' then
    select * into cust from ebda.custodies where id=(req->>'id');
    if not found then return ebda.err('العهدة غير موجودة'); end if;
    patch := req->'patch';
    -- مسئول العهدة: يقدّم عهدته للتسوية فقط
    if urole='custody_officer' then
      if coalesce(cust."user",'')<>u.username then return ebda.err('لا صلاحية على هذه العهدة'); end if;
      if (patch - 'status' - 'id') <> '{}'::jsonb or coalesce(patch->>'status','')<>'pending_settlement' then
        return ebda.err('مسئول العهدة يستطيع تقديم العهدة للتسوية فقط'); end if;
      update ebda.custodies set status='pending_settlement' where id=cust.id and coalesce(status,'open')='open';
      return jsonb_build_object('ok',true);
    end if;
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية المدير المالى مطلوبة'); end if;
    if not ebda.can_custody(u, cust) then return ebda.err('هذه العهدة ليست ضمن نطاقك'); end if;
    if patch ? 'school_id' and not ebda.can_school(u, patch->>'school_id') then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if patch ? 'status' and coalesce(patch->>'status','') not in ('open','pending_settlement','settled','closed') then return ebda.err('حالة عهدة غير صحيحة'); end if;
    if coalesce(patch->>'status','') in ('settled','closed') and exists(select 1 from ebda.expenses e where e.custody_id=cust.id
         and e.approval<>'rejected' and coalesce(e.fin_approval,'')<>'rejected' and not (coalesce(e.settled,'') like '%نعم%')) then
      return ebda.err('توجد مصروفات غير مسوّاة على هذه العهدة — سوِّها أو ارفضها أولاً'); end if;
    update ebda.custodies set label=coalesce(patch->>'label',label), holder=coalesce(patch->>'holder',holder),
      school_id=coalesce(patch->>'school_id',school_id), note=coalesce(patch->>'note',note), "user"=coalesce(patch->>'user',"user"),
      kind=coalesce(patch->>'kind',kind), purpose=coalesce(patch->>'purpose',purpose),
      status=coalesce(patch->>'status',status),
      settled_at = case when patch->>'status'='settled' then now()::text else settled_at end,
      settled_by = case when patch->>'status'='settled' then u.name else settled_by end,
      closed_at  = case when patch->>'status'='closed' then now()::text else closed_at end
    where id=cust.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'deleteCustody' then
    if urole<>'admin' then return ebda.err('حذف العهدة للأدمن فقط — استخدم «إغلاق العهدة»'); end if;
    if exists(select 1 from ebda.expenses e where e.custody_id=(req->>'id') and e.approval='approved') then
      return ebda.err('لا يمكن حذف عهدة عليها مصروفات معتمدة — أغلقها بدلاً من الحذف'); end if;
    delete from ebda.expenses where custody_id=(req->>'id');
    delete from ebda.tranches where custody_id=(req->>'id');
    delete from ebda.custodies where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ بنود الموازنة
  if action = 'addLine' then
    if urole not in ('admin','finance_manager') then return ebda.err('إضافة بنود الموازنة للأدمن والمدير المالى فقط'); end if;
    if not ebda.can_school(u, req#>>'{line,school_id}') then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if not exists(select 1 from ebda.schools s where s.id=req#>>'{line,school_id}') then return ebda.err('الجهة غير موجودة'); end if;
    if coalesce(btrim(req#>>'{line,name}'),'')='' then return ebda.err('اكتب اسم البند'); end if;
    if coalesce(req#>>'{line,allocated}','0') !~ '^\s*[0-9]*\.?[0-9]*\s*$' then return ebda.err('المبلغ يجب أن يكون رقماً موجباً'); end if;
    if exists(select 1 from ebda.lines l where l.school_id=req#>>'{line,school_id}'
              and ebda.norm_txt(l.name)=ebda.norm_txt(req#>>'{line,name}') and ebda.norm_txt(l.section)=ebda.norm_txt(coalesce(req#>>'{line,section}',''))) then
      return ebda.err('هذا البند موجود بالفعل فى نفس القسم لهذه الجهة — عدّل مخصصه بدلاً من إضافته مرة أخرى'); end if;
    newid := ebda.uid();
    insert into ebda.lines(id,school_id,section,name,allocated,note,monthly_plan)
    values(newid, req#>>'{line,school_id}', coalesce(req#>>'{line,section}',''), req#>>'{line,name}', coalesce((req#>>'{line,allocated}')::numeric,0),
           coalesce(req#>>'{line,note}',''), coalesce(req#>>'{line,monthly_plan}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(l) from ebda.lines l where l.id=newid));
  end if;

  if action in ('updateLine','deleteLine') then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية الأدمن أو المدير المالى مطلوبة'); end if;
    sid := (select school_id from ebda.lines where id=(req->>'id'));
    if sid is null then return ebda.err('البند غير موجود'); end if;
    if not ebda.can_school(u, sid) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if action='updateLine' then
      patch := req->'patch';
      if patch ? 'allocated' and coalesce(patch->>'allocated','0') !~ '^\s*[0-9]*\.?[0-9]*\s*$' then return ebda.err('المبلغ يجب أن يكون رقماً موجباً'); end if;
      if (patch ? 'name' or patch ? 'section') and exists(select 1 from ebda.lines l, ebda.lines me where me.id=(req->>'id')
            and l.school_id=me.school_id and l.id<>me.id
            and ebda.norm_txt(l.name)=ebda.norm_txt(coalesce(patch->>'name',me.name))
            and ebda.norm_txt(l.section)=ebda.norm_txt(coalesce(patch->>'section',me.section))) then
        return ebda.err('يوجد بند بنفس الاسم فى نفس القسم لهذه الجهة'); end if;
      update ebda.lines set section=coalesce(patch->>'section',section), name=coalesce(patch->>'name',name),
        allocated=coalesce((patch->>'allocated')::numeric,allocated), note=coalesce(patch->>'note',note),
        monthly_plan=coalesce(patch->>'monthly_plan',monthly_plan)
      where id=(req->>'id');
    else
      if exists(select 1 from ebda.expenses e where e.line_id=(req->>'id')) then
        return ebda.err('لا يمكن حذف بند عليه مصروفات — عدّل اسمه أو مخصصه بدلاً من ذلك'); end if;
      delete from ebda.lines where id=(req->>'id');
    end if;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'importBudget' and coalesce(req->>'mode','') = 'merge' then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية الأدمن أو المدير المالى مطلوبة'); end if;
    if jsonb_typeof(coalesce(req->'lines','null'::jsonb)) <> 'array' or jsonb_array_length(req->'lines') = 0 then
      return ebda.err('لا توجد بنود للاستيراد'); end if;
    -- (1) التحقق من كل السطور قبل أى حفظ
    for ln in select * from jsonb_array_elements(req->'lines') loop
      sid := coalesce(nullif(ln->>'school_id',''), req->>'school_id');
      if sid is null or not exists(select 1 from ebda.schools s where s.id=sid) then
        return ebda.err('جهة غير موجودة فى السطر: '||coalesce(ln->>'name','')); end if;
      if not ebda.can_school(u, sid) then return ebda.err('الجهة ليست ضمن نطاقك: '||coalesce((select name from ebda.schools where id=sid),'')); end if;
      if coalesce(btrim(ln->>'name'),'')='' then return ebda.err('يوجد سطر بدون اسم بند'); end if;
      if coalesce(ln->>'allocated','0') !~ '^\s*[0-9]*\.?[0-9]*\s*$' then
        return ebda.err('مبلغ غير صحيح للبند: '||coalesce(ln->>'name','')); end if;
      if coalesce(ln->>'line_id','')<>'' and not exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and l.school_id=sid) then
        return ebda.err('البند المطابق غير موجود فى الجهة: '||coalesce(ln->>'name','')); end if;
    end loop;
    -- (2) التنفيذ: تحديث المطابق / إضافة الجديد فقط
    for ln in select * from jsonb_array_elements(req->'lines') loop
      sid := coalesce(nullif(ln->>'school_id',''), req->>'school_id');
      lid := nullif(ln->>'line_id','');
      if lid is null then
        select l.id into lid from ebda.lines l where l.school_id=sid
          and ebda.norm_txt(l.name)=ebda.norm_txt(ln->>'name') and ebda.norm_txt(l.section)=ebda.norm_txt(coalesce(ln->>'section','')) limit 1;
      end if;
      if lid is null then
        insert into ebda.lines(id,school_id,section,name,allocated,note,monthly_plan)
        values(ebda.uid(), sid, coalesce(ln->>'section',''), btrim(ln->>'name'), coalesce((nullif(btrim(ln->>'allocated'),''))::numeric,0),
               coalesce(ln->>'note',''), coalesce(ln->>'monthly_plan',''));
        n_new := n_new + 1;
      else
        select * into lrow from ebda.lines where id=lid;
        if lrow.allocated is distinct from coalesce((nullif(btrim(ln->>'allocated'),''))::numeric,0)
           or (coalesce(ln->>'note','')<>'' and coalesce(lrow.note,'')<>(ln->>'note'))
           or (coalesce(ln->>'monthly_plan','')<>'' and coalesce(lrow.monthly_plan,'')<>(ln->>'monthly_plan'))
           or (coalesce(ln->>'rename','')='1' and (lrow.name<>btrim(ln->>'name') or coalesce(lrow.section,'')<>coalesce(ln->>'section',''))) then
          update ebda.lines set allocated=coalesce((nullif(btrim(ln->>'allocated'),''))::numeric,0),
            note=case when coalesce(ln->>'note','')<>'' then ln->>'note' else note end,
            monthly_plan=case when coalesce(ln->>'monthly_plan','')<>'' then ln->>'monthly_plan' else monthly_plan end,
            name=case when coalesce(ln->>'rename','')='1' then btrim(ln->>'name') else name end,
            section=case when coalesce(ln->>'rename','')='1' then coalesce(ln->>'section',section) else section end
          where id=lid;
          n_upd := n_upd + 1;
        else
          n_same := n_same + 1;
        end if;
      end if;
    end loop;
    return jsonb_build_object('ok',true,'added',n_new,'updated',n_upd,'unchanged',n_same,'count',n_new+n_upd+n_same);
  end if;

  if action = 'importBudget' then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية الأدمن أو المدير المالى مطلوبة'); end if;
    sid := req->>'school_id';
    if req ? 'newSchool' then
      if urole<>'admin' then return ebda.err('إنشاء جهة جديدة للأدمن فقط'); end if;
      newid := ebda.uid();
      insert into ebda.schools(id,name,type,period,students,active,category)
      values(newid, req#>>'{newSchool,name}', coalesce(req#>>'{newSchool,type}',''), coalesce(req#>>'{newSchool,period}',''),
         0, 'نعم', coalesce(req#>>'{newSchool,category}','school'));
      sid := newid;
    elsif not ebda.can_school(u, sid) then return ebda.err('هذه الجهة ليست ضمن نطاقك');
    end if;
    if exists(select 1 from ebda.expenses e join ebda.lines l on l.id=e.line_id where l.school_id=sid) then
      return ebda.err('هذه الجهة عليها مصروفات مرتبطة ببنودها — لا يمكن استبدال الموازنة بالكامل. عدّل البنود من شاشة الموازنات');
    end if;
    delete from ebda.lines where school_id = sid;
    for ln in select * from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) loop
      insert into ebda.lines(id,school_id,section,name,allocated,note)
      values(ebda.uid(), sid, coalesce(ln->>'section',''), coalesce(ln->>'name',''), coalesce((ln->>'allocated')::numeric,0), '');
    end loop;
    return jsonb_build_object('ok',true,'school_id',sid,'count',jsonb_array_length(coalesce(req->'lines','[]'::jsonb)));
  end if;

  if action in ('addSpendItem','deleteSpendItem','addHolder','deleteHolder') then
    if urole not in ('admin','finance_manager') then return ebda.err('صلاحية الأدمن أو المدير المالى مطلوبة'); end if;
    if action = 'addSpendItem' then newid:=ebda.uid(); insert into ebda.spend_items(id,name) values(newid, req#>>'{item,name}'); return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.spend_items z where z.id=newid)); end if;
    if action = 'deleteSpendItem' then delete from ebda.spend_items where id=(req->>'id'); return jsonb_build_object('ok',true); end if;
    if action = 'addHolder' then newid:=ebda.uid(); insert into ebda.holders(id,name,title) values(newid, req#>>'{item,name}', coalesce(req#>>'{item,title}','')); return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.holders z where z.id=newid)); end if;
    delete from ebda.holders where id=(req->>'id'); return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ إدارة المستخدمين
  if action in ('addUser','updateUser','deleteUser','resetPin') then
    if not ebda.can_manage_users(u) then return ebda.err('إدارة المستخدمين للأدمن فقط'); end if;
    if action <> 'addUser' then
      select * into xu from ebda.users where id=(req->>'id');
      if not found then return ebda.err('المستخدم غير موجود'); end if;
      if urole<>'admin' and ebda.role_key(xu.role)='admin' then return ebda.err('لا يمكن تعديل حساب الأدمن'); end if;
    end if;
    if action = 'resetPin' then
      update ebda.users set pin=ebda.pin_hash('0000'), must_reset='نعم' where id=xu.id;
      delete from ebda.sessions where user_id=xu.id;
      return jsonb_build_object('ok',true);
    end if;
    if action = 'deleteUser' then
      if xu.id = u.id then return ebda.err('لا يمكنك حذف حسابك'); end if;
      if ebda.role_key(xu.role)='admin' and (select count(*) from ebda.users z where ebda.role_key(z.role)='admin' and coalesce(z.active,'') like '%نعم%')<=1 then
        return ebda.err('لا يمكن حذف آخر أدمن'); end if;
      delete from ebda.sessions where user_id=xu.id;
      delete from ebda.users where id=xu.id;
      return jsonb_build_object('ok',true);
    end if;
    dj := case when action='addUser' then req->'user' else req->'patch' end;
    if dj ? 'role' and ebda.role_key(dj->>'role')='' then return ebda.err('دور غير معروف'); end if;
    if urole<>'admin' and (ebda.role_key(dj->>'role')='admin' or dj ? 'perms') then return ebda.err('منح صلاحيات الأدمن للأدمن فقط'); end if;
    if action = 'addUser' then
      if coalesce(dj->>'username','')='' or length(coalesce(dj->>'pin',''))<4 then return ebda.err('اسم المستخدم وكلمة سر من 4 خانات على الأقل مطلوبان'); end if;
      if exists(select 1 from ebda.users z where z.username=dj->>'username') then return ebda.err('اسم المستخدم مستخدم من قبل'); end if;
      newid := ebda.uid();
      insert into ebda.users(id,username,pin,name,role,schools,active,email,perms,must_reset)
      values(newid, dj->>'username', ebda.pin_hash(dj->>'pin'), dj->>'name', coalesce(ebda.role_legacy(dj->>'role'),'custody'),
         coalesce(dj->>'schools',''), coalesce(dj->>'active','نعم'), coalesce(dj->>'email',''), coalesce(dj->>'perms',''), 'نعم');
      return jsonb_build_object('ok',true,'item',(select ebda.user_public(z) from ebda.users z where z.id=newid));
    end if;
    if xu.id = u.id and dj ? 'role' and ebda.role_key(dj->>'role')<>urole then return ebda.err('لا يمكنك تغيير دورك بنفسك'); end if;
    if dj ? 'username' and exists(select 1 from ebda.users z where z.username=dj->>'username' and z.id<>xu.id) then return ebda.err('اسم المستخدم مستخدم من قبل'); end if;
    update ebda.users set username=coalesce(nullif(dj->>'username',''),username),
      pin = case when length(coalesce(dj->>'pin',''))>=4 and coalesce(dj->>'pin','') not like '$2%' then ebda.pin_hash(dj->>'pin') else pin end,
      name=coalesce(dj->>'name',name), role=coalesce(ebda.role_legacy(dj->>'role'),role), schools=coalesce(dj->>'schools',schools),
      active=coalesce(dj->>'active',active), email=coalesce(dj->>'email',email), perms=coalesce(dj->>'perms',perms)
    where id=xu.id;
    if length(coalesce(dj->>'pin',''))>=4 or coalesce(dj->>'active','نعم') not like '%نعم%' or dj ? 'role' or dj ? 'username' then
      delete from ebda.sessions where user_id=xu.id;
    end if;
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ باقى الإجراءات للأدمن فقط (كما فى النظام الحالى)
  if urole<>'admin' then return ebda.err('صلاحية الأدمن مطلوبة'); end if;

  if action = 'addSalary' then
    newid := ebda.uid();
    insert into ebda.salaries(id,school_id,name,job,monthly,months,note)
    values(newid, req#>>'{salary,school_id}', req#>>'{salary,name}', coalesce(req#>>'{salary,job}',''),
      coalesce((req#>>'{salary,monthly}')::numeric,0), coalesce((req#>>'{salary,months}')::numeric,12), coalesce(req#>>'{salary,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.salaries z where z.id=newid));
  end if;
  if action = 'updateSalary' then
    patch := req->'patch';
    update ebda.salaries set name=coalesce(patch->>'name',name), job=coalesce(patch->>'job',job),
      monthly=coalesce((patch->>'monthly')::numeric,monthly), months=coalesce((patch->>'months')::numeric,months), note=coalesce(patch->>'note',note)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deleteSalary' then delete from ebda.salaries where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  if action = 'importSalaries' then
    sid := req->>'school_id';
    if (req->>'replace') is distinct from 'no' then delete from ebda.salaries where school_id = sid; end if;
    for ln in select * from jsonb_array_elements(coalesce(req->'rows','[]'::jsonb)) loop
      insert into ebda.salaries(id,school_id,name,job,monthly,months,note)
      values(ebda.uid(), sid, coalesce(ln->>'name',''), coalesce(ln->>'job',''),
        coalesce((ln->>'monthly')::numeric,0), coalesce((ln->>'months')::numeric,12), coalesce(ln->>'note',''));
    end loop;
    return jsonb_build_object('ok',true,'count',jsonb_array_length(coalesce(req->'rows','[]'::jsonb)));
  end if;

  if action = 'addEmployee' then
    newid := ebda.uid(); dj := req->'emp';
    insert into ebda.employees(id,school_id,category,emp_no,name,job,job_type,qualification,grad_year,national_id,birth_date,phone,hire_date,work_start,insurance_no,account_no,bank,branch,email,ebda_start,base_salary,contract_type,gender,address,retire_date,note,active,archived)
    values(newid, dj->>'school_id', coalesce(dj->>'category','contract'), coalesce(dj->>'emp_no',''), dj->>'name', coalesce(dj->>'job',''), coalesce(dj->>'job_type',''), coalesce(dj->>'qualification',''), coalesce(dj->>'grad_year',''), coalesce(dj->>'national_id',''), coalesce(dj->>'birth_date',''), coalesce(dj->>'phone',''), coalesce(dj->>'hire_date',''), coalesce(dj->>'work_start',''), coalesce(dj->>'insurance_no',''), coalesce(dj->>'account_no',''), coalesce(dj->>'bank',''), coalesce(dj->>'branch',''), coalesce(dj->>'email',''), coalesce(dj->>'ebda_start',''), coalesce((dj->>'base_salary')::numeric,0), coalesce(dj->>'contract_type',''), coalesce(dj->>'gender',''), coalesce(dj->>'address',''), coalesce(dj->>'retire_date',''), coalesce(dj->>'note',''), 'نعم','لا');
    return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.employees z where z.id=newid));
  end if;
  if action = 'updateEmployee' then
    patch := req->'patch';
    update ebda.employees set
      category=coalesce(patch->>'category',category), emp_no=coalesce(patch->>'emp_no',emp_no), name=coalesce(patch->>'name',name),
      job=coalesce(patch->>'job',job), job_type=coalesce(patch->>'job_type',job_type), qualification=coalesce(patch->>'qualification',qualification),
      grad_year=coalesce(patch->>'grad_year',grad_year), national_id=coalesce(patch->>'national_id',national_id), birth_date=coalesce(patch->>'birth_date',birth_date),
      phone=coalesce(patch->>'phone',phone), hire_date=coalesce(patch->>'hire_date',hire_date), work_start=coalesce(patch->>'work_start',work_start),
      insurance_no=coalesce(patch->>'insurance_no',insurance_no), account_no=coalesce(patch->>'account_no',account_no), bank=coalesce(patch->>'bank',bank),
      branch=coalesce(patch->>'branch',branch), email=coalesce(patch->>'email',email), ebda_start=coalesce(patch->>'ebda_start',ebda_start),
      base_salary=coalesce((patch->>'base_salary')::numeric,base_salary), contract_type=coalesce(patch->>'contract_type',contract_type),
      gender=coalesce(patch->>'gender',gender), address=coalesce(patch->>'address',address), retire_date=coalesce(patch->>'retire_date',retire_date),
      note=coalesce(patch->>'note',note), school_id=coalesce(patch->>'school_id',school_id)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'archiveEmployee' then
    update ebda.employees set archived='نعم', active='لا', archived_at=now()::text, archived_by=u.name where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'restoreEmployee' then
    update ebda.employees set archived='لا', active='نعم', archived_at='', archived_by='' where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deleteEmployee' then delete from ebda.employees where id=(req->>'id'); return jsonb_build_object('ok',true); end if;
  if action = 'importEmployees' then
    sid := req->>'school_id';
    for ln in select * from jsonb_array_elements(coalesce(req->'rows','[]'::jsonb)) loop
      insert into ebda.employees(id,school_id,category,emp_no,name,job,job_type,qualification,grad_year,national_id,birth_date,phone,hire_date,work_start,insurance_no,account_no,bank,branch,email,ebda_start,base_salary,contract_type,gender,address,retire_date,note,active,archived)
      values(ebda.uid(), sid, coalesce(ln->>'category','contract'), coalesce(ln->>'emp_no',''), coalesce(ln->>'name',''), coalesce(ln->>'job',''), coalesce(ln->>'job_type',''), coalesce(ln->>'qualification',''), coalesce(ln->>'grad_year',''), coalesce(ln->>'national_id',''), coalesce(ln->>'birth_date',''), coalesce(ln->>'phone',''), coalesce(ln->>'hire_date',''), coalesce(ln->>'work_start',''), coalesce(ln->>'insurance_no',''), coalesce(ln->>'account_no',''), coalesce(ln->>'bank',''), coalesce(ln->>'branch',''), coalesce(ln->>'email',''), coalesce(ln->>'ebda_start',''), coalesce((ln->>'base_salary')::numeric,0), coalesce(ln->>'contract_type',''), coalesce(ln->>'gender',''), coalesce(ln->>'address',''), coalesce(ln->>'retire_date',''), coalesce(ln->>'note',''), 'نعم','لا');
    end loop;
    return jsonb_build_object('ok',true,'count',jsonb_array_length(coalesce(req->'rows','[]'::jsonb)));
  end if;
  if action = 'addPayslip' then
    newid := ebda.uid(); dj := req->'slip';
    insert into ebda.payslips(id,employee_id,emp_name,school_id,month,base,incentive,allowances,gross,ded_medical,ded_social,ded_tax,ded_other,ded_total,net,note,created_by,created_at)
    values(newid, dj->>'employee_id', coalesce(dj->>'emp_name',''), dj->>'school_id', coalesce(dj->>'month',''),
      coalesce((dj->>'base')::numeric,0), coalesce((dj->>'incentive')::numeric,0), coalesce((dj->>'allowances')::numeric,0), coalesce((dj->>'gross')::numeric,0),
      coalesce((dj->>'ded_medical')::numeric,0), coalesce((dj->>'ded_social')::numeric,0), coalesce((dj->>'ded_tax')::numeric,0), coalesce((dj->>'ded_other')::numeric,0),
      coalesce((dj->>'ded_total')::numeric,0), coalesce((dj->>'net')::numeric,0), coalesce(dj->>'note',''), u.name, now()::text);
    return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.payslips z where z.id=newid));
  end if;
  if action = 'updatePayslip' then
    patch := req->'patch';
    update ebda.payslips set base=coalesce((patch->>'base')::numeric,base), incentive=coalesce((patch->>'incentive')::numeric,incentive),
      allowances=coalesce((patch->>'allowances')::numeric,allowances), gross=coalesce((patch->>'gross')::numeric,gross),
      ded_medical=coalesce((patch->>'ded_medical')::numeric,ded_medical), ded_social=coalesce((patch->>'ded_social')::numeric,ded_social),
      ded_tax=coalesce((patch->>'ded_tax')::numeric,ded_tax), ded_other=coalesce((patch->>'ded_other')::numeric,ded_other),
      ded_total=coalesce((patch->>'ded_total')::numeric,ded_total), net=coalesce((patch->>'net')::numeric,net), note=coalesce(patch->>'note',note)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deletePayslip' then delete from ebda.payslips where id=(req->>'id'); return jsonb_build_object('ok',true); end if;
  if action = 'addPayslipsBatch' then
    for ln in select * from jsonb_array_elements(coalesce(req->'rows','[]'::jsonb)) loop
      insert into ebda.payslips(id,employee_id,emp_name,school_id,month,base,incentive,allowances,gross,ded_medical,ded_social,ded_tax,ded_other,ded_total,net,note,created_by,created_at)
      values(ebda.uid(), ln->>'employee_id', coalesce(ln->>'emp_name',''), ln->>'school_id', coalesce(ln->>'month',''),
        coalesce((ln->>'base')::numeric,0), coalesce((ln->>'incentive')::numeric,0), coalesce((ln->>'allowances')::numeric,0), coalesce((ln->>'gross')::numeric,0),
        coalesce((ln->>'ded_medical')::numeric,0), coalesce((ln->>'ded_social')::numeric,0), coalesce((ln->>'ded_tax')::numeric,0), coalesce((ln->>'ded_other')::numeric,0),
        coalesce((ln->>'ded_total')::numeric,0), coalesce((ln->>'net')::numeric,0), coalesce(ln->>'note',''), u.name, now()::text);
    end loop;
    return jsonb_build_object('ok',true,'count',jsonb_array_length(coalesce(req->'rows','[]'::jsonb)));
  end if;

  if action = 'addTempBudget' then
    newid := ebda.uid();
    insert into ebda.temp_budgets(id,school_id,name,dfrom,dto,amount,note)
    values(newid, req#>>'{tb,school_id}', req#>>'{tb,name}', req#>>'{tb,dfrom}', req#>>'{tb,dto}',
      coalesce((req#>>'{tb,amount}')::numeric,0), coalesce(req#>>'{tb,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(z) from ebda.temp_budgets z where z.id=newid));
  end if;
  if action = 'deleteTempBudget' then delete from ebda.temp_budgets where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  if action = 'addSchool' then
    newid := ebda.uid();
    insert into ebda.schools(id,name,type,period,students,active,category)
    values(newid, req#>>'{school,name}', coalesce(req#>>'{school,type}',''), coalesce(req#>>'{school,period}',''),
       coalesce((req#>>'{school,students}')::numeric,0), 'نعم', coalesce(req#>>'{school,category}','school'));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(s) from ebda.schools s where s.id=newid));
  end if;
  if action = 'updateSchool' then
    patch := req->'patch';
    update ebda.schools set name=coalesce(patch->>'name',name), type=coalesce(patch->>'type',type),
      period=coalesce(patch->>'period',period), students=coalesce((patch->>'students')::numeric,students),
      category=coalesce(patch->>'category',category), active=coalesce(patch->>'active',active)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deleteSchool' then
    if exists(select 1 from ebda.custodies c where c.school_id=(req->>'id')) or exists(select 1 from ebda.expenses e where e.school_id=(req->>'id')) then
      return ebda.err('لا يمكن حذف جهة عليها عهد أو مصروفات — عطّلها بدلاً من الحذف'); end if;
    delete from ebda.lines where school_id=(req->>'id');
    delete from ebda.schools where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

  return ebda.err('إجراء غير معروف: '||coalesce(action,''));
end;
$fn$;

-- ---------------------------------------------------------------- الصلاحيات: الدالة العامة فقط (كما فى 002)
revoke all on all tables in schema ebda from anon, authenticated;
revoke all on all sequences in schema ebda from anon, authenticated;
revoke execute on all functions in schema ebda from public, anon, authenticated;
grant usage on schema ebda to anon, authenticated;
grant execute on function ebda.api(jsonb) to anon, authenticated;
grant execute on function public.api(jsonb) to anon, authenticated;

insert into ebda.config(key,value) values ('schema_version','3') on conflict (key) do update set value='3';
