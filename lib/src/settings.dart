import 'package:shared_preferences/shared_preferences.dart';

import 'pipeline.dart';

/// The choices a person makes once and expects to find again.
class Settings {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  String get model => _p.getString('model') ?? 'whisper-small';
  set model(String v) => _p.setString('model', v);

  Mode get mode => _p.getString('mode') == 'conversation' ? Mode.conversation : Mode.listen;
  set mode(Mode v) => _p.setString('mode', v.name);

  String get mine => _p.getString('mine') ?? 'en';
  set mine(String v) => _p.setString('mine', v);

  String get theirs => _p.getString('theirs') ?? 'es';
  set theirs(String v) => _p.setString('theirs', v);

  /// Listen mode's spoken language; '' = any.
  String get listenFrom => _p.getString('listenFrom') ?? '';
  set listenFrom(String v) => _p.setString('listenFrom', v);

  /// Conversation: tell who is speaking from the sound (off = tap the speaker).
  bool get autoSpeaker => _p.getBool('autoSpeaker') ?? false;
  set autoSpeaker(bool v) => _p.setBool('autoSpeaker', v);

  /// Run the speech model through Android's NNAPI (GPU/NPU) instead of the CPU.
  bool get accel => _p.getBool('accel') ?? false;
  set accel(bool v) => _p.setBool('accel', v);

  /// Set while NNAPI is being tried and cleared after the first successful
  /// transcription. Still set at the next start means the app died trying: the
  /// switch is turned off so it cannot crash-loop.
  bool get accelTrying => _p.getBool('accelTrying') ?? false;
  set accelTrying(bool v) => _p.setBool('accelTrying', v);

  /// Use the Hebrew speech pack for Hebrew when it is installed.
  bool get hebrewPack => _p.getBool('hebrewPack') ?? true;
  set hebrewPack(bool v) => _p.setBool('hebrewPack', v);

  /// The Hebrew translation pack was offered once (it stays in Settings after a "Not now").
  bool get mtOffered => _p.getBool('mtOffered') ?? false;
  set mtOffered(bool v) => _p.setBool('mtOffered', v);

  /// The upgrade from the first Hebrew translation pack (Opus-MT) was offered.
  bool get mtUpgradeOffered => _p.getBool('mtUpgradeOffered') ?? false;
  set mtUpgradeOffered(bool v) => _p.setBool('mtUpgradeOffered', v);

  /// Show the words of a sentence while it is still being spoken.
  bool get partials => _p.getBool('partials') ?? true;
  set partials(bool v) => _p.setBool('partials', v);

  bool get speak => _p.getBool('speak') ?? true;
  set speak(bool v) => _p.setBool('speak', v);

  /// The phone voice picked for a language (its name), or '' for the phone's default.
  String voiceFor(String code) => _p.getString('voice.$code') ?? '';
  void setVoiceFor(String code, String name) => name.isEmpty ? _p.remove('voice.$code') : _p.setString('voice.$code', name);
}
