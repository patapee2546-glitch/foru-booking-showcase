// node website/slot-status-core.test.js
const assert = require('assert');
const { forCustomer, holdCountdown } = require('../web/slot-status-core.js');
const now = Date.parse('2026-10-16T10:00:00Z');
assert.strictEqual(holdCountdown('2026-10-16T10:05:00Z', now), '5:00');
assert.strictEqual(holdCountdown('2026-10-16T10:04:31.2Z', now), '4:32'); // rounds up, never shows 0:00 while held
assert.strictEqual(holdCountdown('2026-10-16T10:00:00Z', now), '');
assert.strictEqual(holdCountdown(null, now), '');
assert.deepStrictEqual(forCustomer({ isOpen:true, isHeld:true, holdUntil:'2026-10-16T10:00:09Z', now }),
  { label:'มีคนกำลังชำระเงิน 0:09', className:'waiting', bookable:false });
assert.strictEqual(forCustomer({ isOpen:true, isHeld:true, now }).label, 'กำลังชำระเงิน');
assert.strictEqual(forCustomer({ isOpen:true, isBooked:true, isHeld:true, now }).label, 'เต็ม');
console.log('slot-status-core ok');
