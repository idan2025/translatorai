import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

typedef Progress = void Function(int done, int total);

/// Downloads model files into one folder. A file is only ever present under
/// its final name once its digest matched: it is written to `<name>.part`,
/// hashed while it streams, and renamed only on a match. An interrupted or
/// tampered download therefore never looks installed.
class ModelStore {
  ModelStore(this.dir, {http.Client? client}) : _client = client ?? http.Client();

  final Directory dir;
  final http.Client _client;

  String pathOf(String name) => '${dir.path}/$name';

  bool has(ModelFile f) {
    final file = File(pathOf(f.name));
    return file.existsSync() && file.lengthSync() == f.bytes;
  }

  bool hasAll(Iterable<ModelFile> files) => files.every(has);

  /// Fetches every missing file. [onProgress] gets bytes across all of them.
  Future<void> ensure(List<ModelFile> files, {Progress? onProgress}) async {
    await dir.create(recursive: true);
    final total = files.fold<int>(0, (a, f) => a + f.bytes);
    var done = files.where(has).fold<int>(0, (a, f) => a + f.bytes);
    onProgress?.call(done, total);
    for (final f in files) {
      if (has(f)) continue;
      await _fetch(f, (n) => onProgress?.call(done + n, total));
      done += f.bytes;
      onProgress?.call(done, total);
    }
  }

  Future<void> _fetch(ModelFile f, void Function(int) onBytes) async {
    final part = File('${pathOf(f.name)}.part');
    final res = await _client.send(http.Request('GET', Uri.parse(f.url)));
    if (res.statusCode != 200) {
      throw ModelError('${f.name}: HTTP ${res.statusCode}');
    }
    final sink = part.openWrite();
    final hashSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashSink);
    var n = 0;
    try {
      await for (final chunk in res.stream) {
        n += chunk.length;
        if (n > f.bytes) throw ModelError('${f.name}: larger than expected');
        hasher.add(chunk);
        sink.add(chunk);
        onBytes(n);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    final got = hashSink.value.toString();
    if (n != f.bytes || got != f.sha256) {
      await part.delete();
      throw ModelError('${f.name}: checksum mismatch (got $got, $n bytes); file discarded');
    }
    await part.rename(pathOf(f.name));
  }

  bool hasAny(Iterable<ModelFile> files) => files.any((f) => File(pathOf(f.name)).existsSync());

  /// Deletes a model's files, except those another model still uses (the
  /// shared vocabulary file).
  Future<void> deleteModel(Iterable<ModelFile> files, {Iterable<ModelFile> except = const []}) async {
    final keep = {for (final f in except) f.name};
    for (final f in files) {
      if (keep.contains(f.name)) continue;
      final file = File(pathOf(f.name));
      if (await file.exists()) await file.delete();
    }
  }

  /// Deletes every file not in [keep] (old models, leftover partial files).
  Future<void> prune(Iterable<ModelFile> keep) async {
    if (!await dir.exists()) return;
    final names = {for (final f in keep) f.name};
    await for (final e in dir.list()) {
      if (e is File && !names.contains(e.uri.pathSegments.last)) await e.delete();
    }
  }
}

class ModelError implements Exception {
  ModelError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
