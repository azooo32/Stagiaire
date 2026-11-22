import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static const MethodChannel _channel =
      MethodChannel('com.invetstecur.stagiaire/security');

  static bool _isSecure = false;
  static bool get isSecure => _isSecure;

  static bool isDeviceRooted = false;
  static bool isDeviceCompromised = false;

  /// Android "Developer options" switch is on. Always false on iOS (no API).
  static bool isDeveloperModeEnabled = false;

  /// The app refuses to run while Developer options are on — release/profile
  /// builds only, so `flutter run` (which needs USB debugging) keeps working.
  static bool get shouldBlockDeveloperMode =>
      !kDebugMode && isDeveloperModeEnabled;

  // يضمن أن init() تُنفَّذ مرة واحدة فقط طوال عمر التطبيق
  static bool _initialized = false;

  static ValueNotifier<bool> isScreenRecording = ValueNotifier<bool>(false);

  /// فحص سلامة الجهاز واكتشاف الروت وكسر الحماية
  static Future<Map<String, bool>> checkIntegrity() async {
    try {
      final res = await _channel.invokeMethod<Map>('checkDeviceIntegrity');
      if (res != null) {
        isDeviceRooted = res['isRooted'] == true;
        isDeviceCompromised = res['isCompromised'] == true;
        isDeveloperModeEnabled = res['isDeveloperMode'] == true;
        return {
          'isRooted': isDeviceRooted,
          'isEmulator': res['isEmulator'] == true,
          'isCompromised': isDeviceCompromised,
        };
      }
    } catch (e) {
      debugPrint('Error checking device integrity: $e');
    }
    return {'isRooted': false, 'isEmulator': false, 'isCompromised': false};
  }

  /// Re-reads the Developer options switch (after the student returns from
  /// Settings). Returns the new value; false on iOS / errors.
  static Future<bool> recheckDeveloperMode() async {
    try {
      final enabled =
          await _channel.invokeMethod<bool>('isDeveloperModeEnabled');
      isDeveloperModeEnabled = enabled == true;
    } catch (e) {
      debugPrint('Error checking developer mode: $e');
      isDeveloperModeEnabled = false;
    }
    return isDeveloperModeEnabled;
  }

  /// Opens Android Developer options (falls back to Settings).
  static Future<void> openDeveloperSettings() async {
    try {
      await _channel.invokeMethod('openDeveloperSettings');
    } catch (e) {
      debugPrint('Error opening developer settings: $e');
    }
  }

  /// يجب استدعاؤها مرة واحدة فقط من main.dart
  static void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenCaptureChanged') {
        final bool captured = call.arguments == true;
        isScreenRecording.value = captured;
      }
    });
  }

  static Future<void> enableSecure() async {
    try {
      // لا نستدعي init() هنا — تم استدعاؤها مسبقاً من main.dart
      await _channel.invokeMethod('enableSecure');
      _isSecure = true;

      // اقرأ الحالة الحالية فوراً
      final bool? captured = await _channel.invokeMethod<bool>('isCaptured');
      if (captured != null) {
        isScreenRecording.value = captured;
      }
    } catch (e) {
      debugPrint('Error enabling secure screen: $e');
    }
  }

  static Future<void> disableSecure() async {
    try {
      await _channel.invokeMethod('disableSecure');
      _isSecure = false;
      isScreenRecording.value = false;
    } catch (e) {
      debugPrint('Error disabling secure screen: $e');
    }
  }
}
