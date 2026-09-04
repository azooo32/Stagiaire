import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PdfStorageService {
  static const String _cachedPdfsFolder = 'cached_pdfs';
  static const String _savedPdfsFolder = 'saved_pdfs';

  /// Returns the private application support directory for caching downloaded station PDFs.
  /// On iOS, this resides in Library/Application Support, which is NOT visible in the Files app.
  static Future<Directory> getPdfCacheDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}/$_cachedPdfsFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the private application support directory for persistently saved PDFs.
  static Future<Directory> getSavedPdfsDirectory() async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory('${baseDir.path}/$_savedPdfsFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the target local path for a given slide/PDF ID.
  static Future<String> getLocalPdfPath(String slideId) async {
    final cacheDir = await getPdfCacheDirectory();
    return '${cacheDir.path}/$slideId.pdf';
  }

  /// Returns the temporary file path during PDF download.
  static Future<String> getLocalPdfTmpPath(String slideId) async {
    final cacheDir = await getPdfCacheDirectory();
    return '${cacheDir.path}/$slideId.pdf.tmp';
  }

  /// Migrates previously downloaded PDFs from the old user-visible Documents folder
  /// to the new hidden Application Support folder.
  /// This ensures students who already downloaded PDFs in older versions don't lose them,
  /// while completely preventing them from browsing or sharing the files via the iOS Files app.
  static Future<void> migrateOldPdfFiles() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final supportDir = await getApplicationSupportDirectory();

      // 1. Migrate cached_pdfs (used by station slides / PDF workspace)
      final oldCacheDir = Directory('${docsDir.path}/$_cachedPdfsFolder');
      final newCacheDir = Directory('${supportDir.path}/$_cachedPdfsFolder');

      if (await oldCacheDir.exists()) {
        debugPrint('[PdfStorageService] Found old cached_pdfs in Documents. Migrating...');
        if (!await newCacheDir.exists()) {
          await newCacheDir.create(recursive: true);
        }

        final entities = oldCacheDir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.path.split(RegExp(r'[/\\]')).last;
            final targetFile = File('${newCacheDir.path}/$fileName');
            try {
              // Only copy if valid or missing
              if (!await targetFile.exists() || (await targetFile.length()) < (await entity.length())) {
                await entity.copy(targetFile.path);
              }
              // Delete old visible file
              await entity.delete();
              debugPrint('[PdfStorageService] Migrated $fileName to hidden storage');
            } catch (e) {
              debugPrint('[PdfStorageService] Error migrating file $fileName: $e');
            }
          }
        }

        // Remove old directory
        try {
          await oldCacheDir.delete(recursive: true);
          debugPrint('[PdfStorageService] Removed old cached_pdfs directory');
        } catch (_) {}
      }

      // 2. Migrate saved_pdfs (used by voice/video attachments)
      final oldSavedDir = Directory('${docsDir.path}/$_savedPdfsFolder');
      final newSavedDir = Directory('${supportDir.path}/$_savedPdfsFolder');

      if (await oldSavedDir.exists()) {
        debugPrint('[PdfStorageService] Found old saved_pdfs in Documents. Migrating...');
        if (!await newSavedDir.exists()) {
          await newSavedDir.create(recursive: true);
        }

        final entities = oldSavedDir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.path.split(RegExp(r'[/\\]')).last;
            final targetFile = File('${newSavedDir.path}/$fileName');
            try {
              if (!await targetFile.exists() || (await targetFile.length()) < (await entity.length())) {
                await entity.copy(targetFile.path);
              }
              await entity.delete();
              debugPrint('[PdfStorageService] Migrated saved PDF $fileName to hidden storage');
            } catch (e) {
              debugPrint('[PdfStorageService] Error migrating saved file $fileName: $e');
            }
          }
        }

        try {
          await oldSavedDir.delete(recursive: true);
          debugPrint('[PdfStorageService] Removed old saved_pdfs directory');
        } catch (_) {}
      }

      // 3. Clean up any loose .pdf or .tmp files in root Documents folder
      try {
        final docEntities = docsDir.listSync();
        for (final entity in docEntities) {
          if (entity is File) {
            final lower = entity.path.toLowerCase();
            if (lower.endsWith('.pdf') || lower.endsWith('.tmp')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

    } catch (e) {
      debugPrint('[PdfStorageService] Migration encountered error: $e');
    }
  }
}
