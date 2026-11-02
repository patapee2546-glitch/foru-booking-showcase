-- New awards are allocated only by successful slip confirmation, never by spin.
alter table public.demo_promo_attempts add column revealed_at timestamptz;
update public.demo_promo_attempts set revealed_at=created_at;
alter table public.demo_referral_codes add column redeemed_at timestamptz;
update public.demo_referral_codes r set redeemed_at=coalesce(b.slip_uploaded_at,b.paid_at,r.created_at)
 from public.demo_bookings b where b.id=r.redeemed_booking_id and b.status='approved';

create table public.demo_booking_promo_candidates(
 booking_id uuid primary key references public.demo_bookings(id) on delete cascade,
 campaign_id uuid not null references public.demo_promo_campaigns(id),
 line_user_id text not null
);
alter table public.demo_booking_promo_candidates enable row level security;
revoke all on public.demo_booking_promo_candidates from public,anon,authenticated;
grant all on public.demo_booking_promo_candidates to service_role;

-- Preserve existing pending wheel reservations; new clients need no reservation.
alter function public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb) rename to demo_create_booking_with_promo_legacy;
create function public.demo_create_booking_with_promo(
 p_customer_id uuid,p_booking_id uuid,p_slot_date date,p_start_time time,p_customer_name text,
 p_customer_phone text,p_removal_service text,p_design_image_path text,p_benefit jsonb default null
) returns public.demo_bookings language plpgsql security invoker set search_path='' as $$
declare b public.demo_bookings%rowtype; v_line text; c uuid; r public.demo_referral_codes%rowtype;
begin
 if p_benefit->>'type'='referral' then
  select * into r from public.demo_referral_codes where code=upper(btrim(p_benefit->>'code')) for update;
  if r.redeemed_at is not null then raise exception 'PROMO_CODE_USED'; end if;
 end if;
 b:=public.demo_create_booking_with_promo_legacy(p_customer_id,p_booking_id,p_slot_date,p_start_time,p_customer_name,p_customer_phone,p_removal_service,p_design_image_path,p_benefit);
 if p_benefit->>'type' is null then
  select line_user_id into v_line from public.demo_line_links where customer_id=p_customer_id;
  select campaign.id into c from public.demo_promo_campaigns campaign
   join public.demo_slots s on s.id=any(campaign.slot_ids)
   where campaign.active and s.slot_date=p_slot_date and s.start_time=p_start_time;
  if c is not null then
   insert into public.demo_booking_promo_candidates values(b.id,c,v_line) on conflict(booking_id) do nothing;
  end if;
 end if;
 return b;
end $$;
revoke all on function public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb) to service_role;

create function private.demo_award_post_slip() returns trigger language plpgsql security invoker set search_path='' as $$
declare candidate public.demo_booking_promo_candidates%rowtype; a public.demo_promo_attempts%rowtype; n int; random_byte int;
begin
 if new.status<>'approved' or old.status='approved' or nullif(new.slip_path,'') is null then return new; end if;
 select * into candidate from public.demo_booking_promo_candidates where booking_id=new.id;
 if not found or exists(select 1 from public.demo_booking_benefits where booking_id=new.id) then return new; end if;
 -- All awarders serialize on the same campaign. Spinning never spends quota.
 perform 1 from public.demo_promo_campaigns where id=candidate.campaign_id for update;
 if exists(select 1 from public.demo_promo_attempts where campaign_id=candidate.campaign_id and line_user_id=candidate.line_user_id) then return new; end if;
 select count(*) into n from public.demo_promo_attempts where campaign_id=candidate.campaign_id and (status<>'held' or expires_at>clock_timestamp());
 if n>=5 then return new; end if;
 loop random_byte:=get_byte(extensions.gen_random_bytes(1),0);exit when random_byte<255;end loop;
 insert into public.demo_promo_attempts(campaign_id,line_user_id,percent,status,expires_at,booking_id)
  values(candidate.campaign_id,candidate.line_user_id,5*(1+random_byte%3),'confirmed','infinity',new.id) returning * into a;
 insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent,status)
  values(new.id,candidate.line_user_id,'wheel',a.id,a.percent,'confirmed');
 return new;
end $$;
create trigger demo_post_slip_award after update of status on public.demo_bookings for each row execute function private.demo_award_post_slip();
revoke all on function private.demo_award_post_slip() from public,anon,authenticated;

