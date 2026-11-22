import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../main_navigation_shell.dart';
import '../screens/complete_profile_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _ink = Color(0xFF16124A);
const Color _muted = Color(0xFF67608A);

/// Google: Android + iOS (iOS uses its own OAuth client and the Info.plist
/// URL scheme; allowed on the App Store because Apple sign-in is offered too).
/// Hidden on web (Telegram mini app): Google blocks embedded webviews.
bool get isGoogleSignInAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Apple: iPhone/iPad only (native sheet). On Android it would need the web
/// OAuth flow with a secret that expires every 6 months.
bool get isAppleSignInAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum _Provider { google, apple }

/// "or" divider + the social sign-in buttons available on this platform.
/// Renders nothing where none is available, so screens include it as-is.
class SocialSignInSection extends StatefulWidget {
  const SocialSignInSection({super.key});

  @override
  State<SocialSignInSection> createState() => _SocialSignInSectionState();
}

class _SocialSignInSectionState extends State<SocialSignInSection> {
  _Provider? _busy;

  Future<void> _signIn(_Provider provider) async {
    if (_busy != null) return;
    setState(() => _busy = provider);
    final supabase = SupabaseService();
    final label = provider == _Provider.google ? 'بجوجل' : 'بأبل';
    try {
      final response = provider == _Provider.google
          ? await supabase.signInWithGoogle()
          : await supabase.signInWithApple();
      if (!mounted) return;
      if (response == null || response.user == null) return; // sheet closed

      // Missing name/stage/university (new account, or old account that
      // skipped it) → mandatory profile step. Complete → straight in.
      final complete = await supabase.isProfileComplete();
      if (!mounted) return;
      final Widget next = complete == false
          ? const CompleteProfileScreen()
          : const MainNavigationShell();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } on AuthException catch (e) {
      debugPrint('Social sign-in ($provider, Supabase) error: ${e.message}');
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      showAppToast(
        context,
        msg.contains('provider') || msg.contains('not enabled')
            ? 'تسجيل الدخول $label غير متاح حالياً، استخدم البريد الإلكتروني'
            : 'تعذر تسجيل الدخول $label، يرجى المحاولة مرة أخرى',
        isError: true,
      );
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in error: ${e.code} ${e.description}');
      if (!mounted) return;
      showAppToast(
        context,
        'تعذر تسجيل الدخول بجوجل، تأكد من الاتصال وحاول مرة أخرى',
        isError: true,
      );
    } catch (e) {
      debugPrint('Social sign-in ($provider) unexpected error: $e');
      if (!mounted) return;
      showAppToast(
        context,
        'تعذر تسجيل الدخول $label، يرجى المحاولة مرة أخرى',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showGoogle = isGoogleSignInAvailable;
    final showApple = isAppleSignInAvailable;
    if (!showGoogle && !showApple) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE2DDF5))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or',
                  style: TextStyle(
                      color: _muted.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
            const Expanded(child: Divider(color: Color(0xFFE2DDF5))),
          ],
        ),
        if (showApple) ...[
          const SizedBox(height: 14),
          _AppleButton(
            loading: _busy == _Provider.apple,
            onTap: _busy == null ? () => _signIn(_Provider.apple) : null,
          ),
        ],
        if (showGoogle) ...[
          const SizedBox(height: 14),
          _GoogleButton(
            loading: _busy == _Provider.google,
            onTap: _busy == null ? () => _signIn(_Provider.google) : null,
          ),
        ],
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            disabledBackgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFDCD6F2), width: 1.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          child: loading
              ? const MiniSpinner(size: 24, color: _purple)
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleLogo(size: 22),
                    SizedBox(width: 12),
                    Text('Google',
                        style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ],
                ),
        ),
      );
}

/// Black Apple button. Apple's review guidelines only accept the titles
/// "Sign in with Apple" / "Continue with Apple" (or the logo alone), so the
/// text is not shortened to "Apple" like the Google button.
class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            disabledBackgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          child: loading
              ? const MiniSpinner(size: 24, color: Colors.white)
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple, color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Text('Sign in with Apple',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ],
                ),
        ),
      );
}

/// The official four-colour Google "G" (paths from Google's sign-in branding
/// SVG, 48x48 viewBox), drawn without an extra SVG package.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: const _GoogleLogoPainter(),
      );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Red (top)
    final red = Path()
      ..moveTo(24, 9.5)
      ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
      ..relativeLineTo(6.85, -6.85)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..relativeLineTo(7.98, 6.19)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close();
    canvas.drawPath(red, paint..color = const Color(0xFFEA4335));

    // Blue (right + bar)
    final blue = Path()
      ..moveTo(46.98, 24.55)
      ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
      ..lineTo(24, 20)
      ..relativeLineTo(0, 9.02)
      ..relativeLineTo(12.94, 0)
      ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
      ..relativeLineTo(7.73, 6)
      ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
      ..close();
    canvas.drawPath(blue, paint..color = const Color(0xFF4285F4));

    // Yellow (left)
    final yellow = Path()
      ..moveTo(10.53, 28.59)
      ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
      ..relativeCubicTo(0, -1.6, 0.27, -3.14, 0.76, -4.59)
      ..relativeLineTo(-7.98, -6.19)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
      ..relativeLineTo(7.97, -6.19)
      ..close();
    canvas.drawPath(yellow, paint..color = const Color(0xFFFBBC05));

    // Green (bottom)
    final green = Path()
      ..moveTo(24, 48)
      ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
      ..relativeLineTo(-7.73, -6)
      ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
      ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
      ..relativeLineTo(-7.98, 6.19)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close();
    canvas.drawPath(green, paint..color = const Color(0xFF34A853));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
