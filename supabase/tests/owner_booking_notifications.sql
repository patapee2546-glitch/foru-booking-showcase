do $$
declare
  customer uuid := gen_random_uuid();
  booking uuid := gen_random_uuid();
  owner_id text := 'U11111111111111111111111111111111';
  result jsonb;
begin
  insert into auth.users(id,aud,role) values(customer,'authenticated','authenticated');
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values('2099-01-05','10:00','12:30',true,customer);
  perform public.demo_link_line_customer(customer,'U'||replace(customer::text,'-',''),now());
  perform public.demo_create_pending_booking(customer,booking,'2099-01-05','10:00','Test','0811111111','none',null);
  result := public.demo_claim_booking_with_owner_notification(booking,customer,'test/slip.png',owner_id);
  if result->>'won' <> 'true' then raise exception 'Approval failed'; end if;
  if not exists(select 1 from public.demo_line_notifications where booking_id=booking and notification_type='owner_booking_confirmed' and recipient_line_user_id=owner_id and scheduled_for<=statement_timestamp()) then
    raise exception 'Missing immediate owner notification';
  end if;
  perform public.demo_claim_booking_with_owner_notification(booking,customer,'test/slip.png',owner_id);
  if (select count(*) from public.demo_line_notifications where booking_id=booking) <> 3 then raise exception 'Expected three unique jobs'; end if;
  if has_function_privilege('authenticated','public.demo_claim_booking_with_owner_notification(uuid,uuid,text,text)','EXECUTE') then raise exception 'Customer can choose owner recipient'; end if;
end $$;
