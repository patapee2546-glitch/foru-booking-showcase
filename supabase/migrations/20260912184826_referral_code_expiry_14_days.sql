-- Keep the customer-facing terms and enforcement in sync: friend codes are
-- redeemable for 14 days, while referral credits retain their existing 60-day expiry.
do $$
declare
 source text;
 old_expiry constant text := 'clock_timestamp()+interval ''30 days''';
 new_expiry constant text := 'clock_timestamp()+interval ''14 days''';
begin
 source := pg_get_functiondef('public.demo_promo_action(uuid,boolean,text,jsonb)'::regprocedure);
 if position(old_expiry in source)=0 then
  raise exception 'Unexpected referral code expiry implementation';
 end if;
 execute replace(source,old_expiry,new_expiry);
end $$;

-- Existing unused codes should follow the published 14-day condition too.
update public.demo_referral_codes
set expires_at=least(expires_at,created_at+interval '14 days')
where not revoked and redeemed_at is null and completed_at is null;
