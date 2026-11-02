from pathlib import Path

root = Path(__file__).resolve().parents[1]
sender = (root / 'web/index.html').read_text()
merchant = (root / 'web/merchant.html').read_text()

assert '<script src="attachment-ui-core.js"></script>' in sender
assert '<script src="attachment-ui-core.js"></script>' in merchant

assert 'ส่งคำจองเมื่อ' in sender
assert 'แนบสลิปเมื่อ' in sender
assert 'customerAttachmentModal' in sender
assert 'บันทึกรูป' in sender

assert 'ส่งคำจองเมื่อ' in merchant
assert 'แนบสลิปเมื่อ' in merchant
assert 'saveSlipImage' in merchant
assert 'บันทึกรูป' in merchant

print('attachment UI integration: passed')
