do $$
declare
  customer uuid := gen_random_uuid();
  booking uuid := gen_random_uuid();
  owner_id text := 'U11111111111111111111111111111111';
  result uuid;
begin
  insert into auth.users(id,aud,role) values(customer,'authenticated','authenticated');
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values('2099-01-05','10:00','12:30',true,customer);
  perform public.demo_link_line_customer(customer,'U'||replace(customer::text,'-',''),now());
  perform public.demo_create_pending_booking(customer,booking,'2099-01-05','10:00','Test','0811111111','none',null);
  perform public.demo_claim_booking_with_owner_notification(booking,customer,'test/slip.png',owner_id);
  result:=public.demo_cancel_booking_and_notify(booking,customer,'customer','refund_due',owner_id);
  if result is distinct from booking then raise exception 'Cancellation failed'; end if;
  if not exists(select 1 from public.demo_line_notifications where booking_id=booking and notification_type='owner_booking_cancelled' and recipient_line_user_id=owner_id and status='pending' and scheduled_for<=statement_timestamp()) then raise exception 'Missing owner cancellation'; end if;
  if exists(select 1 from public.demo_line_notifications where booking_id=booking and notification_type='appointment_reminder' and status<>'cancelled') then raise exception 'Reminder still active'; end if;
  result:=public.demo_cancel_booking_and_notify(booking,customer,'customer','refund_due',owner_id);
  if result is not null then raise exception 'Repeated cancellation should not change booking'; end if;
  if (select count(*) from public.demo_line_notifications where booking_id=booking and notification_type='owner_booking_cancelled')<>1 then raise exception 'Duplicate cancellation'; end if;
  if has_function_privilege('authenticated','public.demo_cancel_booking_and_notify(uuid,uuid,text,text,text)','EXECUTE') then raise exception 'Unsafe public cancellation RPC'; end if;
end $$;
