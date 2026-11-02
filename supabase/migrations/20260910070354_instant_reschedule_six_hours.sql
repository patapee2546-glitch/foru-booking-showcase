-- Keep the original booking/payment/promotion; only move its appointment atomically.
create or replace function public.create_demo_reschedule(p_booking_id uuid,p_customer_id uuid,p_new_slot_date date,p_new_start_time time)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare b public.demo_bookings%rowtype; old_s public.demo_slots%rowtype;
  new_s public.demo_slots%rowtype; r public.demo_reschedule_requests%rowtype;
begin
  perform public.expire_demo_reschedules();
  select * into b from public.demo_bookings where id=p_booking_id and customer_id=p_customer_id for update;
  if not found or b.status<>'approved' then raise exception 'BOOKING_NOT_ELIGIBLE'; end if;
  if now() > ((b.slot_date+b.start_time) at time zone 'Asia/Bangkok')-interval '6 hours' then
    raise exception 'RESCHEDULE_DEADLINE_PASSED';
  end if;
  select * into old_s from public.demo_slots where slot_date=b.slot_date and start_time=b.start_time for update;
  select * into new_s from public.demo_slots where slot_date=p_new_slot_date and start_time=p_new_start_time for update;
  if not found or not new_s.is_open or ((p_new_slot_date+p_new_start_time) at time zone 'Asia/Bangkok')<=now()
    or exists(select 1 from public.demo_bookings where slot_date=p_new_slot_date and start_time=p_new_start_time
      and (status='approved' or (status='pending' and expires_at>now()))) then
    raise exception 'NEW_SLOT_UNAVAILABLE';
  end if;
  insert into public.demo_reschedule_requests(booking_id,customer_id,old_slot_date,old_start_time,old_end_time,new_slot_date,new_start_time,new_end_time)
  values(b.id,p_customer_id,b.slot_date,b.start_time,old_s.end_time,p_new_slot_date,p_new_start_time,new_s.end_time) returning * into r;
  update public.demo_slots set is_open=false,updated_at=now() where id=new_s.id;
  return to_jsonb(r);
end; $$;

create or replace function public.submit_demo_reschedule_slip(p_request_id uuid,p_customer_id uuid,p_slip_path text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare r public.demo_reschedule_requests%rowtype; b public.demo_bookings%rowtype; booking_id uuid;
begin
  select q.booking_id into booking_id from public.demo_reschedule_requests q where id=p_request_id and customer_id=p_customer_id;
  if not found then raise exception 'REQUEST_EXPIRED'; end if;
  select * into b from public.demo_bookings where id=booking_id and customer_id=p_customer_id for update;
  select * into r from public.demo_reschedule_requests where id=p_request_id and customer_id=p_customer_id for update;
  -- A retry after a successful response was lost must not move the booking twice.
  if r.status='approved' then return jsonb_build_object('request',to_jsonb(r),'booking',to_jsonb(b)); end if;
  if r.status<>'awaiting_slip' or r.expires_at<=now() then raise exception 'REQUEST_EXPIRED'; end if;
  if b.id is null or b.status<>'approved' or b.slot_date<>r.old_slot_date or b.start_time<>r.old_start_time then raise exception 'BOOKING_CHANGED'; end if;
  if now()>((b.slot_date+b.start_time) at time zone 'Asia/Bangkok')-interval '6 hours' then raise exception 'RESCHEDULE_DEADLINE_PASSED'; end if;
  if p_slip_path is null or p_slip_path not like p_customer_id::text||'/'||p_request_id::text||'/%' then raise exception 'RESCHEDULE_SLIP_REQUIRED'; end if;
  perform 1 from public.demo_slots where slot_date=r.new_slot_date and start_time=r.new_start_time for update;
  if not found or ((r.new_slot_date+r.new_start_time) at time zone 'Asia/Bangkok')<=now()
    or exists(select 1 from public.demo_bookings where slot_date=r.new_slot_date and start_time=r.new_start_time and id<>b.id
      and (status='approved' or (status='pending' and expires_at>now()))) then raise exception 'NEW_SLOT_UNAVAILABLE'; end if;
  update public.demo_bookings set slot_date=r.new_slot_date,start_time=r.new_start_time where id=b.id returning * into b;
  update public.demo_slots set is_open=true,updated_at=now() where slot_date=r.old_slot_date and start_time=r.old_start_time;
  update public.demo_slots set is_open=false,updated_at=now() where slot_date=r.new_slot_date and start_time=r.new_start_time;
  update public.demo_reschedule_requests set status='approved',slip_path=p_slip_path,slip_uploaded_at=now(),reviewed_at=now(),reviewed_by=null,updated_at=now()
    where id=r.id returning * into r;
  insert into public.demo_booking_reschedule_history(request_id,booking_id,customer_id,old_slot_date,old_start_time,old_end_time,new_slot_date,new_start_time,new_end_time,fee_amount,fee_slip_path,approved_by)
  values(r.id,r.booking_id,r.customer_id,r.old_slot_date,r.old_start_time,r.old_end_time,r.new_slot_date,r.new_start_time,r.new_end_time,r.fee_amount,r.slip_path,null);
  return jsonb_build_object('request',to_jsonb(r),'booking',to_jsonb(b));
end; $$;
revoke all on function public.create_demo_reschedule(uuid,uuid,date,time) from public,anon,authenticated;
revoke all on function public.submit_demo_reschedule_slip(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.create_demo_reschedule(uuid,uuid,date,time) to service_role;
grant execute on function public.submit_demo_reschedule_slip(uuid,uuid,text) to service_role;
