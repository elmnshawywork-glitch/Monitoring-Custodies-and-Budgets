-- ============================================================================
--  ابدأ إديو — Migration 001: الصلاحيات + نطاق البيانات + دورة الاعتماد المالى + الأمان
--  يُشغَّل مرة واحدة على قاعدة البيانات الحالية بعد supabase_setup.sql
--  (Supabase ‹ SQL Editor ‹ New query ‹ الصق ‹ Run). آمن لإعادة التشغيل (idempotent).
--
--  لا يحذف أى جدول أو بيانات. يضيف أعمدة وأكواد ويعيد تعريف الدالة api()
--  مع الحفاظ على كل الإجراءات الحالية وأسمائها وشكل الاستجابة.
--
--  Mapping الأدوار (القيم المخزنة القديمة تبقى كما هى للتوافق):
--    manager    = Administrator      / الأدمن           (role_key: admin)
--    accountant = Financial Manager  / المدير المالى    (role_key: finance_manager)
--    supervisor = Direct Manager     / المدير المباشر   (role_key: direct_manager)
--    custody    = Custody Officer    / مسئول العهدة     (role_key: custody_officer)
--  ويمكن أيضاً تخزين الأسماء الجديدة مباشرة (admin, finance_manager, ...) — تُفهم بنفس المعنى.
-- ============================================================================

