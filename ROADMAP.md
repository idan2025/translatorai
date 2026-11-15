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
8. Store listing, an icon.
