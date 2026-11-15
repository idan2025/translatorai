import 'package:shared_preferences/shared_preferences.dart';

import 'pipeline.dart';

/// The choices a person makes once and expects to find again.
class Settings {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  String get model => _p.getString('model') ?? 'omni-300m';
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

  bool get speak => _p.getBool('speak') ?? true;
  set speak(bool v) => _p.setBool('speak', v);
}
