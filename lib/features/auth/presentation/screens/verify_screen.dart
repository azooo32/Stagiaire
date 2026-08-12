import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../main_navigation_shell.dart';

class VerifyScreen extends StatefulWidget {
  final String email;
  final String name;
  final String university;
  final String stage;

  const VerifyScreen({
    super.key,
    required this.email,
    required this.name,
    required this.university,
    required this.stage,
  });

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen>
    with TickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  late AnimationController _shieldController;
  late Animation<double> _shieldScale;
  bool _loading = false;

  static const Color _purple = Color(0xFF6B4EFF);
  static const Color _purpleDark = Color(0xFF5635D8);
  static const Color _bgLight = Color(0xFFF7F4FF);
  static const Color _fieldBg = Color(0xFFF1EEFB);
  static const Color _labelColor = Color(0xFF16124A);

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _shieldScale =
        CurvedAnimation(parent: _shieldController, curve: Curves.elasticOut);
    _shieldController.forward();
  }

  @override
  void dispose() {
    for (final o in _controllers) {
      o.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shieldController.dispose();
    super.dispose();
  }

  void _onOtpInput(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _handleVerifyOTP() async {
    final token = _controllers.map((o) => o.text).join().trim();
    if (token.length < 6) {
      _showError('يرجى إدخال رمز التحقق المكون من 6 أرقام');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final supabase = SupabaseService();
      // Try verifying as signup confirmation first
      AuthResponse response;
      try {
        response = await supabase.verifyOTP(
          email: widget.email,
          token: token,
          type: OtpType.signup,
        );
      } catch (e) {
        // Fallback to login/magiclink verification type if signup fails
        response = await supabase.verifyOTP(
          email: widget.email,
          token: token,
          type: OtpType.magiclink,
        );
      }

      if (response.user != null) {
        // Save user profile data now that the user has an active session
        await SupabaseService().createUserRecord(
          userId: response.user!.id,
          email: widget.email,
          name: widget.name,
          university: widget.university,
          stage: widget.stage,
        );
        // Navigate to the main application shell
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationShell()),
        );
      } else {
        _showError('رمز التحقق غير صحيح، يرجى المحاولة مرة أخرى');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleResendOTP() async {
    setState(() {
      _loading = true;
    });

    try {
      final supabase = SupabaseService();
      await supabase.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (mounted) {
        showAppToast(context, 'تم إعادة إرسال رمز التحقق بنجاح', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showError(String message) {
    showAppToast(context, message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                // Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF8B6EFF), _purpleDark]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _purple.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),

                const SizedBox(height: 34),

                // Shield Illustration with sparkles
                ScaleTransition(
                  scale: _shieldScale,
                  child: Center(child: _buildShieldIllustration()),
                ),

                const SizedBox(height: 34),

                // Title
                const Text(
                  'Verify Code',
                  style: TextStyle(
                    color: _labelColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter the verification code we sent to',
                  style: TextStyle(
                      color: Colors.grey[500], fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.email.isNotEmpty ? widget.email : 'example@gmail.com',
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 44),

                // OTP Input Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) => _buildOtpBox(index)),
                ),

                const SizedBox(height: 36),

                // Resend section
                Column(
                  children: [
                    Text(
                      "Didn't receive OTP?",
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _loading ? null : _handleResendOTP,
                      child: const Text(
                        'Resend code',
                        style: TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                          decorationColor: _purple,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 44),

                // Verify Button
                _loading
                    ? const Center(child: MiniSpinner(size: 32, color: _purple))
                    : GestureDetector(
                        onTap: _handleVerifyOTP,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B6EFF), _purpleDark],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Verify',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final bool hasFocus = _focusNodes[index].hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 52,
      height: 56,
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasFocus ? const Color(0xFF6B4EFF) : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: hasFocus
                ? const Color(0xFF6B4EFF).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Focus(
        onFocusChange: (_) => setState(() {}),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          onChanged: (val) => _onOtpInput(val, index),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Color(0xFF333355),
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIllustration() {
    return SizedBox(
      width: 180,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer sparkles
          ..._buildSparkles(),
          // Shield
          Container(
            width: 110,
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9B7EFF), Color(0xFF6B4EFF)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B4EFF).withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.lock_outline_rounded,
                  color: Colors.white, size: 44),
            ),
          ),
          // Green oheok badge
          Positioned(
            right: 28,
            bottom: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8FF),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3DD68C).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.check, color: _purple, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSparkles() {
    // Star sparkle positions matching the design illustration
    final positions = [
      {'left': 10.0, 'top': 10.0, 'size': 12.0},
      {'left': 15.0, 'top': 50.0, 'size': 8.0},
      {'right': 10.0, 'top': 10.0, 'size': 10.0},
      {'right': 15.0, 'top': 55.0, 'size': 14.0},
      {'left': 30.0, 'bottom': 10.0, 'size': 8.0},
      {'right': 30.0, 'bottom': 10.0, 'size': 10.0},
    ];

    return positions.map((p) {
      return Positioned(
        left: p['left'] as double?,
        right: p['right'] as double?,
        top: p['top'] as double?,
        bottom: p['bottom'] as double?,
        child: Icon(
          Icons.add,
          color: const Color(0xFFAA99EE).withValues(alpha: 0.6),
          size: p['size'] as double,
        ),
      );
    }).toList();
  }
}








