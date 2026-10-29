-- شغّل هذا مرة واحدة على قاعدة Supabase الحالية لإضافة حقل اليوزر.
alter table public.customers add column if not exists username text not null default '';
