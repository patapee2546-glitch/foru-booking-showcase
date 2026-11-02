-- Always wrapped with BEGIN/ROLLBACK, including the migration under test.
do $$
declare u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); held uuid:=gen_random_uuid(); r jsonb; rid uuid;
begin
 insert into auth.users(id,aud,role) values(u,'authenticated','authenticated'),(v,'authenticated','authenticated');
 insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
 values('2097-03-01','10:00','12:30',true,u),('2097-03-02','10:00','12:30',true,u),('2097-03-03','10:00','12:30',true,u);
 insert into public.demo_bookings(id,customer_id,slot_date,start_time,customer_name,customer_phone,status,slip_path)
 values(b,u,'2097-03-01','10:00','Reschedule QA','0811111111','approved','original-deposit.png'),
 (held,v,'2097-03-03','10:00','Hold QA','0822222222','pending',null);
 begin
   perform public.create_demo_reschedule(b,u,'2097-03-03','10:00');
   raise exception 'LIVE_HOLD_STOLEN';
 exception when others then if sqlerrm<>'NEW_SLOT_UNAVAILABLE' then raise; end if; end;
 r:=public.create_demo_reschedule(b,u,'2097-03-02','10:00'); rid:=(r->>'id')::uuid;
 if (select slot_date from public.demo_bookings where id=b)<>'2097-03-01' or
    (select is_open from public.demo_slots where slot_date='2097-03-01' and start_time='10:00') then raise exception 'ORIGINAL_RELEASED_EARLY'; end if;
 begin
   perform public.submit_demo_reschedule_slip(rid,v,v::text||'/'||rid::text||'/fee.png');
   raise exception 'OTHER_CUSTOMER_ALLOWED';
 exception when others then if sqlerrm<>'REQUEST_EXPIRED' then raise; end if; end;
 r:=public.submit_demo_reschedule_slip(rid,u,u::text||'/'||rid::text||'/fee.png');
 if r->'request'->>'status'<>'approved' or r->'booking'->>'slot_date'<>'2097-03-02' or r->'booking'->>'slip_path'<>'original-deposit.png' then raise exception 'MOVE_OR_PAYMENT_CHANGED'; end if;
 perform public.submit_demo_reschedule_slip(rid,u,u::text||'/'||rid::text||'/fee.png');
 if (select count(*) from public.demo_booking_reschedule_history where request_id=rid)<>1 then raise exception 'DUPLICATE_HISTORY'; end if;
 if not (select is_open from public.demo_slots where slot_date='2097-03-01' and start_time='10:00') then raise exception 'ORIGINAL_NOT_RELEASED'; end if;
 if has_function_privilege('authenticated','public.submit_demo_reschedule_slip(uuid,uuid,text)','EXECUTE') then raise exception 'UNSAFE_RPC'; end if;
end $$;
