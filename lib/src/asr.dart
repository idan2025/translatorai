import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'languages.dart';
import 'lid.dart';

const sampleRate = 16000;

/// Where the speech model's files are, and how to run it.
class AsrConfig {
  const AsrConfig({
    required this.vad,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.threads = 2,
    this.provider = 'cpu',
    this.endSilence = 0.5,
  });

  final String vad, encoder, decoder, tokens;
  final int threads;

  /// Where the speech model runs: 'cpu', or 'nnapi' (Android's route to a
  /// phone's GPU or NPU; experimental).
  final String provider;

  /// Seconds of quiet that end a sentence. Shorter = quicker answers, but a
  /// pause inside a sentence then splits it.
  final double endSilence;

  AsrConfig onCpu() => AsrConfig(
      vad: vad, encoder: encoder, decoder: decoder, tokens: tokens, threads: threads, endSilence: endSilence);
}

/// Which languages the recogniser may write.
///
/// - [force] set: that language, always (Listen with the spoken language picked).
/// - [allowed] set: only these (a conversation's two languages): the model's
///   own guess is used when it is one of them, and otherwise each of them is
///   tried and the one whose text fits its alphabet wins.
/// - both empty: whatever the model hears, among its 99 languages.
class LanguagePolicy {
  const LanguagePolicy({this.allowed = const {}, this.force = ''});
  final Set<String> allowed;
  final String force;

  Map<String, Object> toJson() => {'allowed': allowed.toList(), 'force': force};
  static LanguagePolicy fromJson(Map<Object?, Object?> m) =>
      LanguagePolicy(allowed: {...(m['allowed'] as List).cast<String>()}, force: m['force'] as String);
}

/// One stretch of speech, as heard.
class Heard {
  const Heard(this.text, this.seconds, this.decodeMs, {this.language = '', this.forced = false});
  final String text;
  final double seconds;
  final int decodeMs;

  /// The language it was written in ('' when unknown).
  final String language;

  /// Written in a language the person chose, not one the model guessed.
  final bool forced;

  @override
  String toString() => '[$language ${seconds.toStringAsFixed(1)}s ${decodeMs}ms] $text';
}

