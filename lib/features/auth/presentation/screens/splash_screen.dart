import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/security_service.dart';
import 'package:video_player/video_player.dart';
import '../../../../main_navigation_shell.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'security_block_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _bgColor = Color(0xFF6C4EFF);
  VideoPlayerController? _controller;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
    // Safety net: never block the app if the video fails or stalls.
    Timer(const Duration(seconds: 8), _navigateToNext);
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset('assets/video/logo_full.mp4');
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_onVideoTick);
      setState(() {});
      await controller.play();
    } catch (_) {
      _navigateToNext();
    }
  }

  void _onVideoTick() {
    final v = _controller?.value;
    if (v == null) return;
    if (v.hasError ||
        (v.isInitialized && !v.isPlaying && v.position >= v.duration)) {
      _navigateToNext();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    // فحص أمان الجهاز: حظر الأجهزة المروّتة لحماية المحتوى
    if (SecurityService.isDeviceRooted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SecurityBlockScreen()),
      );
      return;
    }

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
    final c = _controller;
    return Scaffold(
      backgroundColor: _bgColor,
      body: Center(
        child: c != null && c.value.isInitialized
            ? AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
