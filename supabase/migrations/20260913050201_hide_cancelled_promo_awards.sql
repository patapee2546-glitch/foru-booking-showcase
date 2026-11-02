alter table public.demo_promo_attempts
  add column if not exists owner_hidden_at timestamptz;

create or replace function public.demo_promo_hide_award(
  p_customer uuid,
  p_owner boolean,
  p_booking uuid
)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare award public.demo_promo_attempts%rowtype;
begin
  if p_customer is null or not coalesce(p_owner,false) then
    raise exception 'OWNER_REQUIRED';
  end if;
  select * into award from public.demo_promo_attempts
    where booking_id=p_booking for update;
  if not found then raise exception 'PROMO_NOT_FOUND'; end if;
  if award.status<>'cancelled' then raise exception 'PROMO_HIDE_ACTIVE'; end if;
  update public.demo_promo_attempts
    set owner_hidden_at=coalesce(owner_hidden_at,clock_timestamp())
    where id=award.id;
  return jsonb_build_object('hidden',true,'bookingId',p_booking);
end $$;

revoke all on function public.demo_promo_hide_award(uuid,boolean,uuid)
  from public,anon,authenticated;
grant execute on function public.demo_promo_hide_award(uuid,boolean,uuid)
  to service_role;

do $$
declare source text; old_clause text;
begin
  select pg_get_functiondef('public.demo_promo_action(uuid,boolean,text,jsonb)'::regprocedure) into source;
  old_clause:='where t.status<>''held'';';
  if position(old_clause in source)=0 then
    raise exception 'Unexpected promo status version';
  end if;
  source:=replace(source,old_clause,'where t.status<>''held'' and t.owner_hidden_at is null;');
  execute source;
end $$;