-- Mark a referral consumed at confirmation; cancelled confirmed use is permanent.
do $$ declare source text; old_clause text:='elsif f.kind=''referral'' then update public.demo_referral_codes set redeemed_booking_id=null where id=f.source_id and redeemed_booking_id=new.id and completed_at is null;';
begin
 source:=pg_get_functiondef('private.demo_promo_booking_lifecycle()'::regprocedure);
 if position(old_clause in source)=0 then raise exception 'Unexpected referral lifecycle version'; end if;
 source:=replace(source,old_clause,'elsif f.kind=''referral'' and f.status=''reserved'' then update public.demo_referral_codes set redeemed_booking_id=null where id=f.source_id and redeemed_booking_id=new.id and completed_at is null and redeemed_at is null;');
 source:=replace(source,'update public.demo_booking_benefits set status=''confirmed'' where booking_id=new.id;',
  'if f.kind=''referral'' then
   update public.demo_referral_codes set redeemed_at=clock_timestamp()
    where id=f.source_id and redeemed_booking_id=new.id and redeemed_at is null and completed_at is null and not revoked;
   if not found then raise exception ''PROMO_CODE_USED''; end if;
  end if;
  update public.demo_booking_benefits set status=''confirmed'' where booking_id=new.id;');
 execute source;
end $$;

alter function public.demo_promo_action(uuid,boolean,text,jsonb) rename to demo_promo_action_legacy;
create function public.demo_promo_action(p_customer uuid,p_owner boolean,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
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
    values(generated,v_line,b.id,clock_timestamp()+interval '30 days') returning * into r;
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
    'remaining',greatest(0,5-(select count(*) from public.demo_promo_attempts t where t.campaign_id=c.id and (t.status<>'held' or t.expires_at>clock_timestamp()))),
    'slots',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'date',s.slot_date,'start',s.start_time,'end',s.end_time)),'[]') from public.demo_slots s where s.id=any(c.slot_ids)),
    'attempt',(select jsonb_build_object('id',t.id,'booking_id',t.booking_id,'status',t.status,'percent',case when t.revealed_at is not null and t.status<>'held' then t.percent else null end,'revealed_at',t.revealed_at,
      'booking_status',booking.status,'canSpin',t.status in('confirmed','consumed') and t.revealed_at is null and booking.status='approved' and nullif(booking.slip_path,'') is not null)
     from public.demo_promo_attempts t left join public.demo_bookings booking on booking.id=t.booking_id where t.campaign_id=c.id and t.line_user_id=v_line)) as x
   from public.demo_promo_campaigns c where c.active or exists(select 1 from public.demo_promo_attempts t where t.campaign_id=c.id and t.line_user_id=v_line)
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('code',rc.code,'sourceBookingId',rc.source_booking_id,'expires_at',rc.expires_at,
   'status',case when rc.revoked then 'cancelled' when rc.completed_at is not null then 'completed' when rc.redeemed_at is not null then 'used' when exists(select 1 from public.demo_bookings where id=rc.redeemed_booking_id and status='pending' and expires_at>clock_timestamp()) then 'booked' when rc.expires_at<=clock_timestamp() then 'expired' else 'available' end)),'[]') into code_rows from public.demo_referral_codes rc where rc.owner_line_user_id=v_line;
  result:=result||jsonb_build_object('campaigns',campaign_rows,'codes',code_rows);
  if p_action='owner-status' then
   select coalesce(jsonb_agg(jsonb_build_object('code',rc.code,'ownerName',src.customer_name,'ownerLineUserId',rc.owner_line_user_id,'sourceBookingId',rc.source_booking_id,
    'recipientName',dest.customer_name,'recipientLineUserId',f.line_user_id,'redeemedBookingId',rc.redeemed_booking_id,
    'status',case when rc.revoked then 'cancelled' when rc.completed_at is not null then 'completed' when rc.redeemed_at is not null then 'used' when dest.status='pending' and dest.expires_at>clock_timestamp() then 'booked' when rc.expires_at<=clock_timestamp() then 'expired' else 'available' end) order by rc.created_at desc),'[]') into referrals
   from public.demo_referral_codes rc left join public.demo_bookings src on src.id=rc.source_booking_id left join public.demo_bookings dest on dest.id=rc.redeemed_booking_id left join public.demo_booking_benefits f on f.booking_id=rc.redeemed_booking_id;
   select coalesce(jsonb_agg(jsonb_build_object('bookingId',t.booking_id,'customerName',booking.customer_name,'percent',case when t.revealed_at is not null then t.percent else null end,'revealedAt',t.revealed_at,'status',booking.status) order by t.created_at desc),'[]') into awards from public.demo_promo_attempts t join public.demo_bookings booking on booking.id=t.booking_id where t.status<>'held';
   result:=result||jsonb_build_object('referrals',referrals,'awards',awards);
  end if;
 end if;
 return result;
end $$;
revoke all on function public.demo_promo_action(uuid,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.demo_promo_action(uuid,boolean,text,jsonb) to service_role;
