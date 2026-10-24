import 'package:flutter/material.dart';
import '../utils/connectivity_helper.dart';

/// Clean and convert technical error messages into user-friendly Arabic text.
String parseErrorMessage(dynamic error) {
  if (error == null) return 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى';

  final str = error.toString();

  if (str.contains('Invalid login credentials') || str.contains('invalid_credentials')) {
    return 'بيانات الدخول غير صحيحة، يرجى التأكد من البريد وكلمة المرور';
  }
  if (str.contains('User already registered') || str.contains('email_already_in_use')) {
    return 'البريد الإلكتروني مسجل بالفعل، يرجى تسجيل الدخول أو استخدام بريد آخر';
  }
  if (str.contains('Password should be at least 6 characters')) {
    return 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
  }
  if (str.contains('New password should be different') || str.contains('same_password')) {
    return 'يرجى اختيار كلمة مرور جديدة تختلف عن كلمة المرور القديمة';
  }
  if (str.contains('Token has expired') || str.contains('otp_expired') || str.contains('invalid_token')) {
    return 'رمز التحقق غير صحيح أو منتهي الصلاحية، يرجى طلب رمز جديد';
  }
  if (str.contains('Rate limit exceeded') || str.contains('over_email_send_rate_limit')) {
    return 'تم تجاوز الحد المسموح من المحاولات، يرجى الانتظار قليلاً ثم المحاولة مرة أخرى';
  }
  if (str.contains('SocketException') ||
      str.contains('ClientException') ||
      str.contains('Network') ||
      str.contains('Failed host lookup') ||
      str.contains('HandshakeException') ||
      str.contains('TimeoutException')) {
    return 'تعذر الاتصال بالشبكة، يرجى التحقق من اتصالك بالإنترنت';
  }
  if (str.contains('DarwinAudioError') ||
      str.contains('Failed to set source') ||
      str.contains('AVPlayerItem')) {
    return 'تعذر تشغيل الصوت، يرجى المحاولة مرة أخرى';
  }

  // Extract message string from AuthException(...) pattern
  var cleaned = str;
  if (cleaned.contains('AuthException(') || cleaned.contains('message:')) {
    final regExp = RegExp(r'message:\s*([^,\)]+)');
    final match = regExp.firstMatch(cleaned);
    if (match != null && match.group(1) != null) {
      cleaned = match.group(1)!.trim();
    } else {
      cleaned = cleaned.replaceAll(RegExp(r'AuthException\(|\)'), '').trim();
    }
  }

  // Remove leading prefixes like "خطأ:" or "Exception:"
  cleaned = cleaned.replaceAll(RegExp(r'^(خطأ:|Exception:|Error:)\s*'), '').trim();

  return cleaned.isNotEmpty ? cleaned : 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى';
}

/// Student-facing failures: "no internet" banner when the device is offline,
/// otherwise a red banner with [fallbackMessage] (never the raw exception text).
Future<void> showNetworkAwareError(
    BuildContext context, String fallbackMessage) async {
  final online = await hasInternetConnection();
  if (!context.mounted) return;
  if (online) {
    showAppToast(context, fallbackMessage);
  } else {
    showOfflineToast(context);
  }
}

/// Friendly "no internet" banner (amber, wifi-off icon) shown at the bottom.
void showOfflineToast(BuildContext context, {String? message}) {
  showAppToast(
    context,
    message ?? 'لا يوجد اتصال بالإنترنت، تحقق من الشبكة ثم حاول مرة أخرى',
    isError: false,
    icon: Icons.wifi_off_rounded,
    colors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
  );
}

/// Show a beautiful floating notification banner (Toast/SnackBar)
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = true,
  IconData? icon,
  List<Color>? colors,
}) {
  final cleanedText = isError ? parseErrorMessage(message) : message;
  final gradientColors = colors ??
      (isError
          ? const [Color(0xFFE53935), Color(0xFFC62828)]
          : const [Color(0xFF2E7D32), Color(0xFF1B5E20)]);

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      elevation: 0,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 3),
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradientColors),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded),
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cleanedText,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
