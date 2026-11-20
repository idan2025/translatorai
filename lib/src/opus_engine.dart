import 'dart:async';
import 'dart:isolate';

import 'glossary.dart';
import 'marian.dart';
import 'models.dart';
import 'translator.dart';

/// Translation with the installed [TranslationPack]s where they cover a
/// direction, and [fallback] (ML Kit) everywhere else. A pair that has the
/// pack's language on one side only goes through English: Hebrew → Russian is
/// Opus-MT Hebrew → English, then ML Kit English → Russian.
class PackEngine extends TranslationEngine {
  PackEngine({required this.fallback, required this.installed, required this.pathOf, List<TranslationPack>? packs})
      : packs = packs ?? usableTranslationPacks;

  final TranslationEngine fallback;
  final List<TranslationPack> packs;

  /// Whether every file of a direction is on the phone.
  final bool Function(TranslationDirection) installed;

  /// Where a model file lives on the phone.
  final String Function(String name) pathOf;

  TranslateWorker? _worker;

  TranslationDirection? _direction(String from, String to) {
    for (final p in packs) {
      for (final d in p.directions) {
        if (d.from == from && d.to == to && installed(d)) return d;
      }
    }
    return null;
  }

  /// Whether a pack translates this exact direction now.
  bool covers(String from, String to) => _direction(from, to) != null;

  bool _packCovers(String code) => packs.any((p) => p.language == code && p.directions.every(installed));

  @override
  String get name => packs.any((p) => p.directions.any(installed)) ? 'Translation pack + ${fallback.name}' : fallback.name;

  @override
  Set<String> get languages => fallback.languages;

  @override
  Future<bool> isReady(String code) async => _packCovers(code) || await fallback.isReady(code);

  @override
  Future<void> prepare(String code) async {
    if (_packCovers(code)) return; // the pack speaks it; ML Kit's model for it is not needed
    await fallback.prepare(code);
  }

  Future<String> _run(TranslationDirection d, String text) async {
    final dir = pathOf(d.files.first.name);
    final out = await (_worker ??= TranslateWorker()).translate(d, dir.substring(0, dir.lastIndexOf('/')), text);
    return d.from == 'en' && d.to == 'he' ? applyHebrewGlossary(text, out) : out;
  }

  /// Into English, with the known-word corrections for the source language.
  Future<String> _toEnglish(String text, String from) async {
    final d = _direction(from, 'en');
    final english = d != null ? await _run(d, text) : await fallback.translate(text, from: from, to: 'en');
    return from == 'he' ? applyGlossary(text, english) : english;
  }

  @override
  Future<String> translate(String text, {required String from, required String to}) async {
    if (from == to || text.trim().isEmpty) return text;
    if (to == 'en') return _toEnglish(text, from);
    final direct = _direction(from, to);
    if (direct != null) return _run(direct, text);
    if (from != 'en') {
      final first = _direction(from, 'en'), second = _direction('en', to);
      if (first != null || second != null) {
        final english = await _toEnglish(text, from);
        return second != null ? _run(second, english) : fallback.translate(english, from: 'en', to: to);
      }
    }
    return fallback.translate(text, from: from, to: to);
  }

  @override
  Future<void> delete(String code) => fallback.delete(code);

  /// Frees the pack models' memory (after a pack is deleted, or to save memory).
  Future<void> unload() async {
    await _worker?.stop();
    _worker = null;
  }

  @override
  Future<void> close() async {
    await unload();
    await fallback.close();
  }
}

/// Runs [MarianModel]s on a background isolate, so a sentence's translation
/// never stalls the screen. A direction is loaded on its first sentence and
/// then stays in memory until [stop].
class TranslateWorker {
  TranslateWorker({this.threads = 2});

  /// Threads per model: few, since speech recognition runs at the same time.
  final int threads;

  SendPort? _send;
  Isolate? _isolate;
  ReceivePort? _inbox;
  Future<void>? _starting;
  var _next = 0;
  final _waiting = <int, Completer<String>>{};

  Future<void> _start() => _starting ??= () async {
        final inbox = ReceivePort();
        _inbox = inbox;
        final ready = Completer<SendPort>();
        inbox.listen((msg) {
          if (msg is SendPort) {
            ready.complete(msg);
          } else if (msg is List && msg.length == 3) {
            final c = _waiting.remove(msg[1] as int);
            if (msg[0] == 'ok') {
              c?.complete(msg[2] as String);
            } else {
              c?.completeError(StateError(msg[2] as String));
            }
          }
        });
        _isolate = await Isolate.spawn(_main, [inbox.sendPort, threads]);
        _send = await ready.future;
      }();

  Future<String> translate(TranslationDirection d, String dir, String text) async {
    await _start();
    final id = _next++;
    final c = Completer<String>();
    _waiting[id] = c;
    _send!.send([id, '${d.from}-${d.to}', dir, d.prefix, text]);
    return c.future;
  }

  Future<void> stop() async {
    _isolate?.kill(priority: Isolate.immediate);
    _inbox?.close();
    for (final c in _waiting.values) {
      c.completeError(StateError('translation stopped'));
    }
    _waiting.clear();
    _isolate = null;
    _send = null;
    _starting = null;
  }

  static void _main(List<Object> args) {
    final out = args[0] as SendPort;
    final threads = args[1] as int;
    final models = <String, MarianModel>{};
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((msg) {
      final m = msg as List;
      final id = m[0] as int;
      try {
        final model = models.putIfAbsent(m[1] as String, () => MarianModel.load(m[2] as String, prefix: m[3] as String, threads: threads));
        out.send(['ok', id, model.translate(m[4] as String)]);
      } catch (e) {
        out.send(['err', id, '$e']);
      }
    });
  }
}
