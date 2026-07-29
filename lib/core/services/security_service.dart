import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static const MethodChannel _channel =
      MethodChannel('com.invetstecur.stagiaire/security');

  static bool _isSecure = false;
  static bool get isSecure => _isSecure;

  static ValueNotifier<bool> isScreenRecording = ValueNotifier<bool>(false);

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenCaptureChanged') {
        final bool captured = call.arguments == true;
        isScreenRecording.value = captured;
      }
    });
  }

  static Future<void> enableSecure() async {
    try {
      init();
      await _channel.invokeMethod('enableSecure');
      _isSecure = true;

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
