const assert = require('node:assert/strict');
require('../web/reschedule-core.js');
const b = {status:'approved', date:'2026-09-12', time:'17:00'};
const appointmentDay = Date.parse('2026-09-12T00:00:00+07:00');
assert.equal(RescheduleCore.canReschedule(b, appointmentDay-1), true);
assert.equal(RescheduleCore.canReschedule(b, appointmentDay), false);
assert.equal(RescheduleCore.canReschedule({...b,status:'pending'}, appointmentDay-1), false);
assert.match(RescheduleCore.customerAction(b,appointmentDay).reason,/ก่อนวันนัด/);
console.log('day-before boundary tests passed');
