-- شغّل هذا الملف مرة واحدة على قاعدة Supabase الحالية لتفعيل الأدوار والتقارير.
alter table public.staff_profiles add column if not exists role text not null default 'employee' check (role in ('admin','employee'));
alter table public.customers add column if not exists username text not null default '';

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
