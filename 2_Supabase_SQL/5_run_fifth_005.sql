-- ============================================================================
--  ابدأ إديو — Migration 005: دورة المصروف الكاملة · المدير المباشر (Assignment) · الملكية بالمعرّف
--  الفصل بين المهام · تعطيل الجهات والبنود · أنواع العهد والموازنات · النسخ الاحتياطى والاستعادة · الأداء
--  آمن للتكرار. لا يحذف بيانات، ولا يعيد إنشاء المستخدمين، ولا يغيّر كلمات السر أو المعرّفات أو الصلاحيات الحالية.
--  يُشغَّل بعد 001 → 004.
-- ============================================================================
set search_path = ebda, public, extensions;

-- ---------------------------------------------------------------- أعمدة جديدة (كلها اختيارية بقيم افتراضية)
alter table ebda.users     add column if not exists manager_id text default '';   -- المدير المباشر لمسئول العهدة (معرّف المستخدم)
alter table ebda.users     add column if not exists dept text default '';         -- القسم (نطاق إضافى)
alter table ebda.custodies add column if not exists user_id text default '';      -- مالك العهدة بالمعرّف (يُملأ تلقائياً من اسم الدخول)
alter table ebda.requests  add column if not exists requester_id text default '';
alter table ebda.lines     add column if not exists active text default 'نعم';    -- البند المعطّل لا يقبل إدخالات جديدة ويبقى فى التقارير
alter table ebda.expenses  add column if not exists created_by_id text default '';
alter table ebda.expenses  add column if not exists approved_by_id text default '';
alter table ebda.expenses  add column if not exists approval_note text default '';
alter table ebda.expenses  add column if not exists submitted_at text default '';
alter table ebda.expenses  add column if not exists returned_by text default '';
alter table ebda.expenses  add column if not exists returned_at text default '';
alter table ebda.expenses  add column if not exists return_reason text default '';
alter table ebda.expenses  add column if not exists fin_by_id text default '';
alter table ebda.expenses  add column if not exists settled_by text default '';
alter table ebda.expenses  add column if not exists settled_by_id text default '';
alter table ebda.expenses  add column if not exists cancelled_at text default '';
alter table ebda.expenses  add column if not exists cancelled_by text default '';
alter table ebda.expenses  add column if not exists cancel_reason text default '';
alter table ebda.employees add column if not exists dept text default '';
alter table ebda.employees add column if not exists manager_user_id text default '';
alter table ebda.employees add column if not exists birth_place text default '';
alter table ebda.employees add column if not exists secondment_status text default '';  -- حالة الندب / المأمورية
alter table ebda.employees add column if not exists serial_no text default '';

update ebda.lines set active='نعم' where active is null;
update ebda.users set manager_id='' where manager_id is null;

-- ---------------------------------------------------------------- الملكية بالمعرّف وليس بالاسم الظاهر
-- (1) العهدة/الطلب: يُستنتج معرّف المالك من اسم الدخول عند الإضافة أو التغيير
create or replace function ebda.fill_owner_ids() returns trigger language plpgsql security definer set search_path = ebda as $fo$
begin
  if tg_table_name = 'custodies' then
    if tg_op = 'INSERT' or new."user" is distinct from old."user" or coalesce(new.user_id,'') = '' then
      new.user_id := coalesce((select z.id from ebda.users z where z.username = new."user" and coalesce(new."user",'')<>'' order by z.id limit 1), '');
    end if;
  elsif tg_table_name = 'requests' then
    if tg_op = 'INSERT' or new.requester is distinct from old.requester or coalesce(new.requester_id,'') = '' then
      new.requester_id := coalesce((select z.id from ebda.users z where z.username = new.requester and coalesce(new.requester,'')<>'' order by z.id limit 1), '');
    end if;
  end if;
  return new;
end $fo$;
drop trigger if exists trg_owner_custodies on ebda.custodies;
create trigger trg_owner_custodies before insert or update on ebda.custodies for each row execute function ebda.fill_owner_ids();
drop trigger if exists trg_owner_requests on ebda.requests;
create trigger trg_owner_requests before insert or update on ebda.requests for each row execute function ebda.fill_owner_ids();

-- (2) تغيير اسم الدخول لا يفقد المستخدم عهده ولا طلباته
create or replace function ebda.cascade_username() returns trigger language plpgsql security definer set search_path = ebda as $cu$
begin
  if new.username is distinct from old.username then
    update ebda.custodies set "user" = new.username where user_id = new.id;
    update ebda.requests  set requester = new.username where requester_id = new.id;
  end if;
  return null;
end $cu$;
drop trigger if exists trg_cascade_username on ebda.users;
create trigger trg_cascade_username after update of username on ebda.users for each row execute function ebda.cascade_username();

-- (3) ملء المعرّفات للبيانات الحالية (بدون تغيير أى قيمة أخرى)
update ebda.custodies c set user_id = z.id from ebda.users z where coalesce(c.user_id,'')='' and z.username = c."user" and coalesce(c."user",'')<>'';
update ebda.requests r set requester_id = z.id from ebda.users z where coalesce(r.requester_id,'')='' and z.username = r.requester and coalesce(r.requester,'')<>'';

create or replace function ebda.owns_custody(u ebda.users, c ebda.custodies) returns boolean language sql stable as $$
  select c.id is not null and case when coalesce(c.user_id,'')<>'' then c.user_id = u.id else coalesce(c."user",'')<>'' and c."user" = u.username end $$;

create or replace function ebda.can_custody(u ebda.users, c ebda.custodies) returns boolean language sql stable as $$
  select case
    when c.id is null then false
    when ebda.role_key(u.role)='admin' then true
    when ebda.role_key(u.role)='custody_officer' then ebda.owns_custody(u, c)
    when coalesce(c.school_id,'')='' then ebda.role_key(u.role)='finance_manager'
    else ebda.can_school(u, c.school_id) end $$;

-- المدير المباشر المكلَّف: إذا كان لمسئول العهدة مدير مباشر محدد فهو وحده (أو الأدمن) من يعتمد مصروفاته،
-- وإلا يبقى السلوك الحالى (المدير المباشر حسب نطاق المكان).
create or replace function ebda.owner_of(c ebda.custodies) returns ebda.users language sql stable as $$
  select z from ebda.users z where (coalesce(c.user_id,'')<>'' and z.id=c.user_id) or (coalesce(c.user_id,'')='' and z.username=c."user" and coalesce(c."user",'')<>'')
  order by z.id limit 1 $$;
create or replace function ebda.is_assigned_manager(u ebda.users, c ebda.custodies) returns boolean language plpgsql stable as $am$
declare o ebda.users;
begin
  if ebda.role_key(u.role)='admin' then return true; end if;
  if c.id is null then return ebda.can_school(u, null); end if;
  o := ebda.owner_of(c);
  if o.id is not null and coalesce(o.manager_id,'')<>'' then return o.manager_id = u.id; end if;
  return ebda.can_school(u, c.school_id);
end $am$;

-- ---------------------------------------------------------------- حالة المصروف (مصدر واحد للحالة — نفس المنطق فى الواجهة lib/expense.js)
create or replace function ebda.expense_stage(e ebda.expenses) returns text language sql immutable as $$
  select case
    when coalesce(e.cancelled_at,'')<>'' then 'cancelled'
    when e.approval='draft' then 'draft'
    when e.approval='returned' then 'returned'
    when e.approval='rejected' then 'rejected'
    when coalesce(e.approval,'pending')='pending' then 'pending_manager'
    when coalesce(e.settled,'') like '%نعم%' and coalesce(e.fin_approval,'')<>'rejected' then 'settled'
    when e.fin_approval='rejected' then 'fin_rejected'
    when e.fin_approval='returned' then 'fin_returned'
    when e.fin_approval='approved' then 'reviewed'
    else 'pending_finance' end $$;

-- المصروف المحتسب على الموازنة: معتمد من المدير المباشر + معتمد مالياً/مسوّى + غير ملغى
create or replace function ebda.counts_in_budget(e ebda.expenses) returns boolean language sql immutable as $$
  select coalesce(e.approval,'')='approved' and (coalesce(e.fin_approval,'')='approved' or coalesce(e.settled,'') like '%نعم%')
     and coalesce(e.fin_approval,'')<>'rejected' and coalesce(e.cancelled_at,'')='' $$;
-- المصروف القائم على العهدة (يُخصم من رصيدها): غير مرفوض وغير ملغى
create or replace function ebda.active_on_custody(e ebda.expenses) returns boolean language sql immutable as $$
  select coalesce(e.approval,'')<>'rejected' and coalesce(e.fin_approval,'')<>'rejected' and coalesce(e.cancelled_at,'')='' $$;

-- ---------------------------------------------------------------- Master Data: أنواع العهد وأنواع الموازنات (الجهات)
create table if not exists ebda.custody_kinds(id text primary key, name text not null, active text default 'نعم', sort int default 0);
insert into ebda.custody_kinds(id,name,sort)
select v.id, v.name, v.sort from (values ('ck_ops','عهدة تشغيلية',1),('ck_petty','عهدة نثرية مستديمة',2),('ck_purpose','عهدة لغرض محدد',3),
                                          ('ck_activity','عهدة نشاط / تدريب',4),('ck_other','أخرى',5)) v(id,name,sort)
where not exists (select 1 from ebda.custody_kinds);
-- أى نوع مستخدم فعلياً فى العهد الحالية ولم يكن فى القائمة يُضاف (لا يضيع تصنيف قديم)
insert into ebda.custody_kinds(id,name,sort)
select 'ck_'||substr(md5(k),1,10), k, 50 from (select distinct btrim(kind) k from ebda.custodies where coalesce(btrim(kind),'')<>'') x
where not exists (select 1 from ebda.custody_kinds z where z.name = x.k)
on conflict (id) do nothing;

create table if not exists ebda.entity_types(code text primary key, label text not null, active text default 'نعم', sort int default 0);
insert into ebda.entity_types(code,label,sort) values
  ('school','مدرسة',1),('company','الشركة الداخلية',2),('training_general','تدريب عام',3),('training_vocational','تدريب مهنى',4),
  ('training_project','مشروع تدريب',5),('training_program','برنامج تدريب',6),('training_course','دورة تدريبية',7)
on conflict (code) do nothing;
insert into ebda.entity_types(code,label,sort)
select distinct s.category, s.category, 50 from ebda.schools s where coalesce(s.category,'')<>'' on conflict (code) do nothing;

-- ---------------------------------------------------------------- النسخ الاحتياطى (داخل قاعدة البيانات — لا يصل إليها إلا الأدمن عبر الـ API)
create table if not exists ebda.backups(
  id text primary key, name text not null, kind text default 'manual', created_at timestamptz default now(), created_by text default '',
  size_bytes bigint default 0, counts jsonb default '{}'::jsonb, note text default '', data jsonb not null);
create index if not exists ix_backups_created on ebda.backups(created_at desc);

-- الجداول التى تشملها النسخة (بترتيب الاستعادة). الجلسات والنسخ نفسها لا تُنسخ.
create or replace function ebda.backup_tables() returns text[] language sql immutable as $$
  select array['config','users','schools','entity_types','lines','custody_names','custody_kinds','custodies','custody_lines','tranches',
               'expenses','requests','request_items','spend_items','holders','approvers','emails','salaries','temp_budgets',
               'employees','payroll_components','payroll_periods','payslips','import_batches','audit_log','audit_changes'] $$;

