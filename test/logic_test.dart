import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translatorai/src/latest.dart';
import 'package:translatorai/src/glossary.dart';
import 'package:translatorai/src/asr.dart';
import 'package:translatorai/src/languages.dart';
import 'package:translatorai/src/chrf.dart';
import 'package:translatorai/src/joiner.dart';
import 'package:translatorai/src/lid.dart';
import 'package:translatorai/src/updater.dart';
import 'package:translatorai/src/model_store.dart';
import 'package:translatorai/src/models.dart';
import 'package:translatorai/src/pipeline.dart';

void main() {
  glossaryTests();
  latestTests();
  group('direction', () {
    final g = FakeGuesser({'pausa': [Guess('it', .6), Guess('es', .3)], 'buenos dias': [Guess('es', .9)]});
    Heard hr(String text, [String lang = '']) => Heard(text, 1, 1, language: lang);

    test("listen with any language: the recogniser's language is trusted when its text fits", () async {
      expect(await direct(Mode.listen, hr('доброе утро', 'ru'), g, mine: 'en', theirs: 'es'), const Direction('ru', 'en'));
      expect(await direct(Mode.listen, hr('מה זה', 'he'), g, mine: 'en', theirs: 'es'), const Direction('he', 'en'));
    });
    test('a language whose alphabet does not fit the text is not trusted: the text decides', () async {
      // the v0.1 bug: Russian speech labelled Polish
      expect(await direct(Mode.listen, hr('доброе утро', 'pl'), g, mine: 'en', theirs: 'es'), const Direction('ru', 'en'));
      expect(await direct(Mode.listen, hr('buenos dias'), g, mine: 'en', theirs: 'es'), const Direction('es', 'en'));
      expect(await direct(Mode.listen, hr('zzzz'), g, mine: 'en', theirs: 'es'), const Direction('', 'en', guessed: true));
    });
    test('listen with a pinned language never answers another one', () async {
      expect(await direct(Mode.listen, hr('pausa', 'it'), g, mine: 'en', theirs: 'es', listenFrom: 'ru'), const Direction('ru', 'en'));
    });
    test('a conversation only ever answers its two languages', () async {
      expect(await direct(Mode.conversation, hr('доброе утро', 'ru'), g, mine: 'en', theirs: 'ru'), const Direction('ru', 'en'));
      expect(await direct(Mode.conversation, hr('good morning', 'en'), g, mine: 'en', theirs: 'ru'), const Direction('en', 'ru'));
      // heard as Polish: not in the pair, so the text decides between the two
      expect(await direct(Mode.conversation, hr('доброе утро', 'pl'), g, mine: 'en', theirs: 'ru'), const Direction('ru', 'en'));
      // Hebrew letters in an English-Russian conversation fit neither side: turn-taking decides, marked as a guess
      expect(await direct(Mode.conversation, hr('מה זה', 'he'), g, mine: 'en', theirs: 'ru', lastFrom: 'en'),
          const Direction('ru', 'en', guessed: true));
    });
    test('a tapped side is trusted without any guessing, whatever the alphabet', () async {
      final tapped = Heard('Booker Tove', 1, 1, language: 'he', forced: true);
      expect(await direct(Mode.conversation, tapped, g, mine: 'en', theirs: 'he'), const Direction('he', 'en'));
      final mineTapped = Heard('good morning', 1, 1, language: 'en', forced: true);
      expect(await direct(Mode.conversation, mineTapped, g, mine: 'en', theirs: 'he'), const Direction('en', 'he'));
    });
    test('two languages in one alphabet: the identifier picks between them only', () async {
      expect(await direct(Mode.conversation, hr('pausa'), g, mine: 'en', theirs: 'es'), const Direction('es', 'en'));
      expect(await direct(Mode.conversation, hr('qwerty'), g, mine: 'en', theirs: 'es', lastFrom: 'es'),
          const Direction('en', 'es'));
    });
  });

  group('alphabets', () {
    test('scripts are told apart and Japanese wins over Chinese when kana appear', () {
      expect(scriptOf('Привет'), Script.cyrillic);
      expect(scriptOf('שלום'), Script.hebrew);
      expect(scriptOf('مرحبا'), Script.arabic);
      expect(scriptOf('你好'), Script.han);
      expect(scriptOf('こんにちは世界'), Script.kana);
      expect(scriptOf('안녕'), Script.hangul);
      expect(scriptOf('Ça va'), Script.latin);
      expect(scriptOf('123 ?'), Script.other);
    });
    test("ML Kit's legacy tags are mapped", () {
      expect(normaliseTag('iw'), 'he');
      expect(normaliseTag('ru-Latn'), 'ru');
      expect(normaliseTag('fil'), 'tl');
    });
  });

  group('chrF', () {
    test('matches sacreBLEU on the same sentences, across alphabets', () {
      expect(chrF(["The cat sat on the mat.", "He is going to the store now"], ["The cat is on the mat.", "He is going to the store."]), closeTo(80.9638, 0.01));
      expect(chrF(["בוקר טוב לכולם", "אני רוצה כוס קפה"], ["בוקר טוב לכולם!", "אני רוצה כוס קפה בבקשה"]), closeTo(80.2838, 0.01));
      expect(chrF(["Доброе утро, как дела?", "Я ничего не сказал"], ["Доброе утро! Как дела?", "Я ничего не сказал, чтобы ты хотел"]), closeTo(61.5243, 0.01));
      expect(chrF(["identical text here"], ["identical text here"]), closeTo(100.0, 0.01));
      expect(chrF(["abc"], ["xyz"]), closeTo(0.0, 0.01));
    });
  });

  group('sentence joiner', () {
    final t0 = DateTime(2026, 11, 16, 12);
    const d = Direction('en', 'ru');
    Heard h(String t) => Heard(t, 1, 100, language: 'en');

    test('where a sentence ends', () {
      for (final t in ['It is late.', 'Is it late?', 'Stop!', 'Well…', '"Go home."', '你好。', 'Это так.']) {
        expect(endsSentence(t), isTrue, reason: t);
      }
      for (final t in ['Where is the', 'and then,', 'I want a', 'Hello there']) {
        expect(endsSentence(t), isFalse, reason: t);
      }
    });

    test('two halves of one sentence become one, in order', () {
      final j = SentenceJoiner();
      expect(j.offer(h('Where is the'), d, t0), isEmpty);
      final out = j.offer(h('new store till?'), d, t0.add(const Duration(milliseconds: 600)));
      expect(out.length, 1);
      expect(out.single.$1.text, 'Where is the new store till?');
      expect(out.single.$1.seconds, 2);
      expect(j.holding, isFalse);
    });

    test('a finished sentence goes at once, an unfinished one waits for the window then goes alone', () {
      final j = SentenceJoiner();
      expect(j.offer(h('Good morning.'), d, t0).single.$1.text, 'Good morning.');
      expect(j.offer(h('and then'), d, t0), isEmpty);
      expect(j.due(t0.add(const Duration(milliseconds: 1000))), isEmpty);
      expect(j.due(t0.add(const Duration(milliseconds: 1300))).single.$1.text, 'and then');
    });

    test('a piece in the other direction never joins: the old one goes first', () {
      final j = SentenceJoiner();
      expect(j.offer(h('How are'), d, t0), isEmpty);
      final out = j.offer(Heard('Хорошо', 1, 1, language: 'ru'), const Direction('ru', 'en'), t0.add(const Duration(milliseconds: 300)));
      expect(out.map((e) => e.$1.text), ['How are']);
      expect(j.holding, isTrue, reason: 'the new piece now waits for its own sentence');
    });

    test('nothing is held for ever, and stopping lets go', () {
      final j = SentenceJoiner();
      var now = t0;
      var released = <(Heard, Direction)>[];
      for (var i = 0; i < 12 && released.isEmpty; i++) {
        released = j.offer(h('and so on,'), d, now);
        now = now.add(const Duration(milliseconds: 900));
      }
      expect(released.single.$1.text, startsWith('and so on, and so on,'), reason: 'after 8 s it goes whatever it ends with');
      expect(j.flush().single.$1.text, 'and so on,', reason: 'the piece after it starts a new hold');
      expect(j.offer(h('wait'), d, now), isEmpty);
      expect(j.flush().single.$1.text, 'wait');
      expect(j.flush(), isEmpty);
    });

    test('Chinese and Japanese are joined without a space', () {
      expect(joinText('你好', '世界', 'zh'), '你好世界');
      expect(joinText('Hello', 'world', 'en'), 'Hello world');
    });
  });

  group('which recogniser', () {
    test('Hebrew goes to the Hebrew pack when it is installed, everything else to the main model', () {
      expect(modelKeyFor('he', hasHebrewPack: true), 'he');
      expect(modelKeyFor('he', hasHebrewPack: false), 'main');
      expect(modelKeyFor('en', hasHebrewPack: true), 'main');
      expect(modelKeyFor(null, hasHebrewPack: true), 'main', reason: 'language not known in advance');
    });
    test('the Hebrew pack is a pinned download that shares the main vocabulary file', () {
      expect(hebrewPack.language, 'he');
      expect(hebrewPack.tokens.name, speechModels.first.tokens.name);
      expect(allModelFiles.map((f) => f.name), containsAll(hebrewPack.files.map((f) => f.name)));
      for (final f in hebrewPack.files) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(f.url, startsWith('https://huggingface.co/'));
        expect(f.url, contains('/resolve/'), reason: 'pinned to a revision, never a branch');
        expect(f.url, isNot(contains('/resolve/main/')));
      }
    });
  });

  group('locking', () {
    test('settings lock only while really listening, not while a tap conversation waits for a tap', () {
      expect(listeningBusy(running: false, tapMode: true), isFalse);
      expect(listeningBusy(running: true, tapMode: true, side: 'mine'), isTrue, reason: 'a side is being heard');
      expect(listeningBusy(running: true, tapMode: true, side: null), isFalse, reason: 'between turns: the bug in 0.4.0');
      expect(listeningBusy(running: true, tapMode: false), isTrue, reason: 'Listen and auto mode keep the mic busy');
    });
  });

  group('echo and noise', () {
    test("the phone's own translation, heard back, is recognised as echo", () {
      final said = ['Доброе утро, как дела?', 'Where is the station?'];
      expect(isEcho('доброе утро как дела', said), isTrue);
      expect(isEcho('Where is the', said), isTrue, reason: 'a part of what was said');
      expect(isEcho('Wear is the station', said), isTrue, reason: 'a small mistake');
      expect(isEcho('I would like a coffee please', said), isFalse);
      expect(isEcho('ok', said), isFalse, reason: 'too short to judge');
      expect(isEcho('anything', const []), isFalse);
    });
    test('text faster than anyone can speak is noise, not speech', () {
      expect(plausible('Hello there', 1.0), isTrue);
      expect(plausible('I am going to tell you the whole story of my life right now', 0.6), isFalse);
      expect(plausible('...', 2.0), isFalse);
      expect(plausible('שלום', 0.3), isTrue);
    });
  });

  group('audio', () {
    test('the ring cuts an utterance out with margins, by absolute sample index', () {
      final r = AudioRing(10);
      r.add(Float32List.fromList([0, 1, 2, 3, 4, 5, 6, 7]));
      r.add(Float32List.fromList([8, 9, 10, 11]));
      expect(r.slice(5, 9), [5, 6, 7, 8]);
      expect(r.slice(0, 4), [2, 3], reason: 'only what is still held');
      expect(r.slice(10, 99), [10, 11]);
      expect(r.slice(20, 30), isNull);
    });
    test('PCM16 becomes floats and an odd byte waits for the next chunk', () {
      final d = Pcm16Decoder();
      // 0x4000 = 16384 = 0.5; -0x4000 = 0xC000
      final a = d.add(Uint8List.fromList([0x00, 0x40, 0x00]));
      final b = d.add(Uint8List.fromList([0xC0]));
      expect(a, [0.5]);
      expect(b, [-0.5]);
    });
  });

  group('text', () {
    test("Whisper's noise on silence is dropped and real speech kept", () {
      expect(cleanText(' [Music] '), '');
      expect(cleanText('Thank you.'), '');
      expect(cleanText('(applause) ♪♪'), '');
      expect(cleanText('Where is the station?'), 'Where is the station?');
      expect(cleanText('Thank you for the help [laughs]'), 'Thank you for the help');
      expect(cleanText('Je vais vous montrer, je vais vous montrer, je vais vous montrer, je vais vous montrer'), 'Je vais vous montrer');
      expect(cleanText('Ha ha, that is so funny, ha ha'), 'Ha ha, that is so funny, ha ha');
    });
    test('language tags are normalised', () {
      expect(normaliseLanguageTag('<|en|>'), 'en');
      expect(normaliseLanguageTag(' HE '), 'he');
    });
    test('every language has a name and the lists are unique', () {
      final codes = allLanguages().map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(knownLanguages.length, 99);
      expect(hearable.containsAll(['he', 'ar', 'zh', 'ru']), isTrue);
      expect(hearable.contains('eo'), isFalse, reason: 'Esperanto can be written but not heard');
    });
  });

  group('model download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('models-'));
    tearDown(() => dir.deleteSync(recursive: true));

    ModelFile spec(List<int> bytes, {String? digest}) =>
        ModelFile('m.onnx', 'https://example.invalid/m.onnx', digest ?? sha256.convert(bytes).toString(), bytes.length);

    test('a file whose digest matches is installed', () async {
      final bytes = utf8.encode('model bytes');
      final store = ModelStore(dir, client: MockClient((_) async => http.Response.bytes(bytes, 200)));
      final f = spec(bytes);
      final seen = <double>[];
      await store.ensure([f], onProgress: (d, t) => seen.add(d / t));
      expect(store.has(f), isTrue);
      expect(File(store.pathOf('m.onnx')).readAsBytesSync(), bytes);
      expect(seen.last, 1.0);
    });

    test('a file whose digest differs is discarded, never installed', () async {
      final bytes = utf8.encode('model bytes');
      final store = ModelStore(dir, client: MockClient((_) async => http.Response.bytes(utf8.encode('evil bytes!'), 200)));
      final f = spec(bytes);
      await expectLater(store.ensure([f]), throwsA(isA<ModelError>()));
      expect(store.has(f), isFalse);
      expect(dir.listSync(), isEmpty, reason: 'no partial file is left behind');
    });

    test('an HTTP error installs nothing', () async {
      final store = ModelStore(dir, client: MockClient((_) async => http.Response('nope', 404)));
      await expectLater(store.ensure([spec([1, 2, 3])]), throwsA(isA<ModelError>()));
      expect(dir.listSync(), isEmpty);
    });

    test('switching models keeps the other one: prune with every known file removes only leftovers', () async {
      for (final f in allModelFiles) {
        File('${dir.path}/${f.name}').writeAsStringSync('x');
      }
      File('${dir.path}/omni-1b.int8.onnx').writeAsStringSync('old model');
      File('${dir.path}/whisper-small-encoder.int8.onnx.part').writeAsStringSync('half');
      await ModelStore(dir).prune(allModelFiles);
      final left = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(left, {for (final f in allModelFiles) f.name});
    });

    test('deleting a model keeps the vocabulary file the other one shares', () async {
      for (final f in allModelFiles) {
        File('${dir.path}/${f.name}').writeAsStringSync('x');
      }
      final store = ModelStore(dir);
      await store.deleteModel(speechModels[1].files, except: speechModels[0].files);
      expect(store.hasAny(speechModels[1].files.where((f) => f.name != speechModels[0].tokens.name)), isFalse);
      expect(File('${dir.path}/${speechModels[0].tokens.name}').existsSync(), isTrue);
      expect(speechModels[0].files.every((f) => File('${dir.path}/${f.name}').existsSync()), isTrue,
          reason: 'the model in use is untouched');
    });

    test('prune keeps only the files in use', () async {
      File('${dir.path}/old-model.onnx').writeAsStringSync('x');
      File('${dir.path}/keep.onnx').writeAsStringSync('y');
      await ModelStore(dir).prune([const ModelFile('keep.onnx', '', '', 1)]);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['keep.onnx']);
    });

    test('an unknown or old model id falls back to Standard, so setup downloads it', () {
      expect(speechModelById('omni-1b').id, 'whisper-small');
    });

    test('every shipped model file is pinned to a digest', () {
      for (final f in [vadModel, for (final m in speechModels) ...m.files]) {
        expect(f.name, isNot(contains('/')));
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
        expect(f.url, startsWith('https://'));
        expect(f.bytes, greaterThan(0));
      }
    });
  });

  group('updates', () {
    test('versions compare by number, a suffix before the release', () {
      expect(compareVersions('v0.2.0', '0.1.0'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('v0.2.0', '0.2.0'), 0);
      expect(compareVersions('0.2.0-rc1', '0.2.0'), lessThan(0));
    });

    Map<String, dynamic> release(String tag, {bool draft = false, String? digest, bool shaFile = true}) => {
          'tag_name': tag,
          'draft': draft,
          'body': 'notes $tag',
          'html_url': 'https://github.com/x/$tag',
          'assets': [
            {
              'name': 'translatorai-${tag.substring(1)}-android-arm64.apk',
              'browser_download_url': 'https://dl/$tag.apk',
              'size': 4,
              if (digest != null) 'digest': 'sha256:$digest',
            },
            if (shaFile) {'name': 'translatorai-${tag.substring(1)}-android-arm64.apk.sha256', 'browser_download_url': 'https://dl/$tag.sha'},
          ],
        };

    final apkBytes = [1, 2, 3, 4];
    final apkSha = sha256.convert(apkBytes).toString();

    test('the newest non-draft release with an APK is picked', () {
      final p = pickRelease([release('v0.3.0', draft: true), release('v0.1.0'), release('v0.2.0')])!;
      expect(p.release['tag_name'], 'v0.2.0');
      expect(p.shaUrl, 'https://dl/v0.2.0.sha');
    });

    test('a newer release is offered with its digest, an older one is not', () async {
      final c = MockClient((r) async => switch (r.url.toString()) {
            releasesApi => http.Response(jsonEncode([release('v0.2.0', digest: apkSha)]), 200),
            _ => http.Response('', 404),
          });
      final dir = Directory.systemTemp.createTempSync('upd-');
      final u = Updater(dir: dir, client: c);
      final got = await u.check('0.1.0');
      expect(got!.version, '0.2.0');
      expect(got.sha256, apkSha);
      expect(await u.check('0.2.0'), isNull);
      dir.deleteSync(recursive: true);
    });

    test('without a GitHub digest the published .sha256 file is used; with neither, nothing installs', () async {
      final c = MockClient((r) async => switch (r.url.toString()) {
            releasesApi => http.Response(jsonEncode([release('v0.2.0')]), 200),
            'https://dl/v0.2.0.sha' => http.Response('$apkSha  translatorai-0.2.0-android-arm64.apk\n', 200),
            _ => http.Response('', 404),
          });
      final dir = Directory.systemTemp.createTempSync('upd-');
      expect((await Updater(dir: dir, client: c).check('0.1.0'))!.sha256, apkSha);
      final bare = MockClient((r) async => http.Response(jsonEncode([release('v0.2.0', shaFile: false)]), 200));
      await expectLater(Updater(dir: dir, client: bare).check('0.1.0'), throwsA(isA<UpdateError>()));
      dir.deleteSync(recursive: true);
    });

    test('a download that does not match is deleted; a match is kept; clean-up empties the folder', () async {
      final dir = Directory.systemTemp.createTempSync('upd-');
      final good = Update(version: '0.2.0', apkUrl: 'https://dl/a', apkName: 'a.apk', bytes: 4, sha256: apkSha, notes: '', page: '');
      final ok = Updater(dir: dir, client: MockClient((_) async => http.Response.bytes(apkBytes, 200)));
      final f = await ok.download(good);
      expect(f.readAsBytesSync(), apkBytes);
      final bad = Updater(dir: dir, client: MockClient((_) async => http.Response.bytes([9, 9, 9, 9], 200)));
      await expectLater(bad.download(Update(version: '0.2.0', apkUrl: 'https://dl/b', apkName: 'b.apk', bytes: 4,
          sha256: apkSha, notes: '', page: '')), throwsA(isA<UpdateError>()));
      expect(File('${dir.path}/b.apk').existsSync() || File('${dir.path}/b.apk.part').existsSync(), isFalse);
      expect(await ok.cleanUp(), 1);
      expect(dir.listSync(), isEmpty);
      dir.deleteSync(recursive: true);
    });
  });
}

