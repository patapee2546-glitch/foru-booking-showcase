create or replace function public.demo_claim_booking_and_enqueue(
  p_booking_id uuid,
  p_customer_id uuid,
  p_slip_path text
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_booking public.demo_bookings%rowtype;
  v_line_user_id text;
  v_slot public.demo_slots%rowtype;
begin
  select * into v_booking
  from public.demo_bookings
  where id = p_booking_id and customer_id = p_customer_id
  for update;

  if not found then return jsonb_build_object('won', false, 'status', 'lost'); end if;
  if v_booking.status = 'approved' then return jsonb_build_object('won', true, 'status', 'approved'); end if;
  if v_booking.status <> 'pending' then return jsonb_build_object('won', false, 'status', 'lost'); end if;
  if v_booking.expires_at <= statement_timestamp() then
    update public.demo_bookings set status = 'expired' where id = v_booking.id;
    return jsonb_build_object('won', false, 'status', 'expired');
  end if;

  select * into v_slot
  from public.demo_slots
  where slot_date = v_booking.slot_date and start_time = v_booking.start_time
  for update;
  if not found or not v_slot.is_open then
    update public.demo_bookings set status = 'lost' where id = v_booking.id;
    return jsonb_build_object('won', false, 'status', 'lost');
  end if;

  select line_user_id into v_line_user_id
  from public.demo_booking_line_recipients
  where booking_id = v_booking.id;
  if v_line_user_id is null then raise exception 'LINE_RECIPIENT_MISSING'; end if;

  update public.demo_bookings
  set status = 'approved',
      paid_at = statement_timestamp(),
      slip_path = p_slip_path,
      slip_uploaded_at = statement_timestamp()
  where id = v_booking.id;

  update public.demo_slots
  set is_open = false, is_booked = true, updated_at = statement_timestamp()
  where id = v_slot.id;

  insert into public.demo_line_notifications (
    booking_id, recipient_line_user_id, notification_type, scheduled_for
  ) values
    (v_booking.id, v_line_user_id, 'booking_confirmed', statement_timestamp()),
    (v_booking.id, v_line_user_id, 'appointment_reminder',
      ((v_booking.slot_date + v_booking.start_time) at time zone 'Asia/Bangkok') - interval '1 hour')
  on conflict (booking_id, notification_type) do nothing;

  return jsonb_build_object('won', true, 'status', 'approved');
end;
$$;
