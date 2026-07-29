import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../main_navigation_shell.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _showBrandOnly = true;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();

    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showBrandOnly = false);
    });
    Timer(const Duration(milliseconds: 3300), _navigateToNext);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    if (!mounted) return;

    final supabase = SupabaseService();
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;

    if (supabase.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainNavigationShell(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => hasSeenOnboarding
              ? const LoginScreen()
              : const OnboardingScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.white, // Blends seamlessly with the logo's white background
      body: Stack(
        children: [
          // Background subtle design pattern or solid white
          Positioned.fill(
            child: Container(
              color: Colors.white,
            ),
          ),

          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _showBrandOnly
                  ? Image.asset(
                      'assets/app_logo.png',
                      key: const ValueKey('native-logo'),
                      width: 118,
                      height: 118,
                      fit: BoxFit.contain,
                    )
                  : Column(
                      key: const ValueKey('loading-logo'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Image.asset(
                            'assets/file_00000000985c71f481237896d57282a1.png',
                            width: 190,
                            height: 190,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 26),
                        const MiniSpinner(
                          size: 24,
                          color: Color(0xFF6B4EFF),
                          strokeWidth: 2.5,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}