-- ============================================================
--  (0) مواءمة الجداول الأساسية — لقواعد البيانات المنشأة بنسخة أقدم من supabase_setup.sql
--  يُنشئ أى جدول ناقص (مثل audit_log / requests / employees ...) ويضيف أى عمود ناقص. لا يحذف ولا يغيّر بيانات.
-- ============================================================
create schema if not exists ebda;
create table if not exists ebda.users(id text primary key);
alter table ebda.users add column if not exists username text;
alter table ebda.users add column if not exists pin text;
alter table ebda.users add column if not exists name text;
alter table ebda.users add column if not exists role text;
alter table ebda.users add column if not exists schools text;
alter table ebda.users add column if not exists active text default 'نعم';
alter table ebda.users add column if not exists email text default '';
create table if not exists ebda.schools(id text primary key);
alter table ebda.schools add column if not exists name text;
alter table ebda.schools add column if not exists type text;
alter table ebda.schools add column if not exists period text;
alter table ebda.schools add column if not exists students numeric default 0;
alter table ebda.schools add column if not exists active text default 'نعم';
alter table ebda.schools add column if not exists category text default 'school';
create table if not exists ebda.lines(id text primary key);
alter table ebda.lines add column if not exists school_id text;
alter table ebda.lines add column if not exists section text;
alter table ebda.lines add column if not exists name text;
alter table ebda.lines add column if not exists allocated numeric default 0;
alter table ebda.lines add column if not exists note text default '';
create table if not exists ebda.custodies(id text primary key);
alter table ebda.custodies add column if not exists label text;
alter table ebda.custodies add column if not exists holder text;
alter table ebda.custodies add column if not exists school_id text;
alter table ebda.custodies add column if not exists note text default '';
alter table ebda.custodies add column if not exists "user" text default '';
create table if not exists ebda.tranches(id text primary key);
alter table ebda.tranches add column if not exists custody_id text;
alter table ebda.tranches add column if not exists date text;
alter table ebda.tranches add column if not exists amount numeric default 0;
alter table ebda.tranches add column if not exists note text default '';
create table if not exists ebda.expenses(id text primary key);
alter table ebda.expenses add column if not exists date text;
alter table ebda.expenses add column if not exists school_id text;
alter table ebda.expenses add column if not exists custody_id text;
alter table ebda.expenses add column if not exists line_id text;
alter table ebda.expenses add column if not exists spend_item text default '';
alter table ebda.expenses add column if not exists description text default '';
alter table ebda.expenses add column if not exists amount numeric default 0;
alter table ebda.expenses add column if not exists approval text default 'pending';
alter table ebda.expenses add column if not exists approved_by text default '';
alter table ebda.expenses add column if not exists doc_url text default '';
alter table ebda.expenses add column if not exists doc_name text default '';
alter table ebda.expenses add column if not exists review_status text default '';
alter table ebda.expenses add column if not exists review_note text default '';
alter table ebda.expenses add column if not exists settled text default '';
alter table ebda.expenses add column if not exists ref text default '';
alter table ebda.expenses add column if not exists note text default '';
alter table ebda.expenses add column if not exists created_by text default '';
alter table ebda.expenses add column if not exists created_at text default '';
create table if not exists ebda.spend_items(id text primary key);
alter table ebda.spend_items add column if not exists name text;
create table if not exists ebda.holders(id text primary key);
alter table ebda.holders add column if not exists name text;
alter table ebda.holders add column if not exists title text;
create table if not exists ebda.approvers(id text primary key);
alter table ebda.approvers add column if not exists name text;
alter table ebda.approvers add column if not exists email text;
create table if not exists ebda.emails(id text primary key);
alter table ebda.emails add column if not exists email text;
alter table ebda.emails add column if not exists label text;
create table if not exists ebda.config(key text primary key);
alter table ebda.config add column if not exists value text;
create table if not exists ebda.salaries(id text primary key);
alter table ebda.salaries add column if not exists school_id text;
alter table ebda.salaries add column if not exists name text;
alter table ebda.salaries add column if not exists job text;
alter table ebda.salaries add column if not exists monthly numeric default 0;
alter table ebda.salaries add column if not exists months numeric default 12;
alter table ebda.salaries add column if not exists note text default '';
create table if not exists ebda.temp_budgets(id text primary key);
alter table ebda.temp_budgets add column if not exists school_id text;
alter table ebda.temp_budgets add column if not exists name text;
alter table ebda.temp_budgets add column if not exists dfrom text;
alter table ebda.temp_budgets add column if not exists dto text;
alter table ebda.temp_budgets add column if not exists amount numeric default 0;
alter table ebda.temp_budgets add column if not exists note text default '';
create table if not exists ebda.requests(id text primary key);
alter table ebda.requests add column if not exists school_id text;
alter table ebda.requests add column if not exists requester text;
alter table ebda.requests add column if not exists requester_name text;
alter table ebda.requests add column if not exists status text default 'pending_supervisor';
alter table ebda.requests add column if not exists note text default '';
alter table ebda.requests add column if not exists total numeric default 0;
alter table ebda.requests add column if not exists created_at text default '';
alter table ebda.requests add column if not exists custody_id text default '';
alter table ebda.requests add column if not exists decided_by text default '';
alter table ebda.requests add column if not exists acc_by text default '';
create table if not exists ebda.request_items(id text primary key);
alter table ebda.request_items add column if not exists request_id text;
alter table ebda.request_items add column if not exists line_id text;
alter table ebda.request_items add column if not exists name text;
alter table ebda.request_items add column if not exists amount numeric default 0;
alter table ebda.request_items add column if not exists sup_note text default '';
alter table ebda.request_items add column if not exists decision text default 'approved';
create table if not exists ebda.audit_log(id text primary key);
alter table ebda.audit_log add column if not exists ts text;
alter table ebda.audit_log add column if not exists actor text;
alter table ebda.audit_log add column if not exists actor_role text;
alter table ebda.audit_log add column if not exists action text;
alter table ebda.audit_log add column if not exists entity text;
alter table ebda.audit_log add column if not exists details text;
create table if not exists ebda.employees(id text primary key);
alter table ebda.employees add column if not exists school_id text;
alter table ebda.employees add column if not exists category text default 'contract';
alter table ebda.employees add column if not exists emp_no text default '';
alter table ebda.employees add column if not exists name text;
alter table ebda.employees add column if not exists job text default '';
alter table ebda.employees add column if not exists job_type text default '';
alter table ebda.employees add column if not exists qualification text default '';
alter table ebda.employees add column if not exists grad_year text default '';
alter table ebda.employees add column if not exists national_id text default '';
alter table ebda.employees add column if not exists birth_date text default '';
alter table ebda.employees add column if not exists phone text default '';
alter table ebda.employees add column if not exists hire_date text default '';
alter table ebda.employees add column if not exists work_start text default '';
alter table ebda.employees add column if not exists insurance_no text default '';
alter table ebda.employees add column if not exists account_no text default '';
alter table ebda.employees add column if not exists bank text default '';
alter table ebda.employees add column if not exists branch text default '';
alter table ebda.employees add column if not exists email text default '';
alter table ebda.employees add column if not exists ebda_start text default '';
alter table ebda.employees add column if not exists base_salary numeric default 0;
alter table ebda.employees add column if not exists contract_type text default '';
alter table ebda.employees add column if not exists gender text default '';
alter table ebda.employees add column if not exists address text default '';
alter table ebda.employees add column if not exists retire_date text default '';
alter table ebda.employees add column if not exists note text default '';
alter table ebda.employees add column if not exists active text default 'نعم';
alter table ebda.employees add column if not exists archived text default 'لا';
alter table ebda.employees add column if not exists archived_at text default '';
alter table ebda.employees add column if not exists archived_by text default '';
create table if not exists ebda.payslips(id text primary key);
alter table ebda.payslips add column if not exists employee_id text;
alter table ebda.payslips add column if not exists emp_name text default '';
alter table ebda.payslips add column if not exists school_id text;
alter table ebda.payslips add column if not exists month text default '';
alter table ebda.payslips add column if not exists base numeric default 0;
alter table ebda.payslips add column if not exists incentive numeric default 0;
alter table ebda.payslips add column if not exists allowances numeric default 0;
alter table ebda.payslips add column if not exists gross numeric default 0;
alter table ebda.payslips add column if not exists ded_medical numeric default 0;
alter table ebda.payslips add column if not exists ded_social numeric default 0;
alter table ebda.payslips add column if not exists ded_tax numeric default 0;
alter table ebda.payslips add column if not exists ded_other numeric default 0;
alter table ebda.payslips add column if not exists ded_total numeric default 0;
alter table ebda.payslips add column if not exists net numeric default 0;
alter table ebda.payslips add column if not exists note text default '';
alter table ebda.payslips add column if not exists created_by text default '';
alter table ebda.payslips add column if not exists created_at text default '';
alter table ebda.users add column if not exists must_reset text default 'لا';
alter table ebda.expenses add column if not exists doc_type text default '';
create index if not exists ix_emp_school on ebda.employees(school_id);
create index if not exists ix_pay_emp on ebda.payslips(employee_id);
create index if not exists ix_pay_school on ebda.payslips(school_id);
alter table ebda.expenses add column if not exists doc_is_link text default 'لا';
create index if not exists ix_audit_ts on ebda.audit_log(ts);
create index if not exists ix_ri_req on ebda.request_items(request_id);
create index if not exists ix_req_school on ebda.requests(school_id);
create index if not exists ix_sal_school on ebda.salaries(school_id);
create index if not exists ix_tb_school on ebda.temp_budgets(school_id);
create index if not exists ix_lines_school on ebda.lines(school_id);
create index if not exists ix_cust_school on ebda.custodies(school_id);
create index if not exists ix_tr_cust on ebda.tranches(custody_id);
create index if not exists ix_exp_cust on ebda.expenses(custody_id);
create index if not exists ix_exp_school on ebda.expenses(school_id);
insert into ebda.config(key,value) values ('backup_token','CHANGE_ME_TO_A_SECRET') on conflict (key) do nothing;
create or replace function ebda.uid() returns text language sql as
$$ select 'id' || substr(md5(clock_timestamp()::text || random()::text), 1, 14) $$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- أعمدة جديدة
alter table ebda.users     add column if not exists perms      text default '';   -- صلاحيات إضافية مثل manage_users
alter table ebda.users     add column if not exists last_login text default '';

