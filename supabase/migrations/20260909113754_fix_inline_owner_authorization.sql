-- Reuse slot behavior, replacing the auth-table lookup with an internal,
-- service-role-only decision verified from signed app_metadata by the Edge API.
do $$
declare source text;
 old_guard text:='if not exists(select 1 from auth.users where id=p_owner_id and raw_app_meta_data->>''role''=''owner'') then';
begin
 source:=pg_get_functiondef('public.demo_promo_set_slot_type(uuid,date,time,boolean)'::regprocedure);
 if position(old_guard in source)=0 then raise exception 'Unexpected inline authorization version'; end if;
 source:=replace(source,'p_special boolean)','p_special boolean, p_owner boolean)');
 source:=replace(source,old_guard,'if p_owner_id is null or not coalesce(p_owner,false) then');
 execute source;
end $$;
revoke all on function public.demo_promo_set_slot_type(uuid,date,time,boolean,boolean) from public,anon,authenticated;
grant execute on function public.demo_promo_set_slot_type(uuid,date,time,boolean,boolean) to service_role;
revoke all on function public.demo_promo_set_slot_type(uuid,date,time,boolean) from public,anon,authenticated,service_role;
