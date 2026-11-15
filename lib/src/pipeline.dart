import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'asr.dart';
import 'languages.dart';
import 'joiner.dart';
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

/// Which recogniser handles a language: the Hebrew pack for Hebrew when it is
/// installed, the main model for everything else.
String modelKeyFor(String? language, {required bool hasHebrewPack}) =>
    language == 'he' && hasHebrewPack ? 'he' : 'main';

/// Whether settings must stay locked: really listening. A tap conversation
/// waiting between turns (microphone ready, no side tapped) is not busy.
bool listeningBusy({required bool running, required bool tapMode, String? side}) =>
    running && !(tapMode && side == null);

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

  /// A non-error message for the person (a fallback that happened).
  String? notice;

  /// What the recogniser is doing: 'hearing', 'decoding' or 'idle'.
  String phase = 'idle';

  /// The words so far of the sentence being spoken ('' when none).
  String partial = '';

  /// Show [partial] while speaking (only where the language is known in advance).
  bool _partials = true;
  bool get showPartials => _partials;
  set showPartials(bool v) {
    _partials = v;
    for (final w in _workers.values) {
      w.setPartials(v);
    }
    if (!v) partial = '';
  }

  /// Loaded recognisers by key ('main', and 'he' when the Hebrew pack is installed).
  final _workers = <String, AsrWorker>{};
  final _subs = <String, List<StreamSubscription>>{};

  /// What to load: set by the screen from the installed models.
  Map<String, AsrConfig> configs = const {};

  bool get hasHebrewPack => configs.containsKey('he');

  /// The language being listened for right now (a tapped side, or Listen's
  /// picked language), or null when it is not known in advance.
  String? get activeLanguage {
    if (mode == Mode.listen) return listenFrom.isEmpty ? null : listenFrom;
    if (!autoSpeaker && side != null) return side == 'mine' ? mine : theirs;
    return null;
  }

  String get activeKey => modelKeyFor(activeLanguage, hasHebrewPack: hasHebrewPack);

  AsrWorker? get _asr => _workers[activeKey] ?? _workers['main'];

  AudioRecorder? _mic;
  StreamSubscription? _micSub;
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

  /// Loads one recogniser, or keeps the one already loaded when it is the same:
  /// models stay in memory between stop and start (loading the 1 GB one takes
  /// seconds) and go when this translator is disposed or another is asked for.
  Future<bool> _ensureWorker(String key, AsrConfig config) async {
    final have = _workers[key];
    if (have != null && (have.config.sameModel(config) || (_fellBack && have.config.sameModel(config.onCpu())))) {
      have.setEndSilence(config.endSilence);
      return true;
    }
    await _dropWorker(key);
    AsrWorker? w;
    try {
      w = await AsrWorker.start(config);
    } catch (e) {
      if (config.provider == 'cpu') {
        error = '$e';
        return false;
      }
      // the hardware route would not load this model: carry on with the CPU
      notice = 'The GPU could not run this model; using the CPU.';
      try {
        w = await AsrWorker.start(config.onCpu());
        _fellBack = true;
      } catch (e2) {
        error = '$e2';
        return false;
      }
    }
    w.setPartials(_partials);
    _workers[key] = w;
    _subs[key] = [
      w.heard.listen(_onHeard),
      w.phases.listen((p) => _onPhase(key, p)),
      w.partialText.listen((t) {
        if (key != activeKey || t == partial) return;
        partial = t;
        notifyListeners();
      }),
      w.errors.listen((e) {
        error = e;
        notifyListeners();
      }),
    ];
    return true;
  }

  bool _fellBack = false;
  Timer? _missedTimer;
  Timer? _idleTimer;
  Future<bool>? _loading;

  /// The speech model: 'none', 'loading', 'ready' or 'failed'.
  String modelState = 'none';

  /// The recognisers this setup needs: the main one always, the Hebrew pack
  /// too when Hebrew is one of the languages spoken and the pack is installed.
  Set<String> get neededKeys => {
        'main',
        if (hasHebrewPack &&
            ((mode == Mode.conversation && (mine == 'he' || theirs == 'he')) || (mode == Mode.listen && listenFrom == 'he')))
          'he',
      };

  /// Loads the speech models now, before anyone taps, so the first tap is
  /// instant. Safe to call again: a load in progress is shared.
  Future<bool> preload() {
    final needed = neededKeys;
    if (needed.every((k) => _workers[k]?.config.sameModel(configs[k]!) ?? false)) return Future.value(true);
    return _loading ??= () async {
      modelState = 'loading';
      notifyListeners();
      var ok = true;
      for (final k in needed) {
        if (!await _ensureWorker(k, configs[k]!)) {
          ok = false;
          break;
        }
      }
      // a model nobody needs any more leaves memory
      for (final k in _workers.keys.where((k) => !needed.contains(k)).toList()) {
        await _dropWorker(k);
      }
      modelState = ok ? 'ready' : 'failed';
      _loading = null;
      notifyListeners();
      return ok;
    }();
  }

  /// A tap conversation keeps the microphone open between turns (no start-up
  /// lag on the next tap), feeding nothing to the model while no side is
  /// chosen, and closes it after this long without a tap.
  static const idleClose = Duration(seconds: 45);
  bool get tapMode => mode == Mode.conversation && !autoSpeaker;

  /// Sentences written down so far (any outcome): the GPU crash guard reads it.
  int decodes = 0;

  void _onPhase(String key, String p) {
    if (key != activeKey && p != 'decoding' && p != 'missed') return; // a worker that is not listening
    if (phase == 'decoding' && p != 'decoding') decodes++;
    _missedTimer?.cancel();
    if (p == 'missed') {
      // say it for a few seconds, then go quiet again
      _missedTimer = Timer(const Duration(seconds: 4), () {
        if (phase == 'missed') {
          phase = 'idle';
          notifyListeners();
        }
      });
    }
    if (p == phase) return;
    phase = p;
    notifyListeners();
  }

  Future<void> _dropWorker(String key) async {
    for (final sub in _subs.remove(key) ?? const <StreamSubscription>[]) {
      await sub.cancel();
    }
    _workers.remove(key)?.stop();
  }

  Future<void> start() async {
    if (running) return;
    error = null;
    _mic = AudioRecorder();
    if (!await _mic!.hasPermission()) {
      error = 'Microphone permission is needed to listen.';
      notifyListeners();
      return;
    }
    if (!await preload()) {
      notifyListeners();
      return;
    }
    _applyPolicy();
    _asr?.reset();
    _decoder.reset();
    _warmUp();
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
      // a tap conversation between turns: the microphone is open, nobody is speaking to it
      if (tapMode && side == null) return;
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

  /// Gets everything the first sentence will need ready while the person
  /// starts talking: both translation directions and the voices.
  Future<void> _warmUp() async {
    try {
      final pair = {mine, if (mode == Mode.conversation) theirs, if (listenFrom.isNotEmpty) listenFrom};
      for (final c in pair) {
        if (engine.supports(c) && !await engine.isReady(c)) return; // would download: not a warm-up
      }
      if (mode == Mode.conversation) {
        await engine.translate('Hello', from: mine, to: theirs);
        await engine.translate('Hello', from: theirs, to: mine);
        await speaker.warm(theirs);
        await speaker.warm(mine);
      } else {
        await speaker.warm(mine);
        if (listenFrom.isNotEmpty) await engine.translate('Hello', from: listenFrom, to: mine);
      }
    } catch (_) {} // a warm-up must never become an error
  }

  /// What the recogniser may write now. Listen with a language picked: that
  /// one. A tap conversation: the tapped side's. An auto conversation: either.
  LanguagePolicy get policy {
    if (mode == Mode.listen) return LanguagePolicy(force: listenFrom);
    if (!autoSpeaker && side != null) return LanguagePolicy(force: side == 'mine' ? mine : theirs);
    return LanguagePolicy(allowed: {mine, theirs});
  }

  void _applyPolicy() => _asr?.setPolicy(policy);

  /// Switches the microphone to the recogniser for [newSide]'s language: the
  /// one that was listening finishes its sentence first.
  void _switchTo(String newSide) {
    final before = _asr;
    final hadSide = side != null;
    if (hadSide) {
      before?.flush();
      Timer(const Duration(milliseconds: 400), _releaseHeld); // let the finished sentence arrive, then do not hold it
    }
    side = newSide;
    final after = _asr;
    if (!hadSide || !identical(before, after)) {
      after?.reset(); // start clean
      _decoder.reset();
    }
    _applyPolicy();
  }

  /// Tap conversation: listen for [which] ('mine' or 'theirs'). Starts the
  /// microphone if needed; tapping the active side again stops it.
  Future<void> tapSide(String which) async {
    _idleTimer?.cancel();
    if (running && side == which) {
      // done speaking: write it down, keep the microphone warm for the next turn
      final w = _asr;
      side = null;
      notifyListeners();
      _idleTimer = Timer(idleClose, stop);
      await w?.flushAndWait();
      await _ids; // the last sentence has been given its direction
      _releaseHeld();
      return;
    }
    if (running) {
      _switchTo(which);
      notifyListeners();
      return;
    }
    side = which;
    await start();
    if (!running) side = null;
  }

  /// Stops listening. The sentence in progress is still written down and
  /// translated (the old code waited 0.3 s and then threw it away), and the
  /// speech model stays loaded for the next start.
  Future<void> stop() async {
    _idleTimer?.cancel();
    if (!running) return;
    running = false;
    hearing = false;
    side = null;
    notifyListeners();
    await _micSub?.cancel();
    _micSub = null;
    await _mic?.stop();
    await _mic?.dispose();
    _mic = null;
    await Future.wait([for (final w in _workers.values) w.flushAndWait()]);
    await _ids;
    _releaseHeld();
    notifyListeners();
  }

  /// Reads a line's translation aloud again (tap on a bubble).
  Future<void> replay(Line line) async {
    final t = line.translation;
    if (t == null || line.direction.from == line.direction.to) return;
    _muteUntil = DateTime.now().add(const Duration(minutes: 1));
    _muted = true;
    _spoken.add((text: t, at: DateTime.now().add(const Duration(minutes: 1))));
    try {
      await speaker.say(t, line.direction.to);
    } finally {
      _muteUntil = DateTime.now().add(const Duration(milliseconds: 900));
      _spoken.last = (text: t, at: DateTime.now());
    }
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
      _release(_joiner.offer(h, d, DateTime.now()));
      _joinTimer?.cancel();
      if (_joiner.holding) {
        _joinTimer = Timer(_joiner.window, () {
          _release(_joiner.due(DateTime.now()));
          _showHeld();
        });
      }
      _showHeld(); // a piece waiting for the rest of its sentence stays on screen as words so far
    }).catchError((Object e) {
      error = '$e';
      notifyListeners();
    });
  }

  final _joiner = SentenceJoiner();
  Timer? _joinTimer;

  void _showHeld() {
    final t = _joiner.heldText;
    if (t == partial) return;
    partial = t;
    notifyListeners();
  }

  /// Pieces that are ready: shown, translated and spoken, in order.
  void _release(List<(Heard, Direction)> ready) {
    for (final (h, d) in ready) {
      final line = Line(h, d);
      lines.add(line);
      notifyListeners();
      _waiting++;
      _queue = _queue.then((_) => _process(line)).whenComplete(() => _waiting--);
    }
  }

  /// Lets go of a piece still waiting for the rest of its sentence (the person
  /// stopped or changed side: no more is coming).
  void _releaseHeld() {
    _joinTimer?.cancel();
    _release(_joiner.flush());
    _showHeld();
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

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners(); // the last sentence may land after the screen has gone
  }

  @override
  void dispose() {
    _disposed = true;
    _missedTimer?.cancel();
    _idleTimer?.cancel();
    _joinTimer?.cancel();
    stop().whenComplete(() async {
      for (final k in _workers.keys.toList()) {
        await _dropWorker(k);
      }
    }); // the speech models leave memory with the screen
    engine.close();
    guesser.close();
    super.dispose();
  }
}
