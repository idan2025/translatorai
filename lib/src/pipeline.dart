import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'asr.dart';
import 'languages.dart';
import 'lid.dart';
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

  /// '' when the language could not be told.
  final String from, to;

  /// The text fitted none of the expected languages, so the side was
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

/// Decides the direction of an utterance from its text.
///
/// Listen: into [mine]. With a spoken language pinned ([listenFrom]) only it
/// and [mine] are considered, so a phrase can never come out as a third
/// language; with "any language", the alphabet and then the text identifier
/// decide. Conversation: only [mine] and [theirs] are considered; text that
/// fits neither is taken as the turn of whoever did not speak last.
Future<Direction> direct(Mode mode, String text, TextLanguageGuesser guesser,
    {required String mine, required String theirs, String listenFrom = '', String? lastFrom}) async {
  if (mode == Mode.listen) {
    if (listenFrom.isNotEmpty) {
      final id = await identify(text, guesser, among: {listenFrom, mine}, prefer: listenFrom);
      return Direction(id ?? listenFrom, mine);
    }
    final id = await identify(text, guesser);
    return Direction(id ?? '', mine, guessed: id == null);
  }
  final other = lastFrom == theirs ? mine : theirs;
  final id = await identify(text, guesser, among: {mine, theirs}, prefer: other);
  if (id != null) return Direction(id, id == mine ? theirs : mine);
  return Direction(other, other == mine ? theirs : mine, guessed: true);
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
  LiveTranslator({required this.engine, required this.speaker, required this.guesser});

  final TranslationEngine engine;
  final Speaker speaker;
  final TextLanguageGuesser guesser;

  Mode mode = Mode.listen;
  String mine = 'en';
  String theirs = 'es';

  /// Listen mode's spoken language; '' = any (told from the text).
  String listenFrom = '';
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
  Future<void> _ids = Future.value();
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
    // Two queues, both in spoken order: telling the language is quick and
    // shows the line at once; translating and speaking can lag behind it.
    _ids = _ids.then((_) async {
      final d = await direct(mode, h.text, guesser,
          mine: mine, theirs: theirs, listenFrom: listenFrom, lastFrom: _lastFrom);
      if (!d.guessed && d.from.isNotEmpty) _lastFrom = d.from;
      final line = Line(h, d);
      lines.add(line);
      notifyListeners();
      _waiting++;
      _queue = _queue.then((_) => _process(line)).whenComplete(() => _waiting--);
    }).catchError((Object e) {
      error = '$e';
      notifyListeners();
    });
  }

  Future<void> _process(Line line) async {
    final d = line.direction;
    try {
      if (d.from.isEmpty) {
        line.problem = 'Could not tell which language this is. Pick the spoken language above.';
      } else if (d.from == d.to) {
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
    guesser.close();
    super.dispose();
  }
}
