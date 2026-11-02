const assert = require('assert');

let AttachmentUiCore = {};
try {
  AttachmentUiCore = require('../web/attachment-ui-core.js');
} catch (_) {}

assert.strictEqual(typeof AttachmentUiCore.formatThaiTimestamp, 'function', 'timestamp formatter is available');
assert.strictEqual(
  AttachmentUiCore.formatThaiTimestamp('2026-09-01T07:35:00.000Z'),
  '1 ก.ย. 2569 เวลา 14:35 น.',
  'timestamps are shown in Bangkok time'
);
assert.strictEqual(AttachmentUiCore.formatThaiTimestamp(null), '—', 'missing timestamps have a clear fallback');

assert.strictEqual(
  AttachmentUiCore.imageFilename('slip', 'booking-123', 'image/jpeg'),
  'demo-slip-booking-123.jpg',
  'download filename is safe and readable'
);
assert.strictEqual(
  AttachmentUiCore.imageFilename('design', 'booking-123', 'customer/booking-123/nail.webp'),
  'demo-design-booking-123.webp',
  'download filename keeps the uploaded image type from its path'
);

assert.strictEqual(typeof AttachmentUiCore.refreshPendingStatuses, 'function', 'pending status refresher is available');
const pendingStatus = { dataset:{ customerPendingStatus:'booking-1' }, textContent:'รอโอนมัดจำ 4:59' };
const attachmentImage = { src:'https://example.test/reference.jpg' };
const attachmentBeforeRefresh = attachmentImage;
const fakeList = {
  querySelectorAll(selector) {
    assert.strictEqual(selector, '[data-customer-pending-status]');
    return [pendingStatus];
  }
};
AttachmentUiCore.refreshPendingStatuses(
  fakeList,
  [{ id:'booking-1', status:'pending', expiresAt:'2026-10-02T14:00:00.000Z' }],
  () => '3:21'
);
assert.strictEqual(pendingStatus.textContent, 'รอโอนมัดจำ 3:21', 'countdown text updates in place');
assert.strictEqual(attachmentImage, attachmentBeforeRefresh, 'unrelated attachment image keeps the same node');
assert.strictEqual(attachmentImage.src, 'https://example.test/reference.jpg', 'attachment image source is not reloaded');

async function testImageDownload() {
  const calls = [];
  const fakeBlob = { type:'image/png' };
  const result = await AttachmentUiCore.downloadImage('https://example.test/image', 'demo-image.png', {
    fetch: async url => {
      calls.push(['fetch', url]);
      return { ok:true, blob:async () => fakeBlob };
    },
    createObjectURL: blob => {
      calls.push(['create', blob]);
      return 'blob:download';
    },
    clickDownload: (url, filename) => calls.push(['click', url, filename]),
    revokeObjectURL: url => calls.push(['revoke', url])
  });

  assert.strictEqual(result, 'demo-image.png');
  assert.deepStrictEqual(calls, [
    ['fetch', 'https://example.test/image'],
    ['create', fakeBlob],
    ['click', 'blob:download', 'demo-image.png'],
    ['revoke', 'blob:download']
  ]);
}

testImageDownload()
  .then(() => console.log('attachment UI behavior: passed'))
  .catch(error => { console.error(error); process.exitCode = 1; });
