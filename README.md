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
microphone (16 kHz) → Silero VAD → Whisper (on-device) → translation engine → phone TTS
                       cuts speech   text + language     any → any          any earbuds
```

| Stage | Model | Size | Languages |
| --- | --- | --- | --- |
| Voice activity | Silero VAD | 0.6 MB | all |
| Speech to text | Whisper tiny or base, int8, via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | ~100 / ~160 MB | 99 heard, language auto-detected |
| Translation | Google ML Kit on-device translation | ~30 MB per language | 59, any to any |
| Voice | the phone's own text-to-speech | built in | whatever voices the phone has |

A language pair works when the speech model hears the source and the
translation engine writes both. Today that is 57 languages you can speak and 59
you can read, in any combination (3,000+ pairs).

**Measured** (Linux desktop CPU, 2 threads, a 5.9 s English sentence): Whisper
tiny 333 ms, base 567 ms, language detected correctly. A phone CPU is a few
times slower: expect about 1–2 s per sentence with tiny.

Speech models are fetched on first run from pinned URLs and **checked against a
SHA-256 before use**; a file that does not match is discarded
(`lib/src/models.dart`, `lib/src/model_store.dart`).

## Layout

- `lib/main.dart`: setup screen (model download), home screen, language picker
- `lib/src/asr.dart`: VAD + Whisper, run in a background isolate
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

The release APK is signed with the debug key (the Flutter template default):
fine for installing on your own phone, not for a store.

Real-model test (runs Whisper on this machine; needs the model files and the
sherpa-onnx Linux library):

```sh
TRANSLATORAI_MODELS=/path/to/models \
LD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64 \
flutter test test/asr_models_test.dart
```

`/path/to/models` holds `silero_vad.onnx`, `{tiny,base}-{encoder,decoder}.int8.onnx`,
`{tiny,base}-tokens.txt` and a 16 kHz `test0.wav` (sherpa-onnx's
`test_wavs/0.wav`).

See [ROADMAP.md](ROADMAP.md) for what comes next.
