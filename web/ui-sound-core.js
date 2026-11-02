(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.UISoundCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  const PATTERNS = Object.freeze({
    tap: Object.freeze([{ frequency:420, duration:0.035, delay:0 }]),
    select: Object.freeze([{ frequency:590, duration:0.055, delay:0 }]),
    heartbeat: Object.freeze([
      { frequency:180, endFrequency:75, volume:0.04, duration:0.16, delay:0 },
      { frequency:150, endFrequency:65, volume:0.03, duration:0.14, delay:0.22 },
    ]),
    success: Object.freeze([
      { frequency:560, duration:0.07, delay:0 },
      { frequency:760, duration:0.09, delay:0.075 },
    ]),
    close: Object.freeze([{ frequency:280, duration:0.045, delay:0 }]),
  });

  function patternFor(action) {
    return (PATTERNS[action] || PATTERNS.tap).map(tone => ({ ...tone }));
  }

  function createController(options) {
    const config = options || {};
    const storage = config.storage || null;
    const AudioContextClass = config.AudioContextClass || null;
    const key = 'demo-customer-sound';
    let enabled = true;
    let context = null;
    try { enabled = storage?.getItem(key) !== 'off'; } catch (_) {}

    function isEnabled() { return enabled; }
    function toggle() {
      enabled = !enabled;
      try { storage?.setItem(key, enabled ? 'on' : 'off'); } catch (_) {}
      return enabled;
    }
    function play(action) {
      if (!enabled || !AudioContextClass) return false;
      try {
        context = context || new AudioContextClass();
        const schedule = () => {
          const now = context.currentTime;
          patternFor(action).forEach(tone => {
            const oscillator = context.createOscillator();
            const gain = context.createGain();
            const start = now + tone.delay;
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(tone.frequency, start);
            if (tone.endFrequency) oscillator.frequency.exponentialRampToValueAtTime(tone.endFrequency, start + tone.duration);
            gain.gain.setValueAtTime(0.0001, start);
            gain.gain.exponentialRampToValueAtTime(tone.volume || 0.025, start + 0.008);
            gain.gain.exponentialRampToValueAtTime(0.0001, start + tone.duration);
            oscillator.connect(gain);
            gain.connect(context.destination);
            oscillator.start(start);
            oscillator.stop(start + tone.duration + 0.01);
          });
          return true;
        };
        if (context.state === 'suspended') return Promise.resolve(context.resume()).then(schedule).catch(() => false);
        schedule();
        return true;
      } catch (_) { return false; }
    }
    return { isEnabled, toggle, play };
  }

  return { patternFor, createController };
});
