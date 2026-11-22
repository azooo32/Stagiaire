import 'package:flutter/material.dart';

import '../../../../core/services/security_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import 'splash_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _warning = Color(0xFFF39C12);

/// Shown at launch (Android release builds) while "Developer options" is on.
/// The app does not open until the student turns it off; returning from
/// Settings re-checks automatically.
class DeveloperModeBlockScreen extends StatefulWidget {
  const DeveloperModeBlockScreen({super.key});

  @override
  State<DeveloperModeBlockScreen> createState() =>
      _DeveloperModeBlockScreenState();
}

class _DeveloperModeBlockScreenState extends State<DeveloperModeBlockScreen>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings → check again without needing a tap.
    if (state == AppLifecycleState.resumed) _recheck(silent: true);
  }

  Future<void> _recheck({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final stillOn = await SecurityService.recheckDeveloperMode();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!stillOn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
    } else if (!silent) {
      showAppToast(context, 'وضع المطور ما زال مفعّلاً في الجهاز',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final bodyColor = isDark ? const Color(0xFFE0DEF1) : const Color(0xFF2D3436);
    final mutedColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF14121E) : const Color(0xFFF8F9FA),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: _warning.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _warning.withValues(alpha: 0.35), width: 2),
                      ),
                      child: const Icon(Icons.developer_mode_rounded,
                          size: 54, color: _warning),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'يجب إيقاف وضع المطور',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: titleColor),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F1D2B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isDark
                                ? const Color(0xFF2E2B3D)
                                : const Color(0xFFE2E0EF)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'وضع المطور (خيارات المطور) مفعّل في جهازك. لحماية المحتوى التعليمي لا يعمل التطبيق أثناء تفعيله.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.6,
                                color: bodyColor),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'افتح الإعدادات ← خيارات المطور، ثم أوقف المفتاح في أعلى الصفحة وارجع إلى التطبيق.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                height: 1.6,
                                color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: SecurityService.openDeveloperSettings,
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('فتح الإعدادات',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: const BorderSide(color: _purple, width: 1.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _checking ? null : () => _recheck(),
                        child: _checking
                            ? const MiniSpinner(size: 22, color: _purple)
                            : const Text('تحقق مرة أخرى',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
