# Roadmap

## Done (v0.1)

- On-device speech recognition: Silero VAD + Whisper tiny/base (int8,
  sherpa-onnx), 99 languages, language detected per sentence, in an isolate.
- On-device translation through a swappable `TranslationEngine` (ML Kit first).
- Listen and Conversation modes; voice through the phone's TTS into any earbuds.
- Pinned, digest-checked model downloads; one-time, then offline.

## Not verified yet

- **On a real phone.** Built (`app-arm64-v8a-release.apk`) but not run: no
  device or KVM emulator on the build machine. First run checks: microphone
  permission, model download, latency per sentence, echo (the app mutes the
  microphone while it speaks), Bluetooth earbuds output.
- Non-English language detection with real speech (only English was measured).

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
2. **Lower latency.** Streaming recognisers (sherpa-onnx streaming zipformer)
   for the languages that have one, to show words while someone is still
   talking; Whisper stays the fallback for everything else.
3. **Better voices offline.** Piper/VITS voices through sherpa-onnx TTS where
   the phone has no voice for a language.
4. **Face-to-face view.** Split screen, the other person's half upside down.
5. **iOS.** All three libraries support it; needs a Mac to build.
6. Release signing, store listing, an icon.
