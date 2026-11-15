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

## Not verified yet

- v0.2 on a real phone: Omnilingual latency and memory (1B needs a recent
  phone), the text language identifier on short phrases, the update flow end to
  end (first update from 0.2 to a later release).
- v0.1 was tried on a phone by the user: it ran; Whisper misheard languages (fixed in 0.2).

## Next

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
2. **Hybrid recognition.** Whisper small/turbo is better than Omnilingual on
   English (4.7% vs 12.2% words wrong): re-decode with Whisper, forced to the
   language Omnilingual's text revealed, where Whisper is strong.
3. **Lower latency.** Streaming recognisers (sherpa-onnx streaming zipformer)
   for the languages that have one, to show words while someone is still
   talking; Whisper stays the fallback for everything else.
4. **Better voices offline.** Piper/VITS voices through sherpa-onnx TTS where
   the phone has no voice for a language.
5. **Face-to-face view.** Split screen, the other person's half upside down.
6. **iOS.** All three libraries support it; needs a Mac to build.
7. Store listing, an icon.
