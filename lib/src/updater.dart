import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Where releases are published.
const releasesApi = 'https://api.github.com/repos/idan2025/translatorai/releases?per_page=20';
const releasesPage = 'https://github.com/idan2025/translatorai/releases';

/// A version like 0.2.0 compared number by number; a suffix ("-rc1") sorts
/// before the plain version.
int compareVersions(String a, String b) {
  List<int> nums(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = nums(a), y = nums(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  final sa = a.contains('-'), sb = b.contains('-');
  return sa == sb ? 0 : (sa ? -1 : 1);
}

/// A release that carries an installable APK.
class Update {
  const Update({required this.version, required this.apkUrl, required this.apkName, required this.bytes,
      required this.sha256, required this.notes, required this.page});
  final String version;
  final String apkUrl, apkName;
  final int bytes;

  /// Expected digest, from GitHub's own asset digest or the published .sha256 file.
  final String sha256;
  final String notes, page;
}

class UpdateError implements Exception {
  UpdateError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Picks the newest release with an arm64 APK, from the GitHub API's list.
/// Drafts are skipped; pre-releases count (every release so far is one).
/// Returns the release and, if GitHub gave no digest, the .sha256 asset URL.
({Map<String, dynamic> release, Map<String, dynamic> apk, String? shaUrl})? pickRelease(List<dynamic> releases) {
  final apkName = RegExp(r'^translatorai-.+-android-arm64\.apk$');
  Map<String, dynamic>? best, bestApk;
  for (final r in releases.cast<Map<String, dynamic>>()) {
    if (r['draft'] == true) continue;
    final assets = (r['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => apkName.hasMatch(a['name'] as String)).firstOrNull;
    if (apk == null) continue;
    if (best == null || compareVersions(r['tag_name'] as String, best['tag_name'] as String) > 0) {
      best = r;
      bestApk = apk;
    }
  }
  if (best == null) return null;
  final sha = (best['assets'] as List)
      .cast<Map<String, dynamic>>()
      .where((a) => a['name'] == '${bestApk!['name']}.sha256')
      .firstOrNull;
  return (release: best, apk: bestApk!, shaUrl: sha?['browser_download_url'] as String?);
}

class Updater {
  Updater({required this.dir, http.Client? client}) : _client = client ?? http.Client();

  /// Where APKs are downloaded (the app's cache, shared with the installer
  /// through a FileProvider). Everything in it is temporary.
  final Directory dir;
  final http.Client _client;
  static const _installer = MethodChannel('translatorai/installer');

  /// The newest release if it is newer than [current], else null.
  Future<Update?> check(String current) async {
    final res = await _client.get(Uri.parse(releasesApi), headers: {'Accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) throw UpdateError('Could not reach GitHub (HTTP ${res.statusCode})');
    final picked = pickRelease(jsonDecode(res.body) as List);
    if (picked == null) return null;
    final tag = picked.release['tag_name'] as String;
    if (compareVersions(tag, current) <= 0) return null;
    var digest = (picked.apk['digest'] as String?)?.replaceFirst('sha256:', '');
    if (digest == null || digest.length != 64) {
      if (picked.shaUrl == null) throw UpdateError('Release $tag has no checksum; not installing it');
      final s = await _client.get(Uri.parse(picked.shaUrl!));
      if (s.statusCode != 200) throw UpdateError('Could not fetch the checksum (HTTP ${s.statusCode})');
      digest = s.body.trim().split(RegExp(r'\s+')).first.toLowerCase();
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) throw UpdateError('Release $tag has a malformed checksum');
    return Update(
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      apkUrl: picked.apk['browser_download_url'] as String,
      apkName: picked.apk['name'] as String,
      bytes: (picked.apk['size'] as num).toInt(),
      sha256: digest,
      notes: (picked.release['body'] as String?) ?? '',
      page: (picked.release['html_url'] as String?) ?? releasesPage,
    );
  }

  /// Downloads the APK beside, checks its digest, and only then gives it its
  /// name. A file that does not match is deleted and never installed.
  Future<File> download(Update u, {void Function(int done, int total)? onProgress}) async {
    await dir.create(recursive: true);
    final part = File('${dir.path}/${u.apkName}.part');
    final res = await _client.send(http.Request('GET', Uri.parse(u.apkUrl)));
    if (res.statusCode != 200) throw UpdateError('Download failed (HTTP ${res.statusCode})');
    final sink = part.openWrite();
    final out = _DigestSink();
    final hasher = sha256.startChunkedConversion(out);
    var n = 0;
    try {
      await for (final chunk in res.stream) {
        n += chunk.length;
        if (n > u.bytes) throw UpdateError('The download is larger than the release says');
        hasher.add(chunk);
        sink.add(chunk);
        onProgress?.call(n, u.bytes);
      }
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
    await sink.close();
    hasher.close();
    if (n != u.bytes || out.value.toString() != u.sha256) {
      await part.delete();
      throw UpdateError('The download did not match its checksum; it was deleted');
    }
    return part.rename('${dir.path}/${u.apkName}');
  }

  /// Hands the APK to Android's installer. Android asks the person to allow
  /// installs from this app once, then to confirm the update.
  Future<void> install(File apk) async {
    final allowed = await _installer.invokeMethod<bool>('canInstall') ?? false;
    if (!allowed) {
      await _installer.invokeMethod('openInstallSettings');
      throw UpdateError('Allow TranslatorAI to install updates, then tap Update again.');
    }
    await _installer.invokeMethod('install', {'path': apk.path});
  }

  /// Deletes every downloaded APK and partial download. Run at start: after an
  /// update the new app starts here, and the file that installed it is junk.
  Future<int> cleanUp() async {
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        await e.delete();
        n++;
      }
    }
    return n;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
