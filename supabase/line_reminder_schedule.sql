-- Internal polling only. Each booking has one reminder job; this does not
-- send a message every minute. LINE retry keys prevent duplicate delivery.
create extension if not exists pg_net with schema extensions;
select cron.schedule(
  'demo-send-line-notifications',
  '* * * * *',
  $cron$
  select net.http_post(
    url := 'https://YOUR-PROJECT.supabase.co/functions/v1/send-line-notifications',
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
