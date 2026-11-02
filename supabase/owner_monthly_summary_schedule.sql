-- Monthly summary to the owner's LINE: 1st of each month, 09:00 Bangkok (02:00 UTC).
select cron.schedule(
  'demo-owner-monthly-summary',
  '0 2 1 * *',
  $cron$
  select net.http_post(
    url := 'https://YOUR-PROJECT.supabase.co/functions/v1/owner-monthly-summary',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'sb_publishable_YOUR_KEY',
      'x-demo-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'demo_line_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $cron$
);