create or replace function ebda.make_backup(p_kind text, p_actor text, p_note text) returns jsonb
language plpgsql security definer set search_path = ebda as $mb$
declare t text; d jsonb := '{}'::jsonb; c jsonb := '{}'::jsonb; v jsonb; nm text; bid text := ebda.uid(); sz bigint;
begin
  foreach t in array ebda.backup_tables() loop
    if to_regclass('ebda.'||t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from ebda.%I x', t) into v;
    d := d || jsonb_build_object(t, v);
    c := c || jsonb_build_object(t, jsonb_array_length(v));
  end loop;
  d := d || jsonb_build_object('_meta', jsonb_build_object('schema_version', (select value from ebda.config where key='schema_version'),
                                                           'created_at', now()::text, 'tables', ebda.backup_tables()));
  nm := case when p_kind='safety' then 'SafetyBackup_' else 'Backup_' end || to_char(now() at time zone 'Africa/Cairo', 'YYYY-MM-DD_HH24-MI-SS');
  sz := octet_length(d::text);
  insert into ebda.backups(id,name,kind,created_by,size_bytes,counts,note,data) values(bid, nm, p_kind, coalesce(p_actor,''), sz, c, coalesce(p_note,''), d);
  return jsonb_build_object('id',bid,'name',nm,'kind',p_kind,'size_bytes',sz,'counts',c,'created_at',now()::text);
end $mb$;

-- الاستعادة: نسخة أمان تلقائية للحالة الحالية أولاً، ثم إحلال البيانات فى معاملة واحدة (إما كلها أو لا شىء).
-- سجل التدقيق لا يُمسح أبداً: يُدمج (تُضاف السطور غير الموجودة فقط) حتى لا يضيع أثر ما حدث بعد النسخة.
create or replace function ebda.restore_backup(p_id text, p_actor text) returns jsonb
language plpgsql security definer set search_path = ebda as $rb$
declare b ebda.backups; t text; safety jsonb; n int; restored jsonb := '{}'::jsonb; cols text;
begin
  select * into b from ebda.backups where id = p_id;
  if not found then return ebda.err('النسخة غير موجودة'); end if;
  safety := ebda.make_backup('safety', p_actor, 'قبل استعادة '||b.name);
  perform set_config('ebda.restoring', '1', true);
  foreach t in array ebda.backup_tables() loop
    if to_regclass('ebda.'||t) is null or not (b.data ? t) then continue; end if;
    select string_agg(format('%I', a.attname), ',' order by a.attnum) into cols
      from pg_attribute a where a.attrelid = ('ebda.'||t)::regclass and a.attnum > 0 and not a.attisdropped;
    if t in ('audit_log','audit_changes') then
      execute format('insert into ebda.%1$I(%2$s) select %2$s from jsonb_populate_recordset(null::ebda.%1$I, $1) r where not exists (select 1 from ebda.%1$I x where x.id = r.id)', t, cols)
        using b.data->t;
    else
      execute format('delete from ebda.%I', t);
      execute format('insert into ebda.%1$I(%2$s) select %2$s from jsonb_populate_recordset(null::ebda.%1$I, $1)', t, cols) using b.data->t;
    end if;
    get diagnostics n = row_count;
    restored := restored || jsonb_build_object(t, n);
  end loop;
  -- الأرقام المسلسلة لا ترجع للخلف (منع تكرار أرقام العمليات) — وإعادة بناء التجميعات من البيانات المستعادة
  perform set_config('ebda.restoring', '', true);
  perform ebda.rebuild_line_agg();
  return jsonb_build_object('ok', true, 'restored', b.name, 'safety_backup', safety, 'rows', restored);
end $rb$;

-- ---------------------------------------------------------------- تتبع التعديلات: لا يُسجَّل كل سطر أثناء الاستعادة (تُسجَّل العملية نفسها)
create or replace function ebda.track_change() returns trigger
language plpgsql security definer set search_path = ebda as $tc$
declare
  o jsonb; nw jsonb;
  k text; od jsonb := '{}'::jsonb; nd jsonb := '{}'::jsonb; sid text;
  hide text[] := array['pin','updated_at','updated_by','last_login'];
begin
  if coalesce(current_setting('ebda.restoring', true),'') = '1' then return null; end if;
  o  := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  nw := case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end;
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
  if tg_table_name in ('tranches','custody_lines') then
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
  foreach t in array array['custody_kinds','entity_types'] loop
    execute format('drop trigger if exists trg_track_%1$s on ebda.%1$I', t);
    execute format('create trigger trg_track_%1$s after insert or update or delete on ebda.%1$I for each row execute function ebda.track_change()', t);
  end loop;
end $tr$;

-- ---------------------------------------------------------------- فهارس الأداء
create index if not exists ix_exp_date        on ebda.expenses(date);
create index if not exists ix_exp_school_date on ebda.expenses(school_id, date);
create index if not exists ix_exp_approval    on ebda.expenses(approval);
create index if not exists ix_exp_created_by  on ebda.expenses(created_by_id);
create index if not exists ix_cust_user_id    on ebda.custodies(user_id);
create index if not exists ix_users_username  on ebda.users(username);
create index if not exists ix_users_manager   on ebda.users(manager_id);
create index if not exists ix_req_requester   on ebda.requests(requester_id);
create index if not exists ix_sessions_exp    on ebda.sessions(expires_at);
create index if not exists ix_sessions_seen   on ebda.sessions(last_seen);
create index if not exists ix_auditch_row     on ebda.audit_changes(tbl, row_id);
create index if not exists ix_pay_month_only  on ebda.payslips(month);
create index if not exists ix_cl_line         on ebda.custody_lines(line_id);

-- ---------------------------------------------------------------- إعدادات
insert into ebda.config(key,value) values ('require_doc_to_settle','no') on conflict (key) do nothing;

-- ---------------------------------------------------------------- الجلسة: تحديث «آخر نشاط» مرة كل دقيقة على الأكثر (بدلاً من كتابة مع كل طلب قراءة)
create or replace function ebda.api(req jsonb)
returns jsonb language plpgsql security definer set search_path = ebda as $w$
declare
  action text := req->>'action';
  tok text := req#>>'{auth,token}';
  th text; sess ebda.sessions; res jsonb;
  idle int := coalesce(nullif((select value from ebda.config where key='session_idle_hours'),'')::int, 12);
  maxd int := coalesce(nullif((select value from ebda.config where key='session_max_days'),'')::int, 7);
begin
  perform set_config('ebda.auth_uid', '', true);
  perform set_config('ebda.session_hash', '', true);
  if action = 'login' then
    res := ebda.api_core(req);
    if res ? 'ok' then
      tok := encode(extensions.gen_random_bytes(32), 'hex');
      insert into ebda.sessions(id, token_hash, user_id, created_at, last_seen, expires_at, user_agent)
      values (ebda.uid(), encode(extensions.digest(tok, 'sha256'), 'hex'), res#>>'{user,id}', now(), now(),
              now() + make_interval(days => maxd), left(coalesce(req->>'ua',''), 200));
      delete from ebda.sessions where expires_at < now() or last_seen < now() - make_interval(hours => idle);
      res := res || jsonb_build_object('token', tok, 'session_idle_hours', idle);
    end if;
    return res;
  end if;
  if coalesce(tok,'') <> '' then
    th := encode(extensions.digest(tok, 'sha256'), 'hex');
    if action = 'logout' then delete from ebda.sessions where token_hash = th; return jsonb_build_object('ok', true); end if;
    select * into sess from ebda.sessions
     where token_hash = th and expires_at > now() and last_seen > now() - make_interval(hours => idle);
    if not found then return ebda.err('انتهت الجلسة — سجّل الدخول من جديد'); end if;
    if sess.last_seen < now() - interval '60 seconds' then
      update ebda.sessions set last_seen = now() where id = sess.id;
    end if;
    perform set_config('ebda.auth_uid', sess.user_id, true);
    perform set_config('ebda.session_hash', th, true);
    req := req - 'auth';
  elsif action = 'logout' then
    return jsonb_build_object('ok', true);
  end if;
  return ebda.api_core(req);
end $w$;

-- ---------------------------------------------------------------- مساعدات التقارير والحسابات على الخادم (نفس قواعد الواجهة lib/model.js و lib/budget.js)
-- النطاق مرة واحدة (بدلاً من تحليل نص المدارس لكل صف)
create or replace function ebda.scope_arr(u ebda.users) returns text[] language sql immutable as $$
  select array_remove(string_to_array(regexp_replace(coalesce(u.schools,''), '\s', '', 'g'), ','), '') $$;

-- العهد المسموح بها (نفس قاعدة can_custody) بخطة استعلام مناسبة لكل دور
create or replace function ebda.vis_custodies(u ebda.users) returns setof ebda.custodies
language plpgsql stable security definer set search_path = ebda as $vc$
declare rk text := ebda.role_key(u.role); star boolean := coalesce(u.schools,'')='*'; sch text[] := ebda.scope_arr(u);
begin
  if rk = 'admin' then return query select * from ebda.custodies;
  elsif rk = 'custody_officer' then
    return query select * from ebda.custodies c where c.user_id = u.id
      union all select * from ebda.custodies c where coalesce(c.user_id,'')='' and c."user" = u.username and coalesce(u.username,'')<>'';
  else
    return query select * from ebda.custodies c
      where (coalesce(c.school_id,'')='' and rk='finance_manager') or (coalesce(c.school_id,'')<>'' and (star or c.school_id = any(sch)));
  end if;
end $vc$;

-- معرّفات المصروفات المسموح بها (نفس قاعدة can_expense) — مجموعة واحدة بدون استدعاء دالة لكل صف،
-- وتُرجع المعرّفات فقط (خفيفة) ثم تُربط بالجدول بـ hash join
create or replace function ebda.vis_expense_ids(u ebda.users) returns setof text
language plpgsql stable security definer set search_path = ebda as $vi$
declare rk text := ebda.role_key(u.role); star boolean := coalesce(u.schools,'')='*'; sch text[] := ebda.scope_arr(u);
begin
  if rk = 'admin' then return query select e.id from ebda.expenses e;
  elsif rk = 'custody_officer' then
    return query select e.id from ebda.expenses e where e.custody_id = any(array(
      select c.id from ebda.custodies c where c.user_id = u.id
      union all select c.id from ebda.custodies c where coalesce(c.user_id,'')='' and c."user" = u.username and coalesce(u.username,'')<>''));
  elsif star then
    return query select e.id from ebda.expenses e left join ebda.custodies c on c.id = e.custody_id
      where c.id is null or coalesce(c.school_id,'')<>'' or rk='finance_manager';
  else
    return query select e.id from ebda.expenses e where e.school_id = any(sch)
      union all
      select e.id from ebda.expenses e join ebda.custodies c on c.id = e.custody_id
      where coalesce(c.school_id,'')='' and rk='finance_manager';
  end if;
end $vi$;

-- المصروفات المسموح بها (صفوف كاملة) بخطة مناسبة لكل دور (فهرس العهدة لمسئول العهدة، فهرس المكان للمدير)
-- ملاحظة: للأدمن تستخدم الاستعلامات الجدول مباشرة (union all) بدلاً من هذه الدالة لتجنب تجميع كل الصفوف فى الذاكرة
create or replace function ebda.vis_expenses(u ebda.users) returns setof ebda.expenses
language plpgsql stable security definer set search_path = ebda as $ve$
declare rk text := ebda.role_key(u.role); star boolean := coalesce(u.schools,'')='*'; sch text[] := ebda.scope_arr(u);
begin
  if rk = 'admin' then return query select * from ebda.expenses;
  elsif rk = 'custody_officer' then
    return query select e.* from ebda.expenses e where e.custody_id = any(array(
      select c.id from ebda.custodies c where c.user_id = u.id
      union all select c.id from ebda.custodies c where coalesce(c.user_id,'')='' and c."user" = u.username and coalesce(u.username,'')<>''));
  elsif star then
    return query select e.* from ebda.expenses e left join ebda.custodies c on c.id = e.custody_id
      where c.id is null or coalesce(c.school_id,'')<>'' or rk='finance_manager';
  else
    -- مكان المصروف = مكان عهدته دائماً (يُفرض عند التسجيل)، فيكفى فهرس المكان
    return query select e.* from ebda.expenses e where e.school_id = any(sch)
      union all
      select e.* from ebda.expenses e join ebda.custodies c on c.id = e.custody_id
      where coalesce(c.school_id,'')='' and rk='finance_manager';
  end if;
end $ve$;

-- حدود السنة المالية من period مثل «2026/2027» ← 2026-09-01 .. 2027-08-31 (بدون سنة = بدون حدود)
create or replace function ebda.fy_from(p text) returns text language sql immutable as $$
  select case when coalesce(p,'') ~ '\d{4}' then substring(p from '\d{4}') || '-09-01' else '0000-00-00' end $$;
create or replace function ebda.fy_to(p text) returns text language sql immutable as $$
  select case when coalesce(p,'') ~ '\d{4}' then (substring(p from '\d{4}')::int + 1)::text || '-08-31' else '9999-99-99' end $$;

-- مخصص البند لشهر من السنة المالية: monthly_plan (12 قيمة) إن وُجد، وإلا السنوى ÷ 12
create or replace function ebda.plan_month(p_plan text, p_alloc numeric, m int) returns numeric language plpgsql immutable as $pm$
declare j jsonb;
begin
  begin
    j := nullif(btrim(coalesce(p_plan,'')),'')::jsonb;
  exception when others then j := null;
  end;
  if j is not null and jsonb_typeof(j)='array' and jsonb_array_length(j)=12 then
    begin
      return coalesce(nullif(j->>(m-1),'')::numeric, 0);
    exception when others then return 0;
    end;
  end if;
  return coalesce(p_alloc,0) / 12;
end $pm$;

-- حالة البند (نفس budgetStatus فى الواجهة، بهامش نصف جنيه)
create or replace function ebda.budget_state(alloc numeric, spent numeric) returns text language sql immutable as $$
  select case when coalesce(alloc,0) <= 0.5 and coalesce(spent,0) <= 0.5 then 'none'
              when coalesce(alloc,0) <= 0.5 then 'over'
              when spent > alloc + 0.5 then 'over'
              when spent >= alloc - 0.5 then 'reached'
              when spent / alloc >= 0.9 then 'near'
              else 'within' end $$;

-- عمر العهدة بالأيام من تاريخ فتحها
create or replace function ebda.days_since(d text) returns int language sql stable as $$
  select case when coalesce(d,'') ~ '^\d{4}-\d{2}-\d{2}' then (current_date - left(d,10)::date) else 0 end $$;

-- المصروف المحتسب على الموازنة لكل بند لكل شهر من السنة المالية للجهة (نفس budgetModel فى الواجهة) — {line_id: [12 قيمة]}
-- جدول تجميعى للمصروف المحتسب لكل (بند، جهة، سنة مالية، شهر) يُحدَّث داخل نفس المعاملة بـ Trigger
-- (لا يوجد Cache قديم: أى تسجيل/اعتماد/إلغاء مصروف يُحدّثه فوراً)، فتقرأ اللوحة والتقارير أرقاماً جاهزة بدلاً من مسح كل المصروفات.
create table if not exists ebda.agg_line_month(line_id text not null, school_id text not null, fy int not null, m int not null,
  amount numeric not null default 0, primary key(line_id, school_id, fy, m));
create index if not exists ix_agg_lm_school on ebda.agg_line_month(school_id);

create or replace function ebda.exp_fy(d text) returns int language sql immutable as $$
  select case when coalesce(d,'') ~ '^\d{4}-\d{2}' then case when substr(d,6,2)::int >= 9 then substr(d,1,4)::int else substr(d,1,4)::int - 1 end end $$;

create or replace function ebda.agg_line_month_trg() returns trigger language plpgsql security definer set search_path = ebda as $am$
begin
  if coalesce(current_setting('ebda.restoring', true),'') = '1' then return null; end if;
  if tg_op in ('UPDATE','DELETE') and ebda.counts_in_budget(old) and coalesce(old.line_id,'')<>'' and ebda.exp_fy(old.date) is not null then
    update ebda.agg_line_month set amount = amount - coalesce(old.amount,0)
     where line_id = old.line_id and school_id = coalesce(old.school_id,'') and fy = ebda.exp_fy(old.date) and m = ebda.fy_month(old.date);
  end if;
  if tg_op in ('UPDATE','INSERT') and ebda.counts_in_budget(new) and coalesce(new.line_id,'')<>'' and ebda.exp_fy(new.date) is not null then
    insert into ebda.agg_line_month(line_id, school_id, fy, m, amount)
    values (new.line_id, coalesce(new.school_id,''), ebda.exp_fy(new.date), ebda.fy_month(new.date), coalesce(new.amount,0))
    on conflict (line_id, school_id, fy, m) do update set amount = ebda.agg_line_month.amount + excluded.amount;
  end if;
  return null;
end $am$;
drop trigger if exists trg_agg_line_month on ebda.expenses;
create trigger trg_agg_line_month after insert or update or delete on ebda.expenses for each row execute function ebda.agg_line_month_trg();

create or replace function ebda.rebuild_line_agg() returns void language sql security definer set search_path = ebda as $rb$
  delete from ebda.agg_line_month;
  insert into ebda.agg_line_month(line_id, school_id, fy, m, amount)
  select x.line_id, coalesce(x.school_id,''), ebda.exp_fy(x.date), ebda.fy_month(x.date), sum(x.amount)
  from ebda.expenses x where ebda.counts_in_budget(x) and coalesce(x.line_id,'')<>'' and ebda.exp_fy(x.date) is not null
  group by 1, 2, 3, 4 $rb$;
do $ra$ begin perform ebda.rebuild_line_agg(); end $ra$;

-- المصروف المحتسب لكل بند لكل شهر داخل السنة المالية لجهته — تجميع فى مرور واحد على المصروفات (بدون ربط صف بصف)،
-- ثم مطابقة سنة المصروف المالية مع سنة الجهة. أساس line_months وتقارير الموازنة (نفس قاعدة budgetModel فى الواجهة).
create or replace function ebda.line_fy_spend(u ebda.users) returns table(line_id text, school_id text, m int, amount numeric)
language plpgsql stable security definer set search_path = ebda as $lf$
declare star boolean := coalesce(u.schools,'')='*' or ebda.role_key(u.role)='admin'; sch text[] := ebda.scope_arr(u);
begin
  return query
  select a.line_id, a.school_id, a.m, a.amount from ebda.agg_line_month a
  join ebda.schools s on s.id = a.school_id
  join ebda.lines l on l.id = a.line_id and coalesce(l.deleted_at,'') = ''
  where (star or a.school_id = any(sch)) and a.amount <> 0
    and (coalesce(s.period,'') !~ '\d{4}' or a.fy = substring(s.period from '\d{4}')::int);
end $lf$;

create or replace function ebda.line_months(u ebda.users) returns jsonb language sql stable as $lm$
  with z as materialized (select line_id, m, sum(amount) amount from ebda.line_fy_spend(u) group by 1, 2)
  select coalesce(jsonb_object_agg(line_id, arr), '{}'::jsonb) from (
    select k.line_id, jsonb_agg(coalesce(a.amount, 0) order by gs) arr
    from (select distinct line_id from z) k cross join generate_series(1, 12) gs
    left join z a on a.line_id = k.line_id and a.m = gs
    group by k.line_id) q $lm$;

-- ---------------------------------------------------------------- bootstrap قابل للتوسع (v6)
-- • يُبنى الرد مرة واحدة (بدون نسخ متكرر لكائن ضخم) • كل التجميعات محسوبة داخل قاعدة البيانات
-- • عند كثرة المصروفات (> bootstrap_full_limit) تُرسل «نافذة عمل» فقط: آخر bootstrap_expense_days يوماً + كل ما لم يكتمل
--   (مسودة/بانتظار/معاد/بانتظار التسوية)، والباقى متاح بالبحث والتقارير على الخادم. الأرقام كلها من التجميعات الكاملة.
insert into ebda.config(key,value) values ('bootstrap_full_limit','3000'),('bootstrap_expense_days','60'),('bootstrap_expense_max','5000'),('bootstrap_payslip_months','2')
on conflict (key) do nothing;

create or replace function ebda.cfg_int(k text, d int) returns int language sql stable as $$
  select coalesce(nullif((select value from ebda.config where key=k),'')::int, d) $$;

-- (التعريف فى 005_bootstrap.sql)


create or replace function ebda.bootstrap_v6(u ebda.users) returns jsonb
language plpgsql stable security definer set search_path = ebda as $bs$
declare
  urole text := ebda.role_key(u.role);
  sees_amounts boolean := ebda.role_key(u.role) in ('admin','finance_manager','direct_manager');
  sees_pay boolean := ebda.sees_budgets(u) or ebda.can(u,'payroll.view');
  star boolean := coalesce(u.schools,'')='*' or ebda.role_key(u.role)='admin';
  sch text[] := ebda.scope_arr(u);
  full_lim int := ebda.cfg_int('bootstrap_full_limit', 3000);
  max_ship int := ebda.cfg_int('bootstrap_expense_max', 5000);
  since text := to_char(current_date - ebda.cfg_int('bootstrap_expense_days', 60), 'YYYY-MM-DD');
  pay_months int := ebda.cfg_int('bootstrap_payslip_months', 2);
  res jsonb;
  j_admin jsonb := '{}'::jsonb; j_users jsonb := null; j_pay jsonb := null; n_pay bigint := 0; pay_from text := '';
begin
  -- كل الأجزاء الثقيلة فى استعلام واحد: العهد والمصروفات المرئية تُحسب مرة واحدة (materialized) ثم تُبنى منها كل الأجزاء والتجميعات
  with vc as materialized (select * from ebda.vis_custodies(u)),
  ve as materialized (
    select e.id, e.custody_id, e.line_id, e.school_id, e.amount, e.date, e.txn_no, e.approval, e.fin_approval, e.settled, e.cancelled_at,
           e.review_status, e.review_note, e.spend_item,
           ebda.counts_in_budget(e) as cnt, ebda.active_on_custody(e) as act, ebda.expense_stage(e) as stg
    from ebda.expenses e where urole = 'admin'
    union all
    select e.id, e.custody_id, e.line_id, e.school_id, e.amount, e.date, e.txn_no, e.approval, e.fin_approval, e.settled, e.cancelled_at,
           e.review_status, e.review_note, e.spend_item,
           ebda.counts_in_budget(e), ebda.active_on_custody(e), ebda.expense_stage(e)
    from ebda.vis_expenses(u) e where urole <> 'admin'),
  w as (select count(*) as total, count(*) > full_lim as windowed from ve),
  ship_ids as (
    select ve.id from ve, w
    where not w.windowed or ve.date >= since or ve.stg in ('draft','pending_manager','returned','pending_finance','fin_returned','reviewed')
    order by (ve.stg in ('draft','pending_manager','returned','pending_finance','fin_returned','reviewed')) desc, ve.date desc, ve.txn_no desc
    limit case when (select windowed from w) then max_ship else null end),
  ship as (select e.* from ebda.expenses e join ship_ids using (id)),
  stages as (select stg, count(*) n, sum(amount) amount from ve group by stg),
  tagg as (select t.custody_id, sum(t.amount) s from ebda.tranches t where t.custody_id = any(array(select id from vc)) group by 1),
  cagg as (
    select custody_id, sum(amount) filter (where act) spent, count(*) n,
           count(*) filter (where approval='pending' and coalesce(cancelled_at,'')='') pending_n,
           count(*) filter (where act and approval='approved' and coalesce(settled,'') not like '%نعم%') unsettled_n,
           count(*) filter (where coalesce(cancelled_at,'')='' and coalesce(settled,'') not like '%نعم%'
              and (approval in ('rejected','returned') or fin_approval in ('rejected','returned') or coalesce(review_status,'') like '%ناقص%' or coalesce(review_note,'')<>'')) notes_n
    from ve where coalesce(custody_id,'')<>'' group by 1),
  clagg as (select custody_id || '|' || coalesce(line_id,'') k, sum(amount) s from ve where act and coalesce(custody_id,'')<>'' group by 1),
  -- تجميعات الموازنة فى مرور واحد على المصروفات (GROUPING SETS)
  g as (
    select grouping(line_id, school_id, item, m) gid, line_id, school_id, item, m,
           sum(amount) filter (where cnt) counted, sum(amount) filter (where act and not cnt) pend, count(*) n
    from (select line_id, school_id, amount, cnt, act,
                 coalesce(nullif(spend_item,''), case when coalesce(custody_id,'')<>'' then 'مصروف عهدة (غير مصنّف)' else 'شراء مركزى' end) item,
                 ebda.fy_month(date) m from ve where sees_amounts) z
    group by grouping sets ((line_id), (school_id), (school_id, item, m), (school_id, m)))
  select jsonb_build_object(
    'expenses', coalesce((select jsonb_agg(to_jsonb(ship) - 'doc_url' - 'ref'
                          || jsonb_build_object('doc_url', case when ship.doc_url like 'data:%' then 'inline:' else coalesce(ship.doc_url,'') end)) from ship), '[]'::jsonb),
    'window', (select jsonb_build_object('windowed', w.windowed, 'since', case when w.windowed then since else '' end,
                      'shipped', (select count(*) from ship), 'total', w.total) from w),
    'custodies', coalesce((select jsonb_agg(to_jsonb(vc) || jsonb_build_object(
        'received', coalesce(tagg.s,0), 'spent', coalesce(cagg.spent,0), 'exp_count', coalesce(cagg.n,0),
        'pending_n', coalesce(cagg.pending_n,0), 'unsettled_n', coalesce(cagg.unsettled_n,0), 'notes_n', coalesce(cagg.notes_n,0),
        'manager_id', coalesce(o.manager_id,'')))
      from vc left join tagg on tagg.custody_id = vc.id left join cagg on cagg.custody_id = vc.id left join ebda.users o on o.id = vc.user_id), '[]'::jsonb),
    'tranches', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.tranches t where t.custody_id = any(array(select id from vc))), '[]'::jsonb),
    'custody_lines', coalesce((select jsonb_agg(to_jsonb(cl)) from ebda.custody_lines cl where cl.custody_id = any(array(select id from vc))), '[]'::jsonb),
    'agg', jsonb_build_object('custody_line_spent', coalesce((select jsonb_object_agg(k, s) from clagg where k not like '%|'), '{}'::jsonb),
                              'stages', coalesce((select jsonb_object_agg(stg, jsonb_build_object('n', n, 'amount', amount)) from stages), '{}'::jsonb))
      || case when sees_amounts then jsonb_build_object(
        'line_spent', coalesce((select jsonb_object_agg(line_id, counted) from g where gid = 7 and coalesce(line_id,'')<>'' and counted is not null), '{}'::jsonb),
        'line_exp_count', coalesce((select jsonb_object_agg(line_id, n) from g where gid = 7 and coalesce(line_id,'')<>''), '{}'::jsonb),
        'school_spent', coalesce((select jsonb_object_agg(school_id, counted) from g where gid = 11 and counted is not null), '{}'::jsonb),
        'school_pending', coalesce((select jsonb_object_agg(school_id, pend) from g where gid = 11 and pend is not null), '{}'::jsonb),
        'spend_types', coalesce((select jsonb_agg(jsonb_build_object('school_id', school_id, 'item', item, 'm', m, 'amount', counted)) from g where gid = 8 and counted is not null), '[]'::jsonb),
        'month_spent', coalesce((select jsonb_agg(jsonb_build_object('school_id', school_id, 'm', m, 'amount', counted)) from g where gid = 10 and m is not null and counted is not null), '[]'::jsonb))
      else '{}'::jsonb end,
    'requests', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object(
        'stage', case when r.status='transferred' and exists(select 1 from ebda.custodies c where c.id=r.custody_id and c.status in ('settled','closed')) then 'settled'
                      when r.status='transferred' and exists(select 1 from ebda.expenses e where e.custody_id=r.custody_id and e.created_at>=r.fin_at) then 'spent'
                      else r.status end,
        'items', coalesce((select jsonb_agg(to_jsonb(it)) from ebda.request_items it where it.request_id=r.id),'[]'::jsonb)))
      from ebda.requests r
      where (urole='custody_officer' and ((coalesce(r.requester_id,'')<>'' and r.requester_id=u.id) or (coalesce(r.requester_id,'')='' and r.requester=u.username)))
         or (urole<>'custody_officer' and (star or r.school_id = any(sch)))), '[]'::jsonb)
  ) into res;

  res := res || jsonb_build_object(
    'ok', true, 'schema_version', 1,
    'me', jsonb_build_object('id',u.id,'username',u.username,'name',u.name,'role',coalesce(ebda.role_legacy(u.role),u.role),
            'role_key',urole,'role_label',ebda.role_label(u.role),'schools',u.schools,'perms',coalesce(u.perms,''),
            'must_reset',coalesce(u.must_reset,'لا'),'permissions',to_jsonb(ebda.perms_of(u)),'manager_id',coalesce(u.manager_id,'')),
    'schools', coalesce((select jsonb_agg(to_jsonb(s) order by (coalesce(s.active,'') like '%نعم%') desc, s.name) from ebda.schools s where star or s.id = any(sch)),'[]'::jsonb),
    'lines', case when sees_amounts
      then coalesce((select jsonb_agg(to_jsonb(l)) from ebda.lines l where (star or l.school_id = any(sch)) and coalesce(l.deleted_at,'')=''),'[]'::jsonb)
      else coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'school_id',l.school_id,'section',l.section,'name',l.name,'active',coalesce(l.active,'نعم'))) from ebda.lines l
                     where (star or l.school_id = any(sch)) and coalesce(l.deleted_at,'')=''),'[]'::jsonb) end,
    'custody_names', coalesce((select jsonb_agg(to_jsonb(z) order by z.sort, z.name) from ebda.custody_names z),'[]'::jsonb),
    'custody_kinds', coalesce((select jsonb_agg(to_jsonb(z) order by z.sort, z.name) from ebda.custody_kinds z),'[]'::jsonb),
    'entity_types', coalesce((select jsonb_agg(to_jsonb(z) order by z.sort) from ebda.entity_types z),'[]'::jsonb),
    'team', coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'username',z.username,'name',z.name)) from ebda.users z where z.manager_id=u.id),'[]'::jsonb),
    'managers', coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'name',z.name,'role_key',ebda.role_key(z.role)))
        from ebda.users z where ebda.role_key(z.role) in ('direct_manager','admin') and coalesce(z.active,'') like '%نعم%'
          and (case when urole = 'custody_officer' then z.id = coalesce(u.manager_id,'')
                    else star or ebda.role_key(z.role)='admin' or coalesce(z.schools,'')='*' or ebda.scope_arr(z) && sch end)),'[]'::jsonb),
    'spendItems', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.spend_items z),'[]'::jsonb),
    'holders', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.holders z),'[]'::jsonb),
    'approvers', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.approvers z),'[]'::jsonb),
    'emails', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.emails z),'[]'::jsonb),
    'settings', jsonb_build_object('custody_overdue_days', ebda.cfg_int('custody_overdue_days', 30),
        'require_doc_to_settle', coalesce((select value from ebda.config where key='require_doc_to_settle'),'no')));
  if sees_amounts then res := res || jsonb_build_object('line_months', ebda.line_months(u)); end if;

  if sees_pay then
    select count(*) into n_pay from ebda.payslips z where star or z.school_id = any(sch);
    if n_pay > ebda.cfg_int('bootstrap_payslip_limit', 5000) then
      -- آخر N شهر به قسائم فعلاً (وليس شهوراً تقويمية) — والأقدم يُطلب عند اختياره (payrollMonth)
      select coalesce(min(m), '') into pay_from from (select distinct z.month m from ebda.payslips z
        where (star or z.school_id = any(sch)) and z.month ~ '^[0-9]{4}-[0-9]{2}$' order by 1 desc limit pay_months) q;
    end if;
    res := res || jsonb_build_object(
      'payroll_periods', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.payroll_periods z where star or z.school_id = any(sch)),'[]'::jsonb),
      'payroll_components', coalesce((select jsonb_agg(to_jsonb(z) order by z.sort) from ebda.payroll_components z),'[]'::jsonb),
      'payroll_map', coalesce((select value from ebda.config where key='payroll_map'),''),
      'salaries', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.salaries z where star or z.school_id = any(sch)),'[]'::jsonb),
      'employees', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.employees z where star or z.school_id = any(sch)),'[]'::jsonb),
      'payslips', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.payslips z where (star or z.school_id = any(sch)) and (pay_from = '' or z.month >= pay_from)),'[]'::jsonb),
      'payslips_window', jsonb_build_object('windowed', pay_from <> '', 'from', pay_from, 'total', n_pay),
      -- ملخص كل الشهور (للمقارنات والتحليلات) محسوب على الخادم
      'payroll_months', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'school_id', school_id, 'net', net, 'n', n) order by month) from (
          select z.month, z.school_id, sum(z.net) net, count(*) n from ebda.payslips z where star or z.school_id = any(sch) group by 1, 2) q),'[]'::jsonb));
  end if;

  if urole='admin' then
    res := res || jsonb_build_object(
      'deletedBudgets', coalesce((select jsonb_agg(x) from (
          select l.school_id, count(*) as lines, sum(l.allocated) as total, max(l.deleted_at) as deleted_at, max(l.deleted_by) as deleted_by, max(l.delete_reason) as reason
          from ebda.lines l where coalesce(l.deleted_at,'')<>'' group by l.school_id) x),'[]'::jsonb),
      'tempBudgets', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.temp_budgets z),'[]'::jsonb),
      'backups', coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'kind',b.kind,'created_at',b.created_at,
          'created_by',b.created_by,'size_bytes',b.size_bytes,'counts',b.counts,'note',b.note) order by b.created_at desc) from ebda.backups b),'[]'::jsonb),
      'audit', coalesce((select jsonb_agg(to_jsonb(a)) from (select * from ebda.audit_log order by ts desc limit 1000) a),'[]'::jsonb),
      'audit_changes', coalesce((select jsonb_agg(to_jsonb(c)) from ebda.audit_changes c
          where c.txid in (select q.txid from (select txid from ebda.audit_log where txid is not null order by ts desc limit 1000) q)),'[]'::jsonb));
  end if;
  if ebda.can_manage_users(u) then
    res := res || jsonb_build_object('users', coalesce((select jsonb_agg(ebda.user_public(z)) from ebda.users z),'[]'::jsonb));
  elsif urole='finance_manager' then
    res := res || jsonb_build_object('users', coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'username',z.username,'name',z.name,'role',z.role,
        'role_label',ebda.role_label(z.role),'manager_id',coalesce(z.manager_id,''))) from ebda.users z
        where star or coalesce(z.schools,'')='*' or ebda.role_key(z.role)='admin' or ebda.scope_arr(z) && sch),'[]'::jsonb));
  end if;
  return res;
