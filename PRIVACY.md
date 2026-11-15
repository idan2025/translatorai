# Privacy

TranslatorAI works on your phone. **Your voice, your words and your translations never leave the
device**, and the app has no account, no analytics, no advertising and no crash reporting.

## What it does with the network

The app connects to the internet only to download things, never to send what you say:

| When | To | What is fetched |
| --- | --- | --- |
| First run, or when you pick another speech model | `huggingface.co`, `github.com` | The speech model files, checked against a fixed SHA-256 before use |
| When you pick a language, or in Offline languages | Google (ML Kit) | That language's translation model (~30 MB); after that it works offline |
| Settings › Check for updates | `api.github.com`, `github.com` | The list of releases and, if you accept, the newer APK (checked against its SHA-256) |

Fetching a file reveals to that server what any download reveals (your IP address and which file).
The app sends no other data.

## Permissions

- **Microphone**: to hear speech. Audio is processed in memory and not recorded or saved. The
  microphone is open only while you listen, and is released when you leave the app.
- **Internet**: the downloads above.
- **Install packages**: so Settings › Check for updates can hand a downloaded update to Android's
  installer, which asks you to confirm every install.

## What is stored on the phone

Your language choices and settings, the downloaded models, and the conversation shown on screen
(kept in memory, cleared when the app closes or with "Clear transcript"). Backup to the cloud is
turned off for the app.

## Third parties

Speech recognition is OpenAI Whisper (MIT), run with sherpa-onnx (Apache 2.0). Translation and text
language identification are Google ML Kit's on-device models; they run locally. The voice is the
phone's own text-to-speech engine.

Questions: open an issue at https://github.com/idan2025/translatorai/issues
