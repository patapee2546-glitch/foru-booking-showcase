-- Keep the slot entitlement fixed when a customer receives a wheel attempt.
alter table public.demo_promo_attempts add column eligible_slot_ids uuid[];
update public.demo_promo_attempts a set eligible_slot_ids=c.slot_ids from public.demo_promo_campaigns c where c.id=a.campaign_id;
create function private.demo_snapshot_promo_slots() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 select slot_ids into new.eligible_slot_ids from public.demo_promo_campaigns where id=new.campaign_id;
 return new;
end $$;
create trigger demo_snapshot_promo_slots before insert on public.demo_promo_attempts for each row execute function private.demo_snapshot_promo_slots();
revoke all on function private.demo_snapshot_promo_slots() from public,anon,authenticated;

-- Change only the slot-membership lookup in the existing atomic wrapper.
do $$ declare source text; old_lookup text:='select slot_ids into selected from public.demo_promo_campaigns where id=a.campaign_id;'; begin
 source:=pg_get_functiondef('public.demo_create_booking_with_promo(uuid,uuid,date,time,text,text,text,text,jsonb)'::regprocedure);
 if position(old_lookup in source)=0 then raise exception 'Unexpected booking wrapper version'; end if;
 execute replace(source,old_lookup,'selected:=a.eligible_slot_ids;');
end $$;

create function public.demo_promo_set_slot_type(p_owner_id uuid,p_date date,p_start time,p_special boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
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
   update public.demo_promo_campaigns set active=false where id=c.id;
  else update public.demo_promo_campaigns set slot_ids=remaining where id=c.id;
  end if;
 end if;
 return jsonb_build_object('special',p_special,'campaignId',c.id);
end $$;
revoke all on function public.demo_promo_set_slot_type(uuid,date,time,boolean) from public,anon,authenticated;
grant execute on function public.demo_promo_set_slot_type(uuid,date,time,boolean) to service_role;