alter table ebda.expenses  add column if not exists txn_no      text default '';  -- رقم العملية EXP-00001
alter table ebda.expenses  add column if not exists approved_at text default '';
alter table ebda.expenses  add column if not exists fin_approval text default ''; -- '' | approved | rejected
alter table ebda.expenses  add column if not exists fin_by      text default '';
alter table ebda.expenses  add column if not exists fin_at      text default '';
alter table ebda.expenses  add column if not exists fin_note    text default '';
alter table ebda.expenses  add column if not exists settled_at  text default '';
alter table ebda.expenses  add column if not exists updated_by  text default '';
alter table ebda.expenses  add column if not exists updated_at  text default '';

alter table ebda.custodies add column if not exists code        text default '';  -- CUST-001
alter table ebda.custodies add column if not exists status      text default 'open'; -- open | pending_settlement | settled | closed
alter table ebda.custodies add column if not exists opened_at   text default '';
alter table ebda.custodies add column if not exists settled_at  text default '';
alter table ebda.custodies add column if not exists settled_by  text default '';
alter table ebda.custodies add column if not exists closed_at   text default '';

alter table ebda.requests  add column if not exists req_no      text default '';  -- REQ-0001
alter table ebda.requests  add column if not exists reason      text default '';
alter table ebda.requests  add column if not exists decided_at  text default '';
alter table ebda.requests  add column if not exists fin_at      text default '';

