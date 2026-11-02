-- Execute inside BEGIN/ROLLBACK. Cancelling an unused award must disable its discount and code.
do $$
declare customer_id uuid:=gen_random_uuid(); owner_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
 slot_id uuid; campaign_id uuid; v_booking_id uuid:=gen_random_uuid(); result jsonb; code_value text;
begin
 insert into auth.users(id,aud,role) values(customer_id,'authenticated','authenticated'),(owner_id,'authenticated','authenticated'),(outsider_id,'authenticated','authenticated');
 perform public.demo_link_line_customer(customer_id,'U'||replace(customer_id::text,'-',''),now());
 perform public.demo_link_line_customer(outsider_id,'U'||replace(outsider_id::text,'-',''),now());
 insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
 values('2096-06-01','10:00','12:30',true,owner_id) returning id into slot_id;
 update public.demo_promo_campaigns set active=false where active;
 result:=public.demo_promo_action(owner_id,true,'campaign-create',jsonb_build_object('title','Revoke QA','slots',jsonb_build_array(slot_id)));
 campaign_id:=(result->>'id')::uuid;
 perform public.demo_create_booking_with_promo(customer_id,v_booking_id,'2096-06-01','10:00','Revoke QA','0811111111','none',null,null);
 perform public.demo_claim_booking_with_owner_notification(v_booking_id,customer_id,'test/slip.png','');
 result:=public.demo_promo_action(customer_id,false,'spin',jsonb_build_object('campaignId',campaign_id)); code_value:=result->>'code';
 begin
  perform public.demo_promo_revoke_award(outsider_id,false,v_booking_id);
  raise exception 'CUSTOMER_REVOKE_ALLOWED';
 exception when others then if sqlerrm<>'OWNER_REQUIRED' then raise; end if; end;
 result:=public.demo_promo_revoke_award(owner_id,true,v_booking_id);
 if result->>'status'<>'cancelled' then raise exception 'NOT_CANCELLED'; end if;
 if (select status from public.demo_promo_attempts where booking_id=v_booking_id)<>'cancelled' then raise exception 'ATTEMPT_ACTIVE'; end if;
 if (select status from public.demo_booking_benefits where booking_id=v_booking_id)<>'cancelled' then raise exception 'BENEFIT_ACTIVE'; end if;
 if not (select revoked from public.demo_referral_codes where code=code_value) then raise exception 'CODE_ACTIVE'; end if;
 begin
  perform public.demo_promo_action(outsider_id,false,'check-code',jsonb_build_object('code',code_value));
  raise exception 'REVOKED_CODE_ACCEPTED';
 exception when others then if sqlerrm<>'PROMO_CODE' then raise; end if; end;
 perform public.demo_promo_revoke_award(owner_id,true,v_booking_id);
 result:=public.demo_promo_restart_campaign(owner_id,true,campaign_id);
 result:=public.demo_promo_action(owner_id,true,'owner-status','{}');
 if not exists(select 1 from jsonb_array_elements(result->'campaigns') c where c->>'active'='true' and (c->>'remaining')::int=3) then raise exception 'REFRESH_NOT_THREE'; end if;
end $$;