class FakeGuesser extends TextLanguageGuesser {
  FakeGuesser(this.answers);
  final Map<String, List<Guess>> answers;
  @override
  Future<List<Guess>> guess(String text) async => answers[text] ?? const [];
}

void glossaryTests() {
  group('glossary', () {
    test('a word said alone gets its travel sense', () {
      expect(applyGlossary('כפית', 'Spoon'), 'Teaspoon');
      expect(applyGlossary('החשבון, בבקשה', 'The account, please.'), 'The bill, please.');
      expect(applyGlossary('מפתח?', 'Developer?'), 'Key');
      expect(applyGlossary('כרטיס הלוך חזור', 'Ticket Back'), 'Round-trip ticket');
    });
    test('a name after "my name is" is spoken as a name, a bank account stays one', () {
      expect(applyGlossary('קוראים לי עידן', 'They call me an age'), 'My name is Idan.');
      expect(applyGlossary('שמי דני', 'My name is Dani'), 'My name is Dani.');
      expect(applyGlossary('קוראים לי יורם', 'They call me Yoram'), 'They call me Yoram');
      expect(applyGlossary('כמה החשבון יצא?', 'How much did the account come out?'), 'How much did the bill come out?');
      expect(applyGlossary('אני צריך לפתוח חשבון בנק', 'I need to open a bank account'), 'I need to open a bank account');
    });
    test('a charger is a charger only next to a phone word', () {
      expect(applyGlossary('אני צריך מטען לטלפון', 'I need luggage for the phone'), 'I need charger for the phone');
      expect(applyGlossary('המטען שלי בטיסה', 'My luggage is on the flight'), 'My luggage is on the flight');
      expect(applyGlossary('מטען', 'Luggage'), 'Luggage');
    });
    test('English into Hebrew: "my name is" reads as Hebrew and a known name is spelt right', () {
      expect(applyHebrewGlossary('My name is Idan, nice to meet you.', 'שמי הוא אידן, נעים להכיר אותך.'), 'שמי עידן, נעים להכיר אותך.');
      expect(applyHebrewGlossary('My name is Bob.', 'שמי הוא בוב.'), 'שמי בוב.');
      expect(applyHebrewGlossary('Where is the station?', 'איפה התחנה?'), 'איפה התחנה?');
    });
    test('inside a sentence only a one-sense word is swapped back', () {
      expect(applyGlossary('תן לי כפית בבקשה', 'Give me a spoon please'), 'Give me a teaspoon please');
      expect(applyGlossary('שתי כפיות', 'Two spoons'), 'Two teaspoons');
      expect(applyGlossary('אפשר כפית סוכר?', 'Can I have a teaspoon of sugar?'), 'Can I have a teaspoon of sugar?');
      expect(applyGlossary('תן לי כף', 'Give me a spoon'), 'Give me a spoon'); // כף is a spoon
      expect(applyGlossary('יש לי חשבון בנק', 'I have a bank account'), 'I have a bank account');
      expect(applyGlossary('יש עודף משקל', 'There is excess weight'), 'There is excess weight');
    });
  });
}

