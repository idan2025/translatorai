# TranslatorAI

<img src="docs/icon-512.png" width="96" alt="">

Live speech translation that runs entirely on the phone. No account, no
subscription, no special headset: any phone, any earbuds.

The paid "AI translation earbuds" mostly send your voice to a server. This app
hears, translates and speaks on the device; the network is used only once, to
download the models.

## What it does

- **Listen**: everything said around you becomes your language, as text and
  (optionally) a voice in your earbuds. The spoken language is detected per
  sentence, so a room with several languages works.
- **Conversation**: two people, two languages, one phone between them. Two big
  buttons, one per language: tap yours and speak, the other person taps theirs.
  The model is told the language, so it makes one pass per sentence and cannot
  pick the wrong one. (Settings can switch to detecting who speaks from the
  sound: slower, and it misjudges short phrases.)

## In the app

- **Tap a bubble** to hear the translation again, **long-press** to copy it, and use the
  **full-screen** button to show it big (with a flip to face the person across the table).
- **Offline languages** (⋮ › Settings): download the languages of a trip on Wi-Fi; translation
  then works with no connection.
- The speech model loads when the app opens (the status line says when it is ready), stays
  loaded between turns, and the microphone stays warm between turns of a conversation.
- **Words while you speak**: the sentence so far appears faded while you talk (Settings can turn it off).
- **Hebrew speech pack** (Settings, 1 GB): ivrit.ai's Hebrew Whisper, used only when Hebrew is spoken.
- The screen stays on while listening; the microphone is released when the app leaves the screen.

## How it works

```
microphone (16 kHz) → Silero VAD → Whisper, language-controlled → translation → phone TTS
                       cuts speech   99 languages                  any → any     any earbuds
```

| Stage | Model | Size | Languages |
| --- | --- | --- | --- |
| Voice activity | Silero VAD | 0.6 MB | all |
| Speech to text | OpenAI Whisper base (Fast), small (Standard) or large-v3-turbo (Best), int8, via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 160 MB / 375 MB / 1 GB | 99 |
| Which language | Whisper's own guess, checked against the alphabet, then Google ML Kit language identification | built in | 100+ |
| Translation | Google ML Kit on-device translation | ~30 MB per language | 59, any to any |
| Voice | the phone's own text-to-speech | built in | whatever voices the phone has |

**How the language is kept right.** The speech model is told which languages
are in play:

- **Conversation**: only the two chosen languages. If Whisper's own guess is a
  third language (the usual failure on short phrases), the audio is written in
  each of the two and the text that fits its own alphabet wins.
- **Listen with the spoken language picked**: that language, always.
- **Listen with "Any language"**: Whisper's guess, accepted only if the text is
  in that language's alphabet; otherwise the text decides (alphabet, then ML Kit).

Every line is then labelled from that, so Russian can no longer come out as
Polish, or as Hebrew letters.

**Why not Omnilingual** (v0.2 used Meta's Omnilingual ASR, 1,600 languages). It
scored well on clean recordings, but it has no way to be told the language:
on a phone microphone it mixed alphabets inside one phrase and wrote Russian in
Latin letters. Whisper can be told, which removes that failure.

**Measured** on Google FLEURS recordings (desktop CPU, 4 threads), words wrong
(clean read speech; `test/bench_speech_test.dart`):

| Model | Hebrew | Russian | English | Speed (× real time) |
| --- | --- | --- | --- | --- |
| Whisper base (v0.1) | 74.2% | 23.0% | 10.9% | 0.06–0.10 |
| **Whisper small** (Standard) | 54.5% | 11.1% | 4.7% | 0.16–0.34 |
| **Whisper turbo** (Best) | 37.9% | 7.6% | 5.0% | 0.22–0.30 |
| Omnilingual 1B (v0.2) | 32.9% | 13.4% | 12.2% | 0.16 |

Mixed-language runs with noise are in `test/bench_strategy_test.dart`. A phone
is a few times slower than this desktop.

Speech models are fetched on first run from pinned URLs and **checked against a
SHA-256 before use**; a file that does not match is discarded
(`lib/src/models.dart`, `lib/src/model_store.dart`).

## Updates

Settings › Check for updates reads this repository's releases (pre-releases
included), downloads the newest arm64 APK, checks it against GitHub's SHA-256
for the file (or the published `.sha256`), and hands it to Android's installer.
Android asks once to allow installs from the app, then to confirm. The APK is
deleted the next time the app starts. Releases are signed with the project's
release key (kept outside the repo); Android installs an update only over a
copy signed with the same key.

## Trust

Nothing you say leaves the phone ([PRIVACY.md](PRIVACY.md)). Releases are signed with a fixed key and
the fingerprint is published so you can check a download ([SECURITY.md](SECURITY.md)).

## Layout

- `lib/main.dart`: setup screen (model download), home screen, language picker
- `lib/src/asr.dart`: VAD + Whisper with a language policy, in a background isolate; padded cuts
- `lib/src/lid.dart`: which language a text is in (alphabet, then ML Kit), limited to a pair
- `lib/src/updater.dart` + `MainActivity.kt`: checked in-app updates
- `lib/src/translator.dart`: `TranslationEngine` interface; `MlKitEngine`
- `lib/src/pipeline.dart`: microphone → speech → translation → voice; direction logic
- `lib/src/speaker.dart`: text-to-speech
- `lib/src/languages.dart`, `models.dart`, `model_store.dart`, `settings.dart`
- `tool/make_icon.py`: draws the launcher icon (vector + PNGs, stdlib only):
  `python3 tool/make_icon.py android/app/src/main/res docs/icon-512.png`

## Build

Flutter 3.41 / Dart 3.11, Android SDK 36, JDK 17.

```sh
flutter test                                   # unit tests, offline
flutter build apk --release --split-per-abi --target-platform android-arm64
```

A release build is signed with the key in `~/.config/translatorai/key.properties`
(or `TRANSLATORAI_KEY_PROPERTIES`); without it, Gradle falls back to the debug
key, which can build and run but cannot update a release install.

Real-model test (runs Whisper on this machine; needs the model files and the
sherpa-onnx Linux library):

```sh
TRANSLATORAI_MODELS=/path/to/models \
LD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64 \
flutter test test/asr_models_test.dart
```

`/path/to/models` holds `silero_vad.onnx`, `small-{encoder,decoder}.int8.onnx`,
`small-tokens.txt` and a 16 kHz `test0.wav` (sherpa-onnx's `test_wavs/0.wav`).

See [ROADMAP.md](ROADMAP.md) for what comes next.
