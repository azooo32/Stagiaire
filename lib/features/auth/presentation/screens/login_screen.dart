import 'package:flutter/material.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../main_navigation_shell.dart';
import '../../../../core/widgets/app_toast.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _purpleDark = Color(0xFF5635D8);
const Color _ink = Color(0xFF16124A);
const Color _muted = Color(0xFF67608A);
const Color _fieldBg = Color(0xFFF1EEFB);
const String _logoAsset = 'assets/Picsart_26-07-13_19-40-06-144.png';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError('يرجى إدخال البريد الإلكتروني وكلمة المرور');
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await SupabaseService().signIn(email, password);
      if (!mounted) return;
      if (response.user != null) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const MainNavigationShell()));
      } else {
        _showError('فشل تسجيل الدخول، يرجى التحقق من بياناتك');
      }
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
                SizedBox(
                  height: 650,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _PurpleHeader(
                        logoAsset: _logoAsset,
                        title: "Let's get you Login!",
                        subtitle: "Hi! Welcome back, you've been missed",
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      Positioned(
                        left: 22,
                        right: 22,
                        top: 220,
                        child: _AuthCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _Label('Email'),
                              const SizedBox(height: 8),
                              _AuthField(
                                  controller: _emailController,
                                  hint: 'example@gmail.com',
                                  icon: Icons.mail_outline_rounded),
                              const SizedBox(height: 14),
                              const _Label('Password'),
                              const SizedBox(height: 8),
                              _AuthField(
                                controller: _passwordController,
                                hint: '**************',
                                icon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                suffix: IconButton(
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                  icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: _ink,
                                      size: 22),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordScreen()),
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 6),
                                    child: Text('Forgot Password?',
                                        style: TextStyle(
                                            color: _purple,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                TextDecoration.underline)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _loading
                                  ? const Center(
                                      child:
                                          MiniSpinner(size: 34, color: _purple))
                                  : _PrimaryButton(
                                      label: 'Sign In', onTap: _handleSignIn),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("Don't have an account? ",
                                      style:
                                          TextStyle(color: _ink, fontSize: 14)),
                                  InkWell(
                                    onTap: () => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const SignUpScreen())),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      child: Text('Sign Up',
                                          style: TextStyle(
                                              color: _purple,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              decoration:
                                                  TextDecoration.underline)),
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
  final String logoAsset;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _PurpleHeader(
      {required this.logoAsset,
      required this.title,
      required this.subtitle,
      required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 272,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7E5BFF), _purpleDark]),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeaderWavePainter())),
          Column(
            children: [
              const SizedBox(height: 8),
              Image.asset(logoAsset, height: 64, fit: BoxFit.contain),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w500,
                      fontSize: 14)),
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
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: _purple.withValues(alpha: 0.11),
              blurRadius: 28,
              offset: const Offset(0, 16))
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
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: _ink, fontWeight: FontWeight.w800, fontSize: 14));
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;

  const _AuthField(
      {required this.controller,
      required this.hint,
      required this.icon,
      this.obscureText = false,
      this.suffix});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
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
          height: 52,
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(colors: [Color(0xFF7B5EFF), _purpleDark]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: _purple.withValues(alpha: 0.34),
                  blurRadius: 18,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17)),
          ),
        ),
      ),
    );
  }
}

class _HeaderWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final softPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    final glowPaint = Paint()..color = Colors.white.withValues(alpha: 0.045);

    final wave = Path()
      ..moveTo(0, size.height * 0.46)
      ..cubicTo(size.width * 0.26, size.height * 0.26, size.width * 0.50,
          size.height * 0.20, size.width, size.height * 0.06)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(wave, softPaint);

    final lowerWave = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(size.width * 0.26, size.height * 0.58, size.width * 0.58,
          size.height * 0.92, size.width, size.height * 0.64)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(lowerWave, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
