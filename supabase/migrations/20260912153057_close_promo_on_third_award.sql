-- The campaign row is already locked by the award trigger, so closing it in
-- the same transaction makes the third award the single authoritative cutoff.
do $$
declare source text; old_guard text; old_tail text;
begin
  select pg_get_functiondef('private.demo_award_post_slip()'::regprocedure) into source;
  old_guard:='if n>=3 then return new; end if;';
  old_tail:='insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent,status)
  values(new.id,candidate.line_user_id,''wheel'',a.id,a.percent,''confirmed'');
 return new;';
  if position(old_guard in source)=0 or position(old_tail in source)=0 then
    raise exception 'Unexpected award trigger version';
  end if;
  source:=replace(source,old_guard,
    'if n>=3 then
   update public.demo_promo_campaigns set active=false where id=candidate.campaign_id;
   return new;
  end if;');
  source:=replace(source,old_tail,
    'insert into public.demo_booking_benefits(booking_id,line_user_id,kind,source_id,percent,status)
  values(new.id,candidate.line_user_id,''wheel'',a.id,a.percent,''confirmed'');
 if n+1>=3 then
  update public.demo_promo_campaigns set active=false where id=candidate.campaign_id;
 end if;
 return new;');
  execute source;
end $$;

-- Close any campaign that had already reached three before this migration.
update public.demo_promo_campaigns c
set active=false
where c.active
  and 3 <= (select count(*) from public.demo_promo_attempts a
            where a.campaign_id=c.id
              and (a.status<>'held' or a.expires_at>clock_timestamp()));
