import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Text from one language to another, on the device. An engine is swappable:
/// the pipeline only sees this interface, so a different local model
/// (NLLB, Opus-MT, an LLM) can replace ML Kit without touching the rest.
abstract class TranslationEngine {
  String get name;

  /// Language codes this engine can read and write. Any two of them form a pair.
  Set<String> get languages;

  bool supports(String code) => languages.contains(code);

  /// Whether the model for [code] is on the device.
  Future<bool> isReady(String code);

  /// Fetches the model for [code] (once; then it works offline).
  Future<void> prepare(String code);

  Future<String> translate(String text, {required String from, required String to});

  /// Removes the model for [code] from the device.
  Future<void> delete(String code);

  Future<void> close();
}

/// Google ML Kit's on-device translation: one small neural model per
/// language (~30 MB), downloaded once, then fully offline. Any of its
/// languages to any other.
class MlKitEngine extends TranslationEngine {
  final _models = OnDeviceTranslatorModelManager();
  final _open = <String, OnDeviceTranslator>{};

  static final Map<String, TranslateLanguage> _byCode = {
    for (final l in TranslateLanguage.values) l.bcpCode: l,
  };

  @override
  String get name => 'ML Kit (on-device)';

  @override
  Set<String> get languages => _byCode.keys.toSet();

  @override
  Future<bool> isReady(String code) async => code == 'en' || await _models.isModelDownloaded(code);

  @override
  Future<void> prepare(String code) async {
    if (!supports(code)) throw UnsupportedError('no on-device translation for $code');
    if (await isReady(code)) return;
    final ok = await _models.downloadModel(code, isWifiRequired: false);
    if (!ok) throw StateError('could not download the $code translation model');
  }

  @override
  Future<String> translate(String text, {required String from, required String to}) async {
    if (from == to || text.trim().isEmpty) return text;
    final src = _byCode[from], dst = _byCode[to];
    if (src == null || dst == null) {
      throw UnsupportedError('no on-device translation for $from → $to');
    }
    final t = _open.putIfAbsent('$from>$to', () => OnDeviceTranslator(sourceLanguage: src, targetLanguage: dst));
    return t.translateText(text);
  }

  @override
  Future<void> delete(String code) async {
    if (code == 'en') return; // built in: ML Kit translates through English
    for (final k in _open.keys.where((k) => k.contains(code)).toList()) {
      await _open.remove(k)?.close();
    }
    await _models.deleteModel(code);
  }

  @override
  Future<void> close() async {
    for (final t in _open.values) {
      await t.close();
    }
    _open.clear();
  }
}
