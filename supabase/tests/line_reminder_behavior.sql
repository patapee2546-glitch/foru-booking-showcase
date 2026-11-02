-- Run inside a transaction with the LINE migration, then ROLLBACK.
-- No external messages are sent and no fixtures are committed.
do $$
declare
  customer uuid := gen_random_uuid();
  booking uuid := gen_random_uuid();
  result jsonb;
  jobs integer;
  due timestamptz;
begin
  insert into auth.users(id, aud, role) values (customer, 'authenticated', 'authenticated');
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values ('2099-01-05','10:00','12:30',true,customer);
  perform public.demo_link_line_customer(customer, 'U' || replace(customer::text,'-',''), now());
  perform public.demo_create_pending_booking(customer,booking,'2099-01-05','10:00','Test','0811111111','none',null);
  result := public.demo_claim_booking_and_enqueue(booking,customer,'test-only/slip.png');
  if result->>'won' <> 'true' then raise exception 'Booking was not approved'; end if;
  select count(*) into jobs from public.demo_line_notifications where booking_id=booking;
  if jobs <> 2 then raise exception 'Expected confirmation and reminder, got % notifications', jobs; end if;
  select scheduled_for into due from public.demo_line_notifications
    where booking_id=booking and notification_type='booking_confirmed';
  if due is null or due > statement_timestamp() then raise exception 'Confirmation must be immediately due'; end if;
  select scheduled_for into due from public.demo_line_notifications
    where booking_id=booking and notification_type='appointment_reminder';
  if due is distinct from timestamptz '2099-01-05 02:00:00+00' then raise exception 'Reminder must be one hour before Bangkok appointment'; end if;
  perform public.demo_claim_booking_and_enqueue(booking,customer,'test-only/slip.png');
  select count(*) into jobs from public.demo_line_notifications where booking_id=booking;
  if jobs <> 2 then raise exception 'Repeated approval duplicated notification'; end if;
  update public.demo_bookings set status='cancelled' where id=booking;
  if exists(select 1 from public.demo_line_notifications where booking_id=booking and notification_type='appointment_reminder' and status<>'cancelled') then
    raise exception 'Cancellation left a sendable reminder';
  end if;
  if not has_table_privilege('service_role','public.demo_line_notifications','UPDATE') then
    raise exception 'Worker lacks notification update permission';
  end if;
  if has_function_privilege('authenticated','public.demo_claim_due_line_notifications(integer)','EXECUTE') then
    raise exception 'Customer can access internal worker RPC';
  end if;
end;
$$;
