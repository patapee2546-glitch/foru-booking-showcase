-- Execute in BEGIN/ROLLBACK. The fourth paid booking must not receive a wheel right.
do $$
declare u uuid; owner_id uuid:=gen_random_uuid(); c uuid; b uuid; s uuid; slots uuid[]:='{}'; r jsonb; i int;
begin
 insert into auth.users(id,aud,role) values(owner_id,'authenticated','authenticated');
 for i in 1..4 loop
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
  values('2096-05-01'::date+i,'10:00','12:30',true,owner_id) returning id into s;
  slots:=array_append(slots,s);
 end loop;
 update public.demo_promo_campaigns set active=false where active;
 r:=public.demo_promo_action(owner_id,true,'campaign-create',jsonb_build_object('title','Quota QA','slots',to_jsonb(slots)));
 c:=(r->>'id')::uuid;
 for i in 1..4 loop
  u:=gen_random_uuid(); b:=gen_random_uuid();
  insert into auth.users(id,aud,role) values(u,'authenticated','authenticated');
  perform public.demo_link_line_customer(u,'U'||replace(u::text,'-',''),now());
  perform public.demo_create_booking_with_promo(u,b,'2096-05-01'::date+i,'10:00','Quota QA','0811111111','none',null,null);
  perform public.demo_claim_booking_with_owner_notification(b,u,'test/slip.png','');
  if i<=3 and not exists(select 1 from public.demo_promo_attempts where booking_id=b) then raise exception 'FIRST_THREE_MISSING'; end if;
  if i=4 and exists(select 1 from public.demo_promo_attempts where booking_id=b) then raise exception 'FOURTH_BOOKING_AWARDED'; end if;
 end loop;
 if (select count(*) from public.demo_promo_attempts where campaign_id=c)<>3 then raise exception 'WRONG_QUOTA'; end if;
 r:=public.demo_promo_action(owner_id,true,'owner-status','{}');
 if not exists(select 1 from jsonb_array_elements(r->'campaigns') x where x->>'id'=c::text and (x->>'remaining')::int=0) then raise exception 'WRONG_REMAINING'; end if;
end $$;
