-- تشغيل مرة واحدة على مشروع Supabase الحالي لإضافة البرج السابق للمشترك.
alter table public.customers
  add column if not exists tower_name text not null default '';
