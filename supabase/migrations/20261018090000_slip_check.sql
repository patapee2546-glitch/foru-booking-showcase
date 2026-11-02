-- Automatic slip check (SlipOK) result on each booking, 2026-10-18.
-- A failed slip keeps the booking: it is marked 'rejected' and the owner gets a LINE alert.

alter table public.demo_bookings
  add column if not exists slip_check_code text,
  add column if not exists slip_check_message text,
  add column if not exists slip_trans_ref text;
-- one bank transfer can pay for one booking only
create unique index if not exists demo_bookings_slip_trans_ref_key on public.demo_bookings(slip_trans_ref) where slip_trans_ref is not null;

alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in (
    'booking_confirmed','appointment_reminder','owner_booking_confirmed','owner_booking_cancelled',
    'appointment_reminder_day','booking_cancelled_by_shop','owner_booking_rescheduled','review_request','rebook_nudge',
    'waitlist_open','owner_appointment_reminder','owner_slip_failed'));

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
  -- the same transfer already paid for another booking
  if v_ref is not null and exists(select 1 from public.demo_bookings where slip_trans_ref = v_ref and id <> p_booking_id) then
    v_status := 'rejected'; v_code := 'DUP_REF'; v_message := 'สลิปนี้ถูกใช้กับคิวอื่นแล้ว (สลิปซ้ำ)'; v_ref := null;
  end if;
  -- never overrides what the owner already decided by hand
  update public.demo_bookings
     set slip_check_code = v_code,
         slip_check_message = left(v_message, 200),
         slip_trans_ref = coalesce(v_ref, slip_trans_ref),
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
