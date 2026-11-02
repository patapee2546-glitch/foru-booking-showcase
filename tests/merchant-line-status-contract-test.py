from pathlib import Path

html = Path('web/merchant.html').read_text(encoding='utf-8')
data = Path('web/demo-supabase.js').read_text(encoding='utf-8')
core = Path('web/receiver-core.js').read_text(encoding='utf-8')

for required in ['LINE เชื่อมแล้ว', 'เตือนก่อนนัด', 'listMerchantLineNotifications']:
    assert required in html or required in data or required in core, required
assert "table:'demo_line_notifications'" in data
assert 'recipient_line_user_id' not in html
select_start = data.index("const columns = 'id,booking_id,notification_type")
select_end = data.index("';", select_start)
assert 'recipient_line_user_id' not in data[select_start:select_end]

print('merchant LINE status contract: passed')
