from pathlib import Path


customer_path = (
    Path(__file__).resolve().parents[1]
    / 'web'
    / "index.html"
)
customer = customer_path.read_text()

modal_start = customer.index("function ensureRescheduleModal()")
modal_end = customer.index("function startRescheduleSelection", modal_start)
modal = customer[modal_start:modal_end]

assert 'class="reschedule-payment-qr"' in modal
assert 'src="reschedule-payment-qr.png"' in modal
assert 'alt="QR Code สำหรับชำระค่าเลื่อนคิว 20 บาท"' in modal
assert 'กรุณากรอกยอด 20 บาทก่อนยืนยันการโอน' not in modal
assert 'class="reschedule-policy"' in modal
assert 'เลื่อนคิวได้ก่อนวันนัด (ก่อน 00.00 น.) มีค่าดำเนินการ 20 บาท' in modal
assert 'ไม่สามารถเลื่อนคิวภายในวันนัดได้' in modal
assert 'ยกเลิกก่อนเวลานัดอย่างน้อย 48 ชั่วโมง รับเงินมัดจำคืน' in modal
assert 'ยกเลิกน้อยกว่า 48 ชั่วโมง ขอสงวนสิทธิ์ไม่คืนเงินมัดจำ' in modal
assert modal.index('class="reschedule-policy"') < modal.index('class="reschedule-payment-qr"')
assert modal.index('src="reschedule-payment-qr.png"') < modal.index('id="rescheduleSlip"')

asset = customer_path.parent / 'reschedule-payment-qr.png'
assert asset.exists()
assert asset.stat().st_size > 1_000

print("reschedule payment QR contract: passed")
