-- قاعدة متابعة الوايرليس لشركة تكنولوجي للإنترنت
-- نفّذ هذا الملف في Supabase SQL Editor قبل ربط واجهة الموقع.
-- لا تضع service_role key في index.html أو app.js.

create table if not exists public.staff_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'employee' check (role in ('admin','employee')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  id integer primary key check (id = 1),
  company_name text not null default 'شركة تكنولوجي للإنترنت',
  offer_amount integer not null default 15000 check (offer_amount >= 0),
  call_center_phone text not null default '',
  working_hours text not null default '9 الصبح إلى 12 بالليل',
  call_template text not null default E'السلام عليكم {اسم_المشترك}، وياك {اسم_الموظف} من {اسم_الشركة}. أتصل بخصوص اشتراك الوايرليس السابق. حبّينا نعرف شنو السبب اللي خلاك توقف؟\n\nعدنا كول سنتر وصيانة يومياً من {ساعات_العمل}. مناطق التغطية تشمل شمال العلم وجنوب العلم وشرق العلم، وأتأكد من عنوانك بالتحديد قبل ما أأكد توفر الخدمة.\n\nعرض الرجعة: أول شهر بـ{سعر_العرض} دينار. التجديد يكون بسعر باقتك الحالية. باقتك المسجلة: {الباقة}، وسعر التجديد حسب البرنامج: {سعر_التجديد}.\n\nتحب نتحقق من التغطية ونكمل طلب الرجعة؟\n\nللتواصل: {رقم_الكول_سنتر}.',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id bigint generated always as identity primary key,
  import_key text not null unique,
  subscriber_ref text,
  name text not null default '',
  phone text not null default '',
  username text not null default '',
  tower_name text not null default '',
  area text not null default '',
  address text not null default '',
  plan_name text not null default '',
  renewal_price text not null default '',
  churn_reason text not null default '',
  ticket_id text not null default '',
  status text not null default 'pending' check (status in ('pending','no_answer','follow_up','ticket_open','returned','not_interested','do_not_contact','invalid_data')),
  priority smallint not null default 3 check (priority between 1 and 4),
  notes text not null default '',
  callback_at timestamptz,
  assigned_to uuid references auth.users(id),
  claimed_at timestamptz,
  contacted_by uuid references auth.users(id),
  last_contact_at timestamptz,
  imported_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- يضيف الحقل للمشاريع التي شُغّل عليها إصدار سابق من قاعدة البيانات.
alter table public.customers add column if not exists tower_name text not null default '';
alter table public.customers add column if not exists username text not null default '';

create table if not exists public.call_attempts (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  employee_id uuid not null references auth.users(id),
  outcome text not null check (outcome in ('no_answer','follow_up','ticket_open','returned','not_interested','do_not_contact','invalid_data')),
  notes text not null default '',
  ticket_id text not null default '',
  call_script text not null default '',
  callback_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists customers_queue_idx on public.customers (status, priority, created_at);
create index if not exists customers_assigned_idx on public.customers (assigned_to, claimed_at);
create index if not exists customers_callback_idx on public.customers (callback_at) where callback_at is not null;
create index if not exists call_attempts_customer_idx on public.call_attempts (customer_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists staff_profiles_set_updated_at on public.staff_profiles;
create trigger staff_profiles_set_updated_at before update on public.staff_profiles for each row execute function public.set_updated_at();
drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at before update on public.app_settings for each row execute function public.set_updated_at();
drop trigger if exists customers_set_updated_at on public.customers;
create trigger customers_set_updated_at before update on public.customers for each row execute function public.set_updated_at();

alter table public.staff_profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.customers enable row level security;
alter table public.call_attempts enable row level security;

revoke all on public.staff_profiles, public.app_settings, public.customers, public.call_attempts from anon;
grant select, insert, update on public.staff_profiles, public.app_settings to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert on public.call_attempts to authenticated;
grant usage, select on sequence public.customers_id_seq, public.call_attempts_id_seq to authenticated;

-- دور المشرف يُقرأ بصلاحيات محددة، ولا يستطيع الموظف رفع نفسه إلى مشرف.
alter table public.staff_profiles add column if not exists role text not null default 'employee' check (role in ('admin','employee'));
create or replace function public.current_staff_role()
returns text language sql stable security definer set search_path=public
as $$ select role from public.staff_profiles where id=auth.uid() $$;
revoke all on function public.current_staff_role() from public, anon;
grant execute on function public.current_staff_role() to authenticated;
drop policy if exists "staff reads own profile" on public.staff_profiles;
drop policy if exists "staff profiles readable by self or admin" on public.staff_profiles;
create policy "staff profiles readable by self or admin" on public.staff_profiles for select to authenticated using (id = (select auth.uid()) or (select public.current_staff_role()) = 'admin');
drop policy if exists "staff inserts own profile" on public.staff_profiles;
create policy "staff inserts own profile" on public.staff_profiles for insert to authenticated with check (id = (select auth.uid()) and role = 'employee');
drop policy if exists "staff updates own profile" on public.staff_profiles;
create policy "staff updates own profile" on public.staff_profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()) and role = (select public.current_staff_role()));

-- الحساب الحالي للمشرف الرئيسي.
insert into public.staff_profiles (id,display_name,role)
select id,coalesce(email,''),'admin' from auth.users where lower(email)='tinormen@gmail.com'
on conflict(id) do update set role='admin';

create or replace function public.replace_customer_list(p_rows jsonb)
returns integer language plpgsql security definer set search_path=public
as $$
declare v_uid uuid:=auth.uid(); v_count integer;
begin
  if v_uid is null or public.current_staff_role()<>'admin' then raise exception 'استبدال القائمة للمشرف فقط'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>10000 then raise exception 'صيغة القائمة غير صحيحة أو حجمها أكبر من المسموح'; end if;
  delete from public.customers;
  insert into public.customers(import_key,name,phone,username,status,priority,imported_by)
  select distinct on (r.import_key) r.import_key,coalesce(r.name,''),coalesce(r.phone,''),coalesce(r.username,''),'pending',greatest(1,least(4,coalesce(r.priority,4))),v_uid
  from jsonb_to_recordset(p_rows) as r(import_key text,name text,phone text,username text,priority smallint)
  order by r.import_key;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.replace_customer_list(jsonb) from public, anon;
grant execute on function public.replace_customer_list(jsonb) to authenticated;

-- الموظفون المسجّلون دخولاً يتشاركون إعدادات الحملة وقائمة العملاء.
drop policy if exists "signed in staff reads settings" on public.app_settings;
create policy "signed in staff reads settings" on public.app_settings for select to authenticated using ((select auth.uid()) is not null);
drop policy if exists "signed in staff creates settings" on public.app_settings;
create policy "signed in staff creates settings" on public.app_settings for insert to authenticated with check (id = 1 and (select auth.uid()) is not null);
drop policy if exists "signed in staff updates settings" on public.app_settings;
create policy "signed in staff updates settings" on public.app_settings for update to authenticated using (id = 1 and (select auth.uid()) is not null) with check (id = 1 and (select auth.uid()) is not null);

drop policy if exists "signed in staff reads customers" on public.customers;
create policy "signed in staff reads customers" on public.customers for select to authenticated using ((select auth.uid()) is not null);
drop policy if exists "signed in staff adds customers" on public.customers;
create policy "signed in staff adds customers" on public.customers for insert to authenticated with check ((select auth.uid()) is not null and imported_by = (select auth.uid()));
drop policy if exists "signed in staff updates customers" on public.customers;
create policy "signed in staff updates customers" on public.customers for update to authenticated using ((select auth.uid()) is not null) with check ((select auth.uid()) is not null);

drop policy if exists "signed in staff reads call attempts" on public.call_attempts;
create policy "signed in staff reads call attempts" on public.call_attempts for select to authenticated using ((select auth.uid()) is not null);
drop policy if exists "staff records own call attempts" on public.call_attempts;
create policy "staff records own call attempts" on public.call_attempts for insert to authenticated with check (employee_id = (select auth.uid()));

insert into public.app_settings (id, company_name, offer_amount, working_hours)
values (1, 'شركة تكنولوجي للإنترنت', 15000, '9 الصبح إلى 12 بالليل')
on conflict (id) do nothing;

-- يحجز مشتركاً واحداً لموظف واحد، ويرجّع نفس المشترك إذا عاد الموظف قبل انتهاء مهلة الحجز.
create or replace function public.claim_next_customer()
returns setof public.customers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
begin
  if v_uid is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  -- تحرير الحجوزات المهجورة بعد نصف ساعة حتى لا تبقى عالقة.
  update public.customers
    set assigned_to = null, claimed_at = null
    where assigned_to is not null
      and claimed_at < now() - interval '30 minutes'
      and status in ('pending','follow_up');

  select c.id into v_id
    from public.customers c
    where c.assigned_to = v_uid
      and c.status in ('pending','follow_up')
      and (c.callback_at is null or c.callback_at <= now())
    order by c.claimed_at asc nulls last
    limit 1;
  if v_id is not null then
    return query select c.* from public.customers c where c.id = v_id;
    return;
  end if;

  select c.id into v_id
    from public.customers c
    where c.assigned_to is null
      and c.status in ('pending','follow_up')
      and (c.callback_at is null or c.callback_at <= now())
    order by case when coalesce(c.phone, '') ~ '07[78][0-9]{8,10}' then 0 else 1 end,
             c.priority asc, c.created_at asc, c.id asc
    limit 1
    for update skip locked;

  if v_id is null then return; end if;
  update public.customers c set assigned_to = v_uid, claimed_at = now() where c.id = v_id;
  return query select c.* from public.customers c where c.id = v_id;
end;
$$;

revoke all on function public.claim_next_customer() from public, anon;
grant execute on function public.claim_next_customer() to authenticated;


-- يحفظ نتيجة الاتصال وسجل المكالمة ويحرر الحجز بعملية واحدة.
create or replace function public.save_call_and_release(
  p_customer_id bigint,
  p_outcome text,
  p_notes text,
  p_ticket_id text,
  p_call_script text,
  p_callback_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_customer_id bigint;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if p_outcome not in ('no_answer','follow_up','ticket_open','returned','not_interested','do_not_contact','invalid_data') then
    raise exception 'نتيجة الاتصال غير معتمدة';
  end if;
  if p_outcome = 'follow_up' and p_callback_at is null then
    raise exception 'حدد موعد المتابعة قبل الحفظ';
  end if;
  select c.id into v_customer_id
    from public.customers c
    where c.id = p_customer_id and c.assigned_to = v_uid
    for update;
  if not found then raise exception 'هذا المشترك غير محجوز لحسابك. حدّث القائمة وخذ المشترك التالي'; end if;

  insert into public.call_attempts (customer_id, employee_id, outcome, notes, ticket_id, call_script, callback_at)
  values (p_customer_id, v_uid, p_outcome, coalesce(p_notes,''), coalesce(p_ticket_id,''), coalesce(p_call_script,''), p_callback_at);

  update public.customers c
    set status = p_outcome,
        notes = case when coalesce(p_notes,'') = '' then c.notes else p_notes end,
        ticket_id = case when coalesce(p_ticket_id,'') = '' then c.ticket_id else p_ticket_id end,
        contacted_by = v_uid,
        last_contact_at = now(),
        callback_at = p_callback_at,
        assigned_to = null,
        claimed_at = null
    where c.id = p_customer_id;
end;
$$;

revoke all on function public.save_call_and_release(bigint,text,text,text,text,timestamptz) from public, anon;
grant execute on function public.save_call_and_release(bigint,text,text,text,text,timestamptz) to authenticated;

