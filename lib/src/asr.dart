import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'languages.dart';

const sampleRate = 16000;

/// Where the speech model's files are, and how to run it.
class AsrConfig {
  const AsrConfig({
    required this.vad,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.language = '',
    this.threads = 2,
  });

  final String vad, encoder, decoder, tokens;

  /// '' = detect the language of every utterance.
  final String language;
  final int threads;
}

/// One stretch of speech, as heard.
class Heard {
  const Heard(this.text, this.language, this.seconds, this.decodeMs);
  final String text;

  /// Whisper's language code, normalised ('en', 'he'…); '' when unknown.
  final String language;
  final double seconds;
  final int decodeMs;

  @override
  String toString() => '[$language ${seconds.toStringAsFixed(1)}s ${decodeMs}ms] $text';
}

/// Voice activity detection cuts the microphone into utterances; Whisper
/// transcribes each one and names its language. Synchronous: run it off the
/// UI thread ([AsrWorker]).
class Asr {
  Asr(this.config) {
    _vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(
          model: config.vad,
          threshold: 0.5,
          minSilenceDuration: 0.4, // a short pause ends a sentence: lower latency
          minSpeechDuration: 0.25,
          maxSpeechDuration: 8.0, // long monologues are cut so translation keeps up
        ),
        sampleRate: sampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );
    _rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        whisper: so.OfflineWhisperModelConfig(
          encoder: config.encoder,
          decoder: config.decoder,
          language: config.language,
          task: 'transcribe',
          tailPaddings: -1,
        ),
        tokens: config.tokens,
        numThreads: config.threads,
        debug: false,
      ),
    ));
  }

  final AsrConfig config;
  late final so.VoiceActivityDetector _vad;
  late final so.OfflineRecognizer _rec;

  /// Feeds audio (mono, 16 kHz, -1..1). Returns every utterance it completed.
  List<Heard> accept(Float32List samples) {
    _vad.acceptWaveform(samples);
    return _drain();
  }

  /// Ends the current utterance, if any (e.g. push-to-talk released).
  List<Heard> flush() {
    _vad.flush();
    final out = _drain();
    _vad.reset();
    return out;
  }

  bool get speaking => _vad.isDetected();

  List<Heard> _drain() {
    final out = <Heard>[];
    while (!_vad.isEmpty()) {
      final seg = _vad.front();
      _vad.pop();
      final h = transcribe(seg.samples);
      if (h != null) out.add(h);
    }
    return out;
  }

  Heard? transcribe(Float32List samples) {
    final sw = Stopwatch()..start();
    final stream = _rec.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _rec.decode(stream);
      final r = _rec.getResult(stream);
      final text = cleanText(r.text);
      if (text.isEmpty) return null;
      return Heard(text, normaliseLanguageTag(r.lang), samples.length / sampleRate, sw.elapsedMilliseconds);
    } finally {
      stream.free();
    }
  }

  void free() {
    _vad.free();
    _rec.free();
  }
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
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((msg) {
      try {
        if (msg is TransferableTypedData) {
          for (final h in asr.accept(msg.materialize().asFloat32List())) {
            out.send(h);
          }
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
