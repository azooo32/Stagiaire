import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import 'login_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _purpleDark = Color(0xFF5635D8);
const Color _ink = Color(0xFF16124A);
const Color _muted = Color(0xFF67608A);
const Color _fieldBg = Color(0xFFF1EEFB);
const String _logoAsset = 'assets/Picsart_26-07-13_19-40-06-144.png';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _step = 1; // 1: Enter Email, 2: Enter OTP, 3: Create New Password
  bool _loading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('يرجى إدخال البريد الإلكتروني');
      return;
    }
    setState(() => _loading = true);
    try {
      await SupabaseService().resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _step = 2;
      });
      _showSuccess('تم إرسال رمز التحقق (OTP) إلى بريدك الإلكتروني بنجاح');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleVerifyOtpCode() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      _showError('يرجى إدخال رمز التحقق (OTP)');
      return;
    }
    setState(() => _loading = true);
    try {
      final supabase = SupabaseService();
      final authResponse = await supabase.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.recovery,
      );

      if (authResponse.session == null && authResponse.user == null) {
        _showError('رمز التحقق غير صحيح أو منتهي الصلاحية');
        return;
      }

      if (!mounted) return;
      setState(() {
        _step = 3;
      });
      _showSuccess('تم التأكد من الرمز بنجاح! أدخل كلمة المرور الجديدة.');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSaveNewPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('يرجى ملء جميع الحقول المطلوب إدخالها');
      return;
    }
    if (newPassword.length < 6) {
      _showError('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    if (newPassword != confirmPassword) {
      _showError('كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() => _loading = true);
    try {
      await SupabaseService().updatePassword(newPassword);

      if (!mounted) return;
      _showSuccess('تم تحديث وحفظ كلمة المرور بنجاح!');

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    showAppToast(context, message, isError: true);
  }

  void _showSuccess(String message) {
    showAppToast(context, message, isError: false);
  }

  String get _headerTitle {
    switch (_step) {
      case 1:
        return 'Forgot Password';
      case 2:
        return 'Enter OTP Code';
      case 3:
        return 'New Password';
      default:
        return 'Forgot Password';
    }
  }

  String get _headerSubtitle {
    switch (_step) {
      case 1:
        return 'Enter your email address to receive\na numeric OTP reset code.';
      case 2:
        return 'Enter the 6-digit OTP code sent to\n${_emailController.text.trim()}';
      case 3:
        return 'Create and confirm your new password\nto complete recovery.';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepCircle(1, 'Email'),
        _stepLine(_step >= 2),
        _stepCircle(2, 'OTP'),
        _stepLine(_step >= 3),
        _stepCircle(3, 'Password'),
      ],
    );
  }

  Widget _stepCircle(int stepNum, String title) {
    final isActive = _step >= stepNum;
    final isCurrent = _step == stepNum;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? _purple : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? _purple : const Color(0xFFD0C9E8),
              width: 2,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: isActive && stepNum < _step
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : Text(
                    '$stepNum',
                    style: TextStyle(
                      color: isActive ? Colors.white : _muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: isCurrent ? _purple : _muted,
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _stepLine(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 36,
      height: 3,
      margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
      decoration: BoxDecoration(
        color: isActive ? _purple : const Color(0xFFE4DDF8),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _PurpleHeader(
                      title: _headerTitle,
                      subtitle: _headerSubtitle,
                      onBack: () {
                        if (_step > 1) {
                          setState(() => _step--);
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 272, 22, 0),
                      child: _AuthCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStepIndicator(),
                            const SizedBox(height: 20),
                            if (_step == 1) ...[
                              const _Label('Email Address'),
                              const SizedBox(height: 8),
                              _AuthField(
                                controller: _emailController,
                                hint: 'example@gmail.com',
                                icon: Icons.mail_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 28),
                              _loading
                                  ? const Center(
                                      child: MiniSpinner(size: 34, color: _purple))
                                  : _PrimaryButton(
                                      label: 'Send Reset Code',
                                      onTap: _handleSendResetCode,
                                    ),
                            ] else if (_step == 2) ...[
                              const _Label('Numeric OTP Code'),
                              const SizedBox(height: 8),
                              _AuthField(
                                controller: _otpController,
                                hint: 'Enter 6-digit OTP code',
                                icon: Icons.pin_outlined,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 24),
                              _loading
                                  ? const Center(
                                      child: MiniSpinner(size: 34, color: _purple))
                                  : _PrimaryButton(
                                      label: 'Verify Code',
                                      onTap: _handleVerifyOtpCode,
                                    ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    onTap: () => setState(() => _step = 1),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 6),
                                      child: Text(
                                        'Change Email',
                                        style: TextStyle(
                                          color: _purple,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _handleSendResetCode,
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 6),
                                      child: Text(
                                        'Resend OTP',
                                        style: TextStyle(
                                          color: _purple,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (_step == 3) ...[
                              const _Label('New Password'),
                              const SizedBox(height: 8),
                              _AuthField(
                                controller: _newPasswordController,
                                hint: '**************',
                                icon: Icons.lock_outline_rounded,
                                obscureText: _obscureNewPassword,
                                suffix: IconButton(
                                  onPressed: () => setState(() =>
                                      _obscureNewPassword = !_obscureNewPassword),
                                  icon: Icon(
                                    _obscureNewPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: _ink,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const _Label('Confirm New Password'),
                              const SizedBox(height: 8),
                              _AuthField(
                                controller: _confirmPasswordController,
                                hint: '**************',
                                icon: Icons.lock_clock_outlined,
                                obscureText: _obscureConfirmPassword,
                                suffix: IconButton(
                                  onPressed: () => setState(() =>
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword),
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: _ink,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              _loading
                                  ? const Center(
                                      child: MiniSpinner(size: 34, color: _purple))
                                  : _PrimaryButton(
                                      label: 'Save Password',
                                      onTap: _handleSaveNewPassword,
                                    ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Remember your password? ',
                                    style: TextStyle(color: _ink, fontSize: 14)),
                                InkWell(
                                  onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const LoginScreen()),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 6),
                                    child: Text(
                                      'Sign In',
                                      style: TextStyle(
                                        color: _purple,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurpleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _PurpleHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 64),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7E5BFF), _purpleDark],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeaderWavePainter())),
          Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _BackCircle(onTap: onBack),
              ),
              const SizedBox(height: 10),
              Image.asset(_logoAsset, height: 64, fit: BoxFit.contain),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  final Widget child;
  const _AuthCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.11),
            blurRadius: 28,
            offset: const Offset(0, 16),
          )
        ],
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: _ink, fontWeight: FontWeight.w800, fontSize: 14),
      );
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;

  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
          color: _ink, fontWeight: FontWeight.w600, fontSize: 15),
      decoration: InputDecoration(
        filled: true,
        fillColor: _fieldBg,
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 14),
        prefixIcon: Icon(icon, color: _muted, size: 22),
        suffixIcon: suffix,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(colors: [Color(0xFF7B5EFF), _purpleDark]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _purple.withValues(alpha: 0.34),
                blurRadius: 18,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _BackCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 25,
        ),
      ),
    );
  }
}

class _HeaderWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final path = Path()
      ..moveTo(size.width * 0.16, 0)
      ..quadraticBezierTo(
          size.width * 0.68, size.height * 0.18, size.width, size.height * 0.05)
      ..lineTo(size.width, size.height)
      ..quadraticBezierTo(
          size.width * 0.42, size.height * 0.78, 0, size.height * 0.92)
      ..lineTo(0, size.height * 0.28)
      ..quadraticBezierTo(
          size.width * 0.08, size.height * 0.12, size.width * 0.16, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
