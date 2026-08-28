import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
