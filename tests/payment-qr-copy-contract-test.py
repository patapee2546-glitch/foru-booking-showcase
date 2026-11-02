from pathlib import Path

root = Path(__file__).resolve().parents[1]
deploy = root / 'web'
customer = (deploy / 'index.html').read_text()
qr = deploy / 'demo-payment-qr.png'

assert 'เลือกช่วงเวลาที่ต้องการจอง (1 คน/คิว)' in customer
assert 'src="demo-payment-qr.png"' in customer
deposit_title = '<div class="payment-deposit-title">มัดจำจองคิว <span data-shop="DEPOSIT">150</span> บาท</div>'
deposit_note = '<div class="payment-deposit-note">ส่วนที่เหลือชำระเงินเมื่อทำเสร็จค่ะ</div>'
assert deposit_title in customer
assert deposit_note in customer
assert customer.index(deposit_title) < customer.index(deposit_note) < customer.index('<div id="qrcode"></div>')
assert '.payment-deposit-title {' in customer
assert '.payment-deposit-note {' in customer
# showcase repo: the real shop QR is replaced by a placeholder, so only check it exists
assert qr.exists() and qr.stat().st_size > 1_000

print('payment QR and booking copy contract: passed')
