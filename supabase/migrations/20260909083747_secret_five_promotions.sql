-- Promotion records are server-only. LINE identities never leave the customer API.
create table public.demo_promo_campaigns(
 id uuid primary key default gen_random_uuid(),title text not null check(length(title) between 1 and 80),
 active boolean not null default false,slot_ids uuid[] not null check(cardinality(slot_ids)>0),
 created_at timestamptz not null default now(),created_by uuid not null references auth.users(id)
);
create unique index demo_one_active_campaign on public.demo_promo_campaigns(active) where active;
create table public.demo_promo_attempts(
 id uuid primary key default gen_random_uuid(),campaign_id uuid not null references public.demo_promo_campaigns(id),
 line_user_id text not null,percent integer not null check(percent in(5,10,15)),
 status text not null default 'held' check(status in('held','confirmed','consumed')),
 expires_at timestamptz not null,booking_id uuid unique,created_at timestamptz not null default now(),
 unique(campaign_id,line_user_id)
);
create table public.demo_referral_codes(
 id uuid primary key default gen_random_uuid(),code text not null unique,
 owner_line_user_id text not null,source_booking_id uuid not null unique,
 expires_at timestamptz not null,redeemed_booking_id uuid unique,completed_at timestamptz,
 revoked boolean not null default false,created_at timestamptz not null default now()
);
create table public.demo_credit_ledger(
 id uuid primary key default gen_random_uuid(),line_user_id text not null,
 amount integer not null default 5000 check(amount=5000),source_booking_id uuid not null unique,
 expires_at timestamptz not null,reserved_booking_id uuid unique,used_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.demo_booking_benefits(
 booking_id uuid primary key,line_user_id text not null,
 kind text not null check(kind in('wheel','referral','credit')),source_id uuid not null,
 percent integer not null default 0 check(percent in(0,5,10,15)),
 flat integer not null default 0 check(flat in(0,5000)),
 status text not null default 'reserved' check(status in('reserved','confirmed','used','cancelled')),
 created_at timestamptz not null default now()
);
create index demo_benefit_line on public.demo_booking_benefits(line_user_id);
create table public.demo_service_settlements(
 booking_id uuid primary key,subtotal integer not null check(subtotal>=0),discount integer not null,
 deposit integer not null,amount_due integer not null,overpayment integer not null,
 settled_by uuid not null references auth.users(id),settled_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['demo_promo_campaigns','demo_promo_attempts','demo_referral_codes','demo_credit_ledger','demo_booking_benefits','demo_service_settlements'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;

create function public.demo_promo_action(p_customer uuid,p_owner boolean,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 v_line text; c public.demo_promo_campaigns%rowtype; a public.demo_promo_attempts%rowtype;
 b public.demo_bookings%rowtype; f public.demo_booking_benefits%rowtype;
 receipt public.demo_service_settlements%rowtype; codes jsonb; credits jsonb; campaigns jsonb;
 n integer; byte integer; sub integer; disc integer; dep integer; balance integer; result jsonb; selected uuid[];
begin
 if p_customer is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_action in('campaign-create','campaign-close','owner-status','quote','settle') and not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 select line_user_id into v_line from public.demo_line_links where customer_id=p_customer;
 if p_action='campaign-create' then
  select array_agg(value::uuid) into selected from jsonb_array_elements_text(p_data->'slots');
  if coalesce(cardinality(selected),0)<1 or cardinality(selected)>100 then raise exception 'PROMO_SLOTS'; end if;
  if (select count(distinct id) from public.demo_slots where id=any(selected) and is_open and not is_booked and (slot_date+start_time) at time zone 'Asia/Bangkok'>now())<>cardinality(selected) then raise exception 'PROMO_SLOTS'; end if;
  insert into public.demo_promo_campaigns(title,slot_ids,active,created_by)
   values(btrim(p_data->>'title'),selected,true,p_customer) returning * into c;
  return jsonb_build_object('id',c.id);
 elsif p_action='campaign-close' then
  update public.demo_promo_campaigns set active=false where id=(p_data->>'campaignId')::uuid;
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
  select count(*) into n from public.demo_promo_attempts where campaign_id=c.id and (status<>'held' or expires_at>clock_timestamp());
  if n>=5 then raise exception 'PROMO_FULL'; end if;
  loop byte:=get_byte(extensions.gen_random_bytes(1),0);exit when byte<255;end loop;
  insert into public.demo_promo_attempts(campaign_id,line_user_id,percent,expires_at)
   values(c.id,v_line,5*(1+byte%3),clock_timestamp()+interval '5 minutes') returning * into a;
  return to_jsonb(a)-'line_user_id';
 elsif p_action in('status','owner-status') then
  select coalesce(jsonb_agg(x),'[]') into campaigns from (
   select campaign.id,campaign.title,campaign.active,campaign.created_at,
    greatest(0,5-(select count(*) from public.demo_promo_attempts attempt where attempt.campaign_id=campaign.id and (attempt.status<>'held' or attempt.expires_at>now()))) as remaining,
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
end $$;

create function public.demo_create_booking_with_promo(
 p_customer_id uuid,p_booking_id uuid,p_slot_date date,p_start_time time,p_customer_name text,
 p_customer_phone text,p_removal_service text,p_design_image_path text,p_benefit jsonb default null
) returns public.demo_bookings language plpgsql security invoker set search_path='' as $$
declare
 b public.demo_bookings%rowtype; a public.demo_promo_attempts%rowtype;
 r public.demo_referral_codes%rowtype; l public.demo_credit_ledger%rowtype;
 v_line text; kind text; selected uuid[];
begin
 select line_user_id into v_line from public.demo_line_links where customer_id=p_customer_id;
 if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
 -- Serialize benefit claims by identity even when several anonymous sessions are used.
 perform pg_advisory_xact_lock(hashtextextended(v_line,0));
 kind:=p_benefit->>'type';
 if kind is not null and kind not in('wheel','referral','credit') then raise exception 'PROMO_INVALID'; end if;
 if kind='wheel' then
  select * into a from public.demo_promo_attempts where id=(p_benefit->>'id')::uuid and line_user_id=v_line for update;
  if not found or a.status<>'held' or a.expires_at<=now() or a.booking_id is not null then raise exception 'PROMO_EXPIRED'; end if;
  select slot_ids into selected from public.demo_promo_campaigns where id=a.campaign_id;
  if not exists(select 1 from public.demo_slots where id=any(selected) and slot_date=p_slot_date and start_time=p_start_time) then raise exception 'PROMO_SLOT'; end if;
 elsif kind='referral' then
  select * into r from public.demo_referral_codes where code=upper(btrim(p_benefit->>'code')) for update;
  if not found or r.revoked or r.expires_at<=now() or r.completed_at is not null then raise exception 'PROMO_CODE'; end if;
  if r.owner_line_user_id=v_line then raise exception 'PROMO_SELF'; end if;
  if r.redeemed_booking_id is not null then
   if exists(select 1 from public.demo_bookings where id=r.redeemed_booking_id and (status='approved' or (status='pending' and expires_at>now()))) then raise exception 'PROMO_CODE_USED'; end if;
  end if;
  if exists(select 1 from public.demo_booking_line_recipients x join public.demo_bookings prior on prior.id=x.booking_id where x.line_user_id=v_line and (prior.status='approved' or (prior.status='pending' and prior.expires_at>now()))) or
   exists(select 1 from public.demo_booking_benefits where line_user_id=v_line and status='used') then raise exception 'PROMO_NEW_ONLY'; end if;
 elsif kind='credit' then
  select * into l from public.demo_credit_ledger where id=(p_benefit->>'id')::uuid and line_user_id=v_line for update;
  if not found or l.used_at is not null or l.expires_at<=now() then raise exception 'PROMO_CREDIT'; end if;
  if l.reserved_booking_id is not null and exists(select 1 from public.demo_bookings where id=l.reserved_booking_id and (status='approved' or (status='pending' and expires_at>now()))) then raise exception 'PROMO_CREDIT_USED'; end if;
 end if;
 b:=public.demo_create_pending_booking(p_customer_id,p_booking_id,p_slot_date,p_start_time,p_customer_name,p_customer_phone,p_removal_service,p_design_image_path);
 if kind='wheel' then
  update public.demo_bookings set expires_at=least(expires_at,a.expires_at) where id=b.id returning * into b;
  update public.demo_promo_attempts set booking_id=b.id where id=a.id;
  insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent) values(b.id,v_line,kind,a.id,a.percent);
 elsif kind='referral' then
  update public.demo_referral_codes set redeemed_booking_id=b.id where id=r.id;
  insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,flat) values(b.id,v_line,kind,r.id,5000);
 elsif kind='credit' then
  update public.demo_credit_ledger set reserved_booking_id=b.id where id=l.id;
  insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,flat) values(b.id,v_line,kind,l.id,5000);
 end if;
 return b;
end $$;

create function private.demo_promo_booking_lifecycle() returns trigger language plpgsql security invoker set search_path='' as $$
declare f public.demo_booking_benefits%rowtype; a public.demo_promo_attempts%rowtype;
begin
 if old.status is not distinct from new.status then return new; end if;
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
  update public.demo_booking_benefits set status='confirmed' where booking_id=new.id;
 elsif new.status in('cancelled','expired','lost') then
  if f.status='used' then raise exception 'PROMO_ALREADY_SETTLED'; end if;
  update public.demo_booking_benefits set status='cancelled' where booking_id=new.id;
  if f.kind='wheel' then
   update public.demo_promo_attempts set status=case when status='held' then 'held' else 'consumed' end,
    expires_at=least(expires_at,now()) where id=f.source_id;
   update public.demo_referral_codes set revoked=true where source_booking_id=new.id;
  elsif f.kind='referral' then update public.demo_referral_codes set redeemed_booking_id=null where id=f.source_id and redeemed_booking_id=new.id and completed_at is null;
  elsif f.kind='credit' then update public.demo_credit_ledger set reserved_booking_id=null where id=f.source_id and reserved_booking_id=new.id and used_at is null;
  end if;
 end if;
 return new;
end $$;
create trigger demo_promo_booking_lifecycle after update of status on public.demo_bookings for each row execute function private.demo_promo_booking_lifecycle();
revoke all on function private.demo_promo_booking_lifecycle() from public,anon,authenticated;
revoke all on function public.demo_promo_action(uuid,boolean,text,jsonb) from public,anon,authenticated;
revoke all on function public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.demo_promo_action(uuid,boolean,text,jsonb) to service_role;
grant execute on function public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb) to service_role;
