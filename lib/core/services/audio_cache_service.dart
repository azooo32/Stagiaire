import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'secure_file_cache_service.dart';

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._internal();
  factory AudioCacheService() => _instance;
  AudioCacheService._internal();

  final Set<String> _activeDownloads = <String>{};
  final Map<String, Uint8List> _memoryBytesCache = <String, Uint8List>{};

  Uint8List? cachedBytesForUrl(String url) {
    return _memoryBytesCache[url.trim()];
  }

  Future<Uint8List?> getOrDownloadBytes(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (_memoryBytesCache.containsKey(trimmed)) {
      return _memoryBytesCache[trimmed];
    }

    if (!kIsWeb) {
      final cachedPath = await cachedPathForUrl(trimmed);
      if (cachedPath != null) {
        try {
          final file = File(cachedPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            _memoryBytesCache[trimmed] = bytes;
            return bytes;
          }
        } catch (_) {}
      }
    }

    if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      try {
        final file = File(trimmed);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _memoryBytesCache[trimmed] = bytes;
          return bytes;
        }
      } catch (_) {}
      return null;
    }

    try {
      final client = HttpClient()..connectionTimeout = timeout;
      try {
        final request =
            await client.getUrl(Uri.parse(trimmed)).timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }

        final builder = BytesBuilder();
        await response.forEach(builder.add);
        final bytes = builder.takeBytes();
        if (bytes.isNotEmpty) {
          _memoryBytesCache[trimmed] = bytes;
          return bytes;
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[AudioCacheService] Error downloading bytes for $trimmed: $e');
    }
    return null;
  }

  Future<Directory> _cacheDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}stagiaire_audio_cache',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _extensionForUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final ext = path.split('.').last;
    if (ext.length >= 2 && ext.length <= 5) return '.$ext';
    return '.audio';
  }

  String _baseFileNameForUrl(String url) {
    return base64Url.encode(utf8.encode(url));
  }

  String _encryptedFileNameForUrl(String url) {
    return '${_baseFileNameForUrl(url)}${_extensionForUrl(url)}.bin';
  }

  String _runtimeFileNameForUrl(String url) {
    return '${_baseFileNameForUrl(url)}${_extensionForUrl(url)}';
  }

  Future<String?> cachedPathForUrl(String url) async {
    if (kIsWeb) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      return trimmed.isEmpty ? null : trimmed;
    }

    final dir = await _cacheDirectory();
    final encryptedFile = File(
        '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
    if (await encryptedFile.exists() && await encryptedFile.length() > 0) {
      final runtimeFile = await SecureFileCacheService().decryptToRuntimeFile(
        encryptedFile,
        _runtimeFileNameForUrl(trimmed),
      );
      if (runtimeFile != null) return runtimeFile.path;
    }

    final legacyFile = File(
        '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}');
    if (await legacyFile.exists() && await legacyFile.length() > 0) {
      await SecureFileCacheService()
          .writeEncrypted(encryptedFile, await legacyFile.readAsBytes());
      try {
        await legacyFile.delete();
      } catch (_) {}
      final runtimeFile = await SecureFileCacheService().decryptToRuntimeFile(
        encryptedFile,
        _runtimeFileNameForUrl(trimmed),
      );
      if (runtimeFile != null) return runtimeFile.path;
    }
    return null;
  }

  Future<String?> getOrDownload(String url,
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (kIsWeb) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://')))
      return trimmed;

    final existing = await cachedPathForUrl(trimmed);
    if (existing != null) return existing;

    if (_activeDownloads.contains(trimmed)) {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final existingAfterWait = await cachedPathForUrl(trimmed);
        if (existingAfterWait != null) return existingAfterWait;
      }
      return null;
    }
    _activeDownloads.add(trimmed);

    try {
      final dir = await _cacheDirectory();
      final encryptedFile = File(
          '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
      final tempFile = File('${encryptedFile.path}.part');

      final client = HttpClient()..connectionTimeout = timeout;
      try {
        final request =
            await client.getUrl(Uri.parse(trimmed)).timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300)
          return null;

        final sink = tempFile.openWrite();
        await response.pipe(sink).timeout(timeout);
        await sink.close();

        if (await tempFile.length() == 0) return null;
        await SecureFileCacheService()
            .writeEncrypted(encryptedFile, await tempFile.readAsBytes());
        try {
          await tempFile.delete();
        } catch (_) {}
        final runtimeFile = await SecureFileCacheService().decryptToRuntimeFile(
          encryptedFile,
          _runtimeFileNameForUrl(trimmed),
        );
        return runtimeFile?.path;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      print('Error caching audio: $e');
      return null;
    } finally {
      _activeDownloads.remove(trimmed);
    }
  }

  // ── Plain persistent store (large voice recordings) ─────────────────────────
  // The encrypted cache loads the whole file into memory, encrypts it on the UI
  // thread and decrypts it again to play it: with 30-60 MB recordings this froze
  // the app and ran out of memory. Voice recordings are streamed straight to a
  // file inside the private app folder instead (same as lecture recordings / PDFs).

  final Map<String, Future<String?>> _plainDownloads = {};

  Future<Directory> _plainDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}${Platform.pathSeparator}voice_audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _plainFile(String url) async {
    final dir = await _plainDirectory();
    final hash = sha256.convert(utf8.encode(url)).toString().substring(0, 32);
    return File(
        '${dir.path}${Platform.pathSeparator}$hash${_extensionForUrl(url)}');
  }

  /// Path of the downloaded recording, or null if it is not on the device yet.
  Future<String?> plainPathForUrl(String url) async {
    if (kIsWeb) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final file = await _plainFile(trimmed);
    if (await file.exists() && await file.length() > 0) return file.path;
    return null;
  }

  Future<bool> isPlainDownloaded(String url) async =>
      await plainPathForUrl(url) != null;

  /// Streams [url] to disk (no memory copy) and returns the local path, or null on failure.
  /// Concurrent calls for the same URL share one download.
  Future<String?> downloadPlain(String url,
      {Duration idleTimeout = const Duration(seconds: 60)}) {
    final trimmed = url.trim();
    final running = _plainDownloads[trimmed];
    if (running != null) return running;
    final future = _downloadPlain(trimmed, idleTimeout)
        .whenComplete(() => _plainDownloads.remove(trimmed));
    _plainDownloads[trimmed] = future;
    return future;
  }

  Future<String?> _downloadPlain(String url, Duration idleTimeout) async {
    if (kIsWeb || url.isEmpty) return null;
    final existing = await plainPathForUrl(url);
    if (existing != null) return existing;

    final target = await _plainFile(url);
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request =
          await client.getUrl(Uri.parse(url)).timeout(idleTimeout);
      final response = await request.close().timeout(idleTimeout);
      if (response.statusCode != 200) return null;

      final sink = part.openWrite();
      try {
        // timeout() here is per chunk: it fails only if the connection stalls.
        await sink.addStream(response.timeout(idleTimeout));
      } finally {
        await sink.close();
      }

      final written = await part.length();
      final expected = response.contentLength;
      if (written == 0 || (expected > 0 && written != expected)) {
        throw const FileSystemException('Incomplete download');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return target.path;
    } catch (e) {
      debugPrint('[AudioCacheService] Error downloading voice $url: $e');
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> deletePlain(String url) async {
    if (kIsWeb) return;
    try {
      final file = await _plainFile(url.trim());
      if (await file.exists()) await file.delete();
      final part = File('${file.path}.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  /// Cheap check (no decryption): true if the file for [url] is already stored on disk.
  /// Local (non-http) paths count as downloaded.
  Future<bool> isDownloaded(String url) async {
    if (kIsWeb) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      return true;
    }
    final dir = await _cacheDirectory();
    final encryptedFile = File(
        '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
    if (await encryptedFile.exists() && await encryptedFile.length() > 0) {
      return true;
    }
    final legacyFile = File(
        '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}');
    return await legacyFile.exists() && await legacyFile.length() > 0;
  }

  /// Returns true if the given [url] is already cached on disk.
  Future<bool> isCachedForUrl(String url) async {
    if (kIsWeb) return false;
    final path = await cachedPathForUrl(url.trim());
    return path != null;
  }

  /// Removes cached files for the given [urls] from both disk and memory.
  Future<void> clearCacheForUrls(List<String> urls) async {
    if (kIsWeb) return;
    final dir = await _cacheDirectory();
    for (final url in urls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty) continue;
      _memoryBytesCache.remove(trimmed);
      final encFile = File(
          '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
      try {
        if (await encFile.exists()) await encFile.delete();
      } catch (_) {}
      final plainFile = File(
          '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}');
      try {
        if (await plainFile.exists()) await plainFile.delete();
      } catch (_) {}
      final tempFile = File('${encFile.path}.part');
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<void> prefetchQuestionAudios(List<String?> urls,
      {int limit = 2}) async {
    final queue = urls
        .whereType<String>()
        .map((url) => url.trim())
        .where((url) => url.startsWith('http://') || url.startsWith('https://'))
        .toSet()
        .toList();

    var index = 0;
    Future<void> worker() async {
      while (index < queue.length) {
        final current = queue[index++];
        await getOrDownload(current, timeout: const Duration(seconds: 30));
      }
    }

    final workerCount = limit.clamp(1, 4).toInt();
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
  }
}
