from pathlib import Path

root = Path(__file__).resolve().parents[1]
deploy = root / 'web'
adapter = (deploy / 'demo-supabase.js').read_text()
customer = (deploy / 'index.html').read_text()
merchant = (deploy / 'merchant.html').read_text()

for token in (
    'listMyRescheduleRequests', 'createRescheduleRequest', 'uploadRescheduleSlip',
    'submitRescheduleSlip', 'reviewRescheduleRequest', 'getRescheduleSlipUrl',
    "table:'demo_reschedule_requests'",
):
    assert token in adapter, f'missing adapter contract: {token}'

for token in (
    'startRescheduleSelection', 'state.rescheduleBookingId', 'showReschedulePaymentForSlot',
    'submitRescheduleRequest', 'เลื่อนคิว (+20 บาท)',
    'ต้องเลื่อนก่อนวันนัด และชำระเพิ่ม 20 บาท', 'reschedule-core.js',
):
    assert token in customer, f'missing customer reschedule UI: {token}'

for token in (
    'reviewReschedule', 'loadRescheduleSlipThumbnails', 'สลิปค่าเลื่อนคิว 20 บาท',
    'อนุมัติเลื่อนคิว', 'ไม่อนุมัติ', 'reschedule-core.js',
    'rescheduleInboxButton', 'rescheduleInboxCount', 'renderRescheduleInbox',
    'openRescheduleInbox', 'openRescheduleRequest', 'รายการเลื่อนคิว',
    'คำขอเลื่อนคิว',
):
    assert token in merchant, f'missing merchant reschedule UI: {token}'

for token in (
    'bookingInboxButton', 'bookingInboxCount', 'renderBookingInbox',
    'openBookingInbox', 'openBookingRequestDate', 'bookingAlertRange', 'คำขอจองคิว',
    'aria-label="คำขอจองคิว"',
    'item.date>=today',
):
    assert token in merchant, f'missing booking notification inbox: {token}'

print('reschedule UI contract: passed')
