-- ============================================================
--  ابدأ إديو — إعداد قاعدة بيانات Supabase (Postgres)
--  الصق هذا الملف كاملاً في: Supabase ‹ SQL Editor ‹ New query ‹ Run
--  يُنشئ الجداول + دالة api() الآمنة + بيانات أولية.
--  الواجهة تتصل بدالة واحدة فقط: rpc/api ، فلا تُكشف الجداول للعامة.
-- ============================================================

create schema if not exists ebda;

-- ---------- الجداول ----------
create table if not exists ebda.users(
  id text primary key, username text, pin text, name text, role text,
  schools text, active text default 'نعم', email text default '');
create table if not exists ebda.schools(
  id text primary key, name text, type text, period text,
  students numeric default 0, active text default 'نعم', category text default 'school');
create table if not exists ebda.lines(
  id text primary key, school_id text, section text, name text,
  allocated numeric default 0, note text default '');
create table if not exists ebda.custodies(
  id text primary key, label text, holder text, school_id text,
  note text default '', "user" text default '');
create table if not exists ebda.tranches(
  id text primary key, custody_id text, date text, amount numeric default 0, note text default '');
create table if not exists ebda.expenses(
  id text primary key, date text, school_id text, custody_id text, line_id text,
  spend_item text default '', description text default '', amount numeric default 0,
  approval text default 'pending', approved_by text default '',
  doc_url text default '', doc_name text default '',
  review_status text default '', review_note text default '',
  settled text default '', ref text default '', note text default '',
  created_by text default '', created_at text default '');
create table if not exists ebda.spend_items(id text primary key, name text);
create table if not exists ebda.holders(id text primary key, name text, title text);
create table if not exists ebda.approvers(id text primary key, name text, email text);
create table if not exists ebda.emails(id text primary key, email text, label text);
create table if not exists ebda.config(key text primary key, value text);
insert into ebda.config(key,value) values ('backup_token','CHANGE_ME_TO_A_SECRET')
  on conflict (key) do nothing;

create index if not exists ix_lines_school on ebda.lines(school_id);
create index if not exists ix_cust_school on ebda.custodies(school_id);
create index if not exists ix_tr_cust on ebda.tranches(custody_id);
create index if not exists ix_exp_cust on ebda.expenses(custody_id);
create index if not exists ix_exp_school on ebda.expenses(school_id);

-- ---------- مولّد معرفات ----------
create or replace function ebda.uid() returns text language sql as
$$ select 'id' || substr(md5(clock_timestamp()::text || random()::text), 1, 14) $$;

-- ---------- أدوات مساعدة ----------
create or replace function ebda.can_school(u ebda.users, sid text) returns boolean language sql as $$
  select u.role='manager' or u.schools='*' or sid = any(string_to_array(coalesce(u.schools,''), ','))
      or sid = any(array(select trim(x) from unnest(string_to_array(coalesce(u.schools,''), ',')) x));
$$;
create or replace function ebda.sees_budgets(u ebda.users) returns boolean language sql as
$$ select u.role in ('manager','accountant','supervisor') $$;
create or replace function ebda.role_emails(r text) returns text[] language sql as
$$ select array(select email from ebda.users where role=r and coalesce(active,'') like '%نعم%' and coalesce(email,'') like '%@%') $$;

-- ============================================================
--  الدالة الرئيسية api(req jsonb) — تنفّذ كل الإجراءات مع التحقق
-- ============================================================
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
  cust ebda.custodies;
  ex ebda.expenses;
  sid text;
  newid text;
  patch jsonb;
  recs text[];
  ln jsonb;
  res jsonb;