end $bs$;


-- ================================================================ v6: استيراد ملف المصروفات والعهد (القالب المعتمد — بدون ربط أعمدة يدوى)
-- الواجهة تقرأ الملف وتتعرف على الأعمدة تلقائياً وترسل صفوفاً موحّدة؛ وهنا تتم كل المطابقة والتحقق والإنشاء داخل معاملة واحدة:
-- المدرسة ← العهدة (تُنشأ تلقائياً إن لم توجد: المسئول + المدرسة + القيمة + التاريخ) ← البند (رئيسى/فرعى) ← الشهر من التاريخ ← المصروف.
-- السجلات التى بها مشكلة لا توقف الاستيراد: تُستبعد وتظهر فى تقرير الاستثناءات. المكرر (داخل الملف أو المسجل من قبل) لا يُستورد.
alter table ebda.expenses  add column if not exists supplier text default '';
alter table ebda.expenses  add column if not exists doc_no text default '';
alter table ebda.expenses  add column if not exists import_batch text default '';
alter table ebda.expenses  add column if not exists import_row text default '';
alter table ebda.custodies add column if not exists ext_ref text default '';
alter table ebda.custodies add column if not exists import_batch text default '';
create index if not exists ix_exp_import_batch on ebda.expenses(import_batch) where coalesce(import_batch,'') <> '';
create index if not exists ix_cust_ext_ref on ebda.custodies(school_id, ext_ref) where coalesce(ext_ref,'') <> '';
create index if not exists ix_exp_dup on ebda.expenses(custody_id, date, amount);

create table if not exists ebda.import_batches(
  id text primary key, kind text default 'expenses', file_name text default '', actor text default '', actor_id text default '',
  created_at timestamptz default now(), approve_mode text default 'workflow', rows_n int default 0, imported_n int default 0,
  amount numeric default 0, summary jsonb default '{}'::jsonb, exceptions jsonb default '[]'::jsonb,
  reverted_at text default '', reverted_by text default '');
create index if not exists ix_import_batches_created on ebda.import_batches(created_at desc);

-- صلاحية جديدة: expense.import (الأدمن والمدير المالى افتراضياً؛ وتُمنح لغيرهم من شاشة المستخدمين)
create or replace function ebda.perm_defaults(rk text) returns text[] language sql immutable as $$
  select case rk
    when 'admin' then array['budget.edit','custody.create','custody.approve','expense.record','expense.approve','expense.fin_approve',
                            'request.approve','request.fin_approve','payroll.view','payroll.import','payroll.approve','manage_users','expense.import']
    when 'finance_manager' then array['budget.edit','custody.create','custody.approve','expense.fin_approve','request.fin_approve',
                            'payroll.view','payroll.import','payroll.approve','expense.import']
    when 'direct_manager' then array['expense.approve','request.approve']
    when 'custody_officer' then array['expense.record']
    else array[]::text[] end
$$;

-- أرقام عربية/فارسية ← لاتينية، وإزالة الفواصل والعملة
create or replace function ebda.imp_num(t text) returns numeric language plpgsql immutable as $n$
declare s text := translate(coalesce(t,''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫', '01234567890123456789.');
begin
  s := regexp_replace(s, '[,٬\s]|ج\.?م\.?|جنيه|EGP|LE', '', 'gi');
  if s !~ '^-?[0-9]+(\.[0-9]+)?$' then return null; end if;
  return s::numeric;
end $n$;

create or replace function ebda.imp_date_ok(d text) returns boolean language plpgsql immutable as $d$
begin
  if coalesce(d,'') !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  perform d::date; return true;
exception when others then return false;
end $d$;

create or replace function ebda.import_expenses(u ebda.users, req jsonb) returns jsonb
language plpgsql security definer set search_path = ebda as $ie$
declare
  urole text := ebda.rk(u);
  commit_ boolean := coalesce(req->>'mode','preview') = 'commit';
  amode text := case when coalesce(req->>'approve_mode','') = 'approved' and ebda.rk(u) = 'admin' then 'approved' else 'workflow' end;
  fname text := left(coalesce(req->>'file_name',''), 200);
  bid text := ebda.uid();
  sch text[] := ebda.scope_arr(u);
  can_new boolean := ebda.can(u,'custody.create') and ebda.can(u,'custody.approve');
  rw jsonb; i int := 0; st text; errs jsonb; warns jsonb;
  sid text; sname text; ckey text; cno text; hold text; cdate text; d text; mth text; fm text;
  amt numeric; camt numeric; cid text; ccode text; cnew boolean;
  cust ebda.custodies; lid text; lname text; m_ text; s_ text; n int; k text; dupof text;
  hu ebda.users; newid text; dkey text; extra text;
  cmap jsonb := '{}'::jsonb;    -- مفتاح العهدة ← بياناتها (موجودة/جديدة)
  lmap jsonb := '{}'::jsonb;    -- (مدرسة|رئيسى|فرعى) ← البند
  smap jsonb := '{}'::jsonb;    -- اسم المدرسة ← id
  seen text[] := '{}';
  out jsonb := '[]'::jsonb;
  c_ok int := 0; c_warn int := 0; c_dup int := 0; c_err int := 0; tot numeric := 0;
  months jsonb := '{}'::jsonb; lamt jsonb := '{}'::jsonb; camts jsonb := '{}'::jsonb;
  cinfo jsonb; linfo jsonb; res jsonb; exc jsonb;
begin
  if not (urole = 'admin' or ebda.can(u,'expense.import')) then return ebda.err('صلاحية استيراد المصروفات مطلوبة'); end if;
  if jsonb_typeof(coalesce(req->'rows','null'::jsonb)) <> 'array' or jsonb_array_length(req->'rows') = 0 then
    return ebda.err('لم يُتعرَّف على أى صف مصروفات فى الملف'); end if;
  if jsonb_array_length(req->'rows') > 20000 then return ebda.err('الملف أكبر من 20,000 صف — قسّمه إلى أكثر من ملف'); end if;

  for rw in select * from jsonb_array_elements(req->'rows') loop
    i := i + 1; errs := '[]'::jsonb; st := 'ok';
    warns := case when jsonb_typeof(rw->'warnings') = 'array' then rw->'warnings' else '[]'::jsonb end;
    sid := null; sname := ''; cid := null; ccode := ''; cnew := false; lid := null; lname := ''; amt := null; dupof := null; mth := '';
    ckey := null; cinfo := null; linfo := null; d := '';

    -- ---------------------------------------------------------- 1) المدرسة
    if coalesce(rw->>'school_id','') <> '' and exists(select 1 from ebda.schools s where s.id = rw->>'school_id') then
      sid := rw->>'school_id';
    elsif btrim(coalesce(rw->>'school','')) <> '' then
      k := ebda.norm_txt(rw->>'school');
      if smap ? k then sid := smap->>k;
      else
        select min(s.id), count(*) into sid, n from ebda.schools s where ebda.norm_txt(s.name) = k;
        if n <> 1 then
          select min(s.id), count(*) into sid, n from ebda.schools s
           where length(k) >= 3 and (ebda.norm_txt(s.name) like '%'||k||'%' or k like '%'||ebda.norm_txt(s.name)||'%');
        end if;
        if n <> 1 then sid := null; end if;
        smap := smap || jsonb_build_object(k, sid);
      end if;
      if sid is null then errs := errs || to_jsonb('المدرسة غير معروفة: '||btrim(rw->>'school')); end if;
    elsif urole <> 'admin' and coalesce(u.schools,'') <> '*' and cardinality(sch) = 1 then
      sid := sch[1]; warns := warns || to_jsonb('المدرسة غير مذكورة فى الملف — استُخدم مكانك'::text);
    else
      errs := errs || to_jsonb('المدرسة غير محددة'::text);
    end if;
    if sid is not null and not ebda.can_school(u, sid) then errs := errs || to_jsonb('المدرسة ليست ضمن نطاقك'::text); sid := null; end if;
    if sid is not null then select s.name into sname from ebda.schools s where s.id = sid; end if;

    -- ---------------------------------------------------------- 2) القيمة والتاريخ والشهر
    amt := ebda.imp_num(rw->>'amount');
    if amt is null or amt <= 0 then errs := errs || to_jsonb('قيمة المصروف غير صحيحة: '||coalesce(nullif(rw->>'amount',''),'فارغة')); end if;
    d := btrim(coalesce(rw->>'date',''));
    if not ebda.imp_date_ok(d) then
      errs := errs || to_jsonb('تاريخ المصروف غير صحيح: '||coalesce(nullif(rw->>'date_raw',''), nullif(d,''), 'فارغ'));
    elsif d > to_char(now() + interval '1 day','YYYY-MM-DD') then
      -- غالباً اليوم والشهر مقلوبان فى Excel (12/09 ← 09/12): نقترح التاريخ الصحيح
      errs := errs || to_jsonb('تاريخ المصروف فى المستقبل: '||d||
        case when substr(d,9,2)::int <= 12 and ebda.imp_date_ok(substr(d,1,4)||'-'||substr(d,9,2)||'-'||substr(d,6,2))
                  and substr(d,1,4)||'-'||substr(d,9,2)||'-'||substr(d,6,2) <= to_char(now(),'YYYY-MM-DD')
             then ' (ربما المقصود '||substr(d,1,4)||'-'||substr(d,9,2)||'-'||substr(d,6,2)||' — اليوم والشهر مقلوبان)' else '' end);
    else
      mth := substr(d,1,7);
      fm := btrim(coalesce(rw->>'month',''));
      if fm ~ '^\d{1,2}$' and fm::int <> substr(d,6,2)::int then
        warns := warns || to_jsonb('الشهر فى الملف ('||fm||') لا يطابق تاريخ المصروف — اعتُمد شهر التاريخ');
      elsif fm ~ '^\d{4}-\d{2}$' and fm <> mth then
        warns := warns || to_jsonb('الشهر فى الملف ('||fm||') لا يطابق تاريخ المصروف — اعتُمد شهر التاريخ');
      end if;
    end if;

    -- مصروف خارج السنة المالية لموازنة المدرسة (سبتمبر ← أغسطس): يُستورد على العهدة لكنه لا يدخل فى منصرف موازنة السنة الحالية
    if sid is not null and mth <> '' and exists(select 1 from ebda.schools s where s.id = sid and coalesce(s.period,'') ~ '\d{4}'
         and ebda.exp_fy(d) <> substring(s.period from '\d{4}')::int) then
      warns := warns || to_jsonb('التاريخ خارج السنة المالية للموازنة ('||(select s.period from ebda.schools s where s.id = sid)||') — لن يظهر فى منصرف موازنة هذه السنة');
    end if;

    -- ---------------------------------------------------------- 3) العهدة (موجودة أو تُنشأ)
    cno := btrim(translate(coalesce(rw->>'custody_no',''), '٠١٢٣٤٥٦٧٨٩', '0123456789'));
    hold := btrim(regexp_replace(coalesce(rw->>'holder',''), '\s+', ' ', 'g'));
    cdate := btrim(coalesce(rw->>'custody_date',''));
    camt := case when btrim(coalesce(rw->>'custody_amount','')) = '' then null else ebda.imp_num(rw->>'custody_amount') end;
    if btrim(coalesce(rw->>'custody_amount','')) <> '' and (camt is null or camt < 0) then
      errs := errs || to_jsonb('قيمة العهدة غير صحيحة: '||(rw->>'custody_amount')); end if;
    if cdate <> '' and not ebda.imp_date_ok(cdate) then
      warns := warns || to_jsonb('تاريخ العهدة غير مفهوم: '||coalesce(nullif(rw->>'custody_date_raw',''), cdate)); cdate := ''; end if;
    if sid is not null then
      if cno = '' and hold = '' then
        errs := errs || to_jsonb('رقم العهدة ومسئول العهدة غير موجودين'::text);
      else
        ckey := sid || '|' || case when cno <> '' then 'n:'||upper(cno) else 'h:'||ebda.norm_txt(hold) end;
        if cmap ? ckey then
          cinfo := cmap->ckey;
        else
          cust := null;
          if cno <> '' then
            select * into cust from ebda.custodies c where c.school_id = sid and c.ext_ref = cno and coalesce(c.status,'') <> 'cancelled'
              order by c.opened_at desc limit 1;
            if cust.id is null then
              select * into cust from ebda.custodies c where upper(c.code) = upper(cno) limit 1;
            end if;
          else
            select * into cust from ebda.custodies c where c.school_id = sid and coalesce(c.status,'open') in ('open','pending_settlement')
              and ebda.norm_txt(coalesce(nullif(c.holder,''), c.label)) = ebda.norm_txt(hold) order by c.opened_at desc limit 1;
          end if;
          if cust.id is not null then
            cinfo := jsonb_build_object('id', cust.id, 'code', cust.code, 'new', false, 'school_id', cust.school_id,
              'holder', coalesce(nullif(cust.holder,''), cust.label, ''), 'status', coalesce(cust.status,'open'),
              'approval', coalesce(cust.approval,'approved'), 'user_id', coalesce(cust.user_id,''), 'user', coalesce(cust."user",''),
              'received', (select coalesce(sum(t.amount),0) from ebda.tranches t where t.custody_id = cust.id),
              'spent', (select coalesce(sum(e.amount),0) from ebda.expenses e where e.custody_id = cust.id and ebda.active_on_custody(e)),
              'restricted', exists(select 1 from ebda.custody_lines cl where cl.custody_id = cust.id),
              'ext_ref', cno, 'file_amount', camt, 'warn_holder', '');
          else
            hu := null; k := '';
            if hold <> '' then
              select * into hu from ebda.users z where coalesce(z.active,'نعم') like '%نعم%' and ebda.norm_txt(z.name) = ebda.norm_txt(hold)
                and (coalesce(z.schools,'') = '*' or sid = any(ebda.scope_arr(z)))
                order by case when ebda.rk(z) = 'custody_officer' then 0 else 1 end limit 1;
            else
              -- الملف لا يذكر المسئول (ورقة لكل عهدة): يُربط بمسئول العهدة الوحيد فى المدرسة إن وُجد، وإلا تُنشأ باسم الورقة
              select count(*) into n from ebda.users z where coalesce(z.active,'نعم') like '%نعم%' and ebda.rk(z) = 'custody_officer'
                and coalesce(z.schools,'') <> '*' and sid = any(ebda.scope_arr(z));
              if n = 1 then
                select * into hu from ebda.users z where coalesce(z.active,'نعم') like '%نعم%' and ebda.rk(z) = 'custody_officer'
                  and coalesce(z.schools,'') <> '*' and sid = any(ebda.scope_arr(z));
                k := 'مسئول العهدة غير مذكور فى الملف — رُبطت العهدة بمسئول العهدة الوحيد فى المدرسة: '||hu.name;
              else
                k := 'مسئول العهدة غير مذكور فى الملف — أُنشئت العهدة باسم «'||cno||'»؛ حدّد مسئولها من شاشة العهد';
              end if;
            end if;
            cinfo := jsonb_build_object('id', null, 'code', '', 'new', true, 'school_id', sid,
              'holder', coalesce(nullif(hold,''), hu.name, cno), 'auto_note', k, 'note', left(coalesce(rw->>'custody_note',''), 1000), 'status', 'open', 'approval', 'approved',
              'user_id', coalesce(hu.id,''), 'user', coalesce(hu.username,''), 'received', coalesce(camt,0), 'spent', 0, 'restricted', false,
              'ext_ref', cno, 'file_amount', camt, 'date', cdate, 'first_date', d);
          end if;
          cmap := cmap || jsonb_build_object(ckey, cinfo);
        end if;

        if (cinfo->>'new')::boolean then
          cnew := true;
          if not can_new then errs := errs || to_jsonb('العهدة '||coalesce(nullif(cno,''), hold)||' غير موجودة ولا تملك صلاحية إنشاء واعتماد العهد'); end if;
          if coalesce(cinfo->>'holder','') = '' then errs := errs || to_jsonb('اسم مسئول العهدة مطلوب لإنشاء العهدة '||cno); end if;
          if hold <> '' and ebda.norm_txt(hold) <> ebda.norm_txt(cinfo->>'holder') then
            warns := warns || to_jsonb('نفس رقم العهدة بمسئول مختلف فى الملف ('||hold||') — اعتُمد '||(cinfo->>'holder')); end if;
          if camt is not null and cinfo->>'file_amount' is not null and camt <> (cinfo->>'file_amount')::numeric then
            warns := warns || to_jsonb('قيمة العهدة تختلف بين صفوف الملف — اعتُمدت '||(cinfo->>'file_amount')); end if;
          if (cinfo->>'file_amount') is null and camt is not null then
            cinfo := cinfo || jsonb_build_object('file_amount', camt, 'received', camt); cmap := cmap || jsonb_build_object(ckey, cinfo); end if;
          if coalesce(cinfo->>'date','') = '' and cdate <> '' then
            cinfo := cinfo || jsonb_build_object('date', cdate); cmap := cmap || jsonb_build_object(ckey, cinfo); end if;
          if coalesce(cinfo->>'auto_note','') <> '' and not (cinfo ? 'warned_user') then
            warns := warns || to_jsonb(cinfo->>'auto_note');
            cinfo := cinfo || '{"warned_user":true}'::jsonb; cmap := cmap || jsonb_build_object(ckey, cinfo);
          end if;
          if coalesce(cinfo->>'user_id','') = '' and coalesce(cinfo->>'holder','') <> '' and not (cinfo ? 'warned_user') then
            warns := warns || to_jsonb('مسئول العهدة «'||(cinfo->>'holder')||'» غير مسجل كمستخدم — ستُنشأ العهدة باسمه بدون حساب دخول (اربطه لاحقاً)');
            cinfo := cinfo || '{"warned_user":true}'::jsonb; cmap := cmap || jsonb_build_object(ckey, cinfo);
          end if;
        else
          cid := cinfo->>'id'; ccode := cinfo->>'code';
          if cinfo->>'school_id' <> sid then errs := errs || to_jsonb('رقم العهدة '||cno||' تابع لمدرسة أخرى'); end if;
          if cinfo->>'status' in ('settled','closed') then errs := errs || to_jsonb('العهدة '||ccode||' مسوّاة/مغلقة'); end if;
          if cinfo->>'status' = 'cancelled' then errs := errs || to_jsonb('العهدة '||ccode||' ملغاة'); end if;
          if cinfo->>'approval' <> 'approved' then errs := errs || to_jsonb('العهدة '||ccode||' لم تُعتمد بعد'); end if;
          if urole not in ('admin','finance_manager') and coalesce(cinfo->>'user_id','') <> u.id and coalesce(cinfo->>'user','') <> u.username then
            errs := errs || to_jsonb('العهدة '||ccode||' ليست عهدتك'); end if;
          if hold <> '' and ebda.norm_txt(hold) <> ebda.norm_txt(cinfo->>'holder') then
            warns := warns || to_jsonb('اسم المسئول فى الملف ('||hold||') يختلف عن المسجل ('||(cinfo->>'holder')||')'); end if;
          if camt is not null and abs(camt - (cinfo->>'received')::numeric) > 0.5 then
            warns := warns || to_jsonb('قيمة العهدة فى الملف ('||camt||') تختلف عن المسجلة ('||(cinfo->>'received')||') — لم تُعدَّل'); end if;
        end if;
      end if;
    end if;

    -- ---------------------------------------------------------- 4) البند (رئيسى ← فرعى) من موازنة المدرسة
    m_ := ebda.norm_txt(rw->>'main'); s_ := ebda.norm_txt(rw->>'sub');
    if sid is not null then
      if m_ = '' and s_ = '' then
        errs := errs || to_jsonb('البند غير مذكور'::text);
      else
        k := sid || '|' || m_ || '|' || s_;
        if lmap ? k then linfo := lmap->k;
        else
          linfo := null;
          declare cand text[]; how text := '';
          begin
            if s_ <> '' then
              cand := array(select l.id from ebda.lines l where l.school_id = sid and coalesce(l.deleted_at,'') = '' and ebda.norm_txt(l.name) = s_
                              and (m_ = '' or ebda.norm_txt(l.section) = m_));
              if cardinality(cand) = 0 and m_ <> '' then
                cand := array(select l.id from ebda.lines l where l.school_id = sid and coalesce(l.deleted_at,'') = '' and ebda.norm_txt(l.name) = s_);
                if cardinality(cand) = 1 then how := 'section'; end if;
              end if;
              if cardinality(cand) = 0 then
                cand := array(select l.id from ebda.lines l where l.school_id = sid and coalesce(l.deleted_at,'') = '' and length(s_) >= 3
                                and (ebda.norm_txt(l.name) like '%'||s_||'%' or s_ like '%'||ebda.norm_txt(l.name)||'%')
                                and (m_ = '' or ebda.norm_txt(l.section) = m_ or ebda.norm_txt(l.section) like '%'||m_||'%'));
                if cardinality(cand) = 1 then how := 'approx'; end if;
              end if;
            else
              cand := array(select l.id from ebda.lines l where l.school_id = sid and coalesce(l.deleted_at,'') = '' and ebda.norm_txt(l.name) = m_);
              if cardinality(cand) = 0 then
                cand := array(select l.id from ebda.lines l where l.school_id = sid and coalesce(l.deleted_at,'') = '' and ebda.norm_txt(l.section) = m_);
                if cardinality(cand) > 1 then cand := '{}'; how := 'many'; end if;
              end if;
            end if;
            if cardinality(cand) = 1 then
              select jsonb_build_object('id', l.id, 'name', l.name, 'section', coalesce(l.section,''), 'active', coalesce(l.active,'نعم') like '%نعم%', 'how', how)
                into linfo from ebda.lines l where l.id = cand[1];
            else
              linfo := jsonb_build_object('id', null, 'many', cardinality(cand) > 1 or how = 'many');
            end if;
          end;
          lmap := lmap || jsonb_build_object(k, linfo);
        end if;
        if linfo->>'id' is null then
          errs := errs || to_jsonb(case when (linfo->>'many')::boolean then 'البند يطابق أكثر من بند فى موازنة المدرسة — حدّد البند الفرعى: '
                                        else 'بند غير معروف فى موازنة المدرسة: ' end
                                   || concat_ws(' / ', nullif(btrim(rw->>'main'),''), nullif(btrim(rw->>'sub'),'')));
        else
          lid := linfo->>'id'; lname := linfo->>'name';
          if not (linfo->>'active')::boolean then errs := errs || to_jsonb('البند معطّل — لا يقبل مصروفات: '||lname); end if;
          if linfo->>'how' = 'section' then warns := warns || to_jsonb('البند الرئيسى فى الملف يختلف عن قسم البند فى الموازنة ('||(linfo->>'section')||')'); end if;
          if linfo->>'how' = 'approx' then warns := warns || to_jsonb('طوبق البند تقريبياً: «'||btrim(coalesce(rw->>'sub',''))||'» ← «'||lname||'»'); end if;
          if cid is not null and (cinfo->>'restricted')::boolean
             and not exists(select 1 from ebda.custody_lines cl where cl.custody_id = cid and cl.line_id = lid) then
            errs := errs || to_jsonb('البند «'||lname||'» غير مخصص للعهدة '||ccode); end if;
        end if;
      end if;
    end if;

    -- ---------------------------------------------------------- 5) التكرار (داخل الملف أو مسجل من قبل)
    if jsonb_array_length(errs) = 0 then
      dkey := coalesce(ckey,'') || '|' || d || '|' || amt::text || '|' ||
              case when ebda.norm_txt(rw->>'doc_no') <> '' then 'doc:'||ebda.norm_txt(rw->>'doc_no') else 'txt:'||ebda.norm_txt(rw->>'description') end;
      if dkey = any(seen) then
        st := 'duplicate'; dupof := 'مكرر داخل الملف (نفس العهدة والتاريخ والقيمة والمستند/الوصف)';
      elsif cid is not null then
        select e.txn_no into k from ebda.expenses e
         where e.custody_id = cid and e.date = d and e.amount = amt and coalesce(e.cancelled_at,'') = ''
           and case when ebda.norm_txt(rw->>'doc_no') <> '' then ebda.norm_txt(e.doc_no) = ebda.norm_txt(rw->>'doc_no')
                         or (coalesce(e.doc_no,'') = '' and ebda.norm_txt(e.description) = ebda.norm_txt(rw->>'description'))
                    else ebda.norm_txt(e.description) = ebda.norm_txt(rw->>'description') end
         limit 1;
        if k is not null then st := 'duplicate'; dupof := 'مسجل من قبل ('||k||')'; end if;
      end if;
      seen := seen || dkey;
    end if;

    if jsonb_array_length(errs) > 0 then st := 'error'; c_err := c_err + 1;
    elsif st = 'duplicate' then c_dup := c_dup + 1;
    else
      if jsonb_array_length(warns) > 0 then st := 'warning'; c_warn := c_warn + 1; else c_ok := c_ok + 1; end if;
      tot := tot + amt;
      months := months || jsonb_build_object(mth, coalesce((months->>mth)::numeric,0) + amt);
      lamt := lamt || jsonb_build_object(lid, coalesce((lamt->>lid)::numeric,0) + amt);
      camts := camts || jsonb_build_object(ckey, coalesce((camts->>ckey)::numeric,0) + amt);
    end if;

    -- ---------------------------------------------------------- 6) التنفيذ (عند التأكيد فقط)
    newid := null;
    if commit_ and st in ('ok','warning') then
      cinfo := cmap->ckey;
      if (cinfo->>'new')::boolean and cinfo->>'id' is null then
        cid := ebda.uid();
        insert into ebda.custodies(id,label,holder,school_id,note,"user",code,status,opened_at,kind,purpose)
        values(cid, 'عهدة '||(cinfo->>'holder'), cinfo->>'holder', sid,
               concat_ws(' · ', 'أُنشئت تلقائياً من استيراد ملف المصروفات: '||fname, nullif(cinfo->>'note','')),
               cinfo->>'user', 'CUST-'||lpad(nextval('ebda.seq_cust')::text,3,'0'), 'open',
               coalesce(nullif(cinfo->>'date',''), cinfo->>'first_date', to_char(now(),'YYYY-MM-DD')),
               coalesce(req->>'custody_kind',''), '');
        update ebda.custodies set user_id = coalesce(cinfo->>'user_id',''), approval = 'approved', approved_by = u.name, approved_at = now()::text,
          ext_ref = coalesce(cinfo->>'ext_ref',''), import_batch = bid, title = coalesce(req->>'custody_title','')
        where id = cid;
        if coalesce((cinfo->>'file_amount')::numeric, 0) > 0 then
          insert into ebda.tranches(id,custody_id,date,amount,note)
          values(ebda.uid(), cid, coalesce(nullif(cinfo->>'date',''), cinfo->>'first_date', to_char(now(),'YYYY-MM-DD')),
                 (cinfo->>'file_amount')::numeric, 'القيمة الأساسية للعهدة (من ملف الاستيراد)');
        end if;
        select code into ccode from ebda.custodies where id = cid;
        cinfo := cinfo || jsonb_build_object('id', cid, 'code', ccode);
        cmap := cmap || jsonb_build_object(ckey, cinfo);
      end if;
      cid := cinfo->>'id'; ccode := cinfo->>'code';
      extra := (select string_agg(key||': '||value, ' · ') from jsonb_each_text(coalesce(rw->'extra','{}'::jsonb)) where btrim(value) <> '');
      newid := ebda.uid();
      insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,approval,approved_by,doc_url,doc_name,
         review_status,review_note,settled,ref,note,created_by,created_at,txn_no)
      values(newid, d, sid, cid, lid, '', coalesce(nullif(btrim(rw->>'description'),''), lname), amt,
         case when amode = 'approved' then 'approved' else 'pending' end, case when amode = 'approved' then u.name else '' end, '', '',
         '', '', '', coalesce(rw->>'doc_no',''),
         concat_ws(' · ', 'مستورد من ملف'||case when fname <> '' then ' «'||fname||'»' else '' end||' — '||coalesce(rw->>'r', 'صف '||i), extra),
         u.name, now()::text, 'EXP-'||lpad(nextval('ebda.seq_exp')::text,5,'0'));
      update ebda.expenses set pay_method = coalesce(rw->>'pay_method',''), created_by_id = u.id, supplier = coalesce(rw->>'supplier',''),
        doc_no = coalesce(rw->>'doc_no',''), import_batch = bid, import_row = coalesce(rw->>'r', i::text),
        submitted_at = now()::text,
        approved_by_id = case when amode = 'approved' then u.id else '' end,
        approved_at = case when amode = 'approved' then now()::text else '' end,
        approval_note = case when amode = 'approved' then 'معتمد بالاستيراد (بيانات فعلية)' else '' end,
        fin_approval = case when amode = 'approved' then 'approved' else coalesce(fin_approval,'') end,
        fin_by = case when amode = 'approved' then u.name else coalesce(fin_by,'') end,
        fin_by_id = case when amode = 'approved' then u.id else coalesce(fin_by_id,'') end,
        fin_at = case when amode = 'approved' then now()::text else coalesce(fin_at,'') end,
        doc_url = case when coalesce(btrim(rw->>'doc_link'),'') ~* '^https?://' then btrim(rw->>'doc_link') else '' end,
        doc_is_link = case when coalesce(btrim(rw->>'doc_link'),'') ~* '^https?://' then 'نعم' else '' end,
        doc_name = case when coalesce(btrim(rw->>'doc_link'),'') ~* '^https?://' then coalesce(nullif(rw->>'doc_no',''),'رابط مستند') else '' end
      where id = newid;
    end if;

    out := out || jsonb_build_object('i', i, 'r', coalesce(rw->>'r',''), 'status', st, 'errors', errs, 'warnings', warns, 'duplicate_of', dupof,
      'school_id', sid, 'school', coalesce(sname, rw->>'school', ''), 'custody', case when cnew and not commit_ then 'جديدة' else coalesce(ccode, cmap#>>array[ckey,'code'], '') end,
      'custody_no', cno, 'custody_new', cnew, 'holder', coalesce(cmap#>>array[ckey,'holder'], hold), 'line_id', lid, 'line', lname,
      'main', coalesce(rw->>'main',''), 'sub', coalesce(rw->>'sub',''), 'date', d, 'month', mth, 'amount', amt,
      'description', coalesce(rw->>'description',''), 'supplier', coalesce(rw->>'supplier',''), 'doc_no', coalesce(rw->>'doc_no',''),
      'expense_id', newid);
  end loop;

  -- ---------------------------------------------------------- أثر الاستيراد على الموازنة والعهد
  res := jsonb_build_object('ok', true, 'mode', case when commit_ then 'commit' else 'preview' end, 'approve_mode', amode,
    'summary', jsonb_build_object('rows', i, 'ok', c_ok, 'warning', c_warn, 'duplicate', c_dup, 'error', c_err,
       'importable', c_ok + c_warn, 'amount', tot, 'months', months,
       'new_custodies', (select count(*) from jsonb_each(cmap) x where (x.value->>'new')::boolean and camts ? x.key),
       'existing_custodies', (select count(*) from jsonb_each(cmap) x where not (x.value->>'new')::boolean and camts ? x.key),
       'schools', (select count(distinct split_part(x.key,'|',1)) from jsonb_each(camts) x)),
    'rows', out,
    'custodies', coalesce((select jsonb_agg(jsonb_build_object('key', x.key, 'code', coalesce(x.value->>'code',''), 'new', (x.value->>'new')::boolean,
        'ext_ref', x.value->>'ext_ref', 'holder', x.value->>'holder', 'linked_user', coalesce(x.value->>'user_id','') <> '',
        'school', (select s.name from ebda.schools s where s.id = x.value->>'school_id'),
        'received', (x.value->>'received')::numeric, 'spent_before', (x.value->>'spent')::numeric,
        'imported', coalesce((camts->>x.key)::numeric, 0),
        'remaining_after', (x.value->>'received')::numeric - (x.value->>'spent')::numeric - coalesce((camts->>x.key)::numeric, 0))
        order by x.value->>'holder')
      from jsonb_each(cmap) x where camts ? x.key), '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(z order by z->>'school', z->>'section', z->>'line') from (
        select jsonb_build_object('line_id', l.id, 'line', l.name, 'section', coalesce(l.section,''), 'school', s.name,
          'allocated', coalesce(l.allocated,0), 'actual_before', p.pre, 'imported', p.imp, 'counts_now', amode = 'approved',
          'actual_after', p.pre + p.addv, 'remaining_after', coalesce(l.allocated,0) - p.pre - p.addv,
          'pct_after', case when coalesce(l.allocated,0) > 0 then round(100 * (p.pre + p.addv) / l.allocated, 1) end,
          'state', ebda.budget_state(l.allocated, p.pre + p.addv)) z
        from ebda.lines l join ebda.schools s on s.id = l.school_id
        cross join lateral (select coalesce(sum(a.amount),0) spent from ebda.agg_line_month a
                            where a.line_id = l.id and (coalesce(s.period,'') !~ '\d{4}' or a.fy = substring(s.period from '\d{4}')::int)) b
        cross join lateral (select (lamt->>l.id)::numeric imp) m
        -- بعد التنفيذ يكون التجميع قد شمل المصروفات المعتمدة بالفعل؛ فيُطرح للحصول على «قبل»
        cross join lateral (select b.spent - case when amode = 'approved' and commit_ then m.imp else 0 end pre,
                                   case when amode = 'approved' then m.imp else 0 end addv, m.imp imp) p
        where lamt ? l.id) q), '[]'::jsonb));

  if commit_ then
    exc := coalesce((select jsonb_agg(x) from jsonb_array_elements(out) x where x->>'status' in ('error','duplicate','warning')), '[]'::jsonb);
    insert into ebda.import_batches(id,kind,file_name,actor,actor_id,approve_mode,rows_n,imported_n,amount,summary,exceptions)
    values(bid, 'expenses', fname, u.name, u.id, amode, i, c_ok + c_warn, tot, res->'summary', exc);
    res := res || jsonb_build_object('batch_id', bid);
  end if;
  return res;
