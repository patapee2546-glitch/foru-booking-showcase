from pathlib import Path


migrations = Path('supabase/migrations')
matches = list(migrations.glob('*_reschedule_before_appointment_day.sql'))
assert len(matches) == 1, 'missing reschedule-before-appointment-day migration'

sql = matches[0].read_text()
guard = "(now() at time zone 'Asia/Bangkok')::date >= b.slot_date"
assert sql.count(guard) == 2, 'create and submit must both block on the appointment day'
assert 'RESCHEDULE_DEADLINE_PASSED' in sql
assert "interval '6 hours'" not in sql

print('reschedule before appointment day SQL contract: passed')
