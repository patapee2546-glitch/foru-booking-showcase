begin;
-- Track only automatic sellout closure: never reopen an explicitly closed promotion.
alter table public.demo_promo_campaigns add column if not exists closed_by_quota boolean not null default false;
CREATE OR REPLACE FUNCTION private.demo_award_post_slip()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare candidate public.demo_booking_promo_candidates%rowtype; a public.demo_promo_attempts%rowtype; n int; random_byte int;
begin
 if new.status<>'approved' or old.status='approved' or nullif(new.slip_path,'') is null then return new; end if;
 select * into candidate from public.demo_booking_promo_candidates where booking_id=new.id;
 if not found or exists(select 1 from public.demo_booking_benefits where booking_id=new.id) then return new; end if;
 -- All awarders serialize on the same campaign. Spinning never spends quota.
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 perform 1 from public.demo_promo_campaigns where id=candidate.campaign_id and active for update;
 if not found then return new; end if;
 if exists(select 1 from public.demo_promo_attempts where campaign_id=candidate.campaign_id and line_user_id=candidate.line_user_id) then return new; end if;
 select count(*) into n from public.demo_promo_attempts where campaign_id=candidate.campaign_id and status<>'cancelled' and (status<>'held' or expires_at>clock_timestamp());
 if n>=3 then
   update public.demo_promo_campaigns set active=false,closed_by_quota=true where id=candidate.campaign_id;
   return new;
  end if;
 loop random_byte:=get_byte(extensions.gen_random_bytes(1),0);exit when random_byte<255;end loop;
 insert into public.demo_promo_attempts(campaign_id,line_user_id,percent,status,expires_at,booking_id)
  values(candidate.campaign_id,candidate.line_user_id,5*(1+random_byte%3),'confirmed','infinity',new.id) returning * into a;
 insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent,status)
  values(new.id,candidate.line_user_id,'wheel',a.id,a.percent,'confirmed');
 if n+1>=3 then
  update public.demo_promo_campaigns set active=false,closed_by_quota=true where id=candidate.campaign_id;
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.demo_promo_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare f public.demo_booking_benefits%rowtype; a public.demo_promo_attempts%rowtype;
begin
 if old.status is not distinct from new.status then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 perform 1 from public.demo_promo_campaigns where id in(select campaign_id from public.demo_promo_attempts where booking_id=new.id) for update;
 select * into f from public.demo_booking_benefits where booking_id=new.id for update;
 if not found then return new; end if;
 if new.status='approved' and f.status='reserved' then
  if f.kind='wheel' then
   select * into a from public.demo_promo_attempts where id=f.source_id for update;
   -- Confirmation and replacement reservations serialize on the same campaign.
   perform 1 from public.demo_promo_campaigns where id=a.campaign_id for update;
   if a.expires_at<=clock_timestamp() or a.status<>'held' then raise exception 'PROMO_EXPIRED'; end if;
   update public.demo_promo_attempts set status='confirmed' where id=a.id;
   insert into public.demo_referral_codes(code,owner_line_user_id,source_booking_id,expires_at)
    values(upper(encode(extensions.gen_random_bytes(8),'hex')),f.line_user_id,new.id,now()+interval '30 days')
    on conflict(source_booking_id) do nothing;
  elsif f.kind='referral' then
   if not exists(select 1 from public.demo_referral_codes where id=f.source_id and redeemed_booking_id=new.id and completed_at is null) then raise exception 'PROMO_CODE_USED'; end if;
  elsif f.kind='credit' then
   if not exists(select 1 from public.demo_credit_ledger where id=f.source_id and reserved_booking_id=new.id and used_at is null) then raise exception 'PROMO_CREDIT_USED'; end if;
  end if;
  if f.kind='referral' then
   update public.demo_referral_codes set redeemed_at=clock_timestamp()
    where id=f.source_id and redeemed_booking_id=new.id and redeemed_at is null and completed_at is null and not revoked;
   if not found then raise exception 'PROMO_CODE_USED'; end if;
  end if;
  update public.demo_booking_benefits set status='confirmed' where booking_id=new.id;
 elsif new.status in('cancelled','expired','lost') then
  if f.status='used' then raise exception 'PROMO_ALREADY_SETTLED'; end if;
  update public.demo_booking_benefits set status='cancelled' where booking_id=new.id;
  if f.kind='wheel' then
   update public.demo_promo_attempts set status='cancelled',
    expires_at=least(expires_at,now()) where id=f.source_id;
   update public.demo_referral_codes set revoked=true where source_booking_id=new.id;
  elsif f.kind='referral' and f.status='reserved' then update public.demo_referral_codes set redeemed_booking_id=null where id=f.source_id and redeemed_booking_id=new.id and completed_at is null and redeemed_at is null;
  elsif f.kind='credit' then update public.demo_credit_ledger set reserved_booking_id=null where id=f.source_id and reserved_booking_id=new.id and used_at is null;
  end if;
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_revoke_award(p_customer uuid, p_owner boolean, p_booking uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a public.demo_promo_attempts%rowtype; benefit_status text; code_row public.demo_referral_codes%rowtype;
begin
 if p_customer is null or not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 perform 1 from public.demo_bookings where id=p_booking for update;
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 perform 1 from public.demo_promo_campaigns where id in(select campaign_id from public.demo_promo_attempts where booking_id=p_booking) for update;
 select * into a from public.demo_promo_attempts where booking_id=p_booking for update;
 if not found then raise exception 'PROMO_NOT_FOUND'; end if;
 if a.status='cancelled' then return jsonb_build_object('bookingId',p_booking,'status','cancelled'); end if;
 select status into benefit_status from public.demo_booking_benefits where booking_id=p_booking for update;
 if benefit_status='used' or exists(select 1 from public.demo_service_settlements where booking_id=p_booking) then raise exception 'PROMO_ALREADY_USED'; end if;
 select * into code_row from public.demo_referral_codes where source_booking_id=p_booking for update;
 if found and (code_row.redeemed_at is not null or code_row.completed_at is not null or exists(
  select 1 from public.demo_bookings b where b.id=code_row.redeemed_booking_id and (b.status='approved' or (b.status='pending' and b.expires_at>clock_timestamp()))
 )) then raise exception 'PROMO_ALREADY_USED'; end if;
 update public.demo_promo_attempts set status='cancelled' where id=a.id;
 update public.demo_booking_benefits set status='cancelled' where booking_id=p_booking and status<>'used';
 update public.demo_referral_codes set revoked=true where source_booking_id=p_booking;
 return jsonb_build_object('bookingId',p_booking,'status','cancelled');
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_action(p_customer uuid, p_owner boolean, p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_line text; a public.demo_promo_attempts%rowtype; b public.demo_bookings%rowtype;
 r public.demo_referral_codes%rowtype; result jsonb; campaign_rows jsonb; code_rows jsonb; referrals jsonb; awards jsonb; generated text;
begin
 if p_customer is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_action in('campaign-create','campaign-close','owner-status','quote','settle') and not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 select line_user_id into v_line from public.demo_line_links where customer_id=p_customer;
 if p_action='reserve' then raise exception 'PROMO_NOT_APPROVED'; end if;
 if p_action='spin' then
  if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
  -- Lock booking before attempt, matching cancellation lock order.
  select booking.* into b from public.demo_bookings booking join public.demo_promo_attempts attempt on attempt.booking_id=booking.id
   where attempt.campaign_id=(p_data->>'campaignId')::uuid and attempt.line_user_id=v_line for update of booking;
  if not found or b.status<>'approved' or nullif(b.slip_path,'') is null then raise exception 'PROMO_NOT_APPROVED'; end if;
  select * into a from public.demo_promo_attempts where booking_id=b.id and line_user_id=v_line for update;
  if a.status not in('confirmed','consumed') then raise exception 'PROMO_NOT_APPROVED'; end if;
  update public.demo_promo_attempts set revealed_at=coalesce(revealed_at,clock_timestamp()) where id=a.id returning * into a;
  select * into r from public.demo_referral_codes where source_booking_id=b.id;
  if not found then
   loop
    generated:='LP'||upper(encode(extensions.gen_random_bytes(6),'hex'));
    -- Guarantee at least one number, as well as the letter prefix.
    exit when generated ~ '[0-9]' and not exists(select 1 from public.demo_referral_codes where code=generated);
   end loop;
   insert into public.demo_referral_codes(code,owner_line_user_id,source_booking_id,expires_at)
    values(generated,v_line,b.id,clock_timestamp()+interval '14 days') returning * into r;
  end if;
  return jsonb_build_object('id',a.id,'booking_id',b.id,'status',a.status,'percent',a.percent,'revealed_at',a.revealed_at,'canSpin',false,'code',r.code);
 elsif p_action='check-code' then
  if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
  select * into r from public.demo_referral_codes where code=upper(btrim(p_data->>'code'));
  if not found or r.revoked or r.expires_at<=clock_timestamp() then raise exception 'PROMO_CODE'; end if;
  if r.owner_line_user_id=v_line then raise exception 'PROMO_SELF'; end if;
  if r.redeemed_at is not null or r.completed_at is not null or exists(select 1 from public.demo_bookings where id=r.redeemed_booking_id and (status='approved' or (status='pending' and expires_at>clock_timestamp()))) then raise exception 'PROMO_CODE_USED'; end if;
  if exists(select 1 from public.demo_booking_line_recipients x join public.demo_bookings prior on prior.id=x.booking_id where x.line_user_id=v_line and (prior.status='approved' or (prior.status='pending' and prior.expires_at>clock_timestamp()))) or exists(select 1 from public.demo_booking_benefits where line_user_id=v_line and status='used') then raise exception 'PROMO_NEW_ONLY'; end if;
  select * into b from public.demo_bookings where id=r.source_booking_id;
  return jsonb_build_object('valid',true,'code',r.code,'referrerName',coalesce(nullif(b.customer_name,''),'เพื่อนของคุณ'));
 end if;
 result:=public.demo_promo_action_legacy(p_customer,p_owner,p_action,p_data);
 if p_action in('status','owner-status') then
  select coalesce(jsonb_agg(x order by x->>'created_at' desc),'[]') into campaign_rows from (
   select jsonb_build_object('id',c.id,'title',c.title,'active',c.active,'created_at',c.created_at,
    'remaining',greatest(0,3-(select count(*) from public.demo_promo_attempts t where t.campaign_id=c.id and t.status<>'cancelled' and (t.status<>'held' or t.expires_at>clock_timestamp()))),
    'slots',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'date',s.slot_date,'start',s.start_time,'end',s.end_time)),'[]') from public.demo_slots s where s.id=any(c.slot_ids)),
    'attempt',(select jsonb_build_object('id',t.id,'booking_id',t.booking_id,'status',t.status,'percent',case when t.revealed_at is not null and t.status<>'held' then t.percent else null end,'revealed_at',t.revealed_at,
      'booking_status',booking.status,'canSpin',t.status in('confirmed','consumed') and t.revealed_at is null and booking.status='approved' and nullif(booking.slip_path,'') is not null)
     from public.demo_promo_attempts t left join public.demo_bookings booking on booking.id=t.booking_id where t.campaign_id=c.id and t.line_user_id=v_line)) as x
   from public.demo_promo_campaigns c where c.active or exists(select 1 from public.demo_promo_attempts t where t.campaign_id=c.id and t.line_user_id=v_line)
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('code',rc.code,'sourceBookingId',rc.source_booking_id,'expires_at',rc.expires_at,
   'status',case when rc.revoked then 'cancelled' when rc.completed_at is not null then 'completed' when rc.redeemed_at is not null then 'used' when exists(select 1 from public.demo_bookings where id=rc.redeemed_booking_id and status='pending' and expires_at>clock_timestamp()) then 'booked' when rc.expires_at<=clock_timestamp() then 'expired' else 'available' end)),'[]') into code_rows from public.demo_referral_codes rc where rc.owner_line_user_id=v_line and rc.customer_hidden_at is null;
  result:=result||jsonb_build_object('campaigns',campaign_rows,'codes',code_rows);
  if p_action='owner-status' then
   select coalesce(jsonb_agg(jsonb_build_object('code',rc.code,'ownerName',src.customer_name,'ownerLineUserId',rc.owner_line_user_id,'sourceBookingId',rc.source_booking_id,
    'recipientName',dest.customer_name,'recipientLineUserId',f.line_user_id,'redeemedBookingId',rc.redeemed_booking_id,
    'status',case when rc.revoked then 'cancelled' when rc.completed_at is not null then 'completed' when rc.redeemed_at is not null then 'used' when dest.status='pending' and dest.expires_at>clock_timestamp() then 'booked' when rc.expires_at<=clock_timestamp() then 'expired' else 'available' end) order by rc.created_at desc),'[]') into referrals
   from public.demo_referral_codes rc left join public.demo_bookings src on src.id=rc.source_booking_id left join public.demo_bookings dest on dest.id=rc.redeemed_booking_id left join public.demo_booking_benefits f on f.booking_id=rc.redeemed_booking_id
   where rc.owner_hidden_at is null;
   select coalesce(jsonb_agg(jsonb_build_object('bookingId',t.booking_id,'customerName',booking.customer_name,'percent',case when t.revealed_at is not null then t.percent else null end,'revealedAt',t.revealed_at,'status',case when t.status='cancelled' then 'cancelled' else booking.status end) order by t.created_at desc),'[]') into awards from public.demo_promo_attempts t join public.demo_bookings booking on booking.id=t.booking_id where t.status<>'held';
   result:=result||jsonb_build_object('referrals',referrals,'awards',awards);
  end if;
 end if;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_action_legacy(p_customer uuid, p_owner boolean, p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_line text; c public.demo_promo_campaigns%rowtype; a public.demo_promo_attempts%rowtype;
 b public.demo_bookings%rowtype; f public.demo_booking_benefits%rowtype;
 receipt public.demo_service_settlements%rowtype; codes jsonb; credits jsonb; campaigns jsonb;
 n integer; byte integer; sub integer; disc integer; dep integer; balance integer; result jsonb; selected uuid[];
begin
 if p_customer is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_action in('campaign-create','campaign-close','owner-status','quote','settle') and not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 select line_user_id into v_line from public.demo_line_links where customer_id=p_customer;
 if p_action in('campaign-create','campaign-close','reserve') then perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0)); end if;
 if p_action='campaign-create' then
  select array_agg(value::uuid) into selected from jsonb_array_elements_text(p_data->'slots');
  if coalesce(cardinality(selected),0)<1 or cardinality(selected)>100 then raise exception 'PROMO_SLOTS'; end if;
  if (select count(distinct id) from public.demo_slots where id=any(selected) and is_open and not is_booked and (slot_date+start_time) at time zone 'Asia/Bangkok'>now())<>cardinality(selected) then raise exception 'PROMO_SLOTS'; end if;
  insert into public.demo_promo_campaigns(title,slot_ids,active,created_by)
   values(btrim(p_data->>'title'),selected,true,p_customer) returning * into c;
  return jsonb_build_object('id',c.id);
 elsif p_action='campaign-close' then
  update public.demo_promo_campaigns set active=false,closed_by_quota=false where id=(p_data->>'campaignId')::uuid;
  return jsonb_build_object('closed',true);
 elsif p_action in('quote','settle') then
  select * into b from public.demo_bookings where id=(p_data->>'bookingId')::uuid for update;
  if not found or b.status<>'approved' then raise exception 'PROMO_NOT_APPROVED'; end if;
  if coalesce(p_data->>'subtotal','')!~'^\d{1,9}$' then raise exception 'INVALID_AMOUNT'; end if;
  sub:=(p_data->>'subtotal')::integer;
  if sub>100000000 then raise exception 'INVALID_AMOUNT'; end if;
  select * into receipt from public.demo_service_settlements where booking_id=b.id;
  if found then
   if receipt.subtotal<>sub then raise exception 'PROMO_ALREADY_SETTLED'; end if;
   return jsonb_build_object('subtotal',sub,'discount',receipt.discount,'deposit',receipt.deposit,'amountDue',receipt.amount_due,'overpayment',receipt.overpayment,'settled',true);
  end if;
  select * into f from public.demo_booking_benefits where booking_id=b.id for update;
  disc:=case when f.status='confirmed' then least(sub,5000,case when f.percent>0 then floor(sub::numeric*f.percent/100)::integer else f.flat end) else 0 end;
  dep:=case when b.slip_path is not null then 15000 else 0 end;
  balance:=sub-disc-dep;
  result:=jsonb_build_object('subtotal',sub,'discount',disc,'deposit',dep,'amountDue',greatest(0,balance),'overpayment',greatest(0,-balance),'settled',false);
  if p_action='settle' then
   insert into public.demo_service_settlements(booking_id,subtotal,discount,deposit,amount_due,overpayment,settled_by)
    values(b.id,sub,disc,dep,greatest(0,balance),greatest(0,-balance),p_customer);
   if f.status='confirmed' then
    update public.demo_booking_benefits set status='used' where booking_id=b.id;
    if f.kind='referral' then
     update public.demo_referral_codes set completed_at=now() where id=f.source_id and redeemed_booking_id=b.id;
     insert into public.demo_credit_ledger(line_user_id,source_booking_id,expires_at)
      select owner_line_user_id,b.id,now()+interval '60 days' from public.demo_referral_codes where id=f.source_id
      on conflict(source_booking_id) do nothing;
    elsif f.kind='credit' then update public.demo_credit_ledger set used_at=now() where id=f.source_id;
    elsif f.kind='wheel' then update public.demo_promo_attempts set status='consumed' where id=f.source_id;
    end if;
   end if;
   result:=result||jsonb_build_object('settled',true);
  end if;
  return result;
 elsif p_action='reserve' then
  if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
  select * into c from public.demo_promo_campaigns where id=(p_data->>'campaignId')::uuid for update;
  if not found then raise exception 'PROMO_CLOSED'; end if;
  select * into a from public.demo_promo_attempts where campaign_id=c.id and line_user_id=v_line;
  if found then return to_jsonb(a)-'line_user_id'; end if;
  if not c.active then raise exception 'PROMO_CLOSED'; end if;
  select count(*) into n from public.demo_promo_attempts where campaign_id=c.id and status<>'cancelled' and (status<>'held' or expires_at>clock_timestamp());
  if n>=3 then raise exception 'PROMO_FULL'; end if;
  loop byte:=get_byte(extensions.gen_random_bytes(1),0);exit when byte<255;end loop;
  insert into public.demo_promo_attempts(campaign_id,line_user_id,percent,expires_at)
   values(c.id,v_line,5*(1+byte%3),clock_timestamp()+interval '5 minutes') returning * into a;
  return to_jsonb(a)-'line_user_id';
 elsif p_action in('status','owner-status') then
  select coalesce(jsonb_agg(x),'[]') into campaigns from (
   select campaign.id,campaign.title,campaign.active,campaign.created_at,
    greatest(0,3-(select count(*) from public.demo_promo_attempts attempt where attempt.campaign_id=campaign.id and attempt.status<>'cancelled' and (attempt.status<>'held' or attempt.expires_at>now()))) as remaining,
    (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'date',s.slot_date,'start',s.start_time,'end',s.end_time)),'[]') from public.demo_slots s where s.id=any(campaign.slot_ids)) as slots,
    (select to_jsonb(attempt)-'line_user_id' from public.demo_promo_attempts attempt where attempt.campaign_id=campaign.id and attempt.line_user_id=v_line) as attempt
   from public.demo_promo_campaigns campaign where campaign.active or
    exists(select 1 from public.demo_promo_attempts attempt where attempt.campaign_id=campaign.id and attempt.line_user_id=v_line)
   order by campaign.created_at desc limit 20
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('code',r.code,'expires_at',r.expires_at,'status',case when r.revoked then 'cancelled' when r.completed_at is not null then 'completed' when r.redeemed_booking_id is not null then 'booked' when r.expires_at<=now() then 'expired' else 'available' end)),'[]') into codes from public.demo_referral_codes r where r.owner_line_user_id=v_line;
  select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'expires_at',l.expires_at,'status',case when l.used_at is not null then 'used' when exists(select 1 from public.demo_bookings held where held.id=l.reserved_booking_id and (held.status='approved' or (held.status='pending' and held.expires_at>clock_timestamp()))) then 'booked' when l.expires_at<=clock_timestamp() then 'expired' else 'available' end)),'[]') into credits from public.demo_credit_ledger l where l.line_user_id=v_line;
  return jsonb_build_object('serverTime',now(),'linked',v_line is not null,'campaigns',campaigns,'codes',codes,'credits',credits);
 else raise exception 'PROMO_ACTION'; end if;
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_restart_campaign(p_customer uuid, p_owner boolean, p_campaign uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.demo_promo_campaigns%rowtype; replacement uuid;
begin
 if p_customer is null or not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 select * into c from public.demo_promo_campaigns where id=p_campaign for update;
 if not found then raise exception 'PROMO_NOT_FOUND'; end if;
 -- Serialize retries on the original campaign and return the same replacement.
 select id into replacement from public.demo_promo_campaigns where restarted_from=c.id;
 if found then return jsonb_build_object('id',replacement); end if;
 if not c.active then raise exception 'PROMO_CLOSED'; end if;
 if coalesce(cardinality(c.slot_ids),0)=0 then raise exception 'PROMO_SLOTS'; end if;
 update public.demo_promo_campaigns set active=false,closed_by_quota=false where id=c.id;
 insert into public.demo_promo_campaigns(title,slot_ids,active,created_by,restarted_from)
 values(c.title,c.slot_ids,true,p_customer,c.id) returning id into replacement;
 return jsonb_build_object('id',replacement);
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_set_slot_type(p_owner_id uuid, p_date date, p_start time without time zone, p_special boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.demo_promo_campaigns%rowtype; s public.demo_slots%rowtype; remaining uuid[];
begin
 if not exists(select 1 from auth.users where id=p_owner_id and raw_app_meta_data->>'role'='owner') then raise exception 'OWNER_REQUIRED'; end if;
 if p_special is null then raise exception 'PROMO_INVALID'; end if;
 -- Serialize the first special slot (campaign creation) across owner sessions.
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 select * into c from public.demo_promo_campaigns where active for update;
 select * into s from public.demo_slots where slot_date=p_date and start_time=p_start;
 if not found then raise exception 'PROMO_SLOTS'; end if;
 if p_special then
  if not s.is_open or s.is_booked or (s.slot_date+s.start_time) at time zone 'Asia/Bangkok'<=clock_timestamp() then raise exception 'PROMO_SLOTS'; end if;
  if c.id is null then
   insert into public.demo_promo_campaigns(title,slot_ids,active,created_by) values('Demo Secret Five',array[s.id],true,p_owner_id) returning * into c;
  elsif not s.id=any(c.slot_ids) then
   if cardinality(c.slot_ids)>=100 then raise exception 'PROMO_SLOTS'; end if;
   update public.demo_promo_campaigns set slot_ids=array_append(slot_ids,s.id) where id=c.id;
  end if;
 elsif c.id is not null and s.id=any(c.slot_ids) then
  remaining:=array_remove(c.slot_ids,s.id);
  if cardinality(remaining)=0 then
   update public.demo_promo_campaigns set active=false,closed_by_quota=false where id=c.id;
  else update public.demo_promo_campaigns set slot_ids=remaining where id=c.id;
  end if;
 end if;
 return jsonb_build_object('special',p_special,'campaignId',c.id);
end $function$
;
CREATE OR REPLACE FUNCTION public.demo_promo_set_slot_type(p_owner_id uuid, p_date date, p_start time without time zone, p_special boolean, p_owner boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c public.demo_promo_campaigns%rowtype; s public.demo_slots%rowtype; remaining uuid[];
begin
 if p_owner_id is null or not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 if p_special is null then raise exception 'PROMO_INVALID'; end if;
 -- Serialize the first special slot (campaign creation) across owner sessions.
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 select * into c from public.demo_promo_campaigns where active for update;
 select * into s from public.demo_slots where slot_date=p_date and start_time=p_start;
 if not found then raise exception 'PROMO_SLOTS'; end if;
 if p_special then
  if not s.is_open or s.is_booked or (s.slot_date+s.start_time) at time zone 'Asia/Bangkok'<=clock_timestamp() then raise exception 'PROMO_SLOTS'; end if;
  if c.id is null then
   insert into public.demo_promo_campaigns(title,slot_ids,active,created_by) values('Demo Secret Five',array[s.id],true,p_owner_id) returning * into c;
  elsif not s.id=any(c.slot_ids) then
   if cardinality(c.slot_ids)>=100 then raise exception 'PROMO_SLOTS'; end if;
   update public.demo_promo_campaigns set slot_ids=array_append(slot_ids,s.id) where id=c.id;
  end if;
 elsif c.id is not null and s.id=any(c.slot_ids) then
  remaining:=array_remove(c.slot_ids,s.id);
  if cardinality(remaining)=0 then
   update public.demo_promo_campaigns set active=false,closed_by_quota=false where id=c.id;
  else update public.demo_promo_campaigns set slot_ids=remaining where id=c.id;
  end if;
 end if;
 return jsonb_build_object('special',p_special,'campaignId',c.id);
end $function$
;

create or replace function private.demo_return_cancelled_wheel_quota()
returns trigger language plpgsql set search_path='' as $function$
declare c public.demo_promo_campaigns%rowtype; used_count int;
begin
 if new.status<>'cancelled' or old.status='cancelled' then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 select * into c from public.demo_promo_campaigns where id=new.campaign_id for update;
 if not found or c.active or not c.closed_by_quota then return new; end if;
 select count(*) into used_count from public.demo_promo_attempts
 where campaign_id=c.id and status<>'cancelled' and (status<>'held' or expires_at>clock_timestamp());
 -- A newer campaign supersedes this one, even if the newer campaign is closed.
 if used_count<3 and not exists(select 1 from public.demo_promo_campaigns other
  where other.id<>c.id and (other.active or other.created_at>c.created_at or other.restarted_from=c.id)) then
  update public.demo_promo_campaigns set active=true,closed_by_quota=false where id=c.id;
 end if;
 return new;
end $function$;
drop trigger if exists demo_return_cancelled_wheel_quota on public.demo_promo_attempts;
create trigger demo_return_cancelled_wheel_quota after update of status on public.demo_promo_attempts
for each row execute function private.demo_return_cancelled_wheel_quota();
-- Repair old cancelled bookings without touching settled benefits or deleting audit history.
update public.demo_promo_attempts a set status='cancelled'
from public.demo_bookings b, public.demo_booking_benefits f
where a.booking_id=b.id and f.booking_id=b.id and f.kind='wheel' and f.source_id=a.id
 and b.status in('cancelled','expired','lost') and f.status='cancelled' and a.status<>'cancelled'
 and not exists(select 1 from public.demo_service_settlements s where s.booking_id=b.id);
commit;
