# Third-party notices

TranslatorAI runs these models and engines on the phone. Each keeps its own licence.

| Component | Used for | Licence |
| --- | --- | --- |
| OpenAI Whisper (base, small, large-v3-turbo) | Speech recognition | MIT, © 2022 OpenAI |
| ivrit-ai/whisper-large-v3-turbo (Hebrew fine-tune of Whisper), converted by pantinor/whisper-large-v3-turbo-hebrew-sherpa | Hebrew speech pack | Apache License 2.0 |
| Silero VAD | Finding where speech starts and ends | MIT, © Silero Team |
| sherpa-onnx, ONNX Runtime | Running the speech and translation-pack models | Apache License 2.0 / MIT |
| Helsinki-NLP opus-mt-tc-big-he-en (CC-BY 4.0) and opus-mt-en-he (Apache-2.0), by Jörg Tiedemann and the Language Technology Research Group, University of Helsinki; exported to ONNX and quantised to int8 for this app (release `models-mt-1`) | Hebrew translation pack | CC-BY 4.0 / Apache License 2.0 |
| Google ML Kit (Translation, Language ID) | On-device translation and language identification | [ML Kit Terms of Service](https://developers.google.com/ml-kit/terms) |
| Google FLEURS sentences (60 sentences in Hebrew, English and Russian, used only by Settings › Translation quality test) | Measuring translation quality | CC-BY 4.0, © Google; see https://huggingface.co/datasets/google/fleurs |
| Flutter and Dart packages | The app | BSD-3-Clause and similar; the full list is in the app under Settings › About › View licenses |

The speech and translation-pack models are downloaded on first use from pinned revisions and checked against a SHA-256
(`lib/src/models.dart`). Models were chosen so the app can be distributed commercially: nothing under a
non-commercial licence (for example Meta's NLLB translation models) is used.
