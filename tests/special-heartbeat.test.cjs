const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sound = require('../web/ui-sound-core.js');
const html = fs.readFileSync('web/index.html', 'utf8');
const source = html.slice(html.indexOf('  function customerSoundAction('), html.indexOf("  document.addEventListener('click', handleCustomerButtonSound);"));
const played = [];
const context = { customerSounds: { play: action => played.push(action) } };
vm.createContext(context);
vm.runInContext(source, context);
function click(classes, disabled = false) {
  const button = { textContent: '13:30–16:00 ว่าง', dataset: {}, disabled,
    matches: selectors => selectors.split(',').some(s => classes.includes(s.slice(1))) };
  context.handleCustomerButtonSound({ target: { closest: () => button } });
}
click(['mobile-time-row', 'promo-special-slot']);
assert.deepEqual(played, ['heartbeat'], 'special slot plays one heartbeat, not the normal click too');
click(['mobile-time-row']);
assert.deepEqual(played, ['heartbeat', 'select'], 'normal slot retains selection sound');
click(['mobile-time-row', 'promo-special-slot'], true);
assert.equal(played.length, 2, 'disabled special slot remains silent');
const starts = [], stops = [];
class AudioContext {
  state = 'running'; currentTime = 0; destination = {};
  createOscillator() { return { frequency: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {}, start: t => starts.push(t), stop: t => stops.push(t) }; }
  createGain() { return { gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {} }; }
}
sound.createController({AudioContextClass:AudioContext}).play('heartbeat');
assert.equal(starts.length, 2, 'heartbeat schedules exactly two beats');
assert.ok(starts[1] > starts[0] && starts[1] < .4);
assert.ok(stops.every(t => t < .7), 'heartbeat ends quickly without looping');
console.log('PASS special heartbeat routing and finite double beat');
