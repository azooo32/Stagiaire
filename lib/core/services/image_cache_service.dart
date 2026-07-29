import 'dart:convert';
import 'dart:io';
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
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      return trimmed.isEmpty ? null : trimmed;
    }

    if (_memoryCache.containsKey(trimmed)) {
      return _memoryCache[trimmed];
    }

    final dir = await _cacheDirectory();
    final encryptedFile = File(
        '${dir.path}${Platform.pathSeparator}${_encryptedFileNameForUrl(trimmed)}');
    if (await encryptedFile.exists() && await encryptedFile.length() > 0) {
      final runtimeFile = await SecureFileCacheService().decryptToRuntimeFile(
        encryptedFile,
        _runtimeFileNameForUrl(trimmed),
      );
      if (runtimeFile != null) {
        _memoryCache[trimmed] = runtimeFile.path;
        return runtimeFile.path;
      }
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
      if (runtimeFile != null) {
        _memoryCache[trimmed] = runtimeFile.path;
        return runtimeFile.path;
      }
    }
    return null;
  }

  Future<String?> getOrDownload(String url,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
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
        if (runtimeFile != null) {
          _memoryCache[trimmed] = runtimeFile.path;
        }
        return runtimeFile?.path;
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
