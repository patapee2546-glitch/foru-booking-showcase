const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const context = {};
context.globalThis = context;
vm.runInNewContext(fs.readFileSync('web/receiver-core.js', 'utf8'), context);

const presentation = context.ReceiverCore.lineNotificationPresentation('booking-1', [
  { booking_id:'booking-1', notification_type:'booking_confirmed', status:'sent' },
  { booking_id:'booking-1', notification_type:'appointment_reminder', status:'pending' },
]);
assert.equal(presentation.linked, true);
assert.equal(presentation.confirmation, 'ส่งยืนยันแล้ว');
assert.equal(presentation.reminder, 'เตือนก่อนนัด: รอส่ง');

const failed = context.ReceiverCore.lineNotificationPresentation('booking-2', [
  { booking_id:'booking-2', notification_type:'booking_confirmed', status:'failed' },
  { booking_id:'booking-2', notification_type:'appointment_reminder', status:'cancelled' },
]);
assert.equal(failed.confirmation, 'ส่งยืนยันไม่สำเร็จ');
assert.equal(failed.reminder, 'เตือนก่อนนัด: ยกเลิกการส่ง');

const absent = context.ReceiverCore.lineNotificationPresentation('booking-3', []);
assert.equal(absent.linked, false);
assert.equal(absent.confirmation, 'ยังไม่มีงานยืนยัน');

console.log('merchant LINE status: passed');
