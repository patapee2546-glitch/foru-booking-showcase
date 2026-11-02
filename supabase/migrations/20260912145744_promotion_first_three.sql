-- Change only quota checks/counters. Never rewrite or revoke existing rewards.
do $$
declare f record; definition text;
begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='public' and p.proname in ('demo_promo_action','demo_promo_action_legacy'))
     or (n.nspname='private' and p.proname='demo_award_post_slip') loop
  definition:=pg_get_functiondef(f.oid);
  definition:=replace(definition,'if n>=5','if n>=3');
  definition:=replace(definition,'greatest(0,5-','greatest(0,3-');
  execute definition;
 end loop;
end $$;
