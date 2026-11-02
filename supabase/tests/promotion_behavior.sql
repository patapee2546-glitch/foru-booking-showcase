-- Caller wraps this in BEGIN/ROLLBACK. No real messages or committed bookings.
do $$
declare
  actor uuid:=gen_random_uuid(); users uuid[]:=array[]::uuid[];
  slot uuid; campaign uuid; attempt jsonb; again jsonb; booking uuid:=gen_random_uuid();
  friend_booking uuid:=gen_random_uuid(); code text; r jsonb; i integer;
begin
  for i in 1..7 loop
    users:=array_append(users,gen_random_uuid());
    insert into auth.users(id,aud,role) values(users[i],'authenticated','authenticated');
    perform public.demo_link_line_customer(users[i],'U'||replace(users[i]::text,'-',''),now());
  end loop;
  actor:=users[7];
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values('2099-01-05','10:00','12:30',true,actor) returning id into slot;
  r:=public.demo_promo_action(actor,true,'campaign-create',jsonb_build_object('title','Rollback test','slots',jsonb_build_array(slot)));
  campaign:=(r->>'id')::uuid;
  for i in 1..5 loop
    r:=public.demo_promo_action(users[i],false,'reserve',jsonb_build_object('campaignId',campaign));
    if (r->>'percent')::int not in (5,10,15) then raise exception 'Invalid outcome'; end if;
    if i=1 then attempt:=r; end if;
  end loop;
  begin
    perform public.demo_promo_action(users[6],false,'reserve',jsonb_build_object('campaignId',campaign));
    raise exception 'SIXTH_WAS_ALLOWED';
  exception when others then if sqlerrm not like '%PROMO_FULL%' then raise; end if; end;
  again:=public.demo_promo_action(users[1],false,'reserve',jsonb_build_object('campaignId',campaign));
  if again->>'id'<>attempt->>'id' or again->>'percent'<>attempt->>'percent' then raise exception 'Rerolled'; end if;
  update public.demo_promo_attempts set expires_at=now()-interval '1 second' where campaign_id=campaign and line_user_id='U'||replace(users[5]::text,'-','');
  perform public.demo_promo_action(users[6],false,'reserve',jsonb_build_object('campaignId',campaign));
  r:=public.demo_promo_action(users[5],false,'reserve',jsonb_build_object('campaignId',campaign));
  if (r->>'expires_at')::timestamptz>now() then raise exception 'Expired user got retry'; end if;
  perform public.demo_create_booking_with_promo(users[1],booking,'2099-01-05','10:00','Promo test','0811111111','none',null,jsonb_build_object('type','wheel','id',attempt->>'id'));
  if (select expires_at from public.demo_bookings where id=booking)>(attempt->>'expires_at')::timestamptz then raise exception 'Deadline extended'; end if;
  perform public.demo_claim_booking_with_owner_notification(booking,users[1],'test/slip.png','');
  select c.code into code from public.demo_referral_codes c where source_booking_id=booking;
  if code is null then raise exception 'No automatic code'; end if;
  perform public.demo_claim_booking_with_owner_notification(booking,users[1],'test/slip.png','');
  if (select count(*) from public.demo_referral_codes where source_booking_id=booking)<>1 then raise exception 'Duplicate code'; end if;
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values('2099-01-05','13:30','16:00',true,actor);
  begin
    perform public.demo_create_booking_with_promo(users[1],gen_random_uuid(),'2099-01-05','13:30','Self','0811111111','none',null,jsonb_build_object('type','referral','code',code));
    raise exception 'SELF_ALLOWED';
  exception when others then if sqlerrm not like '%PROMO_SELF%' then raise; end if; end;
  perform public.demo_create_booking_with_promo(users[7],friend_booking,'2099-01-05','13:30','Friend','0811111111','none',null,jsonb_build_object('type','referral','code',code));
  perform public.demo_claim_booking_with_owner_notification(friend_booking,users[7],'test/slip.png','');
  if exists(select 1 from public.demo_credit_ledger where source_booking_id=friend_booking) then raise exception 'Credit before completion'; end if;
  r:=public.demo_promo_action(actor,true,'settle',jsonb_build_object('bookingId',friend_booking,'subtotal',60000));
  if (r->>'amountDue')::int<>40000 or (r->>'discount')::int<>5000 then raise exception 'Incorrect final bill %',r; end if;
  perform public.demo_promo_action(actor,true,'settle',jsonb_build_object('bookingId',friend_booking,'subtotal',60000));
  if (select count(*) from public.demo_credit_ledger where source_booking_id=friend_booking and amount=5000)<>1 then raise exception 'Credit missing/duplicated'; end if;
  begin
    perform public.demo_promo_action(users[1],false,'settle',jsonb_build_object('bookingId',booking,'subtotal',60000));
    raise exception 'CUSTOMER_SETTLED';
  exception when others then if sqlerrm not like '%OWNER_REQUIRED%' then raise; end if; end;
  if has_function_privilege('authenticated','public.demo_promo_action(uuid,boolean,text,jsonb)','EXECUTE') then raise exception 'Unsafe RPC'; end if;
  r:=public.demo_promo_action(users[1],false,'status','{}');
  if jsonb_array_length(r->'codes')<>1 or jsonb_array_length(r->'credits')<>1 then raise exception 'Customer cannot see rewards'; end if;
  if r::text like '%line_user_id%' then raise exception 'Identity exposed'; end if;
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
    values('2099-01-05','17:00','19:30',true,actor);
  again:=r->'credits'->0;
  actor:=gen_random_uuid();
  perform public.demo_create_booking_with_promo(users[1],actor,'2099-01-05','17:00','Credit test','0811111111','none',null,jsonb_build_object('type','credit','id',again->>'id'));
  update public.demo_bookings set created_at=now()-interval '6 minutes',expires_at=now()-interval '1 second' where id=actor;
  r:=public.demo_promo_action(users[1],false,'status','{}');
  if r->'credits'->0->>'status'<>'available' then raise exception 'EXPIRED_HOLD_STRANDS_CREDIT'; end if;
end $$;
