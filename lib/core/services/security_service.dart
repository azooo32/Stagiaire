import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static const MethodChannel _channel =
      MethodChannel('com.invetstecur.stagiaire/security');

  static bool _isSecure = false;
  static bool get isSecure => _isSecure;

  static bool isDeviceRooted = false;
  static bool isDeviceCompromised = false;

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
