begin;
do $$
declare v_owner uuid; v_day date := date '2099-12-31'; v_booking uuid;
begin
  select id into v_owner from auth.users where raw_app_meta_data->>'role'='owner' limit 1;
  if v_owner is null then raise exception 'TEST_OWNER_MISSING'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'app_metadata',jsonb_build_object('role','owner'))::text,true);
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values(v_day,time '10:00',time '12:30',true,v_owner);
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values(v_day,time '13:30',time '16:00',false,v_owner);
  insert into public.demo_bookings(customer_id,slot_date,start_time,customer_name,customer_phone,removal_service)
    values(v_owner,v_day,time '10:00','holiday test','0812345678','none') returning id into v_booking;
  begin
    perform public.demo_set_holiday(v_day,true);
    raise exception 'TEST_DID_NOT_BLOCK_BOOKED_DAY';
  exception when others then
    if sqlerrm <> 'DAY_HAS_BOOKINGS' then raise; end if;
  end;
  update public.demo_bookings set status='cancelled' where id=v_booking;
  perform public.demo_set_holiday(v_day,true);
  if not exists(select 1 from public.demo_holidays where day=v_day)
    or exists(select 1 from public.demo_slots where slot_date=v_day and is_open) then
    raise exception 'TEST_DID_NOT_CLOSE_DAY';
  end if;
  begin
    update public.demo_slots set is_open=true where slot_date=v_day;
    raise exception 'TEST_DID_NOT_BLOCK_SLOT_REOPEN';
  exception when others then
    if sqlerrm <> 'HOLIDAY_CLOSED' then raise; end if;
  end;
  perform public.demo_set_holiday(v_day,false);
  if exists(select 1 from public.demo_holidays where day=v_day)
    or not exists(select 1 from public.demo_slots where slot_date=v_day and start_time=time '10:00' and is_open)
    or exists(select 1 from public.demo_slots where slot_date=v_day and start_time=time '13:30' and is_open) then
    raise exception 'TEST_DID_NOT_RESTORE_DAY';
  end if;
end $$;
rollback;
