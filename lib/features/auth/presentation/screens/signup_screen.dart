import 'package:flutter/material.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import 'login_screen.dart';
import 'verify_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _purpleDark = Color(0xFF5635D8);
const Color _ink = Color(0xFF16124A);
const Color _muted = Color(0xFF67608A);
const Color _fieldBg = Color(0xFFF1EEFB);
const String _logoAsset = 'assets/Picsart_26-07-13_19-40-06-144.png';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _agreeTerms = false;
  bool _loading = false;
  String? _selectedStage;
  String? _selectedUniversity;

  final List<String> _stages = const [
    'المرحلة الأولى',
    'المرحلة الثانية',
    'المرحلة الثالثة',
    'المرحلة الرابعة',
    'المرحلة الخامسة',
    'المرحلة السادسة',
    'طالب امتياز',
    'طبيب مقيم',
    'طبيب أخصائي',
    'طبيب استشاري'
  ];
  final List<String> _universities = const [
    'كلية طب الموصل',
    'كلية طب نينوى',
    'كلية طب بغداد',
    'كلية طب الكندي',
    'كلية طب المستنصرية',
    'كلية طب النهرين',
    'كلية طب البصرة',
    'كلية طب الكوفة',
    'كلية طب كربلاء',
    'كلية طب بابل',
    'كلية طب ديالى',
    'كلية طب كركوك',
    'كلية طب الأنبار'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty) {
      _showError('يرجى إدخال الاسم الكامل');
      return;
    }
    if (email.isEmpty) {
      _showError('يرجى إدخال البريد الإلكتروني');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('البريد الإلكتروني غير صالح أو مكتوب بشكل خاطئ، يرجى التأكد منه');
      return;
    }
    if (_selectedStage == null || _selectedStage!.isEmpty) {
      _showError('اختيار المرحلة إجباري، يرجى تحديد مرحلتك الدراسية');
      return;
    }
    if (_selectedUniversity == null || _selectedUniversity!.isEmpty) {
      _showError('اختيار الجامعة إجباري، يرجى تحديد جامعتك');
      return;
    }
    if (password.isEmpty) {
      _showError('يرجى إدخال كلمة المرور');
      return;
    }
    if (password.length < 6) {
      _showError('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    if (!_agreeTerms) {
      _showError('يجب الموافقة على الشروط والأحكام');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await SupabaseService().signUp(
          email: email,
          password: password,
          name: name,
          university: _selectedUniversity!,
          stage: _selectedStage!);
      if (response.user != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyScreen(
              email: email,
              name: name,
              university: _selectedUniversity!,
              stage: _selectedStage!,
            ),
          ),
        );
      } else {
        _showError('فشل تسجيل الحساب، يرجى المحاولة مرة أخرى');
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('email') && (errStr.contains('invalid') || errStr.contains('format') || errStr.contains('unable'))) {
        _showError('البريد الإلكتروني غير صالح أو لم يتم العثور عليه، يرجى التأكد من البريد الإلكتروني');
      } else {
        _showError(e.toString());
      }
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
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _PurpleHeader(
                    title: 'Create Account',
                    subtitle:
                        'Fill your information below to register your account.',
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 272, 22, 0),
                    child: _AuthCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Label('Name'),
                          const SizedBox(height: 8),
                          _AuthField(
                              controller: _nameController,
                              hint: 'John Doe',
                              icon: Icons.person_outline_rounded),
                          const SizedBox(height: 16),
                          _Label('Email'),
                          const SizedBox(height: 8),
                          _AuthField(
                              controller: _emailController,
                              hint: 'example@gmail.com',
                              icon: Icons.mail_outline_rounded),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _Label('المرحلة *'),
                                    const SizedBox(height: 8),
                                    _DropdownField(
                                      value: _selectedStage,
                                      items: _stages,
                                      hint: 'المرحلة *',
                                      onChanged: (v) =>
                                          setState(() => _selectedStage = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _Label('الجامعة *'),
                                    const SizedBox(height: 8),
                                    _DropdownField(
                                      value: _selectedUniversity,
                                      items: _universities,
                                      hint: 'الجامعة *',
                                      onChanged: (v) => setState(
                                          () => _selectedUniversity = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _Label('Password'),
                          const SizedBox(height: 8),
                          _AuthField(
                            controller: _passwordController,
                            hint: '**************',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            suffix: IconButton(
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                              icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: _ink,
                                  size: 22),
                            ),
                          ),
                          const SizedBox(height: 18),
                          InkWell(
                            onTap: () =>
                                setState(() => _agreeTerms = !_agreeTerms),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                        color: _agreeTerms
                                            ? _purple
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: _purple, width: 1.5)),
                                    child: _agreeTerms
                                        ? const Icon(Icons.check_rounded,
                                            color: Colors.white, size: 16)
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                      child: Text(
                                          'Agree with Terms & Condition',
                                          style: TextStyle(
                                              color: _ink,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _loading
                              ? const Center(
                                  child: MiniSpinner(size: 34, color: _purple))
                              : _PrimaryButton(
                                  label: 'Sign Up', onTap: _handleSignUp),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Already have an account? ',
                                  style: TextStyle(color: _ink, fontSize: 14)),
                              InkWell(
                                onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const LoginScreen())),
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  child: Text('Sign In',
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
              const SizedBox(height: 36),
            ],
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

  const _PurpleHeader(
      {required this.title, required this.subtitle, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 338,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 64),
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7E5BFF), _purpleDark])),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeaderWavePainter())),
          Column(
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: _BackCircle(onTap: onBack)),
              const SizedBox(height: 14),
              Image.asset(_logoAsset, height: 72, fit: BoxFit.contain),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 27)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      height: 1.35)),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: _purple.withValues(alpha: 0.11),
                  blurRadius: 28,
                  offset: const Offset(0, 16))
            ]),
        child: child,
      );
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
  Widget build(BuildContext context) => TextField(
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
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
      );
}

class _DropdownField extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;

  const _DropdownField(
      {required this.value,
      required this.items,
      required this.hint,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: _fieldBg, borderRadius: BorderRadius.circular(15)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(hint,
                style: const TextStyle(
                    color: _muted, fontSize: 12, fontFamily: 'Cairo')),
            style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo'),
            items: items
                .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 58,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF7B5EFF), _purpleDark]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: _purple.withValues(alpha: 0.34),
                      blurRadius: 18,
                      offset: const Offset(0, 8))
                ]),
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

class _BackCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _BackCircle({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 25)));
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
