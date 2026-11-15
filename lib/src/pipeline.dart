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

/// Decides the direction of an utterance.
///
/// The recogniser says which language it wrote ([Heard.language]); that is
/// trusted when it is one of the languages in play and its text is in that
/// language's alphabet. Otherwise the text decides (alphabet, then ML Kit).
/// Listen with the spoken language picked: that language. Conversation: only
/// [mine] and [theirs] are ever answered; text that fits neither is taken as
/// the turn of whoever did not speak last.
Future<Direction> direct(Mode mode, Heard h, TextLanguageGuesser guesser,
    {required String mine, required String theirs, String listenFrom = '', String? lastFrom}) async {
  final script = scriptOf(h.text);
  // a language the person chose (tapped their side): no guessing at all
  if (mode == Mode.conversation && h.forced && (h.language == mine || h.language == theirs)) {
    return Direction(h.language, h.language == mine ? theirs : mine);
  }
  bool trusted(String l, Set<String> among) => l.isNotEmpty && (among.isEmpty || among.contains(l)) && writtenIn(l, script);
  if (mode == Mode.listen) {
    if (listenFrom.isNotEmpty) return Direction(listenFrom, mine);
    final l = trusted(h.language, const {}) ? h.language : await identify(h.text, guesser);
    return Direction(l ?? '', mine, guessed: l == null);
  }
  final pair = {mine, theirs};
  final other = lastFrom == theirs ? mine : theirs;
  final l = trusted(h.language, pair) ? h.language : await identify(h.text, guesser, among: pair, prefer: other);
  if (l != null) return Direction(l, l == mine ? theirs : mine);
  return Direction(other, other == mine ? theirs : mine, guessed: true);
}

/// Whether [heard] is the phone's own voice coming back through the
/// microphone: it matches something spoken a moment ago, allowing for the
/// recogniser's small mistakes.
bool isEcho(String heard, Iterable<String> spoken) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final h = norm(heard);
  if (h.length < 4) return false;
  for (final sp in spoken) {
    final t = norm(sp);
    if (t.isEmpty) continue;
    if (t.contains(h) || h.contains(t)) return true;
    final longest = h.length > t.length ? h.length : t.length;
    if (_editDistance(h, t) / longest <= 0.35) return true;
  }
  return false;
}

int _editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
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

  /// Conversation: false = the person taps who is speaking (accurate, one
  /// pass); true = the app tries to tell from the sound (slower, can be wrong).
  bool autoSpeaker = false;

  /// In a tap conversation: whose language is being listened for now.
  /// 'mine', 'theirs', or null when nobody has been picked yet.
  String? side;

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
  bool _muted = false;
  final _spoken = <({String text, DateTime at})>[];

  /// Lines are piling up faster than they are translated: the phone is too
  /// slow for the speech model chosen.
  bool get behind => _waiting >= 3;

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
    _applyPolicy();
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
      if (_muted) {
        // first audio after the voice stopped: start the detector clean
        _muted = false;
        _asr?.reset();
        _decoder.reset();
      }
      _asr?.add(_decoder.add(bytes));
    });
    running = true;
    hearing = true;
    notifyListeners();
  }

  /// What the recogniser may write now. Listen with a language picked: that
  /// one. A tap conversation: the tapped side's. An auto conversation: either.
  LanguagePolicy get policy {
    if (mode == Mode.listen) return LanguagePolicy(force: listenFrom);
    if (!autoSpeaker && side != null) return LanguagePolicy(force: side == 'mine' ? mine : theirs);
    return LanguagePolicy(allowed: {mine, theirs});
  }

  void _applyPolicy() => _asr?.setPolicy(policy);

  /// Tap conversation: listen for [which] ('mine' or 'theirs'). Starts the
  /// microphone if needed; tapping the active side again stops it.
  Future<void> tapSide(String which, AsrConfig config) async {
    if (running && side == which) {
      await stop();
      return;
    }
    if (running) {
      _asr?.flush(); // finish what the other side was saying under the old language
      side = which;
      _applyPolicy();
      notifyListeners();
      return;
    }
    side = which;
    await start(config);
    if (!running) side = null;
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
    side = null;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  void _onHeard(Heard h) {
    // the phone's own voice, heard through the microphone and written down as speech
    if (isEcho(h.text, [for (final s in _spoken) if (DateTime.now().difference(s.at).inMilliseconds < 4000) s.text])) {
      return;
    }
    // Two queues, both in spoken order: telling the language is quick and
    // shows the line at once; translating and speaking can lag behind it.
    _ids = _ids.then((_) async {
      final d = await direct(mode, h, guesser,
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
      // while it speaks (and for 4 s after), what it said counts as echo; a reply that
      // happens to repeat it later is real speech
      _spoken.add((text: text, at: DateTime.now().add(const Duration(minutes: 1))));
      if (_spoken.length > 6) _spoken.removeAt(0);
      _muteUntil = DateTime.now().add(const Duration(minutes: 1));
      _muted = true;
      _asr?.flush(); // finish what was being said before the voice starts
      try {
        final ok = await speaker.say(text, d.to);
        if (!ok) line.problem = 'No voice for ${nameOf(d.to)} on this phone (Settings › Text-to-speech)';
      } finally {
        // the room still rings and the microphone is still delivering old audio
        _muteUntil = DateTime.now().add(const Duration(milliseconds: 900));
        _spoken.last = (text: text, at: DateTime.now());
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
