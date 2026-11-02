from pathlib import Path


sender = Path("web/index.html").read_text(encoding="utf-8")

required = [
    'name="removalService"',
    'aria-required="true"',
    'name="removalService" value="gel" required aria-required="true"',
    'value="gel"',
    'value="pvc"',
    'value="none"',
    'ล้างเล็บเจล',
    'ล้างพีวีซี',
    'ไม่มี',
    'ชื่อ <span class="required-mark">(จำเป็น)</span>',
    'เบอร์โทรศัพท์ <span class="required-mark">(จำเป็น)</span>',
    'กรุณากรอกเบอร์โทรศัพท์ให้ถูกต้อง 9–10 หลัก',
    'ร้านตัวอย่าง กรุงเทพฯ',
    'function backToBookingForm()',
    'id="paymentSlipInput"',
    'accept="image/jpeg,image/png,image/webp"',
    'id="paymentSlipPreview"',
    'แนบสลิปและยืนยันคิว',
    'updatePaymentConfirmationState();',
    "document.getElementById('selectedTimesDisplay').style.display = 'none';",
    "document.getElementById('selectedTimesDisplay').innerHTML = '';",
    'submitButton.disabled = true;',
    "state.currentPendingDraft = null;",
    'function bookingDraftSignature',
    'function setPendingDraft(signature, bookings)',
    'function pendingDraftBookings(draft)',
    'state.currentPendingDraft = { signature, bookings: [...bookings] };',
    'if (state.currentPendingDraft?.signature === draftSignature)',
    'newBookings = pendingDraftBookings(state.currentPendingDraft);',
    'setPendingDraft(draftSignature, newBookings);',
    'setPendingDraft(draftSignature, [booking]);',
    'clearPendingDraft();',
    "file.size > 5 * 1024 * 1024",
    "['image/jpeg', 'image/png', 'image/webp']",
    'removalService: removalService',
    'removalService:booking.removal_service',
    'slipPath:booking.slip_path',
    'slipUploadedAt:booking.slip_uploaded_at',
    'cancelledAt:booking.cancelled_at',
    'cancelledByRole:booking.cancelled_by_role',
    'refundStatus:booking.refund_status',
    'DemoData.uploadPaymentSlip(booking.id, file)',
    'DemoData.claimBooking(booking.id, slipPath)',
    'รอบนี้มีผู้จองแล้ว',
    'await refreshRealtimeData()',
    'ได้คิวแล้ว',
    'แนบสลิปแล้ว',
    'ยกเลิกคิว',
    'function cancelCustomerBooking(id)',
    'DemoData.cancelBooking(id)',
    'ยกเลิกแล้ว — คืนเงินมัดจำ',
    'แคปภาพหน้านี้แล้วติดต่อ LINE @demoshop',
    'ยกเลิกแล้ว — ไม่คืนเงินมัดจำ',
    'ยกเลิกก่อนเวลานัดอย่างน้อย 48 ชม. คืนเงินมัดจำ หากเหลือน้อยกว่า 48 ชม. ขอสงวนสิทธิ์ไม่คืนเงิน',
    'ยกเลิกก่อนเวลานัดอย่างน้อย 48 ชั่วโมง คืนเงินมัดจำ หากน้อยกว่า 48 ชั่วโมง ขอสงวนสิทธิ์ไม่คืนมัดจำ',
    '${esc(booking.name)}',
    '${esc(booking.phone)}',
]

missing = [item for item in required if item not in sender]
assert not missing, f"customer payment flow missing contracts: {missing}"

forbidden = [
    'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
    'id="specialRequest"',
    'specialRequest',
    'id="lineLink"',
    'lineMessage',
    'ส่งสลิปผ่าน LINE',
    'โอนมัดจำเรียบร้อยแล้ว',
    'function markDepositPaid',
    'ร้านตัวอย่าง ทำเล็บทุกลาย',
    'โซนตัวอย่าง กรุงเทพฯ',
    'function updateOwnerPanel()',
    "onclick=\"approveBooking('${date}', '${booking.phone}')\"",
    "onclick=\"rejectBooking('${date}', '${booking.phone}')\"",
    'state.currentPendingDraft = { signature:draftSignature, ids:',
]

present = [item for item in forbidden if item in sender]
assert not present, f"customer payment flow retains forbidden legacy contracts: {present}"

upload_index = sender.index('DemoData.uploadPaymentSlip(booking.id, file)')
claim_index = sender.index('DemoData.claimBooking(booking.id, slipPath)')
refresh_index = sender.index('await refreshRealtimeData()', claim_index)
assert upload_index < claim_index < refresh_index, "slip must upload before claim and authoritative refresh"

open_start = sender.index('function openTimeModal(dateStr)')
open_end = sender.index('function toggleTimeSelection', open_start)
open_body = sender[open_start:open_end]
assert 'resetSelectedTimesUI();' in open_body, "opening a form must synchronize cleared selection UI"

clear_start = sender.index('function clearTemporaryBookingFlow()')
clear_end = sender.index('function closeTimeModal()', clear_start)
clear_body = sender[clear_start:clear_end]
assert 'resetSelectedTimesUI();' in clear_body, "clearing a flow must synchronize selection UI"
assert 'clearPendingDraft();' in clear_body, "closing a flow must deliberately clear its pending draft"

submit_start = sender.index('async function submitBooking()')
reuse_guard = sender.index('if (state.currentPendingDraft?.signature === draftSignature)', submit_start)
create_call = sender.index('DemoData.createPendingBooking(', submit_start)
assert reuse_guard < create_call, "matching pending draft must be reused before any new insert"

refresh_after_insert = sender.index('await refreshRealtimeData()', create_call)
new_record = sender.index('const newBooking = {', create_call)
push_record = sender.index('newBookings.push(newBooking);', new_record)
persist_record = sender.index('setPendingDraft(draftSignature, newBookings);', push_record)
assert create_call < new_record < push_record < persist_record < refresh_after_insert, \
    "each normalized inserted row must persist locally before another insert or refetch can fail"

resume_start = sender.index('function resumePendingPayment(id)')
resume_end = sender.index('async function submitPaymentSlip()', resume_start)
resume_body = sender[resume_start:resume_end]
resume_signature = resume_body.index('const draftSignature = bookingDraftSignature(')
resume_seed = resume_body.index('setPendingDraft(draftSignature, [booking]);')
resume_payment = resume_body.index('showPaymentModal({')
assert resume_signature < resume_seed < resume_payment, \
    "resumed pending booking must seed the reusable full-record draft before payment"

purge_start = sender.index('function purgeExpiredPendingBookings()')
purge_end = sender.index('function renderCalendar()', purge_start)
assert 'clearPendingDraft();' in sender[purge_start:purge_end], "expiry must deliberately clear the pending draft"

claim_start = sender.index('async function submitPaymentSlip()')
claim_end = sender.index('function pendingRemainingLabel', claim_start)
assert 'clearPendingDraft();' in sender[claim_start:claim_end], "completed claim processing must deliberately clear the pending draft"

print("customer payment flow contract: passed")
