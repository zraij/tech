-- يخلي المشتركين اللي عندهم رقم 077/078 يطلعون قبل السجلات اللي بدون رقم.
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
  if v_uid is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;

  update public.customers
    set assigned_to = null, claimed_at = null
    where assigned_to is not null
      and claimed_at < now() - interval '30 minutes'
      and status in ('pending','follow_up');

  -- حرر الحجوزات القديمة بلا رقم حتى ما تتقدم على أصحاب الأرقام.
  update public.customers
    set assigned_to = null, claimed_at = null
    where assigned_to = v_uid
      and status in ('pending','follow_up')
      and coalesce(phone, '') !~ '(^|[^0-9])07[78][0-9]{8}([^0-9]|$)';

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
    order by case when coalesce(c.phone, '') ~ '(^|[^0-9])07[78][0-9]{8}([^0-9]|$)' then 0 else 1 end,
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

-- التخطي يحرر المشترك ويأجله ساعتين، بدون إنشاء سجل اتصال وهمي.
create or replace function public.skip_current_customer(p_customer_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  update public.customers
     set assigned_to = null,
         claimed_at = null,
         callback_at = now() + interval '2 hours'
   where id = p_customer_id
     and assigned_to = v_uid
     and status in ('pending','follow_up');
  if not found then raise exception 'المشترك غير محجوز لحسابك أو لم يعد بانتظار الاتصال'; end if;
end;
$$;

revoke all on function public.skip_current_customer(bigint) from public, anon;
grant execute on function public.skip_current_customer(bigint) to authenticated;
