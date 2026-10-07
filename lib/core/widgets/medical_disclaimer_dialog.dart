import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';

class MedicalDisclaimerDialog extends StatelessWidget {
  final bool isFirstLaunch;
  final VoidCallback? onAccepted;

  const MedicalDisclaimerDialog({
    super.key,
    this.isFirstLaunch = false,
    this.onAccepted,
  });

  static const String prefKey = 'medical_disclaimer_accepted';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) ?? false;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, true);
  }

  static Future<void> show(
    BuildContext context, {
    bool isFirstLaunch = false,
    VoidCallback? onAccepted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isFirstLaunch,
      builder: (ctx) => PopScope(
        canPop: !isFirstLaunch,
        child: MedicalDisclaimerDialog(
          isFirstLaunch: isFirstLaunch,
          onAccepted: onAccepted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? AppColors.surface : Colors.white;
    final textColor = isDark ? AppColors.text : const Color(0xFF1E293B);
    final mutedColor = isDark ? AppColors.textMuted : const Color(0xFF64748B);
    final cardBg = isDark ? AppColors.surface2 : const Color(0xFFF8FAFC);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4EFF).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Color(0xFF6B4EFF),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'إخلاء المسؤولية الطبية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              Text(
                'Medical Disclaimer',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 16),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'تنبيه هام للمستخدمين:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• هذا التطبيق (Stagiaire) مخصص حصراً كأداة تعليمية وتدريبية لطلاب كليات الطب والأطباء المتدربين للمساعدة في المذاكرة والتحضير للامتحانات السريرية والنظرية.\n\n'
                          '• جميع المعلومات، الأسئلة، الشروحات، والمواد السريرية الواردة داخل التطبيق مقدمة لأغراض تعليمية وإرشادية فقط.\n\n'
                          '• المحتوى لا يُعد بأي شكل من الأشكال استشارة طبية مهنية، تشخيصاً لحالات حقيقية، أو خطة علاجية لأي مريض.\n\n'
                          '• يجب دائماً استشارة طبيب مختص أو ممارس رعاية صحية مرخص قبل اتخاذ أي قرار طبي أو بدء أي علاج.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            height: 1.6,
                            color: textColor,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(),
                        ),
                        Text(
                          'Educational & Informational Purpose Only:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: textColor,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Stagiaire is an educational reference platform designed solely for medical students and exam preparation. The information provided does not constitute medical advice, clinical diagnosis, or treatment recommendations. Always seek the advice of a qualified physician or healthcare provider with any questions regarding a medical condition.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: mutedColor,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (isFirstLaunch) {
                      await markAccepted();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        onAccepted?.call();
                      }
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isFirstLaunch ? 'أوافق وأتفهم (I Agree & Understand)' : 'إغلاق (Close)',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
