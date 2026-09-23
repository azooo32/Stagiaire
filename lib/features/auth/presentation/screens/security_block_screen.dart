import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SecurityBlockScreen extends StatelessWidget {
  const SecurityBlockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF14121E) : const Color(0xFFF8F9FA),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon Container
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE74C3C).withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.gpp_bad_rounded,
                      size: 56,
                      color: Color(0xFFE74C3C),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title
                  Text(
                    'تنبيه أمني مشدد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF2D3436),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1F1D2B)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF2E2B3D)
                            : const Color(0xFFE2E0EF),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'تم اكتشاف أن هذا الجهاز تم تعديل نظامه أو يحتوي على صلاحيات الروت (Root / Jailbreak).',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.6,
                            color: isDark
                                ? const Color(0xFFE0DEF1)
                                : const Color(0xFF2D3436),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لحماية المحتوى التعليمي والحفاظ على أمان المنظومة وحقوق النشر، لا يُسمح بتشغيل التطبيق على أجهزة تم كسر حمايتها.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            height: 1.6,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Exit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE74C3C),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        SystemNavigator.pop();
                      },
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: const Text(
                        'إغلاق التطبيق',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
