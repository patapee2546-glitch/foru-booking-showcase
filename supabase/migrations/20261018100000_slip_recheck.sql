-- Re-check slips the bank or SlipOK could not answer yet (1009 / 1010 / network), 2026-10-18.
alter table public.demo_bookings
  add column if not exists slip_check_attempts integer not null default 0,
  add column if not exists slip_checked_at timestamptz;

-- same as 20261018090000, plus it counts attempts and stamps the time of each check
create or replace function public.demo_record_slip_check(
  p_booking_id uuid, p_status text, p_code text, p_message text, p_trans_ref text, p_owner_line_user_id text
) returns text language plpgsql security invoker set search_path = '' as $$
declare
  v_status text := p_status;
  v_code text := p_code;
  v_message text := p_message;
  v_ref text := nullif(btrim(coalesce(p_trans_ref, '')), '');
begin
  if p_status not in ('verified','rejected','unverified') then raise exception 'INVALID_SLIP_STATUS'; end if;
  if v_ref is not null and exists(select 1 from public.demo_bookings where slip_trans_ref = v_ref and id <> p_booking_id) then
    v_status := 'rejected'; v_code := 'DUP_REF'; v_message := 'สลิปนี้ถูกใช้กับคิวอื่นแล้ว (สลิปซ้ำ)'; v_ref := null;
  end if;
  update public.demo_bookings
     set slip_check_code = v_code,
         slip_check_message = left(v_message, 200),
         slip_trans_ref = coalesce(v_ref, slip_trans_ref),
         slip_check_attempts = slip_check_attempts + 1,
         slip_checked_at = statement_timestamp(),
         payment_status = case when v_status = 'unverified' then payment_status else v_status end,
         payment_checked_at = case when v_status = 'unverified' then payment_checked_at else statement_timestamp() end
   where id = p_booking_id and status = 'approved' and payment_status = 'unverified';
  if not found then return 'skipped'; end if;
  if v_status = 'rejected' and p_owner_line_user_id ~ '^U[0-9a-f]{32}$' then
    insert into public.demo_line_notifications(booking_id, recipient_line_user_id, notification_type, scheduled_for)
      values (p_booking_id, p_owner_line_user_id, 'owner_slip_failed', statement_timestamp())
      on conflict do nothing;
  end if;
  return v_status;
end $$;
revoke all on function public.demo_record_slip_check(uuid,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.demo_record_slip_check(uuid,text,text,text,text,text) to service_role;

-- slips waiting for a re-check: still unverified, last answer was a bank delay / outage / network, 10 min apart, max 3 tries
create or replace function public.demo_slip_rechecks_due(p_limit integer)
returns table(id uuid, slip_path text) language sql security invoker set search_path = '' as $$
  select b.id, b.slip_path from public.demo_bookings b
  where b.status = 'approved' and b.payment_status = 'unverified' and b.slip_path is not null
    and b.slip_check_code in ('1009', '1010', 'NETWORK') and b.slip_check_attempts < 3
    and b.slip_checked_at < statement_timestamp() - interval '10 minutes'
  order by b.slip_checked_at limit greatest(1, least(p_limit, 10));
$$;
revoke all on function public.demo_slip_rechecks_due(integer) from public, anon, authenticated;
grant execute on function public.demo_slip_rechecks_due(integer) to service_role;
