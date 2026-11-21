# Roadmap

## Done (v0.1)

- On-device speech recognition: Silero VAD + Whisper tiny/base (int8,
  sherpa-onnx), 99 languages, language detected per sentence, in an isolate.
- On-device translation through a swappable `TranslationEngine` (ML Kit first).
- Listen and Conversation modes; voice through the phone's TTS into any earbuds.
- Pinned, digest-checked model downloads; one-time, then offline.

## Done (v0.2)

- Omnilingual ASR (1,600 languages) instead of Whisper; language told from the
  text, limited to the chosen pair. Fixes Russian heard as Polish/Hebrew.
- Listen mode can pin the spoken language.
- Settings submenu: speech model, check for updates, about, exit.
- Checked in-app updates from GitHub releases; release signing key.

## Done (v0.3)

- Back to Whisper (small and turbo), now told which languages are in play:
  fixes the mixed-alphabet and romanised output seen with Omnilingual on a phone.
- Loop and repeat filtering for Whisper's noise hallucinations.
- 0.9.1: **speaker gender** for Hebrew output (Settings → "I speak Hebrew as": "אני עייפה" / "אני עייף"; the model mixed them), **a word said alone** answered from a 200-word travel list (the model answered "Flight Flight Flight" for 1 word in 2), stutter cut on short phrases.
- 0.9.0: **new Hebrew translation pack** (quickmt, CC-BY 4.0, 546 MB, replaces Opus-MT): FLEURS chrF
  he→en 68.6 (was 68.5), **en→he 63.6 (was 57.6)**, 57 ms a sentence on desktop through the app's own code.
  Exported from quickmt's eole weights to ONNX (plain graph: no masks, self-attention cache only), int8;
  `lib/src/marian.dart` runs both layouts, `lib/src/spm.dart` got byte fallback (ids equal Python's on
  emoji and symbols). The old pack keeps working until the new one is installed, then is deleted; a phone
  that has it is offered the upgrade once. Translation is warmed when the app opens or the language changes
  (first sentence no longer loads models). Glossary: names after "קוראים לי / שמי" (25 common names), חשבון
  as "bill", מטען as "charger" next to a phone word, and en→he "שמי הוא" → "שמי". Tried and rejected on
  the same sentences: Gemma 4 E2B/E4B (no gain, 3–6 s a sentence, 4.6–6.6 GB), Ozen v1 and whistle-he
  Hebrew speech (WER 22.6% and 27.6% against the Hebrew pack's 17.7%; faster but less accurate).
- 0.8.3: voice picker shows the speech engine, marks voices that need internet (listed first: offline ones) and says after a pick what the engine accepted (the user heard no difference between voices).
- 0.8.2: fix: the picked voice was never applied (the engine matches a voice by name and its exact locale tag, `en-US`, and the app sent `en`).
- 0.8.1: voice per language: Settings › Voices lists the phone's voices for your language and the translation's, with a play button; the choice is kept per language (`lib/src/speaker.dart`, `Speaker.preferred`). Phone default when none is picked.
- 0.8.0: one Settings screen (`lib/settings_screen.dart`) instead of a long submenu: sections for speech
  model, Hebrew packs, languages, listening, app. Each model/pack is a row with its size and a Get /
  Use / Delete button, so anything can be downloaded ahead of time (one at a time, with progress).
- 0.7.1: when a sentence takes more than 2.5x its length to write, the app says why if it can know:
  battery saver on, phone hot (thermal status), battery under 15% and not charging. (A user's 2.4 s
  sentence took 9.6 s at 2% battery.)
- 0.7.0: **translation while you speak** (plan item 3, streaming, first step): the words so far are
  translated as they appear and shown under them, one piece at a time, newest only (`lib/src/latest.dart`),
  never if it would download a model.
- 0.6.1: Hebrew → English glossary (`lib/src/glossary.dart`): Opus-MT got 9 of 130 travel words wrong
  when said alone (כפית "spoon", החשבון "the account", מפתח "developer", קבלה "acceptance"…) though
  right inside sentences. A word said alone now gets its travel sense, and כפית is never a plain spoon.
- 0.6.0: **Hebrew translation pack** (Settings, 515 MB): Opus-MT tc-big he→en and opus-mt en→he,
  int8 ONNX, run by the app itself (`lib/src/ort.dart` binds the ONNX Runtime sherpa-onnx already
  ships; `lib/src/spm.dart` is a SentencePiece tokenizer, same ids as Python on 60/60 sentences;
  `lib/src/marian.dart` greedy decoding). Desktop chrF he→en 68.8, en→he 56.8 (119 / 66 ms a
  sentence). Pairs with Hebrew on one side go through English. The quality test scores the pack
  and ML Kit side by side.
- 0.5.1: Hebrew pack starts faster: a warm-up decode while it loads, and no words-while-speaking
  decodes on the 1 GB Hebrew model (they competed with the real decode for the CPU).
- 0.5.0: **Hebrew speech pack** (ivrit.ai Hebrew Whisper, 1 GB, Apache-2.0; used only when Hebrew is
  spoken; the other language keeps the normal model); **1.5 s of silence after every sentence**
  (sherpa-onnx's Whisper drops the last words of audio that ends abruptly: Hebrew words wrong
  37.9% -> 30.6% on stock turbo, 28.3% -> 20.5% on the pack); a more sensitive voice detector with a
  longer pre-roll (the detector found no speech in 3 of 40 Hebrew clips and started 1.1 s late);
  **sentence joiner** (pieces split by a pause are translated as one sentence);
  **words while you speak** (live partial text); **Translation quality test** (Settings) that scores
  the on-device translator with chrF on 60 FLEURS sentences, comparable with desktop runs.
- 0.4.1: fixes the settings staying locked after you tap a language off (the warm microphone
  counted as listening); Mic off button; v2 + v3 signing, no cloud backup, no cleartext traffic;
  PRIVACY.md and SECURITY.md with the signing fingerprint.
- 0.4.0: speech model loads when the app opens with a status line; the microphone stays warm
  between turns of a tap conversation (closes after 45 s idle); screen kept on while listening;
  microphone released in the background; "Open settings" after a refused permission; bubbles:
  tap to replay, long-press to copy, full-screen view with flip; Offline languages manager;
  app icon.
- 0.3.6: the last sentence is no longer lost when you stop (stop waited 0.3 s, writing takes
  1-4 s on a phone: "Writing it down…" then nothing, seen with Chinese); the speech model stays
  loaded between stop and start (was reloaded on every tap); the GPU switch no longer turns
  itself off on a model switch (crash guard runs once per app start); "Didn't catch that" when a
  sentence decodes to nothing.
- 0.3.5: fluency: a tap conversation closes a sentence after 0.4 s of quiet (was 0.5); a
  "Hearing you…" / "Writing it down…" indicator; translation and voices are warmed up in the
  background. User test of 0.3.4 with the GPU switch ON: correct text, and the CPU was a little
  faster, so it stays off by default. (Warming the speech model itself made no measurable
  difference, so it is not done.)
- 0.3.4: experimental "Use the GPU" switch (Settings): runs the speech model through Android's
  NNAPI. Off by default; it falls back to the CPU if the model will not load, and turns itself
  off if the app dies trying. Not measured: needs a phone.
- 0.3.3: Conversation has two tap-to-speak buttons (language known, one decode instead of up to
  three; fixes Hebrew heard as English); a Fast model (Whisper base); auto-detect kept as an option.
- 0.3.2: the phone no longer hears its own translation (microphone closed until the voice
  has really stopped plus 0.9 s, detector reset around it, echo text-match, noise filter
  for text faster than speech); each line shows seconds heard and seconds to write; a
  warning appears when the phone falls behind.
- 0.3.1: downloaded speech models are kept when switching (0.3.0 deleted the other one);
  Settings › Delete the other model frees the space on request.

## Not verified yet

- v0.3 on a real phone: Whisper small/turbo speed and memory, the language policy on
  real speech, and the update flow end to end (first update from 0.2 to 0.3).
- v0.1 was tried on a phone by the user: it ran; Whisper misheard languages (fixed in 0.2).

## Translation engines (measured on desktop, 60 FLEURS sentences, chrF, higher is better)

| Engine | he->en | en->he | ru->en | en->ru | Size | Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Opus-MT (tc-big he-en; base for the rest) | 68.9 | 57.7 | 59.8 | 55.2 | ~75-300 MB per direction | CC-BY 4.0 / Apache-2.0 |
| M2M-100 418M | 62.0 | 50.7 | 58.7 | 53.4 | ~450 MB | MIT |
| Opus-MT int8 greedy, as the app runs it (0.6.0) | 68.8 | 56.8 | | | 366 + 149 MB | CC-BY 4.0 / Apache-2.0 |
| Google ML Kit (the app's engine) | run Settings > Translation quality test | | | | ~30 MB per language | ML Kit terms |
| NLLB-200 | not used | | | | | CC-BY-NC: cannot ship in a paid app |

## Next

0. **Speed of the 1 GB model.** Measured on a desktop CPU (4 threads) the time to write a
   sentence is about 0.55x its length for turbo, 0.2x for small; a phone is ~3x slower. What
   would help: a Hebrew fine-tune of *small* instead of turbo, a native whisper.cpp engine
   (GPU via Vulkan, shorter audio context), or streaming recognition. ONNX Runtime on Android
   has no GPU backend besides NNAPI, which handles quantised Whisper poorly.

1. **Every language to every language.** ML Kit covers 59 languages. To reach
   the full scale, add engines behind `TranslationEngine`:
   - **NLLB-200** (200 languages, distilled 600M, ~600 MB int8 via
     CTranslate2/ONNX). Licence **CC-BY-NC 4.0: non-commercial only**, so it
     cannot ship in a paid or ad-supported app.
   - **M2M-100 418M** (100 languages, MIT licence, ~500 MB int8). Usable commercially.
   - **MADLAD-400** (400+ languages, Apache 2.0) is 3B+ parameters: too big for
     most phones today.
   - **Opus-MT** (Marian, CC-BY 4.0) pairs: tiny (~50 MB) and fast, but one model
     per direction, and many pairs pivot through English.
   The engine is picked per pair: the best installed engine that has both
   languages wins, so adding one widens coverage without changing the rest.
2. **Hebrew.** Whisper turbo gets 38% of Hebrew words wrong; a Hebrew fine-tune
   (ivrit-ai, ONNX) would do much better, as a per-language model that loads
   when Hebrew is chosen.
3. **Languages beyond Whisper's 99.** Omnilingual hears 1,600 but cannot be
   told the language; use it only when the text identifier says Whisper's
   guess is poor.
4. **Lower latency.** Streaming recognisers (sherpa-onnx streaming zipformer)
   for the languages that have one, to show words while someone is still
   talking; Whisper stays the fallback for everything else.
5. **Better voices offline.** Piper/VITS voices through sherpa-onnx TTS where
   the phone has no voice for a language.
6. **Face-to-face view.** Split screen, the other person's half upside down.
7. **iOS.** All three libraries support it; needs a Mac to build.
8. Store listing, privacy policy page, screenshots; crash reporting that stays on-device.
