import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static const MethodChannel _channel =
      MethodChannel('com.invetstecur.stagiaire/security');

  static bool _isSecure = false;
  static bool get isSecure => _isSecure;

  // يضمن أن init() تُنفَّذ مرة واحدة فقط طوال عمر التطبيق
  static bool _initialized = false;

  static ValueNotifier<bool> isScreenRecording = ValueNotifier<bool>(false);

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