/// Voice activity detection cuts the microphone into utterances and Whisper
/// transcribes each one. Synchronous: run it off the UI thread ([AsrWorker]).
class Asr {
  Asr(this.config) {
    _vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
          model: config.vad,
          threshold: 0.5,
          minSilenceDuration: config.endSilence, // a pause this long ends a sentence
          minSpeechDuration: 0.25,
          maxSpeechDuration: 10.0, // long monologues are cut so translation keeps up
        ),
        sampleRate: sampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );
    _rec = so.OfflineRecognizer(_cfg(''));
  }

  so.OfflineRecognizerConfig _cfg(String language) => so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          whisper: so.OfflineWhisperModelConfig(
              encoder: config.encoder, decoder: config.decoder, language: language, task: 'transcribe', tailPaddings: -1),
          tokens: config.tokens,
          numThreads: config.threads,
          provider: config.provider,
          debug: false,
        ),
      );

  final AsrConfig config;
  late final so.VoiceActivityDetector _vad;
  late final so.OfflineRecognizer _rec;
  final _recent = AudioRing(sampleRate * 32);
  var _policy = const LanguagePolicy();
  var _language = ''; // what the recogniser is set to write ('' = its own guess)

  void setPolicy(LanguagePolicy p) => _policy = p;

  /// Told what the recogniser is doing: 'hearing', 'decoding', 'idle'.
  void Function(String phase)? onPhase;
  var _phase = 'idle';
  void _setPhase(String p) {
    if (p == _phase) return;
    _phase = p;
    onPhase?.call(p);
  }


  /// Forgets the audio in progress, unfinished speech included. Used when the
  /// microphone was closed for a moment (the phone was speaking), so the
  /// detector never joins what came before with what comes after.
  void reset() {
    _vad.reset();
    _recent.clear();
  }

  /// Feeds audio (mono, 16 kHz, -1..1). Returns every utterance it completed.
  List<Heard> accept(Float32List samples) {
    _recent.add(samples);
    _vad.acceptWaveform(samples);
    final out = _drain();
    _setPhase(_vad.isDetected() ? 'hearing' : 'idle');
    return out;
  }

  /// Ends the current utterance, if any (e.g. push-to-talk released).
  List<Heard> flush() {
    _vad.flush();
    final out = _drain();
    _vad.reset();
    _recent.clear();
    return out;
  }

  bool get speaking => _vad.isDetected();

  List<Heard> _drain() {
    final out = <Heard>[];
    while (!_vad.isEmpty()) {
      final seg = _vad.front();
      _vad.pop();
      // the detector trims the edges of words; take a little more on each side
      // self-check: the ring must hold exactly the audio the detector returned, else the
      // indexes have drifted apart and padding would cut words; fall back to the plain segment
      final same = _recent.slice(seg.start, seg.start + seg.samples.length);
      final aligned = same != null && same.length == seg.samples.length && _sameStart(same, seg.samples);
      if (!aligned) misaligned++;
      final padded = aligned
          ? _recent.slice(seg.start - padBefore, seg.start + seg.samples.length + padAfter) ?? seg.samples
          : seg.samples;
      _setPhase('decoding');
      final h = transcribe(padded);
      if (h != null) out.add(h);
      _setPhase('idle');
    }
    return out;
  }

  /// Segments the ring could not match (should stay 0).
  int misaligned = 0;

  static bool _sameStart(Float32List a, Float32List b) {
    for (var i = 0; i < 256 && i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  static const padBefore = sampleRate * 3 ~/ 10; // 300 ms
  static const padAfter = sampleRate * 2 ~/ 10; // 200 ms

  ({String text, String lang}) _decode(Float32List samples, String language) {
    if (language != _language) {
      _rec.setConfig(_cfg(language)); // same loaded model, new language: no reload
      _language = language;
    }
    final stream = _rec.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _rec.decode(stream);
      final r = _rec.getResult(stream);
      return (text: cleanText(r.text), lang: language.isNotEmpty ? language : normaliseLanguageTag(r.lang));
    } finally {
      stream.free();
    }
  }

  Heard? transcribe(Float32List samples) {
    final sw = Stopwatch()..start();
    final p = _policy;
    var r = p.force.isNotEmpty ? _decode(samples, p.force) : _decode(samples, '');
    if (p.force.isEmpty && p.allowed.isNotEmpty && !p.allowed.contains(r.lang)) {
      // the model heard a third language: it must be one of the two, so write
      // the audio in each and keep the text that fits its own alphabet
      ({String text, String lang})? best;
      for (final l in p.allowed) {
        final d = _decode(samples, l);
        final fits = d.text.isNotEmpty && writtenIn(l, scriptOf(d.text));
        if (fits && (best == null || d.text.length > best.text.length)) best = d;
      }
      r = best ?? (text: r.text, lang: '');
    }
    final seconds = samples.length / sampleRate;
    if (r.text.isEmpty || !plausible(r.text, seconds)) return null;
    return Heard(r.text, seconds, sw.elapsedMilliseconds, language: r.lang, forced: p.force.isNotEmpty);
  }

  void free() {
    _vad.free();
    _rec.free();
  }
}

/// The last few seconds of audio, addressed by absolute sample index (the
/// detector's segment start), so an utterance can be cut out with margins.
class AudioRing {
  AudioRing(this.capacity) : _buf = Float32List(capacity);
  final int capacity;
  final Float32List _buf;
  int _total = 0; // samples ever added

  void add(Float32List s) {
    for (var i = 0; i < s.length; i++) {
      _buf[(_total + i) % capacity] = s[i];
    }
    _total += s.length;
  }

  void clear() => _total = 0;

  /// Samples [from, to) clamped to what is still held; null if none are.
  Float32List? slice(int from, int to) {
    final lo = from < _total - capacity ? _total - capacity : from;
    final start = lo < 0 ? 0 : lo;
    final end = to > _total ? _total : to;
    if (end <= start) return null;
    final out = Float32List(end - start);
    for (var i = 0; i < out.length; i++) {
      out[i] = _buf[(start + i) % capacity];
    }
    return out;
  }
}

