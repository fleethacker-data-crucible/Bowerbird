// Spoken progress (Web/voice.js) against a fake clock and a fake speech synthesizer. Node is CI-only here,
// never required on the managed workstation; the in-browser behaviour needs a hand check (docs/VOICE.md).
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const voice = require('../Web/voice.js');

new (require('vm').Script)(fs.readFileSync(path.join(__dirname, '..', 'Web', 'voice.js'), 'utf8'), { filename: 'Web/voice.js' });

// A scheduler we drive by hand.
function fakeClock() {
  let time = 0, nextId = 1;
  const timers = new Map();
  return {
    now: () => time,
    setTimeout: (fn, ms) => { const id = nextId++; timers.set(id, { at: time + ms, fn }); return id; },
    clearTimeout: id => { timers.delete(id); },
    pending: () => timers.size,
    advance(ms) {
      const target = time + ms;
      for (;;) {
        let best = null;
        for (const [id, t] of timers) if (t.at <= target && (!best || t.at < best.t.at)) best = { id, t };
        if (!best) break;
        timers.delete(best.id);
        time = best.t.at;
        best.t.fn();
      }
      time = target;
    }
  };
}
function fakeSynth(voices) {
  const spoken = [];
  return {
    spoken,
    cancelled: 0,
    getVoices: () => voices,
    speak(u) { spoken.push(u); },
    cancel() { this.cancelled++; }
  };
}
function Utterance(text) { this.text = text; }
const LOCAL = { name: 'Local English', lang: 'en-US', localService: true };
const CLOUD = { name: 'Online English', lang: 'en-US', localService: false };
function setup(opts) {
  opts = opts || {};
  const clock = fakeClock();
  const synth = opts.noSynth ? null : fakeSynth(opts.voices || [CLOUD, LOCAL]);
  const status = [];
  const state = { enabled: opts.enabled !== false };
  const progress = voice.create({
    synth, Utterance: opts.noSynth ? null : Utterance, lang: 'en-US', now: clock.now, setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout, isEnabled: () => state.enabled, onStatus: t => status.push(t)
  });
  return { clock, synth, status, state, progress };
}

// Voice choice: only local voices, page language first.
{
  const voices = [
    CLOUD,
    { name: 'Local German', lang: 'de-DE', localService: true },
    { name: 'Local English UK', lang: 'en-GB', localService: true },
    LOCAL
  ];
  assert.strictEqual(voice.pickLocalVoice(voices, 'en-US').name, 'Local English');
  assert.strictEqual(voice.pickLocalVoice(voices, 'en-AU').name, 'Local English UK');
  assert.strictEqual(voice.pickLocalVoice(voices, 'fr-FR').name, 'Local German');
  assert.strictEqual(voice.pickLocalVoice([CLOUD], 'en-US'), null, 'cloud voices only: none chosen');
  assert.strictEqual(voice.pickLocalVoice([], 'en-US'), null);
  assert.strictEqual(voice.pickLocalVoice([{ name: 'Unknown', lang: 'en-US' }], 'en-US'), null, 'a voice that does not say localService true is not local');
}

// Wording.
assert.strictEqual(voice.firstSentence('Plan generated. Review every proposed move.'), 'Plan generated.');
assert.strictEqual(voice.firstSentence('Done'), 'Done.');
assert.strictEqual(voice.firstSentence(''), 'Done.');
assert.strictEqual(voice.elapsedWords(20000), '20 seconds');
assert.strictEqual(voice.elapsedWords(60000), '1 minute');
assert.strictEqual(voice.elapsedWords(125000), '2 minutes 5 seconds');

// A quick job is silent and leaves no timer behind.
{
  const t = setup();
  const job = t.progress.begin();
  t.clock.advance(1500);
  job.end(true, 'Search complete');
  t.clock.advance(60000);
  assert.strictEqual(t.synth.spoken.length, 0, 'a quick job is not spoken');
  assert.strictEqual(t.clock.pending(), 0, 'no timer left after a job ends');
}

