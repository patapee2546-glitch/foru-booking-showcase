alter table public.demo_referral_codes
  add column customer_hidden_at timestamptz,
  add column owner_hidden_at timestamptz;

create function public.demo_promo_hide_code(p_customer uuid,p_owner boolean,p_code text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_line text; r public.demo_referral_codes%rowtype;
begin
  if p_customer is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(p_owner,false) then
    select * into r from public.demo_referral_codes where code=upper(btrim(p_code)) for update;
  else
    select line_user_id into v_line from public.demo_line_links where customer_id=p_customer;
    if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
    select * into r from public.demo_referral_codes
      where code=upper(btrim(p_code)) and owner_line_user_id=v_line for update;
  end if;
  if not found then raise exception 'PROMO_CODE'; end if;
  if not r.revoked and r.expires_at>clock_timestamp() then raise exception 'PROMO_HIDE_ACTIVE'; end if;
  if coalesce(p_owner,false) then
    update public.demo_referral_codes set owner_hidden_at=clock_timestamp() where id=r.id;
  else
    update public.demo_referral_codes set customer_hidden_at=clock_timestamp() where id=r.id;
  end if;
  return jsonb_build_object('hidden',true,'code',r.code);
end $$;
revoke all on function public.demo_promo_hide_code(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.demo_promo_hide_code(uuid,boolean,text) to service_role;

do $$
declare source text; customer_clause text; owner_clause text;
begin
  select pg_get_functiondef('public.demo_promo_action(uuid,boolean,text,jsonb)'::regprocedure) into source;
  customer_clause:='where rc.owner_line_user_id=v_line;';
  owner_clause:='left join public.demo_booking_benefits f on f.booking_id=rc.redeemed_booking_id';
  if position(customer_clause in source)=0 or position(owner_clause||';' in source)=0 then
    raise exception 'Unexpected promo status version';
  end if;
  source:=replace(source,customer_clause,'where rc.owner_line_user_id=v_line and rc.customer_hidden_at is null;');
  source:=replace(source,owner_clause||';',owner_clause||E'\n   where rc.owner_hidden_at is null;');
  execute source;
end $$;
