-- Caller wraps in BEGIN / ROLLBACK. No messages sent; fixture uses server role.
do $$
declare users uuid[]:=array[]::uuid[]; bookings uuid[]:=array[]::uuid[]; slots uuid[]:=array[]::uuid[];
 i int; s uuid; c uuid; b uuid; r jsonb; again jsonb; code text; code2 text;
begin
 for i in 1..9 loop
  users:=array_append(users,gen_random_uuid());
  insert into auth.users(id,aud,role) values(users[i],'authenticated','authenticated');
  perform public.demo_link_line_customer(users[i],'U'||replace(users[i]::text,'-',''),now());
 end loop;
 for i in 1..9 loop
  insert into public.demo_slots(slot_date,start_time,end_time,is_open,updated_by)
   values('2099-03-01'::date+i,'10:00','12:30',true,users[9]) returning id into s;
  slots:=array_append(slots,s);
 end loop;
 -- Isolated transaction temporarily hides other campaigns; all changes roll back.
 update public.demo_promo_campaigns set active=false where active;
 set local role service_role;
 r:=public.demo_promo_action(users[9],true,'campaign-create',jsonb_build_object('title','Post slip QA','slots',to_jsonb(slots[1:6])));
 c:=(r->>'id')::uuid;
 begin
  perform public.demo_promo_action(users[1],false,'spin',jsonb_build_object('campaignId',c));
  raise exception 'UNPAID_SPIN_ALLOWED';
 exception when others then if sqlerrm not like '%PROMO_NOT_APPROVED%' then raise; end if; end;
 for i in 1..6 loop
  b:=gen_random_uuid();bookings:=array_append(bookings,b);
  perform public.demo_create_booking_with_promo(users[i],b,'2099-03-01'::date+i,'10:00','QA person '||i,'0811111111','none',null,null);
 end loop;
 if exists(select 1 from public.demo_promo_attempts where campaign_id=c) then raise exception 'AWARDED_BEFORE_SLIP'; end if;
 for i in 1..6 loop
  perform public.demo_claim_booking_with_owner_notification(bookings[i],users[i],'test/slip.png','');
 end loop;
 if (select count(*) from public.demo_promo_attempts where campaign_id=c)<>5 then raise exception 'NOT_FIRST_FIVE'; end if;
 if exists(select 1 from public.demo_promo_attempts where booking_id=bookings[6]) then raise exception 'SIXTH_AWARDED'; end if;
 r:=public.demo_promo_action(users[1],false,'status','{}');
 if not (r->'campaigns'->0->'attempt'->>'canSpin')::boolean or r->'campaigns'->0->'attempt'->>'percent' is not null then raise exception 'EARLY_REVEAL'; end if;
 r:=public.demo_promo_action(users[1],false,'spin',jsonb_build_object('campaignId',c));
 again:=public.demo_promo_action(users[1],false,'spin',jsonb_build_object('campaignId',c));
 if r<>again or (r->>'percent')::int not in(5,10,15) then raise exception 'REROLL'; end if;
 code:=r->>'code';
 if code!~'[A-Z]' or code!~'[0-9]' then raise exception 'MIXED_CODE_MISSING'; end if;
 r:=public.demo_promo_action(users[7],false,'check-code',jsonb_build_object('code',lower(code)));
 if r->>'referrerName'<>'QA person 1' or r::text like '%line%Id%' then raise exception 'ATTRIBUTION_OR_PRIVACY'; end if;
 b:=gen_random_uuid();
 perform public.demo_create_booking_with_promo(users[7],b,'2099-03-08','10:00','Friend','0811111111','none',null,jsonb_build_object('type','referral','code',code));
 begin
  perform public.demo_create_booking_with_promo(users[8],gen_random_uuid(),'2099-03-09','10:00','Other','0811111111','none',null,jsonb_build_object('type','referral','code',code));
  raise exception 'CONCURRENT_CODE_ALLOWED';
 exception when others then if sqlerrm not like '%PROMO_CODE_USED%' then raise; end if; end;
 perform public.demo_claim_booking_with_owner_notification(b,users[7],'test/slip.png','');
 update public.demo_bookings set status='cancelled',cancelled_at=now(),cancelled_by_role='customer' where id=b;
 begin
  perform public.demo_promo_action(users[8],false,'check-code',jsonb_build_object('code',code));
  raise exception 'CANCELLED_CODE_RECYCLED';
 exception when others then if sqlerrm not like '%PROMO_CODE_USED%' then raise; end if; end;
 if exists(select 1 from public.demo_credit_ledger where source_booking_id=b) then raise exception 'EARLY_CREDIT'; end if;
 r:=public.demo_promo_action(users[9],true,'owner-status','{}');
 if not exists(select 1 from jsonb_array_elements(r->'referrals') x where x->>'code'=code and x->>'recipientName'='Friend' and x->>'ownerName'='QA person 1') then raise exception 'OWNER_ATTRIBUTION_MISSING'; end if;
 r:=public.demo_promo_action(users[2],false,'spin',jsonb_build_object('campaignId',c));code2:=r->>'code';
 b:=gen_random_uuid();
 perform public.demo_create_booking_with_promo(users[8],b,'2099-03-09','10:00','Completed friend','0811111111','none',null,jsonb_build_object('type','referral','code',code2));
 perform public.demo_claim_booking_with_owner_notification(b,users[8],'test/slip.png','');
 r:=public.demo_promo_action(users[9],true,'settle',jsonb_build_object('bookingId',b,'subtotal',60000));
 if (r->>'amountDue')::int<>40000 then raise exception 'WRONG_FINAL_BILL'; end if;
 perform public.demo_promo_action(users[9],true,'settle',jsonb_build_object('bookingId',b,'subtotal',60000));
 if (select count(*) from public.demo_credit_ledger where source_booking_id=b)<>1 then raise exception 'CREDIT_NOT_ONCE'; end if;
 if has_function_privilege('authenticated','public.demo_promo_action(uuid,boolean,text,jsonb)','EXECUTE') then raise exception 'PUBLIC_RPC'; end if;
 perform public.demo_promo_action(users[9],true,'settle',jsonb_build_object('bookingId',bookings[3],'subtotal',60000));
 r:=public.demo_promo_action(users[3],false,'status','{}');
 if not (r->'campaigns'->0->'attempt'->>'canSpin')::boolean then raise exception 'SETTLEMENT_HID_UNREVEALED_REWARD'; end if;
 r:=public.demo_promo_action(users[3],false,'spin',jsonb_build_object('campaignId',c));
 if r->>'code' is null then raise exception 'SETTLED_REWARD_CODE_MISSING'; end if;
end $$;