alter table ebda.lines     add column if not exists monthly_plan text default ''; -- اختيارى: JSON بـ 12 قيمة (سبتمبر..أغسطس)

create sequence if not exists ebda.seq_exp;
create sequence if not exists ebda.seq_cust;
create sequence if not exists ebda.seq_req;

create index if not exists ix_exp_line on ebda.expenses(line_id);
create index if not exists ix_cust_user on ebda.custodies("user");

-- ---------------------------------------------------------------- ترحيل البيانات (مرة واحدة لكل صف)
do $mig$
declare r record;
begin
  -- أكواد العهد
  for r in select id from ebda.custodies where coalesce(code,'')='' order by id loop
    update ebda.custodies set code='CUST-'||lpad(nextval('ebda.seq_cust')::text,3,'0') where id=r.id;
  end loop;
  update ebda.custodies set status='open' where coalesce(status,'')='';
  -- أرقام العمليات
  for r in select id from ebda.expenses where coalesce(txn_no,'')='' order by coalesce(created_at,''), id loop
    update ebda.expenses set txn_no='EXP-'||lpad(nextval('ebda.seq_exp')::text,5,'0') where id=r.id;
  end loop;
  for r in select id from ebda.requests where coalesce(req_no,'')='' order by coalesce(created_at,''), id loop
    update ebda.requests set req_no='REQ-'||lpad(nextval('ebda.seq_req')::text,4,'0') where id=r.id;
  end loop;
  -- الاعتماد المالى للبيانات القديمة: المُسوّى والشراء المركزى كانا يُخصمان من الموازنة ⇒ معتمد مالياً
  update ebda.expenses set fin_approval='approved', fin_by='ترحيل تلقائى', fin_at=coalesce(nullif(created_at,''),now()::text)
   where coalesce(fin_approval,'')='' and approval='approved'
     and (coalesce(settled,'') like '%نعم%' or coalesce(custody_id,'')='');
  -- كلمات المرور: تحويل النص الصريح إلى bcrypt (لا يمكن استرجاعها بعد ذلك)
  update ebda.users set pin = extensions.crypt(pin, extensions.gen_salt('bf',8))
   where coalesce(pin,'')<>'' and pin not like '$2%';
end $mig$;

-- ---------------------------------------------------------------- دوال مساعدة
create or replace function ebda.role_key(r text) returns text language sql immutable as $$
  select case lower(trim(coalesce(r,'')))
    when 'manager' then 'admin' when 'admin' then 'admin' when 'administrator' then 'admin'
    when 'accountant' then 'finance_manager' when 'finance_manager' then 'finance_manager' when 'finance' then 'finance_manager'
    when 'supervisor' then 'direct_manager' when 'direct_manager' then 'direct_manager'
    when 'custody' then 'custody_officer' when 'custody_officer' then 'custody_officer'
    else '' end $$;

create or replace function ebda.role_legacy(r text) returns text language sql immutable as $$
  select case ebda.role_key(r) when 'admin' then 'manager' when 'finance_manager' then 'accountant'
    when 'direct_manager' then 'supervisor' when 'custody_officer' then 'custody' else null end $$;

create or replace function ebda.role_label(r text) returns text language sql immutable as $$
  select case ebda.role_key(r) when 'admin' then 'الأدمن' when 'finance_manager' then 'المدير المالى'
    when 'direct_manager' then 'المدير المباشر' when 'custody_officer' then 'مسئول العهدة' else coalesce(r,'') end $$;

create or replace function ebda.rk(u ebda.users) returns text language sql stable as $$ select ebda.role_key(u.role) $$;
create or replace function ebda.is_admin(u ebda.users) returns boolean language sql stable as $$ select ebda.role_key(u.role)='admin' $$;
create or replace function ebda.is_fin(u ebda.users) returns boolean language sql stable as $$ select ebda.role_key(u.role) in ('admin','finance_manager') $$;
create or replace function ebda.can_manage_users(u ebda.users) returns boolean language sql stable as $$
  select ebda.role_key(u.role)='admin' or (ebda.role_key(u.role)='finance_manager' and coalesce(u.perms,'') like '%manage_users%') $$;

