const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const source = fs.readFileSync('web/demo-supabase.js', 'utf8');
const channels = [];
const fake = {
  channel(name) {
    const handlers = [];
    const channel = {
      on(_type, _filter, handler) { handlers.push(handler); return channel; },
      subscribe(onStatus) { onStatus('SUBSCRIBED'); channels.push({ name, handlers }); return channel; }
    };
    return channel;
  },
  removeChannel() {}
};

const context = { console, setTimeout, clearTimeout };
context.window = context;
vm.runInNewContext(source, context);
context.DemoData.configure({ client: fake });

(async () => {
  let calls = 0;
  let active = 0;
  let maxActive = 0;
  let releaseFirst;
  const firstRefresh = new Promise(resolve => { releaseFirst = resolve; });

  context.DemoData.subscribe('test', async () => {
    calls += 1;
    active += 1;
    maxActive = Math.max(maxActive, active);
    if (calls === 1) await firstRefresh;
    active -= 1;
  });

  channels[0].handlers.forEach(handler => handler({}));
  await Promise.resolve();
  assert.strictEqual(calls, 1, 'bursty events must not start overlapping refreshes');
  assert.strictEqual(maxActive, 1, 'at most one refresh may run at a time');

  releaseFirst();
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.strictEqual(calls, 2, 'bursty events should coalesce into one follow-up refresh');
  assert.strictEqual(maxActive, 1, 'the follow-up refresh must remain serialized');
  console.log('realtime subscription serialization: passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