void latestTests() {
  test('words so far: one translation at a time, and only the newest waits', () async {
    final ran = <String>[];
    late LatestOnly<String> r;
    r = LatestOnly<String>((v) async {
      ran.add(v);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    final first = r.offer('a');
    r.offer('a b');
    r.offer('a b c'); // replaces "a b": that one is stale before it starts
    await first;
    expect(ran, ['a', 'a b c']);
    r.offer('x');
    r.clear(); // nothing was waiting; x runs since it was not waiting
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ran, ['a', 'a b c', 'x']);
    expect(r.busy, isFalse);
  });

  test('a woman speaking gets the feminine forms after "אני", and a man or unknown speaker is untouched', () {
    expect(applyHebrewGlossary('I am tired', 'אני עייף', gender: 'f'), 'אני עייפה');
    expect(applyHebrewGlossary('I am very tired', 'אני מאוד עייף', gender: 'f'), 'אני מאוד עייפה'); // one adverb may sit between
    expect(applyHebrewGlossary('I do not understand', 'אני לא מבין', gender: 'f'), 'אני לא מבינה');
    expect(applyHebrewGlossary('I am going to the hotel', 'אני הולך למלון', gender: 'f'), 'אני הולכת למלון');
    expect(applyHebrewGlossary('I want water', 'אני רוצה מים', gender: 'f'), 'אני רוצה מים'); // same for both
    expect(applyHebrewGlossary('He is tired', 'הוא עייף', gender: 'f'), 'הוא עייף'); // only the speaker
    expect(applyHebrewGlossary('I am tired', 'אני עייף', gender: 'm'), 'אני עייף');
    expect(applyHebrewGlossary('I am tired', 'אני עייף'), 'אני עייף');
    expect(feminizeFirstPerson('ואני צריך עזרה, אני לא יודע'), 'ואני צריכה עזרה, אני לא יודעת');
  });

  test('a man speaking gets the masculine forms the model sometimes turns feminine', () {
    expect(applyHebrewGlossary('I am vegetarian', 'אני צמחונית', gender: 'm'), 'אני צמחוני');
    expect(applyHebrewGlossary('I am tired', 'אני עייפה', gender: 'm'), 'אני עייף');
    expect(applyHebrewGlossary('I am tired', 'אני עייפה'), 'אני עייפה'); // unknown: left as the model wrote it
  });

  test('a word said alone is answered from the word list, and a stutter is cut', () {
    expect(applyGlossary('טיסה', 'Flight Flight Flight'), 'Flight');
    expect(applyGlossary('המטוס', 'The Plane'), 'The airplane');
    expect(applyGlossary('תחנת דלק', 'The Gas Station'), 'Gas station');
    expect(applyGlossary('תודה', 'Thank you very much.'), 'Thank you');
    expect(applyGlossary('בבקשה', 'Please Please Please'), 'Please.');
    expect(applyGlossary('מים, בבקשה', 'Water and Water'), 'Water, please.');
    expect(applyGlossary('רציף', 'the Continuous Continuous Continuous'), 'Platform');
    expect(applyGlossary('שוק גדול', 'Market Market Market'), 'Market'); // a stutter outside the list
    expect(applyGlossary('אני רוצה שוק לילה', 'I want a night market.'), 'I want a night market.');
  });
}