create or replace function ebda.pin_ok(stored text, given text) returns boolean language sql stable as $$
  select case when coalesce(stored,'') like '$2%' then extensions.crypt(coalesce(given,''), stored) = stored
              else coalesce(given,'')<>'' and coalesce(stored,'') = coalesce(given,'') end $$;
create or replace function ebda.pin_hash(p text) returns text language sql volatile as $$
  select extensions.crypt(p, extensions.gen_salt('bf',8)) $$;

-- نطاق الجهات (الأدمن كل شىء، وغيره حسب حقل schools أو '*')
create or replace function ebda.can_school(u ebda.users, sid text) returns boolean language sql stable as $$
  select ebda.role_key(u.role)='admin' or coalesce(u.schools,'')='*'
      or coalesce(sid,'') = any(array(select trim(x) from unnest(string_to_array(coalesce(u.schools,''), ',')) x where trim(x)<>''));
$$;
create or replace function ebda.sees_budgets(u ebda.users) returns boolean language sql stable as $$
  select ebda.role_key(u.role) in ('admin','finance_manager') $$;

-- هل يستطيع المستخدم الوصول لهذه العهدة؟
create or replace function ebda.can_custody(u ebda.users, c ebda.custodies) returns boolean language sql stable as $$
  select case
    when c.id is null then false
    when ebda.role_key(u.role)='admin' then true
    when ebda.role_key(u.role)='custody_officer' then coalesce(c."user",'')=u.username
    when coalesce(c.school_id,'')='' then ebda.role_key(u.role)='finance_manager'
    else ebda.can_school(u, c.school_id) end $$;

create or replace function ebda.can_expense(u ebda.users, e ebda.expenses) returns boolean language plpgsql stable as $$
declare c ebda.custodies;
begin
  if e.id is null then return false; end if;
  if ebda.role_key(u.role)='admin' then return true; end if;
  if coalesce(e.custody_id,'')<>'' then
    select * into c from ebda.custodies where id=e.custody_id;
    if found then return ebda.can_custody(u, c); end if;
  end if;
  return ebda.role_key(u.role)<>'custody_officer' and ebda.can_school(u, e.school_id);
end $$;

-- هل المصروف محتسب على الموازنة؟ (معتمد من المدير المباشر + معتمد مالياً، أو مُسوّى قديم)
create or replace function ebda.counts_in_budget(e ebda.expenses) returns boolean language sql immutable as $$
  select coalesce(e.approval,'')='approved' and (coalesce(e.fin_approval,'')='approved' or coalesce(e.settled,'') like '%نعم%')
     and coalesce(e.fin_approval,'')<>'rejected' $$;

-- رقم الشهر فى السنة المالية (سبتمبر=1 ... أغسطس=12) — السنة المالية من حقل period للجهة مثل 2026/2027
create or replace function ebda.fy_month(d text) returns int language sql immutable as $$
  select case when coalesce(d,'') ~ '^\d{4}-\d{2}' then ((substr(d,6,2)::int + 3) % 12) + 1 else null end $$;

create or replace function ebda.user_public(x ebda.users) returns jsonb language sql stable as $$
  select (to_jsonb(x) - 'pin') || jsonb_build_object('role_key', ebda.role_key(x.role), 'role_label', ebda.role_label(x.role)) $$;

create or replace function ebda.audit(u ebda.users, act text, ent text, det jsonb) returns void language sql volatile as $$
  insert into ebda.audit_log(id,ts,actor,actor_role,action,entity,details)
  values(ebda.uid(), now()::text, coalesce(u.name, u.username, 'غير معروف'),
         coalesce(ebda.role_label(u.role),''), act, coalesce(ent,''), left(coalesce(det::text,''), 3000)) $$;

create or replace function ebda.err(msg text) returns jsonb language sql immutable as $$ select jsonb_build_object('error', msg) $$;