begin
  -- نسخ احتياطى كامل (برمز سرّى) — يستخدمه Apps Script للنسخ إلى جوجل شيت
  if action = 'dumpAll' then
    if coalesce(req->>'token','') <> coalesce((select value from ebda.config where key='backup_token'),'') then
      return jsonb_build_object('error','رمز النسخ الاحتياطى غير صحيح'); end if;
    return jsonb_build_object('ok',true,
      'users',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.users x),
      'schools',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.schools x),
      'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.lines x),
      'custodies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.custodies x),
      'tranches',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.tranches x),
      'expenses',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.expenses x),
      'spend_items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.spend_items x),
      'holders',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.holders x),
      'approvers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.approvers x),
      'emails',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from ebda.emails x));
  end if;
  -- تسجيل الدخول
  if action = 'login' then
    select * into u from ebda.users
      where username = (req->>'username') and pin = (req->>'pin') and coalesce(active,'') like '%نعم%' limit 1;
    if not found then return jsonb_build_object('error','بيانات الدخول غير صحيحة'); end if;
    return jsonb_build_object('ok',true,'user',jsonb_build_object('id',u.id,'username',u.username,'name',u.name,'role',u.role,'schools',u.schools));
  end if;

  -- التحقق لبقية الإجراءات
  select * into u from ebda.users where username=a_user and pin=a_pin limit 1;
  if not found then return jsonb_build_object('error','انتهت الجلسة — سجّل الدخول من جديد'); end if;

  if action = 'ping' then
    return jsonb_build_object('ok',true,'connected',true,'db','supabase',
      'users',(select count(*) from ebda.users),'schools',(select count(*) from ebda.schools));
  end if;

  if action = 'bootstrap' then
    res := jsonb_build_object('ok',true,'me',
      jsonb_build_object('id',u.id,'username',u.username,'name',u.name,'role',u.role,'schools',u.schools));
    -- الجهات المرئية
    res := res || jsonb_build_object('schools', coalesce((select jsonb_agg(to_jsonb(s)) from ebda.schools s
        where coalesce(s.active,'') like '%نعم%' and ebda.can_school(u, s.id)),'[]'::jsonb));
    -- العهد
    if u.role='custody' then
      res := res || jsonb_build_object('custodies', coalesce((select jsonb_agg(to_jsonb(c)) from ebda.custodies c
          where coalesce(c."user",'')=u.username),'[]'::jsonb));
    else
      res := res || jsonb_build_object('custodies', coalesce((select jsonb_agg(to_jsonb(c)) from ebda.custodies c
          where c.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id)) or coalesce(c.school_id,'')=''),'[]'::jsonb));
    end if;
    -- البنود (الموازنات) — للأدوار التى ترى الموازنة كاملة، وللمسئول أسماء فقط
    if ebda.sees_budgets(u) then
      res := res || jsonb_build_object('lines', coalesce((select jsonb_agg(to_jsonb(l)) from ebda.lines l
          where l.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id))),'[]'::jsonb));
    elsif u.role='custody' then
      res := res || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'school_id',l.school_id,'section',l.section,'name',l.name)) from ebda.lines l
          where l.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id))),'[]'::jsonb));
    else
      res := res || jsonb_build_object('lines','[]'::jsonb);
    end if;
    -- الدفعات والمصروفات (حسب العهد المرئية)
    res := res || jsonb_build_object('tranches', coalesce((select jsonb_agg(to_jsonb(t)) from ebda.tranches t
        where t.custody_id in (select c.id from ebda.custodies c where
          (u.role='custody' and coalesce(c."user",'')=u.username) or
          (u.role<>'custody' and (c.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id)) or coalesce(c.school_id,'')='')))),'[]'::jsonb));
    if u.role='custody' then
      res := res || jsonb_build_object('expenses', coalesce((select jsonb_agg(to_jsonb(e)) from ebda.expenses e
          where e.custody_id in (select c.id from ebda.custodies c where coalesce(c."user",'')=u.username)),'[]'::jsonb));
    else
      res := res || jsonb_build_object('expenses', coalesce((select jsonb_agg(to_jsonb(e)) from ebda.expenses e
          where e.custody_id in (select c.id from ebda.custodies c where c.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id)))
             or e.school_id in (select s.id from ebda.schools s where ebda.can_school(u,s.id))),'[]'::jsonb));
    end if;
    res := res
      || jsonb_build_object('spendItems', coalesce((select jsonb_agg(to_jsonb(x)) from ebda.spend_items x),'[]'::jsonb))
      || jsonb_build_object('holders', coalesce((select jsonb_agg(to_jsonb(x)) from ebda.holders x),'[]'::jsonb))
      || jsonb_build_object('approvers', coalesce((select jsonb_agg(to_jsonb(x)) from ebda.approvers x),'[]'::jsonb))
      || jsonb_build_object('emails', coalesce((select jsonb_agg(to_jsonb(x)) from ebda.emails x),'[]'::jsonb));
    if u.role='manager' then
      res := res || jsonb_build_object('users', coalesce((select jsonb_agg(to_jsonb(x)) from ebda.users x),'[]'::jsonb));
    end if;
    return res;
  end if;

  -- تسجيل صرف من العهدة
  if action = 'addExpense' then
    select * into cust from ebda.custodies where id = (req#>>'{expense,custody_id}');
    if not found then return jsonb_build_object('error','العهدة غير موجودة'); end if;
    if u.role<>'manager' and coalesce(cust."user",'')<>u.username then return jsonb_build_object('error','لا صلاحية على هذه العهدة'); end if;
    newid := ebda.uid();
    insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,
       approval,approved_by,doc_url,doc_name,review_status,review_note,settled,ref,note,created_by,created_at)
    values(newid, req#>>'{expense,date}', req#>>'{expense,school_id}', req#>>'{expense,custody_id}',
       req#>>'{expense,line_id}', coalesce(req#>>'{expense,spend_item}',''), coalesce(req#>>'{expense,description}',''),
       coalesce((req#>>'{expense,amount}')::numeric,0),'pending','', '','','','','','','', u.name, now()::text);
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid));
  end if;

  -- شراء مركزى (محاسب/مدير) — يُخصم من الموازنة مباشرة
  if action = 'addCentral' then
    if u.role not in ('manager','accountant') then return jsonb_build_object('error','صلاحية المحاسب مطلوبة'); end if;
    newid := ebda.uid();
    insert into ebda.expenses(id,date,school_id,custody_id,line_id,spend_item,description,amount,
       approval,approved_by,doc_url,doc_name,review_status,review_note,settled,ref,note,created_by,created_at)
    values(newid, req#>>'{expense,date}', req#>>'{expense,school_id}', '', req#>>'{expense,line_id}', '',
       coalesce(req#>>'{expense,description}',''), coalesce((req#>>'{expense,amount}')::numeric,0),
       'approved', u.name, coalesce(req->>'dataUrl',''), coalesce(req->>'filename',''),
       'مستوفى','', 'نعم','','', u.name, now()::text);
    return jsonb_build_object('ok',true,'item',(select to_jsonb(e) from ebda.expenses e where e.id=newid));
  end if;

  -- اعتماد/تعديل مصروف
  if action = 'updateExpense' then
    select * into ex from ebda.expenses where id = (req->>'id');
    patch := req->'patch';
    if patch ? 'approval' then
      if u.role not in ('manager','supervisor') then return jsonb_build_object('error','صلاحية الاعتماد مطلوبة'); end if;
    elsif u.role='manager' then
      null;
    else
      select * into cust from ebda.custodies where id = ex.custody_id;
      if not (coalesce(cust."user",'')=u.username and ex.approval='pending') then
        return jsonb_build_object('error','لا يمكن التعديل بعد اعتماد الصرف'); end if;
    end if;
    update ebda.expenses set
      date = coalesce(patch->>'date', date),
      line_id = coalesce(patch->>'line_id', line_id),
      amount = coalesce((patch->>'amount')::numeric, amount),
      description = coalesce(patch->>'description', description),
      approval = coalesce(patch->>'approval', approval),
      approved_by = coalesce(patch->>'approved_by', approved_by),
      settled = coalesce(patch->>'settled', settled),
      note = coalesce(patch->>'note', note)
    where id = (req->>'id');
    return jsonb_build_object('ok',true,'mail','الإشعارات عبر جوجل شيت/الإيميل غير مفعّلة فى وضع Supabase');
  end if;

  -- مراجعة المستند (محاسب/مدير)
  if action = 'reviewExpense' then
    if u.role not in ('manager','accountant') then return jsonb_build_object('error','صلاحية المراجعة مطلوبة'); end if;
    patch := req->'patch';
    update ebda.expenses set
      review_status = coalesce(patch->>'review_status', review_status),
      review_note = coalesce(patch->>'review_note', review_note),
      settled = coalesce(patch->>'settled', settled)
    where id = (req->>'id');
    return jsonb_build_object('ok',true,'mail','تم — الإشعار بالإيميل عبر النسخة الاحتياطية');
  end if;

  -- رفع مستند (تخزين رابط/داتا)
  if action = 'uploadDoc' then
    select * into ex from ebda.expenses where id=(req->>'id');
    if not found then return jsonb_build_object('error','المصروف غير موجود'); end if;
    select * into cust from ebda.custodies where id=ex.custody_id;
    if not (u.role='manager'
            or (cust.id is not null and coalesce(cust."user",'')=u.username)
            or (coalesce(ex.custody_id,'')='' and u.role in ('manager','accountant')))
    then return jsonb_build_object('error','لا صلاحية لرفع مستند'); end if;
    update ebda.expenses set doc_url=coalesce(req->>'dataUrl',''), doc_name=coalesce(req->>'filename','') where id=(req->>'id');
    return jsonb_build_object('ok',true,'url',coalesce(req->>'dataUrl',''));
  end if;

  if action = 'deleteExpense' then
    select * into ex from ebda.expenses where id=(req->>'id');
    if u.role<>'manager' then
      select * into cust from ebda.custodies where id=ex.custody_id;
      if not (coalesce(cust."user",'')=u.username and ex.approval='pending') then
        return jsonb_build_object('error','لا يمكن الحذف بعد اعتماد الصرف'); end if;
    end if;
    delete from ebda.expenses where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

  if action = 'emailReport' then
    if not ebda.sees_budgets(u) then return jsonb_build_object('error','لا صلاحية'); end if;
    return jsonb_build_object('ok',true,'note','الإرسال بالإيميل يتم عبر النسخة الاحتياطية (Apps Script) أو Edge Function');
  end if;

  -- إجراءات المدير فقط
  if u.role<>'manager' then return jsonb_build_object('error','صلاحية المدير مطلوبة'); end if;

  if action = 'addTranche' then
    newid := ebda.uid();
    insert into ebda.tranches(id,custody_id,date,amount,note)
    values(newid, req#>>'{tranche,custody_id}', req#>>'{tranche,date}', coalesce((req#>>'{tranche,amount}')::numeric,0), coalesce(req#>>'{tranche,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(t) from ebda.tranches t where t.id=newid));
  end if;

  if action = 'addCustody' then
    newid := ebda.uid();
    insert into ebda.custodies(id,label,holder,school_id,note,"user")
    values(newid, req#>>'{custody,label}', req#>>'{custody,holder}', req#>>'{custody,school_id}', coalesce(req#>>'{custody,note}',''), coalesce(req#>>'{custody,user}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(c) from ebda.custodies c where c.id=newid));
  end if;

  if action = 'updateCustody' then
    patch := req->'patch';
    update ebda.custodies set label=coalesce(patch->>'label',label), holder=coalesce(patch->>'holder',holder),
      school_id=coalesce(patch->>'school_id',school_id), note=coalesce(patch->>'note',note), "user"=coalesce(patch->>'user',"user")
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

  if action = 'deleteCustody' then
    delete from ebda.expenses where custody_id=(req->>'id');
    delete from ebda.tranches where custody_id=(req->>'id');
    delete from ebda.custodies where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;

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
  if action = 'deleteSchool' then delete from ebda.schools where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  if action = 'addLine' then
    newid := ebda.uid();
    insert into ebda.lines(id,school_id,section,name,allocated,note)
    values(newid, req#>>'{line,school_id}', coalesce(req#>>'{line,section}',''), req#>>'{line,name}', coalesce((req#>>'{line,allocated}')::numeric,0), coalesce(req#>>'{line,note}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(l) from ebda.lines l where l.id=newid));
  end if;
  if action = 'updateLine' then
    patch := req->'patch';
    update ebda.lines set section=coalesce(patch->>'section',section), name=coalesce(patch->>'name',name),
      allocated=coalesce((patch->>'allocated')::numeric,allocated), note=coalesce(patch->>'note',note)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deleteLine' then delete from ebda.lines where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  if action = 'importBudget' then
    sid := req->>'school_id';
    if req ? 'newSchool' then
      newid := ebda.uid();
      insert into ebda.schools(id,name,type,period,students,active,category)
      values(newid, req#>>'{newSchool,name}', coalesce(req#>>'{newSchool,type}',''), coalesce(req#>>'{newSchool,period}',''),
         0, 'نعم', coalesce(req#>>'{newSchool,category}','school'));
      sid := newid;
    end if;
    delete from ebda.lines where school_id = sid;
    for ln in select * from jsonb_array_elements(coalesce(req->'lines','[]'::jsonb)) loop
      insert into ebda.lines(id,school_id,section,name,allocated,note)
      values(ebda.uid(), sid, coalesce(ln->>'section',''), coalesce(ln->>'name',''), coalesce((ln->>'allocated')::numeric,0), '');
    end loop;
    return jsonb_build_object('ok',true,'school_id',sid,'count',jsonb_array_length(coalesce(req->'lines','[]'::jsonb)));
  end if;

  if action = 'addSpendItem' then newid:=ebda.uid(); insert into ebda.spend_items(id,name) values(newid, req#>>'{item,name}'); return jsonb_build_object('ok',true,'item',(select to_jsonb(x) from ebda.spend_items x where x.id=newid)); end if;
  if action = 'deleteSpendItem' then delete from ebda.spend_items where id=(req->>'id'); return jsonb_build_object('ok',true); end if;
  if action = 'addHolder' then newid:=ebda.uid(); insert into ebda.holders(id,name,title) values(newid, req#>>'{item,name}', coalesce(req#>>'{item,title}','')); return jsonb_build_object('ok',true,'item',(select to_jsonb(x) from ebda.holders x where x.id=newid)); end if;
  if action = 'deleteHolder' then delete from ebda.holders where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  if action = 'addUser' then
    newid := ebda.uid();
    insert into ebda.users(id,username,pin,name,role,schools,active,email)
    values(newid, req#>>'{user,username}', req#>>'{user,pin}', req#>>'{user,name}', coalesce(req#>>'{user,role}','custody'),
       coalesce(req#>>'{user,schools}',''), coalesce(req#>>'{user,active}','نعم'), coalesce(req#>>'{user,email}',''));
    return jsonb_build_object('ok',true,'item',(select to_jsonb(x) from ebda.users x where x.id=newid));
  end if;
  if action = 'updateUser' then
    patch := req->'patch';
    update ebda.users set username=coalesce(patch->>'username',username), pin=coalesce(patch->>'pin',pin),
      name=coalesce(patch->>'name',name), role=coalesce(patch->>'role',role), schools=coalesce(patch->>'schools',schools),
      active=coalesce(patch->>'active',active), email=coalesce(patch->>'email',email)
    where id=(req->>'id');
    return jsonb_build_object('ok',true);
  end if;
  if action = 'deleteUser' then delete from ebda.users where id=(req->>'id'); return jsonb_build_object('ok',true); end if;

  return jsonb_build_object('error','إجراء غير معروف: '||coalesce(action,''));
end;
$fn$;

-- ---------- الصلاحيات: كشف الدالة فقط للعامة، لا الجداول ----------
-- غلاف فى public ليكتشفه PostgREST (الجداول تبقى فى ebda غير مكشوفة)
create or replace function public.api(req jsonb) returns jsonb
  language sql security definer set search_path = ebda, public
  as $wrap$ select ebda.api(req) $wrap$;

revoke all on all tables in schema ebda from anon, authenticated;
grant usage on schema ebda to anon, authenticated;
grant execute on function ebda.api(jsonb) to anon, authenticated;
grant execute on function public.api(jsonb) to anon, authenticated;

-- ---------- بذور أولية ----------
create or replace function ebda.seed() returns text language plpgsql as $seed$
declare badr text; dam text; comp text; trg text; trv text;
begin
  if exists(select 1 from ebda.users) then return 'موجود مسبقاً'; end if;
  insert into ebda.users(id,username,pin,name,role,schools,active,email) values (ebda.uid(),'admin','1234','المدير العام','manager','*','نعم','');
  insert into ebda.spend_items(id,name) select ebda.uid(), x from unnest(array[
    'أدوات مكتبية ونظافة ومستهلكات وبوفيه','مستهلكات للورش التدريبية','انتقالات','صيانة المنشأة والورش','مصاريف نثرية','بوفيه']) x;
  insert into ebda.holders(id,name,title) values (ebda.uid(),'أحمد سمير','مدير مدرسة'),(ebda.uid(),'منى فؤاد','منسق');
  insert into ebda.approvers(id,name,email) values (ebda.uid(),'المدير المالى','finance@ebda.com.eg'),(ebda.uid(),'رئيس العمليات','ops@ebda.com.eg');
  insert into ebda.emails(id,email,label) values (ebda.uid(),'ebda.edu@ebda.com.eg','الإدارة');
  badr:=ebda.uid(); dam:=ebda.uid(); comp:=ebda.uid(); trg:=ebda.uid(); trv:=ebda.uid();
  insert into ebda.schools(id,name,type,period,students,active,category) values
   (badr,'مدرسة ابدأ للعلوم التقنية — بدر','مدرسة','2026/2027',253,'نعم','school'),
   (dam,'مدرسة ابدأ للعلوم التقنية — دمياط','مدرسة','2026/2027',255,'نعم','school'),
   (comp,'الشركة — العهدة الداخلية','الشركة','2026/2027',0,'نعم','company'),
   (trg,'التدريب العام','تدريب','2026/2027',0,'نعم','training_general'),
   (trv,'التدريب المهنى','تدريب','2026/2027',0,'نعم','training_vocational');
  return 'تم';
end; $seed$;
select ebda.seed();
