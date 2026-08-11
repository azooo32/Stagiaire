import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_config.dart';
import '../models/app_update_info.dart';
import '../widgets/app_update_dialog.dart';

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final _supabase = Supabase.instance.client;
  bool _isChecking = false;
  bool _dialogShownInSession = false;

  /// Check Supabase for the latest app update
  Future<AppUpdateInfo?> fetchLatestUpdate() async {
    try {
      final response = await _supabase
          .from('app_updates')
          .select()
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return AppUpdateInfo.fromMap(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching app update: $e');
      }
      return null;
    }
  }

  /// Check if the latest update on the server is newer than current app version
  bool isUpdateAvailable(AppUpdateInfo info) {
    return info.versionCode > AppConfig.currentVersionCode;
  }

  /// Automatically or manually check and present the update dialog
  Future<void> checkForUpdates(
    BuildContext context, {
    bool isManualCheck = false,
  }) async {
    if (_isChecking) return;
    if (!isManualCheck && _dialogShownInSession) return;

    _isChecking = true;

    try {
      final latest = await fetchLatestUpdate();

      if (latest != null && isUpdateAvailable(latest)) {
        _dialogShownInSession = true;
        if (context.mounted) {
          await showDialog(
            context: context,
            barrierDismissible: !latest.isForced,
            builder: (ctx) => AppUpdateDialog(updateInfo: latest),
          );
        }
      } else if (isManualCheck && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أنت تستخدم أحدث إصدار من التطبيق (${AppConfig.currentVersionName})',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1E2C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to check for updates: $e');
      }
      if (isManualCheck && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر فحص التحديثات، يرجى المحاولة لاحقاً',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
          ),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  /// Downloads the APK from Supabase Storage with stream progress and triggers installer
  Future<void> downloadAndInstallApk(
    AppUpdateInfo info, {
    required void Function(double progress, String statusText) onProgress,
    required void Function(String errorMessage) onError,
    required VoidCallback onComplete,
  }) async {
    try {
      // If it's a web/store link instead of direct APK, open directly
      if (!info.isApkUrl && (info.isStoreUrl || info.apkUrl.startsWith('http'))) {
        final uri = Uri.parse(info.apkUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          onComplete();
          return;
        }
      }

      onProgress(0.0, 'بدء الاتصال بالخادم...');

      final uri = Uri.parse(info.apkUrl);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);

      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        onError('فشل التحميل من السيرفر (كود الخطأ: ${response.statusCode})');
        return;
      }

      final contentLength = response.contentLength;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/Stagiaire_v${info.versionCode}.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;

      await for (var chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          final progress = (receivedBytes / contentLength).clamp(0.0, 1.0);
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, 'جاري التحميل... ($mbReceived / $mbTotal ميغابايت)');
        } else {
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, 'جاري التحميل... ($mbReceived ميغابايت)');
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      onProgress(1.0, 'اكتمل التحميل! جاري فتح المثبت...');
      onComplete();

      // Launch Android Package Installer
      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && result.type != ResultType.noAppToOpen) {
        if (kDebugMode) {
          print('OpenFilex result: ${result.message}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading and installing update: $e');
      }
      onError('حدث خطأ أثناء تحميل التحديث: $e');
    }
  }
}
