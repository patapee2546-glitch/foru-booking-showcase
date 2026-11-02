from pathlib import Path

link = Path('supabase/functions/link-line-customer/index.ts').read_text(encoding='utf-8')
create = Path('supabase/functions/create-booking/index.ts').read_text(encoding='utf-8')
worker = Path('supabase/functions/send-line-notifications/index.ts').read_text(encoding='utf-8')

for code in (link, create):
    assert "withSupabase({ auth:'user' }" in code or "withSupabase({ auth: 'user' }" in code
    assert "Deno.env.get('LINE_LOGIN_CHANNEL_ID')" in code
    assert "auth:'none'" not in code and "auth: 'none'" not in code

assert 'verifyLineIdToken' in link and 'verifyLineAccess' in link
body_fields = link.split('type Body =', 1)[1].split('\n', 1)[0]
assert 'lineUserId' not in body_fields  # never trust a browser-provided LINE user ID
assert 'verifyLineAccess' in create
assert "Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN')" in worker
assert "Deno.env.get('LINE_CRON_SECRET')" in worker

for code in (link, create, worker):
    assert 'SUPABASE_SERVICE_ROLE_KEY' not in code
    assert 'LINE_CHANNEL_ACCESS_TOKEN =' not in code

print('LINE Edge Function security contract: passed')