-- ============================================================================
--  الدالة الرئيسية api(req jsonb)
-- ============================================================================
create or replace function ebda.api(req jsonb)
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
  select * into u from ebda.users where username=a_user and coalesce(active,'') like '%نعم%' order by id limit 1;
  if not found or not ebda.pin_ok(u.pin, a_pin) then return ebda.err('انتهت الجلسة — سجّل الدخول من جديد'); end if;
  urole := ebda.rk(u);
  if urole = '' then return ebda.err('دور المستخدم غير معروف — راجع الأدمن'); end if;

  -- سجل التدقيق لكل إجراء تعديلى
  if action not in ('bootstrap','ping') then
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
    return jsonb_build_object('ok',true);
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
      res := res || jsonb_build_object('audit', coalesce((select jsonb_agg(to_jsonb(a)) from (select * from ebda.audit_log order by ts desc limit 500) a),'[]'::jsonb));
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
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid));
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
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid));
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
    return jsonb_build_object('ok',true,'mail','');
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
    insert into ebda.custodies(id,label,holder,school_id,note,"user",code,status,opened_at)
    values(newid, req#>>'{custody,label}', req#>>'{custody,holder}', req#>>'{custody,school_id}', coalesce(req#>>'{custody,note}',''),
           coalesce(req#>>'{custody,user}',''), 'CUST-'||lpad(nextval('ebda.seq_cust')::text,3,'0'), 'open', now()::text);
    return jsonb_build_object('ok',true,'item',(select to_jsonb(c) from ebda.custodies c where c.id=newid));
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
      return jsonb_build_object('ok',true);
    end if;
    if action = 'deleteUser' then
      if xu.id = u.id then return ebda.err('لا يمكنك حذف حسابك'); end if;
      if ebda.role_key(xu.role)='admin' and (select count(*) from ebda.users z where ebda.role_key(z.role)='admin' and coalesce(z.active,'') like '%نعم%')<=1 then
        return ebda.err('لا يمكن حذف آخر أدمن'); end if;
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

-- ============================================================================
--  تصدير منظّم لمزامنة Google Sheets (يُستدعى من Apps Script بالرمز السرّى)
--  المصدر الرئيسى للبيانات = قاعدة البيانات. الشيتات = نسخة متابعة وتقارير.
-- ============================================================================
create or replace function ebda.sync_export() returns jsonb language plpgsql stable security definer set search_path = ebda as $sx$
declare res jsonb;
begin
  res := jsonb_build_object('ok', true, 'generated_at', now()::text, 'schema_version', 1);

  -- الموازنات: صف لكل (جهة × بند) مع المصروف لكل شهر من السنة المالية
  res := res || jsonb_build_object('budget', coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', l.id, 'entity_id', s.id, 'entity', s.name, 'entity_type', coalesce(s.category,'school'), 'fiscal_year', coalesce(s.period,''),
      'section', coalesce(l.section,''), 'line', l.name, 'annual', coalesce(l.allocated,0),
      'monthly', round(coalesce(l.allocated,0)/12.0, 2),
      'months', (select jsonb_agg(coalesce((select sum(e.amount) from ebda.expenses e
                    where e.line_id=l.id and ebda.counts_in_budget(e) and ebda.fy_month(e.date)=m),0) order by m)
                 from generate_series(1,12) m),
      'spent', coalesce((select sum(e.amount) from ebda.expenses e where e.line_id=l.id and ebda.counts_in_budget(e)),0),
      'pending', coalesce((select sum(e.amount) from ebda.expenses e where e.line_id=l.id and e.approval<>'rejected'
                    and coalesce(e.fin_approval,'')<>'rejected' and not ebda.counts_in_budget(e)),0)
    ) order by s.name, l.section, l.name)
    from ebda.lines l join ebda.schools s on s.id=l.school_id), '[]'::jsonb));

  -- العهد
  res := res || jsonb_build_object('custodies', coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', c.id, 'code', c.code, 'entity', coalesce(s.name,''), 'entity_type', coalesce(s.category,''), 'holder', coalesce(c.holder,''),
      'user', coalesce(c."user",''), 'label', coalesce(c.label,''), 'opened_at', coalesce(nullif(c.opened_at,''), (select min(t.date) from ebda.tranches t where t.custody_id=c.id), ''),
      'received', coalesce((select sum(t.amount) from ebda.tranches t where t.custody_id=c.id),0),
      'spent', coalesce((select sum(e.amount) from ebda.expenses e where e.custody_id=c.id and e.approval<>'rejected' and coalesce(e.fin_approval,'')<>'rejected'),0),
      'settled_amount', coalesce((select sum(e.amount) from ebda.expenses e where e.custody_id=c.id and coalesce(e.settled,'') like '%نعم%'),0),
      'exp_count', (select count(*) from ebda.expenses e where e.custody_id=c.id),
      'pending_count', (select count(*) from ebda.expenses e where e.custody_id=c.id and e.approval='pending'),
      'unsettled_count', (select count(*) from ebda.expenses e where e.custody_id=c.id and e.approval='approved' and coalesce(e.fin_approval,'')<>'rejected' and not (coalesce(e.settled,'') like '%نعم%')),
      'status', coalesce(c.status,'open'), 'settled_at', coalesce(c.settled_at,''), 'closed_at', coalesce(c.closed_at,'')
    ) order by c.code)
    from ebda.custodies c left join ebda.schools s on s.id=c.school_id), '[]'::jsonb));

  -- المصروفات
  res := res || jsonb_build_object('expenses', coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', e.id, 'txn_no', coalesce(e.txn_no,''), 'date', coalesce(e.date,''), 'entity', coalesce(s.name,''),
      'custody_code', coalesce(c.code, 'شراء مركزى'), 'holder', coalesce(c.holder,''), 'line', coalesce(l.name,''), 'section', coalesce(l.section,''),
      'spend_item', coalesce(e.spend_item,''), 'description', coalesce(e.description,''), 'amount', coalesce(e.amount,0),
      'approval', coalesce(e.approval,''), 'approved_by', coalesce(e.approved_by,''), 'approved_at', coalesce(e.approved_at,''),
      'fin_approval', coalesce(e.fin_approval,''), 'fin_by', coalesce(e.fin_by,''), 'fin_at', coalesce(e.fin_at,''),
      'settled', case when coalesce(e.settled,'') like '%نعم%' then 'نعم' else 'لا' end, 'settled_at', coalesce(e.settled_at,''),
      'review_status', coalesce(e.review_status,''), 'review_note', coalesce(e.review_note,''),
      'doc_name', coalesce(e.doc_name,''), 'doc_type', coalesce(e.doc_type,''),
      'doc_link', case when coalesce(e.doc_is_link,'') like '%نعم%' then coalesce(e.doc_url,'') else '' end,
      'has_doc', case when coalesce(e.doc_url,'')<>'' then 'نعم' else 'لا' end,
      'in_budget', case when ebda.counts_in_budget(e) then 'نعم' else 'لا' end,
      'created_by', coalesce(e.created_by,''), 'created_at', coalesce(e.created_at,''), 'updated_by', coalesce(e.updated_by,''), 'updated_at', coalesce(e.updated_at,''),
      'note', coalesce(e.note,'')
    ) order by e.txn_no)
    from ebda.expenses e left join ebda.custodies c on c.id=e.custody_id left join ebda.schools s on s.id=e.school_id left join ebda.lines l on l.id=e.line_id), '[]'::jsonb));

  -- طلبات العهد
  res := res || jsonb_build_object('requests', coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', r.id, 'req_no', coalesce(r.req_no,''), 'entity', coalesce(s.name,''), 'requester', coalesce(r.requester_name,''),
      'created_at', coalesce(r.created_at,''), 'total', coalesce(r.total,0), 'status', r.status, 'reason', coalesce(r.reason,''), 'note', coalesce(r.note,''),
      'decided_by', coalesce(r.decided_by,''), 'fin_by', coalesce(r.acc_by,''), 'custody_code', coalesce(c.code,''),
      'items', coalesce((select string_agg(coalesce(l.name, it.name)||': '||it.amount::text, ' | ') from ebda.request_items it left join ebda.lines l on l.id=it.line_id where it.request_id=r.id),'')
    ) order by r.req_no)
    from ebda.requests r left join ebda.schools s on s.id=r.school_id left join ebda.custodies c on c.id=r.custody_id), '[]'::jsonb));
  return res;
end $sx$;

-- ---------------------------------------------------------------- الصلاحيات (كما هى: الدالة فقط مكشوفة)
create or replace function public.api(req jsonb) returns jsonb
  language sql security definer set search_path = ebda, public
  as $wrap$ select ebda.api(req) $wrap$;
revoke all on all tables in schema ebda from anon, authenticated;
revoke all on all sequences in schema ebda from anon, authenticated;
revoke execute on all functions in schema ebda from public, anon, authenticated;
grant usage on schema ebda to anon, authenticated;
grant execute on function ebda.api(jsonb) to anon, authenticated;
grant execute on function public.api(jsonb) to anon, authenticated;

insert into ebda.config(key,value) values ('schema_version','1') on conflict (key) do update set value='1';
