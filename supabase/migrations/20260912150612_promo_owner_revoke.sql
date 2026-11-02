alter table public.demo_promo_attempts drop constraint demo_promo_attempts_status_check;
alter table public.demo_promo_attempts add constraint demo_promo_attempts_status_check
 check(status=any(array['held'::text,'confirmed'::text,'consumed'::text,'cancelled'::text]));

create function public.demo_promo_revoke_award(p_customer uuid,p_owner boolean,p_booking uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a public.demo_promo_attempts%rowtype; benefit_status text; code_row public.demo_referral_codes%rowtype;
begin
 if p_customer is null or not coalesce(p_owner,false) then raise exception 'OWNER_REQUIRED'; end if;
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
end $$;
revoke all on function public.demo_promo_revoke_award(uuid,boolean,uuid) from public,anon,authenticated;
grant execute on function public.demo_promo_revoke_award(uuid,boolean,uuid) to service_role;

do $$
declare source text;
begin
 select pg_get_functiondef(p.oid) into source from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='demo_promo_action';
 if position('''status'',booking.status' in source)=0 then raise exception 'Unexpected promo action version'; end if;
 source:=replace(source,'''status'',booking.status','''status'',case when t.status=''cancelled'' then ''cancelled'' else booking.status end');
 execute source;
end $$;
