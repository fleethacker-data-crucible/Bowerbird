'use strict';
/*
 Spoken progress for long jobs. Off until the person turns it on.
 - Speaks only with a voice installed on this PC (SpeechSynthesisVoice.localService === true). Browsers also list
   online voices that send the text to a vendor; those are never chosen, and an utterance always carries an
   explicit local voice so the browser cannot fall back to its default one.
 - A job that finishes quickly stays silent. After `thresholdMs` it says it is still working, repeats every
   `repeatMs`, and says when it is done or failed.
 - What is spoken is fixed wording plus the first sentence of the app's own "done" message. Error text and file
   names are never read out (they can hold paths); the message stays on screen.
 - Fallback: with no speech support or no local voice, nothing is spoken and the status line says why. The
   on-screen notice (an aria-live region) is always shown whether or not speech works.
 Pure logic with injected browser objects, so Tests\Voice.js runs it under Node with a fake clock and a fake synth.
*/
(function (root) {
  var DEFAULTS = { thresholdMs: 4000, repeatMs: 20000 };

  function baseLang(lang) { return String(lang || '').toLowerCase().split('-')[0]; }

  // A local voice for the page language, else any local voice, else null. Never a voice that is not local.
  function pickLocalVoice(voices, lang) {
    var local = Array.prototype.filter.call(voices || [], function (v) { return v && v.localService === true; });
    if (!local.length) return null;
    var want = String(lang || '').toLowerCase();
    var exact = local.filter(function (v) { return String(v.lang).toLowerCase() === want; })[0];
    var sameDefault = local.filter(function (v) { return v['default'] && baseLang(v.lang) === baseLang(want); })[0];
    var same = local.filter(function (v) { return baseLang(v.lang) === baseLang(want); })[0];
    return exact || sameDefault || same || local[0] || null;
  }

  function elapsedWords(ms) {
    var s = Math.max(1, Math.round(ms / 1000));
    if (s < 60) return s + ' seconds';
    var m = Math.floor(s / 60);
    var rest = s % 60;
    return m + (m === 1 ? ' minute' : ' minutes') + (rest ? ' ' + rest + ' seconds' : '');
  }

  // The app's own completion message, cut at its first sentence ("Plan generated. Review every move." -> "Plan generated.").
  function firstSentence(text) {
    var t = String(text || '').replace(/\s+/g, ' ').trim();
    if (!t) return 'Done.';
    var m = /^[^.!?]*[.!?]/.exec(t);
    var s = (m ? m[0] : t).slice(0, 120).trim();
    return /[.!?]$/.test(s) ? s : s + '.';
  }

  function create(options) {
    var o = options || {};
    var synth = o.synth || null;
    var Utterance = o.Utterance || null;
    var lang = o.lang || 'en-US';
    var now = o.now || function () { return Date.now(); };
    var setT = o.setTimeout || function (f, ms) { return setTimeout(f, ms); };
    var clearT = o.clearTimeout || function (id) { clearTimeout(id); };
    var isEnabled = o.isEnabled || function () { return false; };
    var onStatus = o.onStatus || function () {};
    var thresholdMs = o.thresholdMs || DEFAULTS.thresholdMs;
    var repeatMs = o.repeatMs || DEFAULTS.repeatMs;

    function availability() {
      if (!synth || !Utterance || typeof synth.speak !== 'function') {
        return { ok: false, reason: 'This browser cannot speak. Progress stays on screen.' };
      }
      var voice = pickLocalVoice(synth.getVoices(), lang);
      if (!voice) {
        return { ok: false, reason: 'No voice is installed on this PC (online voices are never used). Progress stays on screen.' };
      }
      return { ok: true, voice: voice };
    }

    function refreshStatus() {
      var a = availability();
      onStatus(a.ok ? 'Speaks with ' + a.voice.name + ', installed on this PC.' : a.reason);
      return a;
    }

    function speak(text, interrupt) {
      var a = availability();
      if (!a.ok) return false;
      try {
        if (interrupt && typeof synth.cancel === 'function') synth.cancel();
        var u = new Utterance(text);
        u.voice = a.voice;
        u.lang = a.voice.lang || lang;
        synth.speak(u);
        return true;
      } catch (e) {
        return false;
      }
    }

    // Called when the person turns the switch on: confirms the voice works, or says why it cannot.
    function announceEnabled() {
      var a = refreshStatus();
      if (a.ok) speak('Spoken progress is on.', true);
      return a.ok;
    }

    function stop() {
      if (synth && typeof synth.cancel === 'function') { try { synth.cancel(); } catch (e) { /* nothing to stop */ } }
    }

    // job = begin(); ...; job.end(true, 'Index built. 12 files.') or job.end(false)
    function begin() {
      var started = now();
      var timer = null;
      var finished = false;
      function tick() {
        timer = null;
        if (finished) return;
        if (isEnabled()) speak('Still working. ' + elapsedWords(now() - started) + ' so far.', false);
        timer = setT(tick, repeatMs);
      }
      timer = setT(tick, thresholdMs);
      return {
        end: function (ok, doneText) {
          if (finished) return;
          finished = true;
          if (timer !== null) { clearT(timer); timer = null; }
          var long = now() - started >= thresholdMs;
          if (!long || !isEnabled()) return;
          speak(ok ? firstSentence(doneText) : 'That job failed. The message is on screen.', true);
        }
      };
    }

    return { begin: begin, refreshStatus: refreshStatus, announceEnabled: announceEnabled, stop: stop, availability: availability };
  }

  var api = { create: create, pickLocalVoice: pickLocalVoice, firstSentence: firstSentence, elapsedWords: elapsedWords, DEFAULTS: DEFAULTS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.BowerbirdVoice = api;
})(typeof window !== 'undefined' ? window : this);