// A long job: still working at the threshold, again every 20 s, then the done sentence; never an online voice.
{
  const t = setup();
  const job = t.progress.begin();
  t.clock.advance(3999);
  assert.strictEqual(t.synth.spoken.length, 0, 'nothing before the threshold');
  t.clock.advance(1);
  assert.deepStrictEqual(t.synth.spoken.map(u => u.text), ['Still working. 4 seconds so far.']);
  t.clock.advance(20000);
  assert.strictEqual(t.synth.spoken[1].text, 'Still working. 24 seconds so far.');
  t.clock.advance(1000);
  job.end(true, 'Index built. 120 files.');
  assert.strictEqual(t.synth.spoken[2].text, 'Index built.', 'the first sentence of the done message');
  assert.ok(t.synth.cancelled >= 1, 'the done message interrupts a queued update');
  assert.strictEqual(t.clock.pending(), 0, 'timers cleared');
  t.clock.advance(120000);
  assert.strictEqual(t.synth.spoken.length, 3, 'nothing after the job ended');
  for (const u of t.synth.spoken) { assert.strictEqual(u.voice, LOCAL, 'always the explicit local voice'); assert.strictEqual(u.lang, 'en-US'); }
  job.end(false);
  assert.strictEqual(t.synth.spoken.length, 3, 'ending twice says nothing more');
}

// A failed long job says it failed and never reads the error text.
{
  const t = setup();
  const job = t.progress.begin();
  t.clock.advance(9000);
  job.end(false, 'C:\\Secret\\payroll.xlsx could not be read');
  const last = t.synth.spoken[t.synth.spoken.length - 1].text;
  assert.strictEqual(last, 'That job failed. The message is on screen.');
  assert.ok(!t.synth.spoken.some(u => /payroll|Secret/.test(u.text)), 'file names are never spoken');
}

// Switched off: silent, and the timers still go away.
{
  const t = setup({ enabled: false });
  const job = t.progress.begin();
  t.clock.advance(30000);
  job.end(true, 'Done');
  assert.strictEqual(t.synth.spoken.length, 0, 'off means silent');
  assert.strictEqual(t.clock.pending(), 0);
}

// Turning it on while a job runs speaks from the next update.
{
  const t = setup({ enabled: false });
  const job = t.progress.begin();
  t.clock.advance(5000);
  t.state.enabled = true;
  t.clock.advance(20000);
  job.end(true, 'Plan applied. 3 files moved.');
  assert.deepStrictEqual(t.synth.spoken.map(u => u.text), ['Still working. 24 seconds so far.', 'Plan applied.']);
}

// Fallback 1: only online voices. Nothing is spoken, ever; the status line says why.
{
  const t = setup({ voices: [CLOUD] });
  assert.strictEqual(t.progress.announceEnabled(), false);
  assert.match(t.status[t.status.length - 1], /No voice is installed.*Progress stays on screen/);
  const job = t.progress.begin();
  t.clock.advance(30000);
  job.end(true, 'Done');
  assert.strictEqual(t.synth.spoken.length, 0, 'an online voice is never used');
}

// Fallback 2: no speech support at all. Nothing throws.
{
  const t = setup({ noSynth: true });
  assert.strictEqual(t.progress.announceEnabled(), false);
  assert.match(t.status[t.status.length - 1], /cannot speak.*stays on screen/);
  const job = t.progress.begin();
  t.clock.advance(30000);
  job.end(false);
  t.progress.stop();
  assert.strictEqual(t.clock.pending(), 0);
}

// With a local voice, announcing says so and confirms by speaking.
{
  const t = setup();
  assert.strictEqual(t.progress.announceEnabled(), true);
  assert.strictEqual(t.status[t.status.length - 1], 'Speaks with Local English, installed on this PC.');
  assert.deepStrictEqual(t.synth.spoken.map(u => u.text), ['Spoken progress is on.']);
}

console.log('PASS: Bowerbird spoken progress (local voices only, silent fallback, fake clock)');
