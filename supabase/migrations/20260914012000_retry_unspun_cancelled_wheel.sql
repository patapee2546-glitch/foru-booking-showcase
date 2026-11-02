begin;

create or replace function private.demo_award_post_slip()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
 candidate public.demo_booking_promo_candidates%rowtype;
 a public.demo_promo_attempts%rowtype;
 n int;
 random_byte int;
begin
 if new.status<>'approved' or old.status='approved' or nullif(new.slip_path,'') is null then return new; end if;
 select * into candidate from public.demo_booking_promo_candidates where booking_id=new.id;
 if not found or exists(select 1 from public.demo_booking_benefits where booking_id=new.id) then return new; end if;

 perform pg_advisory_xact_lock(hashtextextended('demo-inline-promo-campaign',0));
 perform 1 from public.demo_promo_campaigns where id=candidate.campaign_id and active for update;
 if not found then return new; end if;

 select * into a from public.demo_promo_attempts
  where campaign_id=candidate.campaign_id and line_user_id=candidate.line_user_id
  for update;
 if found and not (a.status='cancelled' and a.revealed_at is null) then return new; end if;

 select count(*) into n from public.demo_promo_attempts
  where campaign_id=candidate.campaign_id and status<>'cancelled'
   and (status<>'held' or expires_at>clock_timestamp());
 if n>=3 then
  update public.demo_promo_campaigns set active=false,closed_by_quota=true where id=candidate.campaign_id;
  return new;
 end if;

 if a.id is not null then
  -- Reuse the unique per-LINE attempt. The cancelled booking benefit remains as audit history.
  update public.demo_promo_attempts
   set status='confirmed',expires_at='infinity',booking_id=new.id
   where id=a.id returning * into a;
 else
  loop random_byte:=get_byte(extensions.gen_random_bytes(1),0);exit when random_byte<255;end loop;
  insert into public.demo_promo_attempts(campaign_id,line_user_id,percent,status,expires_at,booking_id)
   values(candidate.campaign_id,candidate.line_user_id,5*(1+random_byte%3),'confirmed','infinity',new.id)
   returning * into a;
 end if;

 insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent,status)
  values(new.id,candidate.line_user_id,'wheel',a.id,a.percent,'confirmed');
 if n+1>=3 then
  update public.demo_promo_campaigns set active=false,closed_by_quota=true where id=candidate.campaign_id;
 end if;
 return new;
end
$function$;

revoke all on function private.demo_award_post_slip() from public,anon,authenticated;

commit;
