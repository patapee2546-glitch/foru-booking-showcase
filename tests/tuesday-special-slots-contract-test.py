from pathlib import Path

root = Path(__file__).resolve().parents[1]
customer = (root / 'web/index.html').read_text()
config = (root / 'web/demo-config.js').read_text()
data = (root / 'web/demo-supabase.js').read_text()
schema = (root / 'supabase/schema.sql').read_text()
edge = (root / 'supabase/functions/create-reschedule-request/index.ts').read_text()

for value in ('15:00', '17:30', '19:00', '21:00'):
    assert value in config, f'shop config schedule missing {value}'
    assert value in schema, f'database constraint missing {value}'

assert 'DEMO_CONFIG?.SLOTS' in data, 'data period mapping must come from shop config'

for value in ('15:00', '19:00'):
    assert value in edge, f'reschedule function missing {value}'

assert 'bookingSlotsForDate' in customer, 'customer must choose slots by date'
print('Tuesday special slots contract: passed')
