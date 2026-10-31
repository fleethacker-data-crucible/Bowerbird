# Spoken progress for long jobs

Studio can say out loud how a long job is going, so you can look away while an index builds or a plan applies. It is a switch in the status bar ("Speak progress"), **off until you turn it on**, and it remembers your choice in this browser.

Code: `Web/voice.js` (the logic), wired in `Web/app.js` (`run()` wraps every request as a job). Tests: `Tests/Voice.js` (Node, CI only) and the contract checks in `Tests/UiContract.js`.

## What it says

- A job that finishes within 4 seconds is silent.
- After 4 seconds: "Still working. 4 seconds so far." Then again every 20 seconds.
- When it ends: the first sentence of the app's own message ("Index built.", "Plan applied."), or "That job failed. The message is on screen."
- Turning the switch on says "Spoken progress is on." so you know the voice works.

Error text and file names are never spoken, because they can hold paths. The message always stays on screen in the notice area, which is an `aria-live` region, whether or not speech works.

## Local voices only

The browser's speech list also holds online voices that send the text to a vendor. Bowerbird chooses a voice only when the browser says it runs on this PC (`localService` is `true`), prefers the page language, and always sets that voice on the utterance, so the browser can never fall back to its default (possibly online) voice. The module makes no network call, which `Tests/UiContract.js` checks.

## Fallback

If the browser cannot speak, or no voice is installed on this PC (only online ones), nothing is spoken and the status bar says why ("No voice is installed on this PC (online voices are never used). Progress stays on screen."). Nothing else changes; the on-screen notice is the same.

## Not built

- The Fleet contract names TalkForge through Fairlead (`/v1/audio/speech`) as the suite voice. That needs a running Fairlead and TalkForge, so it is not built here; this is the local-browser-voice fallback the contract allows.
- Speech in (Whisper, Windows speech recognition) is not part of this.
- Not heard on a workstation: the fake-clock tests prove what is said and when, but a hand check on a PC with an installed voice is still needed (turn the switch on, build an index of a large folder, listen).
