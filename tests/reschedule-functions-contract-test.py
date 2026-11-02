from pathlib import Path

functions = {
    name: Path(f'supabase/functions/{name}/index.ts')
    for name in (
        'create-reschedule-request',
        'submit-reschedule-slip',
        'review-reschedule-request',
        'cancel-reschedule-request',
        'expire-reschedule-requests',
    )
}

for name, path in functions.items():
    assert path.exists(), f'missing Edge Function: {name}'
    source = path.read_text()
    assert "import { withSupabase } from '@supabase/server'" in source, f'{name} must use pinned server wrapper import map'
    assert "req.method !== 'POST'" in source, f'{name} must reject non-POST requests'
    assert Path(path.parent / 'deno.json').exists(), f'{name} missing import map'

create = functions['create-reschedule-request'].read_text()
for needle in ("withSupabase({ auth: 'user' }", "rpc('create_demo_reschedule'", 'p_customer_id: userId', '23505', 'NEW_SLOT_UNAVAILABLE'):
    assert needle in create, f'create request missing: {needle}'

submit = functions['submit-reschedule-slip'].read_text()
for needle in ("withSupabase({ auth: 'user' }", "from('demo-reschedule-slips')", "startsWith(`${userId}/${requestId}/`)", "rpc('submit_demo_reschedule_slip'", "p_customer_id: userId"):
    assert needle in submit, f'submit slip missing: {needle}'

review = functions['review-reschedule-request'].read_text()
for needle in ('ctx.jwtClaims?.app_metadata', "appMetadata?.role !== 'owner'", "rpc('review_demo_reschedule'", "decision !== 'approve' && decision !== 'reject'"):
    assert needle in review, f'review request missing: {needle}'

cancel = functions['cancel-reschedule-request'].read_text()
for needle in ("withSupabase({ auth: 'user' }", ".eq('customer_id', userId)", ".in('status', ['awaiting_slip', 'pending_review'])", "status: 'cancelled'", "from('demo_slots')"):
    assert needle in cancel, f'cancel request missing: {needle}'

expire = functions['expire-reschedule-requests'].read_text()
for needle in ("withSupabase({ auth: 'none' }", "Deno.env.get('RESCHEDULE_CRON_SECRET')", "rpc('expire_demo_reschedules'"):
    assert needle in expire, f'expire request missing: {needle}'

for name, path in functions.items():
    deno = (path.parent / 'deno.json').read_text()
    assert 'npm:@supabase/server@1.4.1' in deno, f'{name} must pin @supabase/server'

print('reschedule functions contract: passed')
