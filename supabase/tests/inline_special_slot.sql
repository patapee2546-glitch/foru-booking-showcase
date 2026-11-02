-- Entire fixture must be run inside BEGIN/ROLLBACK.
do $$
declare u uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid(); s uuid; c uuid; a jsonb; b uuid:=gen_random_uuid(); r jsonb;
begin
 if to_regprocedure('public.demo_promo_set_slot_type(uuid,date,time,boolean,boolean)') is null then raise exception 'INLINE_SLOT_CONTROL_MISSING'; end if;
 insert into auth.users(id,aud,role,raw_app_meta_data) values(u,'authenticated','authenticated','{"role":"owner"}'),(customer,'authenticated','authenticated','{}');
 perform public.demo_link_line_customer(customer,'U'||replace(customer::text,'-',''),now());
 insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by) values('2099-02-02','10:00','12:30',true,u) returning id into s;
 -- Match the actual Edge API role: it cannot SELECT auth.users.
 set local role service_role;
 begin
  perform public.demo_promo_set_slot_type(customer,'2099-02-02','10:00',true,false);
  raise exception 'CUSTOMER_CHANGED_SLOT';
 exception when others then if sqlerrm not like '%OWNER_REQUIRED%' then raise; end if; end;
 r:=public.demo_promo_set_slot_type(u,'2099-02-02','10:00',true,true);
 c:=(r->>'campaignId')::uuid;
 perform public.demo_promo_set_slot_type(u,'2099-02-02','10:00',true,true);
 if (select cardinality(slot_ids) from public.demo_promo_campaigns where id=c)<>1 then raise exception 'DUPLICATE_SLOT'; end if;
 a:=public.demo_promo_action(customer,false,'reserve',jsonb_build_object('campaignId',c));
 perform public.demo_promo_set_slot_type(u,'2099-02-02','10:00',false,true);
 if exists(select 1 from public.demo_promo_campaigns where id=c and active) then raise exception 'LAST_SLOT_NOT_CLOSED'; end if;
 if not (select is_open from public.demo_slots where id=s) then raise exception 'AVAILABILITY_CHANGED'; end if;
 perform public.demo_create_booking_with_promo(customer,b,'2099-02-02','10:00','QA','0811111111','none',null,jsonb_build_object('type','wheel','id',a->>'id'));
 perform public.demo_claim_booking_with_owner_notification(b,customer,'test/slip.png','');
 if not exists(select 1 from public.demo_booking_benefits where booking_id=b and status='confirmed') then raise exception 'EXISTING_RIGHT_LOST'; end if;
 if has_function_privilege('authenticated','public.demo_promo_set_slot_type(uuid,date,time,boolean,boolean)','EXECUTE') or has_function_privilege('anon','public.demo_promo_set_slot_type(uuid,date,time,boolean,boolean)','EXECUTE') then raise exception 'RPC_EXPOSED'; end if;
 if has_function_privilege('service_role','public.demo_promo_set_slot_type(uuid,date,time,boolean)','EXECUTE') then raise exception 'LEGACY_RPC_STILL_ACTIVE'; end if;
end $$;
