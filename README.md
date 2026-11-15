# TranslatorAI

Live speech translation that runs entirely on the phone. No account, no
subscription, no special headset: any phone, any earbuds.

The paid "AI translation earbuds" mostly send your voice to a server. This app
hears, translates and speaks on the device; the network is used only once, to
download the models.

## What it does

- **Listen**: everything said around you becomes your language, as text and
  (optionally) a voice in your earbuds. The spoken language is detected per
  sentence, so a room with several languages works.
- **Conversation**: two people, two languages, one phone between them. Each
  sentence is translated into the other person's language; the app tells who is
  speaking from the language it hears.

## How it works

```
microphone (16 kHz) → Silero VAD → Omnilingual ASR → language from the text → translation → phone TTS
                       cuts speech   1,600 languages   alphabet + ML Kit ID    any → any     any earbuds
```

| Stage | Model | Size | Languages |
| --- | --- | --- | --- |
| Voice activity | Silero VAD | 0.6 MB | all |
| Speech to text | Meta Omnilingual ASR 300M or 1B, int8 CTC, via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 365 MB / 1 GB | 1,600 |
| Which language | the alphabet, then Google ML Kit language identification | built in | 100+ |
| Translation | Google ML Kit on-device translation | ~30 MB per language | 59, any to any |
| Voice | the phone's own text-to-speech | built in | whatever voices the phone has |

**Why Omnilingual, not Whisper** (v0.1 used Whisper). Whisper guesses the
language first and then writes in that language, and on short phrases the guess
is often wrong: "доброе утро" came out as Polish "Dobra utra", Russian as Hebrew
letters. Omnilingual makes no guess; it writes what it hears in that language's
own alphabet. The language is then told from the text: the alphabet first
(exact), then ML Kit's identifier. In a conversation, or with the spoken
language picked in Listen, only those languages can ever be answered.

**Measured** on Google FLEURS recordings (desktop CPU, 4 threads), word / character error rate:

| Model | Hebrew (40 clips) | Russian (30) | English (30) | Speed (× real time) |
| --- | --- | --- | --- | --- |
| Whisper base (v0.1 "Accurate") | 74.2 / 41.7 | 23.0 / 7.1 | 10.9 / 5.7 | 0.06–0.10 |
| Whisper small | 60.1 / 33.9 | 11.1 / 3.5 | 4.7 / 2.8 | 0.16–0.34 |
| Whisper turbo | 43.0 / 28.5 | 7.6 / 3.6 | 5.0 / 2.6 | 0.22–0.30 |
| **Omnilingual 300M** (Standard) | 54.5 / 17.6 | 24.7 / 5.3 | 19.1 / 6.8 | 0.07 |
| **Omnilingual 1B** (Best) | 32.9 / 11.8 | 13.4 / 2.9 | 12.2 / 4.4 | 0.16 |

Whisper is better on English; Omnilingual is far better on Hebrew and keeps
working across languages, which is what a trip abroad needs. A phone is a few
times slower than this desktop. `test/bench_speech_test.dart` repeats the run.

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

## Layout

- `lib/main.dart`: setup screen (model download), home screen, language picker
- `lib/src/asr.dart`: VAD + Omnilingual, run in a background isolate; padded cuts
- `lib/src/lid.dart`: which language a text is in (alphabet, then ML Kit), limited to a pair
- `lib/src/updater.dart` + `MainActivity.kt`: checked in-app updates
- `lib/src/translator.dart`: `TranslationEngine` interface; `MlKitEngine`
- `lib/src/pipeline.dart`: microphone → speech → translation → voice; direction logic
- `lib/src/speaker.dart`: text-to-speech
- `lib/src/languages.dart`, `models.dart`, `model_store.dart`, `settings.dart`

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

`/path/to/models` holds `silero_vad.onnx`, `omni300/{model.int8.onnx,tokens.txt}` and a
16 kHz `test0.wav` (sherpa-onnx's `test_wavs/0.wav`).

See [ROADMAP.md](ROADMAP.md) for what comes next.
