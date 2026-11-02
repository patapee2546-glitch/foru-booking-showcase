-- Retain every existing award, code, benefit and pending candidate.
alter table public.demo_promo_campaigns add column restarted_from uuid unique references public.demo_promo_campaigns(id);
create function public.demo_promo_restart_campaign(p_customer uuid,p_owner boolean,p_campaign uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.demo_promo_campaigns%rowtype; replacement uuid;
begin
 if p_customer is null or not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
 select * into c from public.demo_promo_campaigns where id=p_campaign for update;
 if not found then raise exception 'PROMO_NOT_FOUND'; end if;
 -- Serialize retries on the original campaign and return the same replacement.
 select id into replacement from public.demo_promo_campaigns where restarted_from=c.id;
 if found then return jsonb_build_object('id',replacement); end if;
 if not c.active then raise exception 'PROMO_CLOSED'; end if;
 if coalesce(cardinality(c.slot_ids),0)=0 then raise exception 'PROMO_SLOTS'; end if;
 update public.demo_promo_campaigns set active=false where id=c.id;
 insert into public.demo_promo_campaigns(title,slot_ids,active,created_by,restarted_from)
 values(c.title,c.slot_ids,true,p_customer,c.id) returning id into replacement;
 return jsonb_build_object('id',replacement);
end $$;
revoke all on function public.demo_promo_restart_campaign(uuid,boolean,uuid) from public,anon,authenticated;
grant execute on function public.demo_promo_restart_campaign(uuid,boolean,uuid) to service_role;
