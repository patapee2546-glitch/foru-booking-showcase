const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const calls = [];
const holidays = [{ day:'2026-10-05' }];
const client = {
  from(table) {
    assert.equal(table, 'demo_holidays');
    return { select(columns) {
      assert.equal(columns, 'day');
      return { gte(column, from) {
        assert.equal(column, 'day');
        return { lte(column2, to) {
          assert.equal(column2, 'day');
          calls.push({ type:'list', from, to });
          return Promise.resolve({ data:holidays, error:null });
        } };
      } };
    } };
  },
  rpc(name, args) {
    calls.push({ type:'rpc', name, args });
    return Promise.resolve({ data:true, error:null });
  },
  auth:{ getSession:() => Promise.resolve({ data:{ session:{ user:{ id:'owner-1' } } }, error:null }) }
};
const context = { window:{ location:{ pathname:'/merchant.html' } }, crypto, console };
context.window.window = context.window;
vm.runInNewContext(fs.readFileSync('web/demo-supabase.js','utf8'), context);
const api = context.window.DemoData;
api.configure({ client });
(async () => {
  const days = await api.listHolidays('2026-10-01','2026-10-31');
  assert.deepEqual(Array.from(days, item=>item.day), ['2026-10-05']);
  await api.setHoliday('2026-10-05', true);
  await api.setHoliday('2026-10-05', false);
  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [
    { type:'list', from:'2026-10-01', to:'2026-10-31' },
    { type:'rpc', name:'demo_set_holiday', args:{ p_day:'2026-10-05', p_closed:true } },
    { type:'rpc', name:'demo_set_holiday', args:{ p_day:'2026-10-05', p_closed:false } },
  ]);
  console.log('holiday adapter: passed');
})().catch(error=>{ console.error(error); process.exitCode=1; });
