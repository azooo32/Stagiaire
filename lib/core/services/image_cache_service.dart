import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'secure_file_cache_service.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final Set<String> _activeDownloads = <String>{};
  final Map<String, String> _memoryCache = {};

  String? getCachedPathSync(String url) {
    final trimmed = url.trim();
    return _memoryCache[trimmed];
  }

  /// Saves raw image bytes into the disk cache and updates memory cache for [url].
  Future<String?> saveBytesForUrl(String url, Uint8List bytes) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      final dir = await _cacheDirectory();
      final targetFile = File(
        '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}',
      );
      await targetFile.writeAsBytes(bytes, flush: true);
      _memoryCache[trimmed] = targetFile.path;
      return targetFile.path;
    } catch (e) {
      return null;
    }
  }

  /// Fire-and-forget: populates _memoryCache for every URL that is already
  /// cached on disk, and downloads any missing slide images in the background.
  /// This is kept for callers that do not need to wait for the preload.
  void warmupCacheForUrls(List<String> urls) {
    unawaited(preloadUrls(urls));
  }

  /// Makes all slide images available on the device before the Slides page is
  /// shown. Files are stored in the application support directory, so future
  /// opens do not depend on Supabase or an internet connection.
  Future<void> preloadUrls(
    List<String> urls, {
    int concurrency = 4,
  }) async {
    final uniqueUrls = <String>{
      for (final url in urls)
        if (url.trim().startsWith('http')) url.trim(),
    }.toList();

    final batchSize = concurrency.clamp(1, 8).toInt();
    for (var start = 0; start < uniqueUrls.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, uniqueUrls.length);
      await Future.wait(
        uniqueUrls.sublist(start, end).map((url) => getOrDownload(url)),
      );
    }
  }

  Future<Directory> _cacheDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}stagiaire_image_cache',
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
    return '.image';
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

    if (_memoryCache.containsKey(trimmed)) {
      return _memoryCache[trimmed];
    }

    final dir = await _cacheDirectory();
    final legacyFile = File(
        '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}');

    // 1. If plain file already exists, return it immediately (fast path)
    if (await legacyFile.exists() && await legacyFile.length() > 0) {
      _memoryCache[trimmed] = legacyFile.path;
      return legacyFile.path;
    }

    // 2. Backward compatibility: if only encrypted file exists, decrypt and migrate to plain file once
    final encryptedFile = File(
        '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
    if (await encryptedFile.exists() && await encryptedFile.length() > 0) {
      final runtimeFile = await SecureFileCacheService().decryptToRuntimeFile(
        encryptedFile,
        _runtimeFileNameForUrl(trimmed),
      );
      if (runtimeFile != null) {
        try {
          await File(runtimeFile.path).copy(legacyFile.path);
          _memoryCache[trimmed] = legacyFile.path;
          // Clean up encrypted file to prevent redundant migrations
          await encryptedFile.delete();
          return legacyFile.path;
        } catch (_) {
          return runtimeFile.path;
        }
      }
    }
    return null;
  }

  Future<String?> getOrDownload(String url,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (kIsWeb) return trimmed;
    if (trimmed.startsWith('data:image') || trimmed.startsWith('blob:'))
      return trimmed;
    if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://')))
      return trimmed;

    if (_memoryCache.containsKey(trimmed)) {
      return _memoryCache[trimmed];
    }

    final existing = await cachedPathForUrl(trimmed);
    if (existing != null) {
      _memoryCache[trimmed] = existing;
      return existing;
    }

    if (_activeDownloads.contains(trimmed)) {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final existingAfterWait = await cachedPathForUrl(trimmed);
        if (existingAfterWait != null) {
          _memoryCache[trimmed] = existingAfterWait;
          return existingAfterWait;
        }
      }
      return null;
    }
    _activeDownloads.add(trimmed);

    try {
      final dir = await _cacheDirectory();
      final legacyFile = File(
          '${dir.path}${Platform.pathSeparator}${_runtimeFileNameForUrl(trimmed)}');
      final tempFile = File('${legacyFile.path}.part');

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

        // Save as plain file directly
        if (await legacyFile.exists()) {
          try {
            await legacyFile.delete();
          } catch (_) {}
        }
        await tempFile.rename(legacyFile.path);

        _memoryCache[trimmed] = legacyFile.path;
        return legacyFile.path;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      print('Error caching image: $e');
      return null;
    } finally {
      _activeDownloads.remove(trimmed);
    }
  }
}
