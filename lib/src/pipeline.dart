import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'asr.dart';
import 'languages.dart';
import 'speaker.dart';
import 'translator.dart';

enum Mode {
  /// Everything heard becomes your language: wear earbuds, keep the phone out.
  listen,

  /// Two people, two languages: each side is translated into the other's.
  conversation,
}

/// Which way one utterance goes.
class Direction {
  const Direction(this.from, this.to, {this.guessed = false});
  final String from, to;

  /// The speech model's language was outside the pair, so the side was
  /// inferred from turn-taking.
  final bool guessed;

  @override
  bool operator ==(Object other) =>
      other is Direction && other.from == from && other.to == to && other.guessed == guessed;
  @override
  int get hashCode => Object.hash(from, to, guessed);
  @override
  String toString() => '$from→$to${guessed ? '?' : ''}';
}

/// Decides the direction of an utterance. Pure, so it is tested alone.
///
/// Listen: whatever was said, into [mine]. Conversation: the language heard
/// picks the side; a short clip is sometimes heard as a third language, and
/// then the speaker is taken to be the one who did not speak last.
Direction decide(Mode mode, String heard, {required String mine, required String theirs, String? lastFrom}) {
  if (mode == Mode.listen) return Direction(heard.isEmpty ? theirs : heard, mine, guessed: heard.isEmpty);
  if (heard == mine) return Direction(mine, theirs);
  if (heard == theirs) return Direction(theirs, mine);
  final from = lastFrom == theirs ? mine : theirs;
  return Direction(from, from == mine ? theirs : mine, guessed: true);
}

/// One line of the transcript.
class Line {
  Line(this.heard, this.direction);
  final Heard heard;
  final Direction direction;
  String? translation;
  String? problem;
  bool get pending => translation == null && problem == null;
}

/// Microphone → speech model → translation → voice, with the transcript as
/// state for the UI.
class LiveTranslator extends ChangeNotifier {
  LiveTranslator({required this.engine, required this.speaker});

  final TranslationEngine engine;
  final Speaker speaker;

  Mode mode = Mode.listen;
  String mine = 'en';
  String theirs = 'es';
  bool speak = true;

  final lines = <Line>[];
  bool running = false;
  bool hearing = false;
  String? error;

  AsrWorker? _asr;
  AudioRecorder? _mic;
  StreamSubscription? _micSub, _heardSub, _errSub;
  final _decoder = Pcm16Decoder();
  Future<void> _queue = Future.value();
  int _waiting = 0;
  DateTime _muteUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastFrom;

  Future<void> start(AsrConfig config) async {
    if (running) return;
    error = null;
    _mic = AudioRecorder();
    if (!await _mic!.hasPermission()) {
      error = 'Microphone permission is needed to listen.';
      notifyListeners();
      return;
    }
    try {
      _asr = await AsrWorker.start(config);
    } catch (e) {
      error = '$e';
      notifyListeners();
      return;
    }
    _heardSub = _asr!.heard.listen(_onHeard);
    _errSub = _asr!.errors.listen((e) {
      error = e;
      notifyListeners();
    });
    final stream = await _mic!.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      // the phone's own microphone hears the room; earbuds stay on high-quality
      // playback instead of switching to a call headset
      androidConfig: AndroidRecordConfig(manageBluetooth: false, audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _micSub = stream.listen((bytes) {
      // never hear ourselves: drop the microphone while a translation plays
      if (DateTime.now().isBefore(_muteUntil)) return;
      _asr?.add(_decoder.add(bytes));
    });
    running = true;
    hearing = true;
    notifyListeners();
  }

  Future<void> stop() async {
    _asr?.flush();
    await _micSub?.cancel();
    await _mic?.stop();
    await _mic?.dispose();
    _mic = null;
    await Future.delayed(const Duration(milliseconds: 300));
    await _heardSub?.cancel();
    await _errSub?.cancel();
    _asr?.stop();
    _asr = null;
    running = false;
    hearing = false;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  void _onHeard(Heard h) {
    final d = decide(mode, h.language, mine: mine, theirs: theirs, lastFrom: _lastFrom);
    _lastFrom = d.from;
    final line = Line(h, d);
    lines.add(line);
    notifyListeners();
    _waiting++;
    _queue = _queue.then((_) => _process(line)).whenComplete(() => _waiting--);
  }

  Future<void> _process(Line line) async {
    final d = line.direction;
    try {
      if (d.from == d.to) {
        line.translation = line.heard.text;
      } else if (!engine.supports(d.from)) {
        line.problem = '${nameOf(d.from)} cannot be translated on this device yet';
      } else {
        await engine.prepare(d.from);
        await engine.prepare(d.to);
        line.translation = await engine.translate(line.heard.text, from: d.from, to: d.to);
      }
    } catch (e) {
      line.problem = '$e';
    }
    notifyListeners();
    final text = line.translation;
    // when lines pile up, read only the newest: a voice that lags is worse than a skipped line
    if (speak && text != null && d.from != d.to && _waiting <= 1) {
      _muteUntil = DateTime.now().add(const Duration(minutes: 1));
      try {
        final ok = await speaker.say(text, d.to);
        if (!ok) line.problem = 'No voice for ${nameOf(d.to)} on this phone (Settings › Text-to-speech)';
      } finally {
        _muteUntil = DateTime.now().add(const Duration(milliseconds: 350));
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    engine.close();
    super.dispose();
  }
}
