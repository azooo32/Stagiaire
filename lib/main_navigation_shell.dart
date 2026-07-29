import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/providers/app_provider.dart';
import 'core/theme/colors.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/subjects/presentation/screens/subjects_screen.dart';
import 'features/favorites/presentation/screens/favorites_screen.dart';
import 'features/progress/presentation/screens/progress_screen.dart';
import 'features/clinical/presentation/screens/clinical_screen.dart';
import 'features/auth/presentation/screens/login_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  bool _isAnimating = false;

  final List<Widget> _screens = [
    const SubjectsScreen(), // Index 0: استكشف
    const FavoritesScreen(), // Index 1: المفضلة
    const HomeScreen(), // Index 2: الرئيسية (Center)
    const ProgressScreen(), // Index 3: المتصدرين
    const ClinicalScreen(), // Index 4: السريري (Clinical Screen)
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.initializeData();
      provider.addListener(_onProviderUpdate);
    });
  }

  @override
  void dispose() {
    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.removeListener(_onProviderUpdate);
    } catch (_) {}
    super.dispose();
  }

  void _onProviderUpdate() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.isSessionInvalidated) {
      provider.removeListener(_onProviderUpdate);
      _showSessionInvalidatedDialog();
    }
  }

  void _showSessionInvalidatedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تنبيه الأمان',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'تم تسجيل الخروج لأن حسابك مفتوح حالياً من جهازين آخرين. يُسمح بفتح الحساب من جهازين كحد أقصى.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'تسجيل الدخول مجدداً',
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor:
          provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
      body: Stack(
        children: [
          IndexedStack(
            index: provider.currentTab,
            children: _screens,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset > 0 ? bottomInset + 2.0 : 4.0,
            child: _buildFloatingNavigationBar(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNavigationBar(AppProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: provider.isDarkTheme ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: provider.isDarkTheme
                ? AppColors.indigoGlow
                : const Color(0xFF6B4EFF).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = constraints.maxWidth / 5;
          final double dotWidth = _isAnimating ? 6.0 : 12.0;
          final double dotLeft = ((4 - provider.currentTab) * itemWidth) +
              (itemWidth / 2) -
              (dotWidth / 2);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                left: dotLeft,
                bottom: _isAnimating ? 14 : 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: dotWidth,
                  height: 6,
                  decoration: BoxDecoration(
                    color: provider.isDarkTheme
                        ? AppColors.indigo
                        : const Color(0xFF6B4EFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabItem(
                        provider,
                        index: 0,
                        icon: Icons.menu_book_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildTabItem(
                        provider,
                        index: 1,
                        icon: Icons.favorite_border_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildTabItem(
                        provider,
                        index: 2,
                        icon: Icons.home_filled,
                      ),
                    ),
                    Expanded(
                      child: _buildTabItem(
                        provider,
                        index: 3,
                        icon: Icons.leaderboard_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildTabItem(
                        provider,
                        index: 4,
                        icon: Icons
                            .health_and_safety_outlined, // Clinical training
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabItem(
    AppProvider provider, {
    required int index,
    required IconData icon,
  }) {
    final isSelected = provider.currentTab == index;
    final color = isSelected
        ? (provider.isDarkTheme ? AppColors.indigo : const Color(0xFF6B4EFF))
        : (provider.isDarkTheme
            ? AppColors.textMuted
            : const Color(0xFF9E9EBF));

    return GestureDetector(
      onTap: () {
        if (provider.currentTab == index) return;
        provider.setCurrentTab(index);
        setState(() {
          _isAnimating = true;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _isAnimating = false;
            });
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        transform: Matrix4.translationValues(0, isSelected ? -5 : 0, 0),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          scale: isSelected ? 1.25 : 1.0,
          curve: Curves.easeOutBack,
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}





