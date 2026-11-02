-- Run inside BEGIN/ROLLBACK; no committed bookings or external sends.
do $$
declare u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); s uuid; s2 uuid;
 c uuid; next_id uuid; b uuid:=gen_random_uuid(); b2 uuid:=gen_random_uuid(); r jsonb; old_result jsonb;
begin
 insert into auth.users(id,aud,role) values(u,'authenticated','authenticated'),(v,'authenticated','authenticated');
 perform public.demo_link_line_customer(u,'U'||replace(u::text,'-',''),now());
 perform public.demo_link_line_customer(v,'U'||replace(v::text,'-',''),now());
 insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by) values('2098-04-01','10:00','12:30',true,u) returning id into s;
 insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by) values('2098-04-02','10:00','12:30',true,u) returning id into s2;
 set local role service_role;
 update public.demo_promo_campaigns set active=false where active;
 r:=public.demo_promo_action(u,true,'campaign-create',jsonb_build_object('title','Restart QA','slots',jsonb_build_array(s,s2)));
 c:=(r->>'id')::uuid;
 perform public.demo_create_booking_with_promo(u,b,'2098-04-01','10:00','QA','0811111111','none',null,null);
 perform public.demo_claim_booking_with_owner_notification(b,u,'test/slip.png','');
 old_result:=public.demo_promo_action(u,false,'spin',jsonb_build_object('campaignId',c));
 begin
  perform public.demo_promo_restart_campaign(u,false,c);
  raise exception 'CUSTOMER_RESTART_ALLOWED';
 exception when others then if sqlerrm not like '%OWNER_REQUIRED%' then raise; end if; end;
 r:=public.demo_promo_restart_campaign(u,true,c);next_id:=(r->>'id')::uuid;
 if next_id=c or (select active from public.demo_promo_campaigns where id=c) then raise exception 'OLD_CAMPAIGN_ACTIVE'; end if;
 if (select slot_ids from public.demo_promo_campaigns where id=next_id)<>array[s,s2] then raise exception 'SLOTS_CHANGED'; end if;
 if public.demo_promo_restart_campaign(u,true,c)<>r then raise exception 'RETRY_CREATED_ANOTHER_CAMPAIGN'; end if;
 if public.demo_promo_action(u,false,'spin',jsonb_build_object('campaignId',c))<>old_result then raise exception 'OLD_REWARD_CHANGED'; end if;
 if (select status from public.demo_bookings where id=b)<>'approved' then raise exception 'BOOKING_CHANGED'; end if;
 r:=public.demo_promo_action(u,true,'owner-status','{}');
 if not exists(select 1 from jsonb_array_elements(r->'campaigns') x where x->>'id'=next_id::text and (x->>'remaining')::int=5) then raise exception 'NOT_FIVE_NEW_RIGHTS'; end if;
 perform public.demo_create_booking_with_promo(v,b2,'2098-04-02','10:00','QA2','0811111111','none',null,null);
 perform public.demo_claim_booking_with_owner_notification(b2,v,'test/slip.png','');
 if not exists(select 1 from public.demo_promo_attempts where booking_id=b2 and campaign_id=next_id) then raise exception 'NEW_BOOKING_WRONG_CAMPAIGN'; end if;
 if has_function_privilege('authenticated','public.demo_promo_restart_campaign(uuid,boolean,uuid)','EXECUTE') then raise exception 'PUBLIC_RESTART'; end if;
end $$;
