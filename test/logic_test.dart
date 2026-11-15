import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translatorai/src/asr.dart';
import 'package:translatorai/src/languages.dart';
import 'package:translatorai/src/model_store.dart';
import 'package:translatorai/src/models.dart';
import 'package:translatorai/src/pipeline.dart';

void main() {
  group('direction', () {
    test('listen sends everything into my language', () {
      expect(decide(Mode.listen, 'ja', mine: 'en', theirs: 'es'), const Direction('ja', 'en'));
      expect(decide(Mode.listen, 'en', mine: 'en', theirs: 'es'), const Direction('en', 'en'));
    });
    test('conversation goes by the language heard', () {
      expect(decide(Mode.conversation, 'en', mine: 'en', theirs: 'he'), const Direction('en', 'he'));
      expect(decide(Mode.conversation, 'he', mine: 'en', theirs: 'he'), const Direction('he', 'en'));
    });
    test('a third language is taken as the turn of whoever did not speak last', () {
      expect(decide(Mode.conversation, 'yi', mine: 'en', theirs: 'he', lastFrom: 'he'),
          const Direction('en', 'he', guessed: true));
      expect(decide(Mode.conversation, 'yi', mine: 'en', theirs: 'he', lastFrom: 'en'),
          const Direction('he', 'en', guessed: true));
    });
  });

  group('audio', () {
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
    });
    test('language tags are normalised', () {
      expect(normaliseLanguageTag('<|en|>'), 'en');
      expect(normaliseLanguageTag(' HE '), 'he');
    });
    test('every language has a name and the lists are unique', () {
      final codes = allLanguages().map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(whisperLanguages.length, 99);
      expect(hearable.contains('he') && hearable.contains('ar') && hearable.contains('zh'), isTrue);
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

    test('prune keeps only the files in use', () async {
      File('${dir.path}/old-model.onnx').writeAsStringSync('x');
      File('${dir.path}/keep.onnx').writeAsStringSync('y');
      await ModelStore(dir).prune([const ModelFile('keep.onnx', '', '', 1)]);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['keep.onnx']);
    });

    test('every shipped model file is pinned to a digest', () {
      for (final f in [vadModel, for (final m in speechModels) ...m.files]) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
        expect(f.url, startsWith('https://'));
        expect(f.bytes, greaterThan(0));
      }
    });
  });
}
