const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const calls = [];
let queryResult;
const rows = [{
  id:'notice-1', booking_id:'booking-1', notification_type:'booking_confirmed',
  scheduled_for:'2026-09-08T03:00:00Z', status:'sent', attempt_count:1,
  last_error:null, sent_at:'2026-09-05T03:00:00Z', demo_bookings:{ slot_date:'2026-09-08' },
}];
queryResult = { data:rows, error:null };

function query() {
  const chain = {
    select(columns) { calls.push(['select', columns]); return chain; },
    gte(column, value) { calls.push(['gte', column, value]); return chain; },
    lte(column, value) { calls.push(['lte', column, value]); return chain; },
    order(column, options) {
      calls.push(['order', column, options]);
      return Promise.resolve(queryResult);
    },
  };
  return chain;
}

const fake = { from(table) { calls.push(['from', table]); return query(); } };
const context = { console, location:{ pathname:'/merchant.html' }, DEMO_CONFIG:{} };
context.window = context;
context.globalThis = context;
vm.runInNewContext(fs.readFileSync('web/demo-supabase.js', 'utf8'), context);
context.DemoData.configure({ url:'https://example.supabase.co', publishableKey:'sb_publishable_test', client:fake });

(async () => {
  const result = await context.DemoData.listMerchantLineNotifications('2026-09-01', '2026-09-30');
  assert.equal(result.length, 1);
  assert.deepEqual(calls[0], ['from', 'demo_line_notifications']);
  assert.ok(calls[1][1].includes('booking_id'));
  assert.ok(!calls[1][1].includes('recipient_line_user_id'));
  assert.deepEqual(calls[2], ['gte', 'demo_bookings.slot_date', '2026-09-01']);
  assert.deepEqual(calls[3], ['lte', 'demo_bookings.slot_date', '2026-09-30']);

  queryResult = {
    data:null,
    error:{ code:'PGRST205', message:"Could not find the table 'public.demo_line_notifications' in the schema cache" },
  };
  const beforeMigration = await context.DemoData.listMerchantLineNotifications('2026-09-01', '2026-09-30');
  assert.deepEqual(beforeMigration, [], 'calendar remains usable before the optional LINE migration is deployed');
  console.log('demo merchant LINE notifications: passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