end $ie$;

-- التراجع عن دفعة استيراد (الأدمن): إلغاء (لا حذف) مصروفات الدفعة غير المسوّاة، وإلغاء العهد التى أنشأتها الدفعة إن لم يبق عليها مصروفات
create or replace function ebda.revert_import(u ebda.users, p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = ebda as $ri$
declare b ebda.import_batches; n_exp int; n_cust int; n_skip int;
begin
  select * into b from ebda.import_batches where id = p_id;
  if not found then return ebda.err('دفعة الاستيراد غير موجودة'); end if;
  if coalesce(b.reverted_at,'') <> '' then return ebda.err('تم التراجع عن هذه الدفعة من قبل'); end if;
  if length(btrim(coalesce(p_reason,''))) < 2 then return ebda.err('اكتب سبب التراجع'); end if;
  select count(*) into n_skip from ebda.expenses e where e.import_batch = p_id and coalesce(e.settled,'') like '%نعم%' and coalesce(e.cancelled_at,'') = '';
  update ebda.expenses e set cancelled_at = now()::text, cancelled_by = u.name, cancel_reason = 'تراجع عن استيراد: '||btrim(p_reason)
   where e.import_batch = p_id and coalesce(e.cancelled_at,'') = '' and coalesce(e.settled,'') not like '%نعم%';
  get diagnostics n_exp = row_count;
  update ebda.custodies c set status = 'cancelled'
   where c.import_batch = p_id and coalesce(c.status,'open') = 'open'
     and not exists(select 1 from ebda.expenses e where e.custody_id = c.id and coalesce(e.cancelled_at,'') = '');
  get diagnostics n_cust = row_count;
  update ebda.import_batches set reverted_at = now()::text, reverted_by = u.name where id = p_id;
  return jsonb_build_object('ok', true, 'cancelled_expenses', n_exp, 'cancelled_custodies', n_cust, 'skipped_settled', n_skip);
end $ri$;


-- ============================================================================
--  الدالة الأساسية (قواعد 001 → 004 + الإضافات أعلاه)
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
  nk text;
  pid text;
  n_emp int := 0;
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
  if action not in ('bootstrap','ping','lineStatus','notifyInfo','docAuth','getDoc','expenseHistory','backupInfo','searchExpenses','report','payrollMonth','importBatches')
     and not (action in ('importExpensesFile','importEmployeesSafe') and coalesce(req->>'mode','preview') <> 'commit') then
    dj := req - 'auth' - 'pin' - 'dataBase64' - 'dataUrl' - 'html' - 'attachment';
    if dj ? 'user' then dj := dj #- '{user,pin}'; end if;
    if action in ('importExpensesFile','importEmployeesSafe') then dj := (dj - 'rows') || jsonb_build_object('rows_n', jsonb_array_length(coalesce(req->'rows','[]'::jsonb))); end if;
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
      if not (urole='admin' or (cust.id is not null and ebda.owns_custody(u, cust))
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
    if exists(select 1 from jsonb_array_elements(coalesce(req#>'{request,items}','[]'::jsonb)) it join ebda.lines l on l.id=it->>'line_id'
              where coalesce(l.active,'نعم') not like '%نعم%') then
      return ebda.err('بند معطّل — لا يقبل طلبات جديدة'); end if;
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
    if not ebda.can(u,'request.approve') then return ebda.err('صلاحية اعتماد الطلبات مطلوبة'); end if;
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
    if not ebda.can(u,'request.approve') then return ebda.err('صلاحية اعتماد الطلبات مطلوبة'); end if;
    select * into rq from ebda.requests where id=(req->>'id');
    if not found then return ebda.err('الطلب غير موجود'); end if;
    if not ebda.can_school(u, rq.school_id) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if urole<>'admin' and ((coalesce(rq.requester_id,'')<>'' and rq.requester_id=u.id) or rq.requester = u.username) then return ebda.err('لا يمكنك اعتماد طلبك بنفسك'); end if;
    if rq.status <> 'pending_supervisor' then return ebda.err('الطلب ليس فى مرحلة اعتماد المدير المباشر'); end if;
    if urole<>'admin' and exists(select 1 from ebda.users z where z.id=rq.requester_id and coalesce(z.manager_id,'')<>'' and z.manager_id<>u.id) then
      return ebda.err('هذا الطلب تابع لمسئول عهدة مرتبط بمدير مباشر آخر'); end if;
    update ebda.requests set status = case when (req->>'decision')='approve' then 'pending_accountant' else 'rejected' end,
      decided_by=u.name, decided_at=now()::text, note=coalesce(req->>'note',note) where id=rq.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'transferRequest' then
    if not ebda.can(u,'request.fin_approve') then return ebda.err('صلاحية الاعتماد المالى للطلبات مطلوبة'); end if;
    select * into rq from ebda.requests where id=(req->>'id');
    if not found then return ebda.err('الطلب غير موجود'); end if;
    if not ebda.can_school(u, rq.school_id) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if rq.status <> 'pending_accountant' then return ebda.err('الطلب ليس فى مرحلة الاعتماد المالى'); end if;
    if urole<>'admin' and ((coalesce(rq.requester_id,'')<>'' and rq.requester_id=u.id) or rq.requester = u.username) then return ebda.err('لا يمكنك اعتماد طلبك بنفسك'); end if;
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
    return ebda.bootstrap_v6(u);
  end if;

  -- ================================================================ المصروفات
  if action = 'addExpense' then
    select * into cust from ebda.custodies where id = (req#>>'{expense,custody_id}');
    if not found then return ebda.err('العهدة غير موجودة'); end if;
    if not (urole='admin' or ebda.owns_custody(u, cust)) then return ebda.err('لا صلاحية على هذه العهدة'); end if;
    if coalesce(cust.status,'open') in ('settled','closed') then return ebda.err('العهدة '||coalesce(cust.code,'')||' مسوّاة/مغلقة — اطلب عهدة جديدة'); end if;
    if coalesce(cust.status,'open')='cancelled' then return ebda.err('العهدة ملغاة — لا يمكن الصرف منها'); end if;
    if coalesce(cust.approval,'approved')<>'approved' then return ebda.err('العهدة لم تُعتمد بعد — لا يمكن الصرف منها'); end if;
    if not ebda.can(u,'expense.record') then return ebda.err('لا صلاحية لتسجيل المصروفات'); end if;
    if exists(select 1 from ebda.custody_lines cl where cl.custody_id=cust.id)
       and not exists(select 1 from ebda.custody_lines cl where cl.custody_id=cust.id and cl.line_id=coalesce(req#>>'{expense,line_id}','')) then
      return ebda.err('هذا البند غير مخصص لهذه العهدة — اختر بنداً من بنود العهدة'); end if;
    if coalesce(req#>>'{expense,date}','') > to_char(now() + interval '1 day','YYYY-MM-DD') then return ebda.err('تاريخ المصروف فى المستقبل'); end if;
    if coalesce(req#>>'{expense,line_id}','')<>'' and exists(select 1 from ebda.lines l where l.id=req#>>'{expense,line_id}' and coalesce(l.deleted_at,'')<>'') then
      return ebda.err('بند الموازنة محذوف'); end if;
    if coalesce(req#>>'{expense,line_id}','')<>'' and exists(select 1 from ebda.lines l where l.id=req#>>'{expense,line_id}' and coalesce(l.active,'نعم') not like '%نعم%') then
      return ebda.err('بند الموازنة معطّل — لا يقبل مصروفات جديدة'); end if;
    if coalesce(btrim(req#>>'{expense,doc_link}'),'')<>'' and btrim(req#>>'{expense,doc_link}') !~* '^https?://' then
      return ebda.err('رابط المستند يجب أن يبدأ بـ http:// أو https://'); end if;
    if coalesce((req#>>'{expense,amount}')::numeric,0) <= 0 then return ebda.err('قيمة المصروف يجب أن تكون أكبر من صفر'); end if;
    if coalesce(req#>>'{expense,line_id}','')<>'' and not exists(select 1 from ebda.lines l where l.id=req#>>'{expense,line_id}' and l.school_id=cust.school_id) then
      return ebda.err('بند الموازنة غير تابع لجهة هذه العهدة'); end if;
    newid := ebda.uid();
    insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,
       approval,approved_by,doc_url,doc_name,review_status,review_note,settled,ref,note,created_by,created_at,txn_no)
    values(newid, req#>>'{expense,date}', cust.school_id, cust.id,
       req#>>'{expense,line_id}', coalesce(req#>>'{expense,spend_item}',''), coalesce(req#>>'{expense,description}',''),
       (req#>>'{expense,amount}')::numeric, case when coalesce(req#>>'{expense,draft}','') in ('1','true','نعم') then 'draft' else 'pending' end,
       '', '','','','','','',coalesce(req#>>'{expense,note}',''), u.name, now()::text,
       'EXP-'||lpad(nextval('ebda.seq_exp')::text,5,'0'));
    update ebda.expenses set pay_method=coalesce(req#>>'{expense,pay_method}',''), created_by_id=u.id,
      submitted_at=case when approval='pending' then now()::text else '' end where id=newid;
    -- رابط المستند المؤيد (فاتورة/إيصال/Drive/OneDrive/SharePoint...) يُسجَّل مع المصروف
    if coalesce(btrim(req#>>'{expense,doc_link}'),'') ~* '^https?://' then
      update ebda.expenses set doc_url=btrim(req#>>'{expense,doc_link}'), doc_is_link='نعم',
        doc_name=coalesce(nullif(req#>>'{expense,doc_name}',''),'رابط مستند'), doc_type=coalesce(req#>>'{expense,doc_type}','') where id=newid;
    end if;
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) - 'doc_url' || jsonb_build_object('doc_url', case when e.doc_url like 'data:%' then 'inline:' else coalesce(e.doc_url,'') end)
                                                from ebda.expenses e where e.id=newid))
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
    update ebda.expenses set pay_method=coalesce(req#>>'{expense,pay_method}',''), created_by_id=u.id, approved_by_id=u.id, fin_by_id=u.id,
      settled_by=u.name, settled_by_id=u.id where id=newid;
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
      if not ebda.can(u,'expense.approve') then return ebda.err('صلاحية اعتماد المصروفات مطلوبة'); end if;
      if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى'); end if;
      -- الفصل بين المهام: لا يعتمد أحد مصروفاً هو صاحب عهدته أو منشئه (إلا الأدمن)
      if urole<>'admin' and (ebda.owns_custody(u, cust) or coalesce(ex.created_by_id,'')=u.id) then return ebda.err('لا يمكنك اعتماد مصروفك بنفسك'); end if;
      if urole<>'admin' and cust.id is not null and not ebda.is_assigned_manager(u, cust) then
        return ebda.err('هذا المصروف تابع لمسئول عهدة مرتبط بمدير مباشر آخر'); end if;
      if urole<>'admin' and ex.approval<>'pending' then return ebda.err('تم اتخاذ القرار على هذا المصروف من قبل'); end if;
      if patch->>'approval' not in ('approved','rejected','returned','pending') then return ebda.err('قيمة اعتماد غير صحيحة'); end if;
      if patch->>'approval' in ('rejected','returned') and length(btrim(coalesce(patch->>'note','')))<2 then
        return ebda.err('اكتب سبب الرفض أو الإعادة للتعديل'); end if;
      update ebda.expenses set approval=patch->>'approval', approved_by=u.name, approved_by_id=u.id, approved_at=now()::text,
        approval_note=coalesce(patch->>'note',''),
        returned_by=case when patch->>'approval'='returned' then u.name else returned_by end,
        returned_at=case when patch->>'approval'='returned' then now()::text else returned_at end,
        return_reason=case when patch->>'approval'='returned' then btrim(patch->>'note') else return_reason end,
        updated_by=u.name, updated_at=now()::text
      where id=ex.id;
      return jsonb_build_object('ok',true,'mail','');
    end if;
    -- تعديل بيانات المصروف: الأدمن دائماً، أو صاحب العهدة قبل الاعتماد فقط
    if not (urole='admin' or (ebda.owns_custody(u, cust) and coalesce(ex.cancelled_at,'')=''
            and (ex.approval in ('pending','draft','returned') or (ex.approval='approved' and ex.fin_approval='returned')))) then
      return ebda.err('لا يمكن التعديل بعد اعتماد الصرف'); end if;
    if patch ? 'date' and coalesce(patch->>'date','') > to_char(now() + interval '1 day','YYYY-MM-DD') then return ebda.err('تاريخ المصروف فى المستقبل'); end if;
    if patch ? 'line_id' and patch->>'line_id' is distinct from ex.line_id and exists(select 1 from ebda.lines l where l.id=patch->>'line_id' and coalesce(l.active,'نعم') not like '%نعم%') then
      return ebda.err('بند الموازنة معطّل — لا يقبل مصروفات جديدة'); end if;
    -- تغيير المبلغ أو البند بعد اعتماد المدير المباشر يعيد المصروف لاعتماده من جديد
    if urole<>'admin' and ex.approval='approved' and ((patch ? 'amount' and (patch->>'amount')::numeric is distinct from ex.amount)
                                                   or (patch ? 'line_id' and patch->>'line_id' is distinct from ex.line_id)) then
      update ebda.expenses set approval='returned', fin_approval='', return_reason='تم تعديل المبلغ/البند بعد الاعتماد — يلزم اعتماد جديد' where id=ex.id;
    end if;
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
    if not ebda.can(u,'expense.fin_approve') then return ebda.err('صلاحية الاعتماد المالى مطلوبة'); end if;
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if not ebda.can_expense(u, ex) then return ebda.err('هذا المصروف ليس ضمن نطاقك'); end if;
    select * into cust from ebda.custodies where id = ex.custody_id;
    if urole<>'admin' and ((cust.id is not null and ebda.owns_custody(u, cust)) or coalesce(ex.created_by_id,'')=u.id) then
      return ebda.err('لا يمكنك مراجعة مصروف أنت صاحبه أو منشئه'); end if;
    if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى'); end if;
    patch := req->'patch';
    if patch ? 'fin_approval' and coalesce(patch->>'fin_approval','') in ('rejected','returned') and length(btrim(coalesce(patch->>'fin_note','')))<2 then
      return ebda.err('اكتب سبب الرفض أو الإعادة للتعديل'); end if;
    if coalesce(patch->>'settled','') like '%نعم%' and coalesce(patch->>'fin_approval', ex.fin_approval)='returned' then
      return ebda.err('لا يمكن تسوية مصروف معاد للتعديل'); end if;
    if coalesce(patch->>'settled','') like '%نعم%' and urole<>'admin' and coalesce(ex.doc_url,'')=''
       and coalesce((select value from ebda.config where key='require_doc_to_settle'),'no')='yes' then
      return ebda.err('لا يمكن التسوية بدون المستند المؤيد'); end if;
    if (patch ? 'fin_approval' or coalesce(patch->>'settled','') like '%نعم%') and ex.approval<>'approved' and urole<>'admin' then
      return ebda.err('يجب اعتماد المدير المباشر أولاً'); end if;
    if patch ? 'fin_approval' and coalesce(patch->>'fin_approval','') not in ('','approved','rejected','returned') then return ebda.err('قيمة اعتماد مالى غير صحيحة'); end if;
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
    update ebda.expenses set
      fin_by_id = case when patch ? 'fin_approval' or coalesce(patch->>'settled','') like '%نعم%' then u.id else fin_by_id end,
      settled_by = case when patch ? 'settled' then case when coalesce(patch->>'settled','') like '%نعم%' then u.name else '' end else settled_by end,
      settled_by_id = case when patch ? 'settled' then case when coalesce(patch->>'settled','') like '%نعم%' then u.id else '' end else settled_by_id end,
      returned_by = case when patch->>'fin_approval'='returned' then u.name else returned_by end,
      returned_at = case when patch->>'fin_approval'='returned' then now()::text else returned_at end,
      return_reason = case when patch->>'fin_approval'='returned' then btrim(patch->>'fin_note') else return_reason end
    where id = ex.id;
    return jsonb_build_object('ok',true,'mail','') || case when patch->>'fin_approval'='approved' then ebda.over_warning(u, ex.line_id) else '{}'::jsonb end;
  end if;

  if action = 'uploadDoc' then
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى'); end if;
    if coalesce(req->>'link','')<>'' and btrim(req->>'link') !~* '^(https?://|storage:)' then return ebda.err('رابط المستند يجب أن يبدأ بـ http:// أو https://'); end if;
    select * into cust from ebda.custodies where id=ex.custody_id;
    if not (urole='admin'
            or (cust.id is not null and ebda.owns_custody(u, cust))
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
      if not (ebda.owns_custody(u, cust) and ex.approval in ('pending','draft','returned') and coalesce(ex.fin_approval,'')='') then
        return ebda.err('لا يمكن الحذف بعد اعتماد الصرف'); end if;
    elsif coalesce(ex.fin_approval,'')='approved' or coalesce(ex.settled,'') like '%نعم%' then
      return ebda.err('المصروف معتمد مالياً/مسوّى — استخدم «إلغاء المصروف» حتى يبقى أثره فى التقارير وتتبع التعديلات');
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
    if not ebda.can(u,'custody.create') then return ebda.err('لا صلاحية لإضافة دفعات للعهد'); end if;
    select * into cust from ebda.custodies where id=req#>>'{tranche,custody_id}';
    if not ebda.can_custody(u, cust) then return ebda.err('هذه العهدة ليست ضمن نطاقك'); end if;
    if coalesce(cust.status,'open') in ('settled','closed','cancelled') then return ebda.err('العهدة مسوّاة/مغلقة/ملغاة — أنشئ عهدة جديدة'); end if;
    newid := ebda.uid();
    insert into ebda.tranches(id,custody_id,date,amount,note)
    values(newid, cust.id, req#>>'{tranche,date}', coalesce((req#>>'{tranche,amount}')::numeric,0), coalesce(req#>>'{tranche,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(t) from ebda.tranches t where t.id=newid));
  end if;

  if action = 'addCustody' then
    if not ebda.can(u,'custody.create') then return ebda.err('لا صلاحية لإنشاء العهد'); end if;
    for ln in select * from jsonb_array_elements(coalesce(req#>'{custody,lines}','[]'::jsonb)) loop
      if not exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and l.school_id=req#>>'{custody,school_id}' and coalesce(l.deleted_at,'')='') then
        return ebda.err('بند غير تابع لمكان العهدة'); end if;
      if exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and coalesce(l.active,'نعم') not like '%نعم%') then
        return ebda.err('بند معطّل — لا يمكن التوزيع عليه'); end if;
      if not ebda.num_ok(ln->>'amount') then return ebda.err('مبلغ توزيع غير صحيح'); end if;
    end loop;
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
    -- الاسم/المسئول من العاملين/حالة الاعتماد (المسودة لمن لا يملك صلاحية الاعتماد)
    update ebda.custodies set title=coalesce(req#>>'{custody,title}',''), holder_emp_id=coalesce(req#>>'{custody,holder_emp_id}',''),
      approval = case when coalesce(req#>>'{custody,approval}','approved') in ('draft','review') then req#>>'{custody,approval}'
                      when ebda.can(u,'custody.approve') then 'approved' else 'draft' end
    where id=newid;
    update ebda.custodies set approved_by=u.name, approved_at=now()::text where id=newid and approval='approved';
    for ln in select * from jsonb_array_elements(coalesce(req#>'{custody,lines}','[]'::jsonb)) loop
      if not exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and l.school_id=req#>>'{custody,school_id}' and coalesce(l.deleted_at,'')='') then
        raise exception 'بند غير تابع لمكان العهدة'; end if;
      insert into ebda.custody_lines(id,custody_id,line_id,amount) values(ebda.uid(), newid, ln->>'line_id', coalesce(nullif(btrim(ln->>'amount'),'')::numeric,0))
      on conflict (custody_id,line_id) do update set amount=excluded.amount;
    end loop;
    if coalesce((nullif(btrim(req#>>'{custody,amount}'),''))::numeric,0) > 0 then
      insert into ebda.tranches(id,custody_id,date,amount,note)
      values(ebda.uid(), newid, coalesce(nullif(req#>>'{custody,date}',''), to_char(now(),'YYYY-MM-DD')),
             (req#>>'{custody,amount}')::numeric, 'القيمة الأساسية للعهدة');
    end if;
    return jsonb_build_object('ok',true,'item',(select to_jsonb(c) || jsonb_build_object(
        'received',(select coalesce(sum(t.amount),0) from ebda.tranches t where t.custody_id=c.id),'spent',0,'exp_count',0)
      from ebda.custodies c where c.id=newid),
      'tranches', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.tranches t where t.custody_id=newid),'[]'::jsonb),
      'custody_lines', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.custody_lines t where t.custody_id=newid),'[]'::jsonb));
  end if;

  if action = 'updateCustody' then
    select * into cust from ebda.custodies where id=(req->>'id');
    if not found then return ebda.err('العهدة غير موجودة'); end if;
    patch := req->'patch';
    -- مسئول العهدة: يقدّم عهدته للتسوية فقط
    if urole='custody_officer' then
      if not ebda.owns_custody(u, cust) then return ebda.err('لا صلاحية على هذه العهدة'); end if;
      if (patch - 'status' - 'id') <> '{}'::jsonb or coalesce(patch->>'status','')<>'pending_settlement' then
        return ebda.err('مسئول العهدة يستطيع تقديم العهدة للتسوية فقط'); end if;
      update ebda.custodies set status='pending_settlement' where id=cust.id and coalesce(status,'open')='open';
      return jsonb_build_object('ok',true);
    end if;
    if not (ebda.can(u,'custody.create') or ebda.can(u,'custody.approve')) then return ebda.err('لا صلاحية لتعديل العهد'); end if;
    if not ebda.can_custody(u, cust) then return ebda.err('هذه العهدة ليست ضمن نطاقك'); end if;
    if coalesce(cust.status,'open')='cancelled' then return ebda.err('العهدة ملغاة — لا يمكن تعديلها'); end if;
    if coalesce(cust.approval,'approved')='approved' and urole<>'admin'
       and (patch ? 'school_id' or patch ? 'holder' or patch ? 'user' or patch ? 'title' or patch ? 'kind' or patch ? 'label') then
      return ebda.err('العهدة معتمدة — تعديل بياناتها الأساسية للأدمن فقط'); end if;
    if patch ? 'school_id' and not ebda.can_school(u, patch->>'school_id') then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if patch ? 'status' and coalesce(patch->>'status','') not in ('open','pending_settlement','settled','closed') then return ebda.err('حالة عهدة غير صحيحة'); end if;
    if coalesce(patch->>'status','') in ('settled','closed') and exists(select 1 from ebda.expenses e where e.custody_id=cust.id
         and e.approval<>'rejected' and coalesce(e.fin_approval,'')<>'rejected' and not (coalesce(e.settled,'') like '%نعم%')) then
      return ebda.err('توجد مصروفات غير مسوّاة على هذه العهدة — سوِّها أو ارفضها أولاً'); end if;
    update ebda.custodies set label=coalesce(patch->>'label',label), holder=coalesce(patch->>'holder',holder),
      school_id=coalesce(patch->>'school_id',school_id), note=coalesce(patch->>'note',note), "user"=coalesce(patch->>'user',"user"),
      kind=coalesce(patch->>'kind',kind), purpose=coalesce(patch->>'purpose',purpose),
      title=coalesce(patch->>'title',title), holder_emp_id=coalesce(patch->>'holder_emp_id',holder_emp_id),
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
    if not ebda.can(u,'budget.edit') then return ebda.err('لا صلاحية لإضافة بنود الموازنة'); end if;
    if not ebda.can_school(u, req#>>'{line,school_id}') then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if not exists(select 1 from ebda.schools s where s.id=req#>>'{line,school_id}') then return ebda.err('الجهة غير موجودة'); end if;
    if coalesce(btrim(req#>>'{line,name}'),'')='' then return ebda.err('اكتب اسم البند'); end if;
    if coalesce(req#>>'{line,allocated}','0') !~ '^\s*[0-9]*\.?[0-9]*\s*$' then return ebda.err('المبلغ يجب أن يكون رقماً موجباً'); end if;
    if exists(select 1 from ebda.lines l where l.school_id=req#>>'{line,school_id}' and coalesce(l.deleted_at,'')=''
              and ebda.norm_txt(l.name)=ebda.norm_txt(req#>>'{line,name}') and ebda.norm_txt(l.section)=ebda.norm_txt(coalesce(req#>>'{line,section}',''))) then
      return ebda.err('هذا البند موجود بالفعل فى نفس القسم لهذه الجهة — عدّل مخصصه بدلاً من إضافته مرة أخرى'); end if;
    newid := ebda.uid();
    insert into ebda.lines(id,school_id,section,name,allocated,note,monthly_plan)
    values(newid, req#>>'{line,school_id}', coalesce(req#>>'{line,section}',''), req#>>'{line,name}', coalesce((req#>>'{line,allocated}')::numeric,0),
           coalesce(req#>>'{line,note}',''), coalesce(req#>>'{line,monthly_plan}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(l) from ebda.lines l where l.id=newid));
  end if;

  if action in ('updateLine','deleteLine') then
    if not ebda.can(u,'budget.edit') then return ebda.err('لا صلاحية لتعديل الموازنة'); end if;
    sid := (select school_id from ebda.lines where id=(req->>'id'));
    if sid is null then return ebda.err('البند غير موجود'); end if;
    if not ebda.can_school(u, sid) then return ebda.err('هذه الجهة ليست ضمن نطاقك'); end if;
    if action='updateLine' then
      patch := req->'patch';
      if patch ? 'allocated' and coalesce(patch->>'allocated','0') !~ '^\s*[0-9]*\.?[0-9]*\s*$' then return ebda.err('المبلغ يجب أن يكون رقماً موجباً'); end if;
      if (patch ? 'name' or patch ? 'section') and exists(select 1 from ebda.lines l, ebda.lines me where me.id=(req->>'id')
            and l.school_id=me.school_id and l.id<>me.id and coalesce(l.deleted_at,'')=''
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
    if not ebda.can(u,'budget.edit') then return ebda.err('لا صلاحية لاستيراد الموازنة'); end if;
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
        select l.id into lid from ebda.lines l where l.school_id=sid and coalesce(l.deleted_at,'')=''
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
    if not ebda.can(u,'budget.edit') then return ebda.err('لا صلاحية لاستيراد الموازنة'); end if;
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
      if exists(select 1 from ebda.custodies c where c.user_id=xu.id) or exists(select 1 from ebda.expenses e where e.created_by_id=xu.id)
         or exists(select 1 from ebda.users z where z.manager_id=xu.id) then
        return ebda.err('لا يمكن حذف مستخدم له عهد أو مصروفات أو فريق — عطّله بدلاً من الحذف'); end if;
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
      if coalesce(dj->>'manager_id','')<>'' and not exists(select 1 from ebda.users z where z.id=dj->>'manager_id') then return ebda.err('المدير المباشر غير موجود'); end if;
      insert into ebda.users(id,username,pin,name,role,schools,active,email,perms,must_reset,manager_id,dept)
      values(newid, dj->>'username', ebda.pin_hash(dj->>'pin'), dj->>'name', coalesce(ebda.role_legacy(dj->>'role'),'custody'),
         coalesce(dj->>'schools',''), coalesce(dj->>'active','نعم'), coalesce(dj->>'email',''), coalesce(dj->>'perms',''), 'نعم',
         coalesce(dj->>'manager_id',''), coalesce(dj->>'dept',''));
      return jsonb_build_object('ok',true,'item',(select ebda.user_public(z) from ebda.users z where z.id=newid));
    end if;
    if xu.id = u.id and dj ? 'role' and ebda.role_key(dj->>'role')<>urole then return ebda.err('لا يمكنك تغيير دورك بنفسك'); end if;
    if dj ? 'username' and exists(select 1 from ebda.users z where z.username=dj->>'username' and z.id<>xu.id) then return ebda.err('اسم المستخدم مستخدم من قبل'); end if;
    if coalesce(dj->>'manager_id','')<>'' and (dj->>'manager_id'=xu.id or not exists(select 1 from ebda.users z where z.id=dj->>'manager_id')) then
      return ebda.err('المدير المباشر غير صحيح'); end if;
    update ebda.users set username=coalesce(nullif(dj->>'username',''),username),
      pin = case when length(coalesce(dj->>'pin',''))>=4 and coalesce(dj->>'pin','') not like '$2%' then ebda.pin_hash(dj->>'pin') else pin end,
      name=coalesce(dj->>'name',name), role=coalesce(ebda.role_legacy(dj->>'role'),role), schools=coalesce(dj->>'schools',schools),
      active=coalesce(dj->>'active',active), email=coalesce(dj->>'email',email), perms=coalesce(dj->>'perms',perms),
      manager_id=coalesce(dj->>'manager_id',manager_id), dept=coalesce(dj->>'dept',dept)
    where id=xu.id;
    if length(coalesce(dj->>'pin',''))>=4 or coalesce(dj->>'active','نعم') not like '%نعم%' or dj ? 'role' or dj ? 'username' then
      delete from ebda.sessions where user_id=xu.id;
    end if;
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ v4: أسماء العهد (Master Data)
  if action = 'saveCustodyName' then
    if urole<>'admin' then return ebda.err('إدارة أسماء العهد للأدمن فقط'); end if;
    dj := req->'item';
    if coalesce(btrim(dj->>'name'),'')='' then return ebda.err('اكتب اسم العهدة'); end if;
    if exists(select 1 from ebda.custody_names z where ebda.norm_txt(z.name)=ebda.norm_txt(dj->>'name') and z.id<>coalesce(dj->>'id','')) then
      return ebda.err('هذا الاسم موجود بالفعل'); end if;
    if coalesce(dj->>'id','')='' then
      newid := ebda.uid();
      insert into ebda.custody_names(id,name,active,sort,sections)
      values(newid, btrim(dj->>'name'), coalesce(nullif(dj->>'active',''),'نعم'), coalesce(nullif(dj->>'sort','')::int, 99), coalesce(dj->>'sections',''));
    else
      newid := dj->>'id';
      update ebda.custody_names set name=btrim(dj->>'name'), active=coalesce(nullif(dj->>'active',''),active),
        sort=coalesce(nullif(dj->>'sort','')::int,sort), sections=coalesce(dj->>'sections',sections) where id=newid;
      if not found then return ebda.err('الاسم غير موجود'); end if;
    end if;
    return jsonb_build_object('ok',true,'id',newid);
  end if;

  -- ================================================================ v4: دورة اعتماد العهدة · الإلغاء · التوزيع على البنود
  if action in ('submitCustody','approveCustody','cancelCustody','setCustodyLines') then
    select * into cust from ebda.custodies where id=coalesce(req->>'id', req->>'custody_id');
    if not found then return ebda.err('العهدة غير موجودة'); end if;
    if not ebda.can_custody(u, cust) then return ebda.err('هذه العهدة ليست ضمن نطاقك'); end if;
    if coalesce(cust.status,'open')='cancelled' then return ebda.err('العهدة ملغاة بالفعل'); end if;

    if action = 'submitCustody' then  -- مسودة ← مراجعة
      if not ebda.can(u,'custody.create') then return ebda.err('لا صلاحية'); end if;
      if coalesce(cust.approval,'approved')<>'draft' then return ebda.err('العهدة ليست مسودة'); end if;
      update ebda.custodies set approval='review', submitted_by=u.name where id=cust.id;
      return jsonb_build_object('ok',true);
    end if;

    if action = 'approveCustody' then  -- مراجعة/مسودة ← معتمدة
      if not ebda.can(u,'custody.approve') then return ebda.err('صلاحية اعتماد العهد مطلوبة (الأدمن أو المدير المالى)'); end if;
      if coalesce(cust.approval,'approved')='approved' then return ebda.err('العهدة معتمدة بالفعل'); end if;
      if not exists(select 1 from ebda.tranches t where t.custody_id=cust.id and t.amount>0) then return ebda.err('لا يمكن اعتماد عهدة بدون قيمة'); end if;
      update ebda.custodies set approval='approved', approved_by=u.name, approved_at=now()::text where id=cust.id;
      return jsonb_build_object('ok',true);
    end if;

    if action = 'cancelCustody' then  -- للأدمن فقط، حتى بعد الاعتماد — لا حذف: الحالة «ملغاة» مع السبب
      if urole<>'admin' then return ebda.err('إلغاء العهدة للأدمن فقط'); end if;
      if length(coalesce(btrim(req->>'reason'),''))<3 then return ebda.err('اكتب سبب الإلغاء'); end if;
      update ebda.custodies set status='cancelled', cancel_reason=btrim(req->>'reason'), cancelled_by=u.name, cancelled_at=now()::text where id=cust.id;
      return jsonb_build_object('ok',true);
    end if;

    -- setCustodyLines: المخصص داخل العهدة لكل بند
    if not ebda.can(u,'custody.create') then return ebda.err('لا صلاحية لتعديل توزيع العهدة'); end if;
    if coalesce(cust.approval,'approved')='approved' and urole<>'admin' then return ebda.err('العهدة معتمدة — تعديل توزيعها للأدمن فقط'); end if;
    if coalesce(cust.status,'open') in ('closed','settled') then return ebda.err('لا يمكن تعديل عهدة مسوّاة/مغلقة'); end if;
    for ln in select * from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) loop
      if not exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and l.school_id=cust.school_id and coalesce(l.deleted_at,'')='') then
        return ebda.err('بند غير تابع لمكان العهدة'); end if;
      if exists(select 1 from ebda.lines l where l.id=ln->>'line_id' and coalesce(l.active,'نعم') not like '%نعم%')
         and not exists(select 1 from ebda.custody_lines cl where cl.custody_id=cust.id and cl.line_id=ln->>'line_id') then
        return ebda.err('بند معطّل — لا يمكن التوزيع عليه'); end if;
      if not ebda.num_ok(ln->>'amount') or coalesce(nullif(btrim(ln->>'amount'),'')::numeric,0) < 0 then return ebda.err('مبلغ توزيع غير صحيح'); end if;
    end loop;
    if exists(select 1 from ebda.custody_lines cl where cl.custody_id=cust.id
              and not exists(select 1 from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) x where x->>'line_id'=cl.line_id)
              and exists(select 1 from ebda.expenses e where e.custody_id=cust.id and e.line_id=cl.line_id)) then
      return ebda.err('لا يمكن إزالة بند عليه مصروفات من توزيع العهدة'); end if;
    delete from ebda.custody_lines cl where cl.custody_id=cust.id
      and not exists(select 1 from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) x where x->>'line_id'=cl.line_id);
    for ln in select * from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) loop
      insert into ebda.custody_lines(id,custody_id,line_id,amount,note)
      values(ebda.uid(), cust.id, ln->>'line_id', coalesce(nullif(btrim(ln->>'amount'),'')::numeric,0), coalesce(ln->>'note',''))
      on conflict (custody_id,line_id) do update set amount=excluded.amount, note=excluded.note;
    end loop;
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ v4: حذف الموازنة (حذف منطقى للأدمن فقط) واسترجاعها
  if action in ('deleteBudget','restoreBudget') then
    if urole<>'admin' then return ebda.err('حذف الموازنة للأدمن فقط'); end if;
    sid := req->>'school_id';
    if sid is null or not exists(select 1 from ebda.schools s where s.id=sid) then return ebda.err('المكان غير موجود'); end if;
    if action = 'deleteBudget' then
      if length(coalesce(btrim(req->>'reason'),''))<3 then return ebda.err('اكتب سبب الحذف'); end if;
      n := (select count(*) from ebda.expenses e join ebda.lines l on l.id=e.line_id where l.school_id=sid and coalesce(l.deleted_at,'')='');
      if n > 0 then return ebda.err('لا يمكن حذف موازنة مرتبط بها '||n||' مصروف — المصروفات والتقارير تعتمد عليها'); end if;
      if exists(select 1 from ebda.custody_lines cl join ebda.lines l on l.id=cl.line_id where l.school_id=sid and coalesce(l.deleted_at,'')='') then
        return ebda.err('لا يمكن حذف موازنة موزعة على عهد'); end if;
      if exists(select 1 from ebda.request_items it join ebda.lines l on l.id=it.line_id join ebda.requests r on r.id=it.request_id
                where l.school_id=sid and coalesce(l.deleted_at,'')='' and r.status in ('pending_supervisor','pending_accountant')) then
        return ebda.err('توجد طلبات عهد معلّقة على بنود هذه الموازنة'); end if;
      n := (select count(*) from ebda.lines l where l.school_id=sid and coalesce(l.deleted_at,'')='');
      if n = 0 then return ebda.err('لا توجد موازنة لحذفها'); end if;
      update ebda.lines set deleted_at=now()::text, deleted_by=u.name, delete_reason=btrim(req->>'reason')
      where school_id=sid and coalesce(deleted_at,'')='';
      return jsonb_build_object('ok',true,'count',n);
    end if;
    -- استرجاع: البنود التى لا يوجد مثلها حالياً فقط (لا تكرار)
    update ebda.lines l set deleted_at='', deleted_by='', delete_reason=''
    where l.school_id=sid and coalesce(l.deleted_at,'')<>''
      and not exists(select 1 from ebda.lines a where a.school_id=sid and coalesce(a.deleted_at,'')='' and a.id<>l.id
                     and ebda.norm_txt(a.name)=ebda.norm_txt(l.name) and ebda.norm_txt(a.section)=ebda.norm_txt(l.section));
    get diagnostics n_new = row_count;
    return jsonb_build_object('ok',true,'count',n_new);
  end if;

  -- ================================================================ v4: الرواتب الشهرية (Payroll)
  if action = 'importPayroll' then
    if not ebda.can(u,'payroll.import') then return ebda.err('صلاحية استيراد الرواتب مطلوبة'); end if;
    sid := req->>'school_id';
    if sid is null or not exists(select 1 from ebda.schools s where s.id=sid) then return ebda.err('المكان غير موجود'); end if;
    if not ebda.can_school(u, sid) then return ebda.err('هذا المكان ليس ضمن نطاقك'); end if;
    if coalesce(req->>'month','') !~ '^[0-9]{4}-[0-9]{2}$' then return ebda.err('الشهر غير صحيح'); end if;
    if exists(select 1 from ebda.payroll_periods p where p.school_id=sid and p.month=req->>'month' and p.status='approved') then
      return ebda.err('رواتب هذا الشهر معتمدة — يجب إعادة فتحها (للأدمن) قبل الاستيراد'); end if;
    if jsonb_typeof(coalesce(req->'rows','null'::jsonb))<>'array' or jsonb_array_length(req->'rows')=0 then return ebda.err('لا توجد بيانات'); end if;
    -- (1) تحقق كامل قبل أى حفظ
    for ln in select * from jsonb_array_elements(req->'rows') loop
      if coalesce(btrim(ln->>'name'),'')='' then return ebda.err('يوجد سطر بدون اسم موظف'); end if;
      if not (ebda.num_ok(ln->>'salary') and ebda.num_ok(ln->>'net') and ebda.num_ok(ln->>'ded_total') and ebda.num_ok(ln->>'absent_days')
              and ebda.num_ok(ln->>'permissions') and ebda.num_ok(ln->>'deduct_days') and ebda.num_ok(ln->>'month_days') and ebda.num_ok(ln->>'allowances')
              and ebda.num_ok(ln->>'direct_ded') and ebda.num_ok(ln->>'leave_opening') and ebda.num_ok(ln->>'leave_used') and ebda.num_ok(ln->>'leave_balance')) then
        return ebda.err('قيمة رقمية غير صحيحة للموظف: '||(ln->>'name')); end if;
      if coalesce(ln->>'employee_id','')<>'' and not exists(select 1 from ebda.employees e where e.id=ln->>'employee_id' and e.school_id=sid) then
        return ebda.err('الموظف المطابق غير تابع لهذا المكان: '||(ln->>'name')); end if;
    end loop;
    -- (2) الموظف: مطابقة بالمعرّف ثم الرقم القومى ثم الاسم — لا يُنشأ الموظف مرة أخرى كل شهر
    for ln in select * from jsonb_array_elements(req->'rows') loop
      lid := nullif(ln->>'employee_id','');
      nk := regexp_replace(coalesce(ln->>'national_id',''),'[^0-9]','','g');
      if lid is null and nk<>'' then select e.id into lid from ebda.employees e where e.school_id=sid and e.national_key=nk order by e.id limit 1; end if;
      if lid is null then select e.id into lid from ebda.employees e where e.school_id=sid and ebda.norm_txt(e.name)=ebda.norm_txt(ln->>'name') order by e.id limit 1; end if;
      if lid is null then
        lid := ebda.uid();
        insert into ebda.employees(id,school_id,category,name,job,national_id,national_key,account_no,bank,ebda_start,hire_date,base_salary,
            staff_group,assignment,work_type,insurance_status,emp_no,active,archived)
        values(lid, sid, case when ln->>'staff_group'='gov' then 'gov' else 'contract' end, btrim(ln->>'name'), coalesce(ln->>'job',''),
            coalesce(ln->>'national_id',''), nk, coalesce(ln->>'account_no',''), coalesce(ln->>'bank',''), coalesce(ln->>'start_date',''), coalesce(ln->>'start_date',''),
            coalesce(nullif(btrim(ln->>'salary'),'')::numeric,0), coalesce(ln->>'staff_group',''), coalesce(ln->>'assignment',''), coalesce(ln->>'work_type',''),
            coalesce(ln->>'insurance_status',''), coalesce(ln->>'emp_no',''), 'نعم','لا');
        n_emp := n_emp + 1;
      else
        update ebda.employees set job=coalesce(nullif(ln->>'job',''),job), assignment=coalesce(nullif(ln->>'assignment',''),assignment),
          work_type=coalesce(nullif(ln->>'work_type',''),work_type), staff_group=coalesce(nullif(ln->>'staff_group',''),staff_group),
          national_id=case when coalesce(national_id,'')='' then coalesce(ln->>'national_id','') else national_id end,
          national_key=case when coalesce(national_key,'')='' then nk else national_key end,
          account_no=coalesce(nullif(ln->>'account_no',''),account_no), bank=coalesce(nullif(ln->>'bank',''),bank),
          ebda_start=coalesce(nullif(ln->>'start_date',''),ebda_start), base_salary=coalesce(nullif(btrim(ln->>'salary'),'')::numeric,base_salary),
          insurance_status=coalesce(nullif(ln->>'insurance_status',''),insurance_status), emp_no=coalesce(nullif(ln->>'emp_no',''),emp_no)
        where id=lid;
      end if;
      -- بيانات العاملين فقط (مثل شيت «مؤثرات الرواتب»: الكود والحالة التأمينية) — بدون قسيمة شهرية
      if coalesce(ln->>'employee_only','')='1' then continue; end if;
      -- (3) قسيمة الشهر: سطر واحد لكل موظف لكل شهر (تحديث عند إعادة الاستيراد مع الإبقاء على المؤثرات)
      pid := null;
      select p.id into pid from ebda.payslips p where p.employee_id=lid and p.month=req->>'month' order by p.id limit 1;
      if pid is null then
        pid := ebda.uid();
        insert into ebda.payslips(id,employee_id,emp_name,school_id,month,created_by,created_at,adjustments) values(pid, lid, btrim(ln->>'name'), sid, req->>'month', u.name, now()::text, '{}'::jsonb);
        n_new := n_new + 1;
      else
        n_upd := n_upd + 1;
      end if;
      update ebda.payslips set emp_name=btrim(ln->>'name'), staff_group=coalesce(ln->>'staff_group',''), job=coalesce(ln->>'job',''),
        base=coalesce(nullif(btrim(ln->>'salary'),'')::numeric,0), allowances=coalesce(nullif(btrim(ln->>'allowances'),'')::numeric,0),
        gross=coalesce(nullif(btrim(ln->>'salary'),'')::numeric,0)+coalesce(nullif(btrim(ln->>'allowances'),'')::numeric,0),
        ded_total=coalesce(nullif(btrim(ln->>'ded_total'),'')::numeric,0), direct_ded=coalesce(nullif(btrim(ln->>'direct_ded'),'')::numeric,0),
        month_days=coalesce(nullif(btrim(ln->>'month_days'),'')::numeric,0), work_days=coalesce(nullif(btrim(ln->>'work_days'),'')::numeric,0),
        attend_days=coalesce(nullif(btrim(ln->>'attend_days'),'')::numeric,0), rest_days=coalesce(nullif(btrim(ln->>'rest_days'),'')::numeric,0),
        absent_days=coalesce(nullif(btrim(ln->>'absent_days'),'')::numeric,0), permissions=coalesce(nullif(btrim(ln->>'permissions'),'')::numeric,0),
        deduct_days=coalesce(nullif(btrim(ln->>'deduct_days'),'')::numeric,0),
        leave_opening=coalesce(nullif(btrim(ln->>'leave_opening'),'')::numeric,0), leave_used=coalesce(nullif(btrim(ln->>'leave_used'),'')::numeric,0),
        leave_balance=coalesce(nullif(btrim(ln->>'leave_balance'),'')::numeric,0),
        task_pct=coalesce(nullif(btrim(ln->>'task_pct'),'')::numeric,0), quality_pct=coalesce(nullif(btrim(ln->>'quality_pct'),'')::numeric,0),
        avg_pct=coalesce(nullif(btrim(ln->>'avg_pct'),'')::numeric,0),
        net_import=coalesce(nullif(btrim(ln->>'net'),'')::numeric,0), note=coalesce(ln->>'note',''), source_file=coalesce(req->>'file_name',''),
        updated_at=now()::text
      where id=pid;
      update ebda.payslips set net=ebda.payslip_net(net_import, adjustments) where id=pid;
    end loop;
    if n_new + n_upd > 0 then
      insert into ebda.payroll_periods(id,school_id,month,status,file_name,imported_at,imported_by)
      values(ebda.uid(), sid, req->>'month', 'draft', coalesce(req->>'file_name',''), now()::text, u.name)
      on conflict (school_id,month) do update set file_name=excluded.file_name, imported_at=excluded.imported_at, imported_by=excluded.imported_by;
    end if;
    return jsonb_build_object('ok',true,'employees_added',n_emp,'payslips_added',n_new,'payslips_updated',n_upd);
  end if;

  if action = 'adjustPayslip' then  -- المؤثرات على الراتب (عناصر الراتب من Master Data)
    if not ebda.can(u,'payroll.import') then return ebda.err('صلاحية تعديل الرواتب مطلوبة'); end if;
    select p.school_id, p.month into sid, nk from ebda.payslips p where p.id=(req->>'id');
    if sid is null then return ebda.err('السطر غير موجود'); end if;
    if not ebda.can_school(u, sid) then return ebda.err('هذا المكان ليس ضمن نطاقك'); end if;
    if exists(select 1 from ebda.payroll_periods pp where pp.school_id=sid and pp.month=nk and pp.status='approved') then
      return ebda.err('رواتب هذا الشهر معتمدة — لا يمكن التعديل'); end if;
    if jsonb_typeof(coalesce(req->'adjustments','{}'::jsonb))<>'object' then return ebda.err('بيانات غير صحيحة'); end if;
    if exists(select 1 from jsonb_each_text(req->'adjustments') a where not ebda.num_ok(a.value) or coalesce(nullif(btrim(a.value),'')::numeric,0)<0
              or not exists(select 1 from ebda.payroll_components c where c.code=a.key and c.active like '%نعم%')) then
      return ebda.err('عنصر راتب غير معروف أو قيمة غير صحيحة'); end if;
    update ebda.payslips set adjustments=(select coalesce(jsonb_object_agg(a.key, a.value::numeric),'{}'::jsonb)
                                         from jsonb_each_text(req->'adjustments') a where coalesce(nullif(btrim(a.value),'')::numeric,0)<>0),
      note=coalesce(req->>'note', note), updated_at=now()::text
    where id=(req->>'id');
    update ebda.payslips set net=ebda.payslip_net(net_import, adjustments) where id=(req->>'id');
    return jsonb_build_object('ok',true,'net',(select net from ebda.payslips where id=(req->>'id')));
  end if;

  if action in ('approvePayroll','reopenPayroll') then
    sid := req->>'school_id';
    if not ebda.can_school(u, sid) then return ebda.err('هذا المكان ليس ضمن نطاقك'); end if;
    select p.id into pid from ebda.payroll_periods p where p.school_id=sid and p.month=req->>'month';
    if pid is null then return ebda.err('لا توجد رواتب مستوردة لهذا الشهر'); end if;
    if action='approvePayroll' then
      if not ebda.can(u,'payroll.approve') then return ebda.err('صلاحية اعتماد الرواتب مطلوبة'); end if;
      update ebda.payroll_periods set status='approved', approved_by=u.name, approved_at=now()::text where id=pid;
    else
      if urole<>'admin' then return ebda.err('إعادة فتح رواتب معتمدة للأدمن فقط'); end if;
      update ebda.payroll_periods set status='draft', approved_by='', approved_at='' where id=pid;
    end if;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'savePayrollComponent' then
    if urole<>'admin' then return ebda.err('إدارة عناصر الراتب للأدمن فقط'); end if;
    dj := req->'item';
    if coalesce(btrim(dj->>'name'),'')='' then return ebda.err('اكتب اسم العنصر'); end if;
    if coalesce(dj->>'kind','') not in ('earning','deduction') then return ebda.err('نوع العنصر: إضافة أو خصم'); end if;
    if coalesce(dj->>'id','')='' then
      if coalesce(dj->>'code','') !~ '^[a-z][a-z0-9_]{1,30}$' then return ebda.err('الرمز بالإنجليزية الصغيرة (مثال: transport)'); end if;
      if exists(select 1 from ebda.payroll_components c where c.code=dj->>'code') then return ebda.err('الرمز موجود بالفعل'); end if;
      insert into ebda.payroll_components(id,code,name,kind,active,sort,system)
      values(ebda.uid(), dj->>'code', btrim(dj->>'name'), dj->>'kind', coalesce(nullif(dj->>'active',''),'نعم'), coalesce(nullif(dj->>'sort','')::int,99), 'لا');
    else
      update ebda.payroll_components set name=btrim(dj->>'name'), kind=dj->>'kind', active=coalesce(nullif(dj->>'active',''),active),
        sort=coalesce(nullif(dj->>'sort','')::int,sort) where id=dj->>'id';
    end if;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'savePayrollMap' then
    if not ebda.can(u,'payroll.import') then return ebda.err('لا صلاحية'); end if;
    update ebda.config set value=coalesce(req->>'map','') where key='payroll_map';
    return jsonb_build_object('ok',true);
  end if;
  -- ================================================================ v6: دورة المصروف
  if action = 'submitExpense' then   -- مسودة / معاد للتعديل ← بانتظار المدير المباشر · معاد من المدير المالى ← المراجعة المالية
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    select * into cust from ebda.custodies where id=ex.custody_id;
    if not (urole='admin' or ebda.owns_custody(u, cust)) then return ebda.err('الإرسال لصاحب المصروف فقط'); end if;
    if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى'); end if;
    if ex.approval in ('draft','returned') then
      update ebda.expenses set approval='pending', submitted_at=now()::text, updated_by=u.name, updated_at=now()::text where id=ex.id;
      return jsonb_build_object('ok',true,'stage','pending_manager');
    elsif ex.approval='approved' and ex.fin_approval='returned' then
      update ebda.expenses set fin_approval='', submitted_at=now()::text, updated_by=u.name, updated_at=now()::text where id=ex.id;
      return jsonb_build_object('ok',true,'stage','pending_finance');
    end if;
    return ebda.err('المصروف ليس مسودة ولا معاداً للتعديل');
  end if;

  if action = 'cancelExpense' then   -- للأدمن فقط، فى أى مرحلة: لا حذف — الحالة «ملغى» مع السبب (يخرج من الموازنة ورصيد العهدة)
    if urole<>'admin' then return ebda.err('إلغاء المصروف للأدمن فقط'); end if;
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى بالفعل'); end if;
    if length(coalesce(btrim(req->>'reason'),''))<3 then return ebda.err('اكتب سبب الإلغاء'); end if;
    update ebda.expenses set cancelled_at=now()::text, cancelled_by=u.name, cancel_reason=btrim(req->>'reason'),
      updated_by=u.name, updated_at=now()::text where id=ex.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'unapproveExpense' then   -- إلغاء الاعتماد (للأدمن): يعود المصروف لاعتماد المدير المباشر
    if urole<>'admin' then return ebda.err('إلغاء الاعتماد للأدمن فقط'); end if;
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if coalesce(ex.cancelled_at,'')<>'' then return ebda.err('المصروف ملغى'); end if;
    if length(coalesce(btrim(req->>'reason'),''))<3 then return ebda.err('اكتب سبب إلغاء الاعتماد'); end if;
    update ebda.expenses set approval='pending', approved_by='', approved_by_id='', approved_at='', approval_note='',
      fin_approval='', fin_by='', fin_by_id='', fin_at='', settled='', settled_at='', settled_by='', settled_by_id='',
      return_reason='إلغاء اعتماد بواسطة الأدمن: '||btrim(req->>'reason'), updated_by=u.name, updated_at=now()::text
    where id=ex.id;
    return jsonb_build_object('ok',true);
  end if;

  if action = 'getDoc' then   -- فتح مستند مرفوع داخل النظام (لا يُرسَل محتوى الملفات مع تحميل الصفحة)
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if not ebda.can_expense(u, ex) then return ebda.err('لا صلاحية على هذا المستند'); end if;
    return jsonb_build_object('ok',true,'url',coalesce(ex.doc_url,''),'name',coalesce(ex.doc_name,''));
  end if;

  if action = 'expenseHistory' then   -- كل خطوات المصروف من «تتبع التعديلات»
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return ebda.err('المصروف غير موجود'); end if;
    if not ebda.can_expense(u, ex) then return ebda.err('لا صلاحية على هذا المصروف'); end if;
    return jsonb_build_object('ok',true,'items', coalesce((
      select jsonb_agg(jsonb_build_object('ts', l.ts, 'actor', l.actor, 'role', l.actor_role, 'action', l.action,
                                          'old', c.old_v - 'doc_url', 'new', c.new_v - 'doc_url') order by l.ts)
      from ebda.audit_changes c join ebda.audit_log l on l.txid = c.txid
      where c.tbl='expenses' and c.row_id=ex.id),'[]'::jsonb));
  end if;

  -- ================================================================ v6: Master Data (أنواع العهد · أنواع الموازنات/الجهات)
  if action = 'saveCustodyKind' then
    if urole<>'admin' then return ebda.err('إدارة أنواع العهد للأدمن فقط'); end if;
    dj := req->'item';
    if coalesce(btrim(dj->>'name'),'')='' then return ebda.err('اكتب اسم النوع'); end if;
    if exists(select 1 from ebda.custody_kinds z where ebda.norm_txt(z.name)=ebda.norm_txt(dj->>'name') and z.id<>coalesce(dj->>'id','')) then
      return ebda.err('هذا النوع موجود بالفعل'); end if;
    if coalesce(dj->>'id','')='' then
      newid := ebda.uid();
      insert into ebda.custody_kinds(id,name,active,sort) values(newid, btrim(dj->>'name'), coalesce(nullif(dj->>'active',''),'نعم'), coalesce(nullif(dj->>'sort','')::int,99));
    else
      newid := dj->>'id';
      -- تغيير الاسم ينعكس على العهد القديمة (التصنيف مخزّن كنص)
      update ebda.custodies c set kind=btrim(dj->>'name') from ebda.custody_kinds z where z.id=newid and c.kind=z.name and z.name<>btrim(dj->>'name');
      update ebda.custody_kinds set name=btrim(dj->>'name'), active=coalesce(nullif(dj->>'active',''),active), sort=coalesce(nullif(dj->>'sort','')::int,sort) where id=newid;
      if not found then return ebda.err('النوع غير موجود'); end if;
    end if;
    return jsonb_build_object('ok',true,'id',newid);
  end if;

  if action = 'saveEntityType' then
    if urole<>'admin' then return ebda.err('إدارة أنواع الموازنات للأدمن فقط'); end if;
    dj := req->'item';
    if coalesce(btrim(dj->>'label'),'')='' then return ebda.err('اكتب اسم النوع'); end if;
    if coalesce(dj->>'code','')='' then
      newid := 'et_'||substr(md5(dj->>'label'||clock_timestamp()::text),1,8);
      insert into ebda.entity_types(code,label,active,sort) values(newid, btrim(dj->>'label'), coalesce(nullif(dj->>'active',''),'نعم'), coalesce(nullif(dj->>'sort','')::int,99));
    else
      newid := dj->>'code';
      update ebda.entity_types set label=btrim(dj->>'label'), active=coalesce(nullif(dj->>'active',''),active), sort=coalesce(nullif(dj->>'sort','')::int,sort) where code=newid;
      if not found then return ebda.err('النوع غير موجود'); end if;
    end if;
    return jsonb_build_object('ok',true,'code',newid);
  end if;

  if action = 'setLineActive' then   -- تعطيل/تفعيل بند (للأدمن): المعطّل لا يقبل إدخالات جديدة ويبقى بتاريخه فى التقارير
    if urole<>'admin' then return ebda.err('تعطيل البنود للأدمن فقط'); end if;
    if not exists(select 1 from ebda.lines where id=(req->>'id')) then return ebda.err('البند غير موجود'); end if;
    update ebda.lines set active=case when coalesce(req->>'active','') like '%نعم%' then 'نعم' else 'لا' end where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

  if action = 'setSetting' then   -- إعدادات يغيّرها الأدمن من الواجهة (قائمة محددة فقط)
    if urole<>'admin' then return ebda.err('الإعدادات للأدمن فقط'); end if;
    if coalesce(req->>'key','') not in ('require_doc_to_settle','custody_overdue_days') then return ebda.err('إعداد غير معروف'); end if;
    if req->>'key'='require_doc_to_settle' and coalesce(req->>'value','') not in ('yes','no') then return ebda.err('قيمة غير صحيحة'); end if;
    if req->>'key'='custody_overdue_days' and coalesce(req->>'value','') !~ '^[0-9]{1,4}$' then return ebda.err('عدد أيام غير صحيح'); end if;
    insert into ebda.config(key,value) values(req->>'key', req->>'value') on conflict (key) do update set value=excluded.value;
    return jsonb_build_object('ok',true);
  end if;

  -- ================================================================ v6: النسخ الاحتياطى والاستعادة (للأدمن فقط)
  if action in ('createBackup','downloadBackup','restoreBackup','backupInfo') then
    if urole<>'admin' then return ebda.err('النسخ الاحتياطى للأدمن فقط'); end if;
    if action = 'createBackup' then
      return jsonb_build_object('ok',true,'backup', ebda.make_backup('manual', u.name, coalesce(req->>'note','')));
    end if;
    if action = 'backupInfo' then
      return jsonb_build_object('ok',true,'item',(select jsonb_build_object('id',b.id,'name',b.name,'kind',b.kind,'created_at',b.created_at,'created_by',b.created_by,
             'size_bytes',b.size_bytes,'counts',b.counts,'note',b.note,'schema_version',b.data#>>'{_meta,schema_version}') from ebda.backups b where b.id=(req->>'id')));
    end if;
    if action = 'downloadBackup' then
      return jsonb_build_object('ok',true,'name',(select name from ebda.backups where id=(req->>'id')),
                                'data',(select data from ebda.backups where id=(req->>'id')));
    end if;
    -- restoreBackup: يتطلب كتابة اسم النسخة للتأكيد
    if coalesce(req->>'confirm','') <> coalesce((select name from ebda.backups where id=(req->>'id')),'~') then
      return ebda.err('للتأكيد اكتب اسم النسخة كما هو'); end if;
    nk := (select value from ebda.config where key='schema_version');
    res := ebda.restore_backup(req->>'id', u.name);
    if res ? 'error' then return res; end if;
    update ebda.config set value=nk where key='schema_version';   -- إصدار قاعدة البيانات الحالى لا يتغير بالاستعادة
    return res;
  end if;

  -- ================================================================ v6: استيراد العاملين الآمن (معاينة ← تحقق ← تأكيد) — بدون تكرار وبدون حذف
  -- الموظف له معرّف ثابت: يُطابَق بالرقم القومى (فى كل الأماكن) ثم بالرقم الوظيفى ثم بالاسم داخل المكان.
  -- ---------------------------------------------------------------- استيراد ملف المصروفات والعهد (معاينة ← استيراد)
  if action = 'importExpensesFile' then
    return ebda.import_expenses(u, req);
  end if;
  if action = 'importBatches' then
    if not (urole = 'admin' or ebda.can(u,'expense.import')) then return ebda.err('صلاحية استيراد المصروفات مطلوبة'); end if;
    return jsonb_build_object('ok', true, 'batches', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'file_name', b.file_name, 'actor', b.actor,
        'created_at', b.created_at, 'approve_mode', b.approve_mode, 'rows_n', b.rows_n, 'imported_n', b.imported_n, 'amount', b.amount,
        'summary', b.summary, 'exceptions_n', jsonb_array_length(b.exceptions), 'reverted_at', b.reverted_at, 'reverted_by', b.reverted_by,
        'exceptions', case when b.id = req->>'id' then b.exceptions else null end) order by b.created_at desc)
      from (select * from ebda.import_batches z where urole = 'admin' or z.actor_id = u.id order by z.created_at desc limit 100) b), '[]'::jsonb));
  end if;
  if action = 'revertImport' then
    if urole <> 'admin' then return ebda.err('التراجع عن الاستيراد للأدمن فقط'); end if;
    return ebda.revert_import(u, req->>'id', req->>'reason');
  end if;

  if action = 'importEmployeesSafe' then
    if not (ebda.can(u,'payroll.import') or urole='admin') then return ebda.err('صلاحية استيراد العاملين مطلوبة'); end if;
    sid := req->>'school_id';
    if sid is null or not exists(select 1 from ebda.schools s where s.id=sid) then return ebda.err('اختر المكان'); end if;
    if not ebda.can_school(u, sid) then return ebda.err('هذا المكان ليس ضمن نطاقك'); end if;
    if jsonb_typeof(coalesce(req->'rows','null'::jsonb))<>'array' then return ebda.err('لا توجد بيانات'); end if;
    catv := case when req->>'category'='gov' then 'gov' else 'contract' end;
    declare
      fields text[] := array['serial_no','emp_no','name','job','job_type','qualification','grad_year','national_id','birth_date','birth_place','phone',
                             'hire_date','work_start','gender','secondment_status','address','retire_date','email','bank','account_no','branch',
                             'insurance_no','base_salary','contract_type','dept','note'];
      f text; nm text; ek ebda.employees; eid text; st text; reasons jsonb; changes jsonb; out jsonb := '[]'::jsonb;
      seen_nk text[] := '{}'; seen_nm text[] := '{}'; i int := 0;
      c_new int := 0; c_upd int := 0; c_same int := 0; c_dup int := 0; c_err int := 0; c_warn int := 0;
      commit_ boolean := coalesce(req->>'mode','preview') = 'commit';
      rw jsonb;
    begin
      for rw in select * from jsonb_array_elements(req->'rows') loop
        i := i + 1; reasons := '[]'::jsonb; changes := '[]'::jsonb; eid := null; ek := null;
        nm := btrim(coalesce(rw->>'name',''));
        nk := regexp_replace(translate(coalesce(rw->>'national_id',''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[^0-9]', '', 'g');
        if nm = '' then
          st := 'error'; reasons := reasons || to_jsonb('اسم الموظف مطلوب'::text);
        elsif coalesce(rw->>'base_salary','') <> '' and not ebda.num_ok(rw->>'base_salary') then
          st := 'error'; reasons := reasons || to_jsonb('الراتب/الحافز ليس رقماً'::text);
        elsif (nk <> '' and nk = any(seen_nk)) or (nk = '' and ebda.norm_txt(nm) = any(seen_nm)) then
          st := 'duplicate'; reasons := reasons || to_jsonb(case when nk<>'' then 'الرقم القومى مكرر داخل الملف' else 'الاسم مكرر داخل الملف' end);
        else
          if nk <> '' and length(nk) <> 14 then reasons := reasons || to_jsonb('الرقم القومى ليس 14 رقماً'::text); end if;
          if nk = '' then reasons := reasons || to_jsonb('الرقم القومى غير موجود'::text); end if;
          if coalesce(rw->>'phone','') = '' then reasons := reasons || to_jsonb('رقم الهاتف غير موجود'::text); end if;
          if nk <> '' then select * into ek from ebda.employees e where e.national_key = nk order by e.id limit 1; end if;
          if ek.id is null and coalesce(rw->>'emp_no','')<>'' then
            select * into ek from ebda.employees e where e.school_id=sid and e.emp_no = rw->>'emp_no' order by e.id limit 1; end if;
          if ek.id is null then
            select * into ek from ebda.employees e where e.school_id=sid and ebda.norm_txt(e.name)=ebda.norm_txt(nm) order by e.id limit 1; end if;
          if ek.id is null then
            st := 'new';
          else
            eid := ek.id;
            foreach f in array fields loop
              if coalesce(btrim(rw->>f),'') <> '' and coalesce(to_jsonb(ek)->>f,'') is distinct from btrim(rw->>f)
                 and not (f='base_salary' and ebda.num_ok(rw->>f) and coalesce(ek.base_salary,0) = nullif(btrim(rw->>f),'')::numeric) then
                changes := changes || to_jsonb(f);
              end if;
            end loop;
            if ek.school_id is distinct from sid then
              changes := changes || to_jsonb('school_id'::text);
              reasons := reasons || to_jsonb(('مسجل فى مكان آخر: ' || coalesce((select s.name from ebda.schools s where s.id=ek.school_id),'—') || ' — سيُنقل لهذا المكان')::text);
            end if;
            st := case when jsonb_array_length(changes) > 0 then 'updated' else 'same' end;
          end if;
          if nk <> '' then seen_nk := seen_nk || nk; else seen_nm := seen_nm || ebda.norm_txt(nm); end if;
        end if;
        if st = 'new' then c_new := c_new + 1; elsif st = 'updated' then c_upd := c_upd + 1; elsif st = 'same' then c_same := c_same + 1;
        elsif st = 'duplicate' then c_dup := c_dup + 1; else c_err := c_err + 1; end if;
        if st in ('new','updated','same') and jsonb_array_length(reasons) > 0 then c_warn := c_warn + 1; end if;
        if commit_ and st = 'new' then
          eid := ebda.uid();
          insert into ebda.employees(id,school_id,category,emp_no,serial_no,name,job,job_type,qualification,grad_year,national_id,national_key,birth_date,birth_place,phone,
              hire_date,work_start,gender,secondment_status,address,retire_date,email,bank,account_no,branch,insurance_no,base_salary,contract_type,dept,note,
              staff_group,active,archived)
          values(eid, sid, catv, coalesce(rw->>'emp_no',''), coalesce(rw->>'serial_no',''), nm, coalesce(rw->>'job',''), coalesce(rw->>'job_type',''),
              coalesce(rw->>'qualification',''), coalesce(rw->>'grad_year',''), coalesce(rw->>'national_id',''), nk, coalesce(rw->>'birth_date',''),
              coalesce(rw->>'birth_place',''), coalesce(rw->>'phone',''), coalesce(rw->>'hire_date',''), coalesce(rw->>'work_start',''), coalesce(rw->>'gender',''),
              coalesce(rw->>'secondment_status',''), coalesce(rw->>'address',''), coalesce(rw->>'retire_date',''), coalesce(rw->>'email',''), coalesce(rw->>'bank',''),
              coalesce(rw->>'account_no',''), coalesce(rw->>'branch',''), coalesce(rw->>'insurance_no',''), coalesce(nullif(btrim(rw->>'base_salary'),'')::numeric,0),
              coalesce(nullif(rw->>'contract_type',''), case when catv='gov' then 'منتدب' else '' end), coalesce(rw->>'dept',''), coalesce(rw->>'note',''),
              case when catv='gov' then 'gov' else '' end, 'نعم', 'لا');
        elsif commit_ and st = 'updated' then
          -- تحديث الحقول القادمة فى الملف فقط — لا يُمسح أى حقل موجود بقيمة فارغة
          update ebda.employees set school_id=sid,
            emp_no=coalesce(nullif(btrim(rw->>'emp_no'),''),emp_no), serial_no=coalesce(nullif(btrim(rw->>'serial_no'),''),serial_no),
            name=nm, job=coalesce(nullif(btrim(rw->>'job'),''),job), job_type=coalesce(nullif(btrim(rw->>'job_type'),''),job_type),
            qualification=coalesce(nullif(btrim(rw->>'qualification'),''),qualification), grad_year=coalesce(nullif(btrim(rw->>'grad_year'),''),grad_year),
            national_id=coalesce(nullif(btrim(rw->>'national_id'),''),national_id), national_key=coalesce(nullif(nk,''),national_key),
            birth_date=coalesce(nullif(btrim(rw->>'birth_date'),''),birth_date), birth_place=coalesce(nullif(btrim(rw->>'birth_place'),''),birth_place),
            phone=coalesce(nullif(btrim(rw->>'phone'),''),phone), hire_date=coalesce(nullif(btrim(rw->>'hire_date'),''),hire_date),
            work_start=coalesce(nullif(btrim(rw->>'work_start'),''),work_start), gender=coalesce(nullif(btrim(rw->>'gender'),''),gender),
            secondment_status=coalesce(nullif(btrim(rw->>'secondment_status'),''),secondment_status), address=coalesce(nullif(btrim(rw->>'address'),''),address),
            retire_date=coalesce(nullif(btrim(rw->>'retire_date'),''),retire_date), email=coalesce(nullif(btrim(rw->>'email'),''),email),
            bank=coalesce(nullif(btrim(rw->>'bank'),''),bank), account_no=coalesce(nullif(btrim(rw->>'account_no'),''),account_no),
            branch=coalesce(nullif(btrim(rw->>'branch'),''),branch), insurance_no=coalesce(nullif(btrim(rw->>'insurance_no'),''),insurance_no),
            base_salary=coalesce(nullif(btrim(rw->>'base_salary'),'')::numeric,base_salary), contract_type=coalesce(nullif(btrim(rw->>'contract_type'),''),contract_type),
            dept=coalesce(nullif(btrim(rw->>'dept'),''),dept), note=coalesce(nullif(btrim(rw->>'note'),''),note)
          where id=eid;
        end if;
        out := out || jsonb_build_object('i', i, 'name', nm, 'national_id', coalesce(rw->>'national_id',''), 'status', st, 'reasons', reasons,
                                         'changes', changes, 'employee_id', coalesce(eid,''));
      end loop;
      return jsonb_build_object('ok', true, 'mode', case when commit_ then 'commit' else 'preview' end,
        'counts', jsonb_build_object('new', c_new, 'updated', c_upd, 'same', c_same, 'duplicate', c_dup, 'error', c_err, 'warnings', c_warn),
        'rows', out);
    end;
  end if;

  if action = 'payrollMonth' then   -- قسائم شهر أقدم من نافذة التحميل (تُطلب عند اختياره فقط)
    if not (ebda.sees_budgets(u) or ebda.can(u,'payroll.view')) then return ebda.err('لا صلاحية لعرض الرواتب'); end if;
    if coalesce(req->>'month','') !~ '^[0-9]{4}-[0-9]{2}$' then return ebda.err('الشهر غير صحيح'); end if;
    return jsonb_build_object('ok',true,'payslips', coalesce((select jsonb_agg(to_jsonb(z)) from ebda.payslips z
      where z.month = req->>'month' and ebda.can_school(u, z.school_id)),'[]'::jsonb));
  end if;

  -- ================================================================ v6: البحث فى المصروفات والتقارير الديناميكية — على الخادم
  -- (فلترة + تجميع + ترقيم صفحات داخل قاعدة البيانات، وتُرسل النتائج المطلوبة فقط، وكل ذلك داخل نطاق المستخدم)
  if action in ('searchExpenses','report') then
    declare
      f jsonb := coalesce(req->'filters','{}'::jsonb);
      rkind text := coalesce(req->>'kind', 'expenses');
      star boolean := coalesce(u.schools,'')='*' or urole='admin';
      sch text[] := ebda.scope_arr(u);
      lo text := coalesce(nullif(req#>>'{filters,from}',''), '0000');
      hi text := coalesce(nullif(req#>>'{filters,to}',''), '9999');
      ps int := least(greatest(coalesce(nullif(req->>'page_size','')::int, 50), 1), case when action='report' then 5000 else 500 end);
      pg int := greatest(coalesce(nullif(req->>'page','')::int, 1) - 1, 0);
      odays int := ebda.cfg_int('custody_overdue_days', 30);
      can_appr boolean := ebda.can(u,'expense.approve');
      can_fin boolean := ebda.can(u,'expense.fin_approve');
      stages text[] := case when jsonb_typeof(req#>'{filters,stages}')='array' then array(select jsonb_array_elements_text(req#>'{filters,stages}')) else '{}'::text[] end;
    begin
    if action = 'searchExpenses' or rkind = 'expenses' then
      return (with v as materialized (
        select e.id, e.date, e.txn_no, e.amount, e.custody_id, e.school_id, e.line_id, e.created_by_id, ebda.expense_stage(e) stage
        from (select * from ebda.expenses where urole = 'admin' union all select * from ebda.vis_expenses(u) where urole <> 'admin') e
        where true
          and (coalesce(f->>'school_id','') = '' or e.school_id = f->>'school_id')
          and (coalesce(f->>'custody_id','') = '' or e.custody_id = f->>'custody_id')
          and (coalesce(f->>'line_id','') = '' or e.line_id = f->>'line_id')
          and (coalesce(f->>'spend_item','') = '' or e.spend_item = f->>'spend_item')
          and (coalesce(f->>'from','') = '' or e.date >= f->>'from')
          and (coalesce(f->>'to','') = '' or e.date <= f->>'to')
          and (coalesce(f->>'q','') = '' or e.txn_no ilike '%'||(f->>'q')||'%' or e.description ilike '%'||(f->>'q')||'%'
               or coalesce(e.supplier,'') ilike '%'||(f->>'q')||'%' or coalesce(e.doc_no,'') ilike '%'||(f->>'q')||'%')
          and (coalesce(f->>'import_batch','') = '' or e.import_batch = f->>'import_batch')
          and (cardinality(stages) = 0 or ebda.expense_stage(e) = any(stages))
          and (coalesce(f->>'no_doc','') <> '1' or coalesce(e.doc_url,'') = '')
          and (coalesce(f->>'incomplete','') <> '1' or coalesce(e.review_status,'') like '%ناقص%')
      ), base as (
        select v.*, o.manager_id as mgr_id from v
        left join ebda.custodies c on c.id = v.custody_id
        left join ebda.users o on o.id = c.user_id
        where (coalesce(f->>'holder_id','') = '' or c.user_id = f->>'holder_id')
          and (coalesce(f->>'holder','') = '' or coalesce(nullif(c.holder,''), c.label, '') = f->>'holder')
          and (coalesce(f->>'manager_id','') = '' or o.manager_id = f->>'manager_id')
          and (coalesce(f->>'kind','') = '' or c.kind = f->>'kind')
          and (coalesce(f->>'title','') = '' or c.title = f->>'title')
          and (coalesce(f->>'mine','') <> '1' or c.user_id = u.id)
          and (coalesce(f->>'my_queue','') <> '1' or (
                 (v.stage = 'pending_manager' and can_appr and c.id is not null
                   and not ebda.owns_custody(u, c) and coalesce(v.created_by_id,'') <> u.id
                   and (urole = 'admin' or (coalesce(o.manager_id,'') <> '' and o.manager_id = u.id)
                        or (coalesce(o.manager_id,'') = '' and (star or c.school_id = any(sch)))))
              or (v.stage in ('pending_finance','reviewed') and can_fin
                   and not (c.id is not null and ebda.owns_custody(u, c)) and coalesce(v.created_by_id,'') <> u.id)
              or (v.stage in ('draft','returned','fin_returned') and c.id is not null and ebda.owns_custody(u, c))))
      ), page as (
        select base.id, base.stage, base.mgr_id from base
        order by case when coalesce(req->>'sort','') = 'amount' then null else base.date end desc nulls last,
                 case when coalesce(req->>'sort','') = 'amount' then base.amount end desc nulls last,
                 base.txn_no desc
        limit ps offset pg * ps
      )
      select jsonb_build_object('ok', true,
        'total', (select count(*) from base),
        'sum', (select coalesce(sum(amount),0) from base where stage not in ('cancelled','rejected','fin_rejected')),
        'by_stage', coalesce((select jsonb_object_agg(stage, jsonb_build_object('n', cnt, 'amount', amt)) from
                     (select stage, count(*) cnt, sum(amount) amt from base group by stage) z), '{}'::jsonb),
        'rows', coalesce((select jsonb_agg(jsonb_build_object(
            'id', e.id, 'txn_no', e.txn_no, 'date', e.date, 'school_id', e.school_id, 'school', s.name, 'category', s.category,
            'custody_id', e.custody_id, 'custody_code', coalesce(c.code, 'شراء مركزى'), 'custody_title', coalesce(nullif(c.title,''), c.label, ''),
            'custody_kind', coalesce(c.kind,''), 'holder', coalesce(nullif(c.holder,''), c.label, ''), 'holder_id', coalesce(c.user_id,''),
            'manager_id', coalesce(p.mgr_id,''), 'manager', coalesce(m.name,''),
            'line_id', e.line_id, 'line', coalesce(l.name,''), 'section', coalesce(l.section,''), 'spend_item', coalesce(e.spend_item,''),
            'description', e.description, 'amount', e.amount, 'pay_method', coalesce(e.pay_method,''), 'stage', p.stage,
            'approval', e.approval, 'approved_by', coalesce(e.approved_by,''), 'approved_at', coalesce(e.approved_at,''), 'approval_note', coalesce(e.approval_note,''),
            'fin_approval', coalesce(e.fin_approval,''), 'fin_by', coalesce(e.fin_by,''), 'fin_at', coalesce(e.fin_at,''), 'fin_note', coalesce(e.fin_note,''),
            'settled', coalesce(e.settled,''), 'settled_by', coalesce(e.settled_by,''), 'settled_at', coalesce(e.settled_at,''),
            'review_status', coalesce(e.review_status,''), 'review_note', coalesce(e.review_note,''),
            'return_reason', coalesce(e.return_reason,''), 'returned_by', coalesce(e.returned_by,''), 'returned_at', coalesce(e.returned_at,''),
            'cancel_reason', coalesce(e.cancel_reason,''), 'cancelled_by', coalesce(e.cancelled_by,''), 'cancelled_at', coalesce(e.cancelled_at,''),
            'created_by', coalesce(e.created_by,''), 'created_by_id', coalesce(e.created_by_id,''), 'created_at', coalesce(e.created_at,''),
            'submitted_at', coalesce(e.submitted_at,''), 'doc_name', coalesce(e.doc_name,''), 'doc_type', coalesce(e.doc_type,''),
            'doc_url', case when e.doc_url like 'data:%' then 'inline:' else coalesce(e.doc_url,'') end)
            || jsonb_build_object('supplier', coalesce(e.supplier,''), 'doc_no', coalesce(e.doc_no,''), 'import_batch', coalesce(e.import_batch,''))
            order by case when coalesce(req->>'sort','') = 'amount' then null else e.date end desc nulls last,
                     case when coalesce(req->>'sort','') = 'amount' then e.amount end desc nulls last, e.txn_no desc)
          from page p join ebda.expenses e on e.id = p.id
          left join ebda.custodies c on c.id = e.custody_id left join ebda.schools s on s.id = e.school_id
          left join ebda.lines l on l.id = e.line_id left join ebda.users m on m.id = p.mgr_id), '[]'::jsonb)));
    end if;

    if rkind = 'custodyHolder' then   -- تقرير حالة عهد مسئول/مسئولين (فلتر واحد أو أكثر)
      return (with vc as materialized (
        select c.* from ebda.vis_custodies(u) c
        where (coalesce(f->>'holder_id','')='' or c.user_id = f->>'holder_id')
          and (coalesce(f->>'holder','')='' or coalesce(nullif(c.holder,''), c.label, '') = f->>'holder')
          and (coalesce(f->>'school_id','')='' or c.school_id = f->>'school_id')
          and (coalesce(f->>'title','')='' or c.title = f->>'title')
          and (coalesce(f->>'kind','')='' or c.kind = f->>'kind')
      ), tr as (
        select t.custody_id, sum(t.amount) s, bool_or(t.date between lo and hi) inr from ebda.tranches t where t.custody_id = any(array(select id from vc)) group by 1
      ), ea as (
        select e.custody_id,
          sum(e.amount) filter (where ebda.active_on_custody(e)) spent,
          sum(e.amount) filter (where ebda.active_on_custody(e) and (coalesce(f->>'line_id','')='' or e.line_id=f->>'line_id') and e.date between lo and hi) f_spent,
          count(*) filter (where coalesce(e.cancelled_at,'')='' and ebda.expense_stage(e) in ('pending_manager','pending_finance')) under_review,
          count(*) filter (where ebda.active_on_custody(e) and e.approval='approved' and coalesce(e.settled,'') not like '%نعم%') unsettled,
          count(*) filter (where coalesce(e.cancelled_at,'')='' and coalesce(e.settled,'') not like '%نعم%'
             and (e.approval in ('rejected','returned') or e.fin_approval in ('rejected','returned') or coalesce(e.review_status,'') like '%ناقص%' or coalesce(e.review_note,'')<>'')) notes,
          bool_or(e.date between lo and hi) inr, bool_or(e.line_id = f->>'line_id') has_line
        from ebda.expenses e where e.custody_id = any(array(select id from vc)) group by 1
      ), cs as (
        select vc.*, s.name as s_name, coalesce(tr.s,0) received, coalesce(ea.spent,0) spent, coalesce(ea.f_spent,0) f_spent,
               coalesce(ea.under_review,0) under_review, coalesce(ea.unsettled,0) unsettled, coalesce(ea.notes,0) notes,
               greatest(ebda.days_since(vc.opened_at), 0) as age
        from vc left join ebda.schools s on s.id = vc.school_id left join tr on tr.custody_id = vc.id left join ea on ea.custody_id = vc.id
        where (coalesce(f->>'line_id','')='' or coalesce(ea.has_line,false)
               or exists(select 1 from ebda.custody_lines cl where cl.custody_id = vc.id and cl.line_id = f->>'line_id'))
          and ((coalesce(f->>'from','')='' and coalesce(f->>'to','')='') or left(coalesce(vc.opened_at,''),10) between lo and hi
               or coalesce(ea.inr,false) or coalesce(tr.inr,false))
      ), st as (
        select cs.*, case
            when coalesce(nullif(cs.status,''),'open') = 'open' and coalesce(cs.approval,'approved') = 'approved' and cs.notes > 0 then 'notes'
            when coalesce(nullif(cs.status,''),'open') = 'open' and coalesce(cs.approval,'approved') = 'approved' and cs.age > odays then 'overdue'
            else coalesce(nullif(cs.status,''),'open') end as state
        from cs
      ), fl as (
        select * from st
        where (coalesce(f->>'state','')='' or st.state = f->>'state')
          and (coalesce(f->>'settle','')='' or (f->>'settle'='settled' and st.state in ('settled','closed'))
               or (f->>'settle'='unsettled' and st.state not in ('settled','closed','cancelled')))
      )
      select jsonb_build_object('ok', true, 'kind', 'custodyHolder',
        'summary', jsonb_build_object(
          'holders', coalesce((select jsonb_agg(distinct coalesce(nullif(holder,''), label, '')) from fl), '[]'::jsonb),
          'count', (select count(*) from fl),
          'received', (select coalesce(sum(received),0) from fl where state <> 'cancelled'),
          'spent', (select coalesce(sum(spent),0) from fl where state <> 'cancelled'),
          'remaining', (select coalesce(sum(received - spent),0) from fl where state <> 'cancelled'),
          'filtered_spent', (select coalesce(sum(f_spent),0) from fl where state <> 'cancelled'),
          'open', (select count(*) from fl where state in ('open','notes','overdue','pending_settlement')),
          'settled', (select count(*) from fl where state in ('settled','closed')),
          'overdue', (select count(*) from fl where state = 'overdue'),
          'cancelled', (select count(*) from fl where state = 'cancelled'),
          'under_review', (select coalesce(sum(under_review),0) from fl where state <> 'cancelled'),
          'unsettled', (select coalesce(sum(unsettled),0) from fl where state <> 'cancelled'),
          'overdue_days', odays),
        'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'title', coalesce(title,''), 'kind', coalesce(kind,''),
            'school_id', school_id, 'school', s_name, 'holder', coalesce(nullif(holder,''), label, ''), 'holder_id', coalesce(user_id,''),
            'opened_at', coalesce(opened_at,''), 'approval', coalesce(approval,'approved'), 'state', state, 'age', age,
            'received', received, 'spent', spent, 'remaining', received - spent, 'filtered_spent', f_spent,
            'under_review', under_review, 'unsettled', unsettled, 'notes', notes) order by code)
            from (select * from fl order by code limit 5000) z), '[]'::jsonb)));
    end if;

    if rkind = 'budget' then   -- تقرير الموازنة: المكان · السنة · النوع · البند · المخصص · المصروف · المتبقى · النسبة · الحالة (شهر أو سنة)
      return (with ents as materialized (
        select s.* from ebda.schools s where (star or s.id = any(sch))
          and (coalesce(f->>'school_id','')='' or s.id = f->>'school_id')
          and (coalesce(f->>'period','')='' or f->>'period'='all' or s.period = f->>'period')
          and (coalesce(f->>'category','')='' or f->>'category'='all' or coalesce(nullif(s.category,''),'school') = f->>'category')
      ), ls as (
        select l.*, e.name as e_name, e.period as e_period, coalesce(nullif(e.category,''),'school') as e_cat,
               ebda.fy_from(e.period) as f_from, ebda.fy_to(e.period) as f_to
        from ebda.lines l join ents e on e.id = l.school_id
        where coalesce(l.deleted_at,'')=''
          and (coalesce(f->>'line_id','')='' or l.id = f->>'line_id')
          and (coalesce(f->>'section','')='' or l.section = f->>'section')
      ), sp as (
        select z.line_id, sum(z.amount) filter (where coalesce(nullif(f->>'month',''),'0')::int = 0 or z.m = (f->>'month')::int) as amt
        from ebda.line_fy_spend(u) z group by 1
      ), r as (
        select ls.*, case when coalesce(nullif(f->>'month',''),'0')::int = 0 then coalesce(ls.allocated,0)
                          else ebda.plan_month(ls.monthly_plan, ls.allocated, (f->>'month')::int) end as alloc,
               coalesce(sp.amt,0) as spent
        from ls left join sp on sp.line_id = ls.id
      ), fs as (
        select r.*, ebda.budget_state(r.alloc, r.spent) as state from r
      ), gs as (
        select * from fs where coalesce(f->>'state','')='' or fs.state = f->>'state'
      )
      select jsonb_build_object('ok', true, 'kind', 'budget',
        'summary', jsonb_build_object('lines', (select count(*) from gs), 'alloc', (select coalesce(sum(alloc),0) from gs),
          'spent', (select coalesce(sum(spent),0) from gs), 'remaining', (select coalesce(sum(alloc - spent),0) from gs),
          'over', (select count(*) from gs where state='over'), 'reached', (select count(*) from gs where state='reached'),
          'near', (select count(*) from gs where state='near'), 'within', (select count(*) from gs where state='within')),
        'rows', coalesce((select jsonb_agg(jsonb_build_object('line_id', id, 'school_id', school_id, 'school', e_name, 'period', coalesce(e_period,''),
            'category', e_cat, 'section', coalesce(section,''), 'line', name, 'active', coalesce(active,'نعم'),
            'alloc', alloc, 'spent', spent, 'remaining', alloc - spent,
            'pct', case when alloc > 0.5 then spent / alloc when spent > 0.5 then 1 else 0 end, 'state', state)
            order by e_name, section, name) from gs), '[]'::jsonb)));
    end if;

    if rkind = 'financial' then   -- التقرير المالى الشامل: الموازنات + العهد + المصروفات + التسويات
      return (with ents as materialized (
        select s.* from ebda.schools s where (star or s.id = any(sch))
          and (coalesce(f->>'school_id','')='' or s.id = f->>'school_id')
          and (coalesce(f->>'period','')='' or f->>'period'='all' or s.period = f->>'period')
      ), ls as (
        select l.id, l.name, coalesce(l.allocated,0) alloc, ebda.fy_from(e.period) f_from, ebda.fy_to(e.period) f_to, e.name e_name
        from ebda.lines l join ents e on e.id=l.school_id where coalesce(l.deleted_at,'')=''
      ), lspent as (
        select z.line_id, sum(z.amount) s from ebda.line_fy_spend(u) z group by 1
      ), lsp as (
        select ls.id, ls.name, ls.e_name, ls.alloc, coalesce(lspent.s,0) spent from ls left join lspent on lspent.line_id = ls.id
      ), exx as materialized (
        select e.amount, ebda.expense_stage(e) stage
        from (select * from ebda.expenses where urole = 'admin' union all select * from ebda.vis_expenses(u) where urole <> 'admin') e
        where e.school_id in (select id from ents)
          and (coalesce(f->>'from','')='' or e.date >= f->>'from') and (coalesce(f->>'to','')='' or e.date <= f->>'to')
      ), vc as materialized (
        select c.* from ebda.vis_custodies(u) c where c.school_id in (select id from ents) and coalesce(c.status,'') <> 'cancelled'
      ), tr as (select t.custody_id, sum(t.amount) s from ebda.tranches t where t.custody_id = any(array(select id from vc)) group by 1
      ), ea as (
        select e.custody_id, sum(e.amount) filter (where ebda.active_on_custody(e)) spent,
          count(*) filter (where coalesce(e.cancelled_at,'')='' and coalesce(e.settled,'') not like '%نعم%'
             and (e.approval in ('rejected','returned') or e.fin_approval in ('rejected','returned') or coalesce(e.review_status,'') like '%ناقص%' or coalesce(e.review_note,'')<>'')) notes
        from ebda.expenses e where e.custody_id = any(array(select id from vc)) group by 1
      ), cu as (
        select vc.*, coalesce(tr.s,0) received, coalesce(ea.spent,0) spent, coalesce(ea.notes,0) notes
        from vc left join tr on tr.custody_id = vc.id left join ea on ea.custody_id = vc.id
      ), od as (
        select cu.* from cu where coalesce(nullif(cu.status,''),'open')='open' and coalesce(cu.approval,'approved')='approved'
          and greatest(ebda.days_since(cu.opened_at),0) > odays and cu.notes = 0
      )
      select jsonb_build_object('ok', true, 'kind', 'financial', 'summary', jsonb_build_object(
          'budget_total', (select coalesce(sum(alloc),0) from lsp),
          'budget_spent', (select coalesce(sum(spent),0) from lsp),
          'budget_remaining', (select coalesce(sum(alloc - spent),0) from lsp),
          'custody_total', (select coalesce(sum(received),0) from cu),
          'custody_spent', (select coalesce(sum(spent),0) from cu),
          'custody_remaining', (select coalesce(sum(received - spent),0) from cu),
          'expenses_total', (select coalesce(sum(amount),0) from exx where stage not in ('cancelled','rejected','fin_rejected')),
          'expenses_count', (select count(*) from exx where stage not in ('cancelled','rejected','fin_rejected')),
          'pending_manager', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage='pending_manager'),
          'pending_finance', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage='pending_finance'),
          'returned', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage in ('returned','fin_returned','draft')),
          'settled', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage='settled'),
          'unsettled', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage in ('pending_finance','reviewed')),
          'cancelled', (select jsonb_build_object('n', count(*), 'amount', coalesce(sum(amount),0)) from exx where stage='cancelled'),
          'over_lines', (select count(*) from lsp where ebda.budget_state(alloc, spent)='over'),
          'overdue_custodies', (select count(*) from od)),
        'over_lines', coalesce((select jsonb_agg(jsonb_build_object('line_id', id, 'line', name, 'school', e_name, 'alloc', alloc, 'spent', spent, 'over', spent - alloc)
                         order by spent - alloc desc) from (select * from lsp where ebda.budget_state(alloc, spent)='over' order by spent - alloc desc limit 500) z), '[]'::jsonb),
        'overdue_custodies', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'holder', coalesce(nullif(holder,''), label, ''),
                         'age', greatest(ebda.days_since(opened_at),0), 'remaining', received - spent) order by opened_at) from (select * from od order by opened_at limit 500) z), '[]'::jsonb)));
    end if;

    if rkind = 'lineMonths' then   -- المصروف المحتسب لكل بند لكل شهر من السنة المالية (للوحة المتابعة — يُحسب على الخادم)
      return jsonb_build_object('ok', true, 'line_months', ebda.line_months(u));
    end if;
    return ebda.err('نوع تقرير غير معروف');
    end;
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
    -- منع تكرار الموظف عند الإضافة اليدوية أيضاً (نفس الرقم القومى)
    nk := regexp_replace(translate(coalesce(dj->>'national_id',''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[^0-9]', '', 'g');
    if nk <> '' and exists(select 1 from ebda.employees z where z.national_key = nk) then
      return ebda.err('يوجد موظف مسجل بنفس الرقم القومى — عدّل بياناته بدلاً من إضافته مرة أخرى'); end if;
    insert into ebda.employees(id,school_id,category,emp_no,name,job,job_type,qualification,grad_year,national_id,birth_date,phone,hire_date,work_start,insurance_no,account_no,bank,branch,email,ebda_start,base_salary,contract_type,gender,address,retire_date,note,active,archived)
    values(newid, dj->>'school_id', coalesce(dj->>'category','contract'), coalesce(dj->>'emp_no',''), dj->>'name', coalesce(dj->>'job',''), coalesce(dj->>'job_type',''), coalesce(dj->>'qualification',''), coalesce(dj->>'grad_year',''), coalesce(dj->>'national_id',''), coalesce(dj->>'birth_date',''), coalesce(dj->>'phone',''), coalesce(dj->>'hire_date',''), coalesce(dj->>'work_start',''), coalesce(dj->>'insurance_no',''), coalesce(dj->>'account_no',''), coalesce(dj->>'bank',''), coalesce(dj->>'branch',''), coalesce(dj->>'email',''), coalesce(dj->>'ebda_start',''), coalesce((dj->>'base_salary')::numeric,0), coalesce(dj->>'contract_type',''), coalesce(dj->>'gender',''), coalesce(dj->>'address',''), coalesce(dj->>'retire_date',''), coalesce(dj->>'note',''), 'نعم','لا');
    update ebda.employees set dept=coalesce(dj->>'dept',''), manager_user_id=coalesce(dj->>'manager_user_id',''), birth_place=coalesce(dj->>'birth_place',''),
      secondment_status=coalesce(dj->>'secondment_status',''), serial_no=coalesce(dj->>'serial_no',''),
      national_key=regexp_replace(translate(coalesce(dj->>'national_id',''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[^0-9]', '', 'g') where id=newid;
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
      note=coalesce(patch->>'note',note), school_id=coalesce(patch->>'school_id',school_id),
      dept=coalesce(patch->>'dept',dept), manager_user_id=coalesce(patch->>'manager_user_id',manager_user_id),
      birth_place=coalesce(patch->>'birth_place',birth_place), secondment_status=coalesce(patch->>'secondment_status',secondment_status),
      serial_no=coalesce(patch->>'serial_no',serial_no),
      national_key=case when patch ? 'national_id' then regexp_replace(translate(coalesce(patch->>'national_id',''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[^0-9]', '', 'g') else national_key end
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'linkEmployee' then
    update ebda.employees set dept=coalesce(req#>>'{patch,dept}',dept), manager_user_id=coalesce(req#>>'{patch,manager_user_id}',manager_user_id),
      school_id=coalesce(req#>>'{patch,school_id}',school_id), job=coalesce(req#>>'{patch,job}',job), contract_type=coalesce(req#>>'{patch,contract_type}',contract_type)
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

-- ---------------------------------------------------------------- الصلاحيات: الدالة العامة فقط (كما فى 002) — جداول النسخ الاحتياطى غير متاحة لأى دور عام
revoke all on all tables in schema ebda from anon, authenticated;
revoke all on all sequences in schema ebda from anon, authenticated;
revoke execute on all functions in schema ebda from public, anon, authenticated;
grant usage on schema ebda to anon, authenticated;
grant execute on function ebda.api(jsonb) to anon, authenticated;
grant execute on function public.api(jsonb) to anon, authenticated;

insert into ebda.config(key,value) values ('schema_version','5') on conflict (key) do update set value='5';
