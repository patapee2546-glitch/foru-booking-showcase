const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../web/demo-supabase.js'), 'utf8');
const memory = () => { const m = new Map(); return { getItem: k => m.has(k) ? m.get(k) : null, setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) }; };

let storage;
const window = {
  location: { pathname: '/merchant.html' },
  localStorage: memory(), sessionStorage: memory(),
  DEMO_CONFIG: { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' },
  supabase: { createClient(_u, _k, options) { storage = options.auth.storage; return { auth: {} }; } },
};
vm.runInNewContext(source, { window, globalThis: window });
const data = window.DemoData;

data.setOwnerRemember(true);
storage.setItem('s', 'a');
assert.equal(window.localStorage.getItem('s'), 'a', 'remembered session must survive closing the browser');

data.setOwnerRemember(false);
storage.setItem('s', 'b');
assert.equal(window.localStorage.getItem('s'), null, 'unticked must not leave the session in localStorage');
assert.equal(storage.getItem('s'), 'b');

storage.removeItem('s');
assert.equal(storage.getItem('s'), null);
console.log('owner remember-me: passed');