/// Whether this much text can have been said in this much audio. Whisper
/// invents long sentences from a second of rustle; people do not speak faster
/// than about 30 characters a second.
bool plausible(String text, double seconds) {
  final letters = text.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length;
  if (letters == 0) return false;
  return letters / (seconds < 0.5 ? 0.5 : seconds) <= 30;
}

/// Whisper's known noise on silence or music: bracketed tags and a few
/// phrases it hallucinates when nobody is talking.
String cleanText(String raw) {
  var t = raw.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|♪+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = t.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '').trim();
  const ghosts = {
    'thank you', 'thanks for watching', 'thank you for watching', 'you', 'bye',
    'subtitles by the amaraorg community', 'please subscribe',
  };
  if (lower.isEmpty || ghosts.contains(lower)) return '';
  // Whisper sometimes loops on noise: "je vais vous montrer, je vais vous montrer, ..."
  t = t.replaceAllMapped(RegExp(r'(.{6,}?)(?:[,.!?\s]+\1){2,}', unicode: true, caseSensitive: false), (m) => m[1]!);
  return t;
}

/// PCM16 little-endian bytes to floats in -1..1. An odd trailing byte is kept
/// for the next call by the caller ([Pcm16Decoder]).
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final view = ByteData.sublistView(bytes, 0, n * 2);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Stream chunks are not aligned to samples; this carries the odd byte over.
class Pcm16Decoder {
  int? _carry;
  void reset() => _carry = null;
  Float32List add(Uint8List chunk) {
    Uint8List b = chunk;
    if (_carry != null) {
      b = Uint8List(chunk.length + 1)
        ..[0] = _carry!
        ..setRange(1, chunk.length + 1, chunk);
      _carry = null;
    }
    if (b.length.isOdd) {
      _carry = b.last;
      b = Uint8List.sublistView(b, 0, b.length - 1);
    }
    return pcm16ToFloat(b);
  }
}

// ---------------------------------------------------------------- isolate

/// Runs [Asr] in its own isolate, so decoding never stalls the UI.
class AsrWorker {
  AsrWorker._(this._isolate, this._toWorker, this._events);

  final Isolate _isolate;
  final SendPort _toWorker;
  final Stream<Object> _events;

  Stream<Heard> get heard => _events.where((e) => e is Heard).cast<Heard>();
  Stream<String> get errors => _events.where((e) => e is String).cast<String>();

  /// 'hearing' (speech detected), 'decoding' (writing it down), 'idle'.
  Stream<String> get phases => _events.where((e) => e is List).map((e) => (e as List)[1] as String);

  static Future<AsrWorker> start(AsrConfig config) async {
    final fromWorker = ReceivePort();
    final iso = await Isolate.spawn(_main, [fromWorker.sendPort, config]);
    final events = fromWorker.asBroadcastStream();
    final first = await events.first;
    if (first is String) {
      iso.kill();
      throw StateError(first);
    }
    return AsrWorker._(iso, first as SendPort, events.cast<Object>());
  }

  void add(Float32List samples) => _toWorker.send(TransferableTypedData.fromList([samples]));
  void flush() => _toWorker.send('flush');
  void reset() => _toWorker.send('reset');
  void setPolicy(LanguagePolicy p) => _toWorker.send(p.toJson());

  void stop() {
    _toWorker.send('stop');
    Future.delayed(const Duration(seconds: 2), () => _isolate.kill());
  }

  static void _main(List<Object> args) {
    final out = args[0] as SendPort;
    final config = args[1] as AsrConfig;
    Asr asr;
    try {
      so.initBindings();
      asr = Asr(config);
    } catch (e) {
      out.send('could not load the speech model: $e');
      return;
    }
    asr.onPhase = (p) => out.send(['phase', p]);
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((msg) {
      try {
        if (msg is TransferableTypedData) {
          for (final h in asr.accept(msg.materialize().asFloat32List())) {
            out.send(h);
          }
        } else if (msg is Map) {
          asr.setPolicy(LanguagePolicy.fromJson(msg));
        } else if (msg == 'reset') {
          asr.reset();
        } else if (msg == 'flush') {
          for (final h in asr.flush()) {
            out.send(h);
          }
        } else if (msg == 'stop') {
          asr.free();
          inbox.close();
        }
      } catch (e) {
        out.send('speech error: $e');
      }
    });
  }
}
