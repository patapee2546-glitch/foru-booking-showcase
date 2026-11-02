const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const calls = [];
const fake = {
  auth: {
    getSession: async () => ({ data:{ session:{ user:{ id:'customer-a' } } }, error:null }),
  },
  functions: {
    invoke: async (name, options) => {
      calls.push({ name, options });
      return { data:{ id:options.body.id, slot_date:options.body.date, start_time:'10:00:00', status:'pending' }, error:null };
    },
  },
  from: () => { throw new Error('browser must not insert bookings directly'); },
};

const context = {
  console,
  crypto:{ randomUUID:() => 'generated-id' },
  location:{ pathname:'/' },
  DEMO_CONFIG:{},
};
context.window = context;
context.globalThis = context;
vm.runInNewContext(fs.readFileSync('web/demo-supabase.js', 'utf8'), context);
context.DemoData.configure({ url:'https://example.supabase.co', publishableKey:'sb_publishable_test', client:fake });

(async () => {
  const booking = await context.DemoData.createPendingBooking({
    id:'20000000-0000-4000-8000-000000000001',
    date:'2026-09-08',
    start:'10:00',
    name:'Customer',
    phone:'081-234-5678',
    removalService:'gel',
    designImagePath:null,
    lineAccessToken:'fresh-line-token',
  });
  assert.equal(booking.start_time, '10:00');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, 'create-booking');
  assert.equal(calls[0].options.body.phone, '0812345678');
  assert.equal(calls[0].options.body.lineAccessToken, 'fresh-line-token');
  console.log('demo data create booking: passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
