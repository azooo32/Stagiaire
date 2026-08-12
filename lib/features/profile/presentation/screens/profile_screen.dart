import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import 'subscriptions_management_screen.dart';


class _ProfilePalette {
  static const Color lightBg = Color(0xFF5B3EEF);
  static const Color lightSheet = Colors.white;
  static const Color lightTile = Color(0xFFF8FAFC);
  static const Color lightText = Color(0xFF1E1E50);
  static const Color lightMuted = Color(0xFF9E9EBF);
  static const Color lightAccent = Color(0xFF6B4EFF);

  static const Color darkBg = Color(0xFF100F1F);
  static const Color darkSheet = Color(0xFF18162B);
  static const Color darkTile = Color(0xFF211E38);
  static const Color darkTile2 = Color(0xFF2C2848);
  static const Color darkBorder = Color(0xFF3B365C);
  static const Color darkAccent = Color(0xFF6C58E8);
  static const Color darkAccentDeep = Color(0xFF4930B6);
  static const Color darkAccentSoft = Color(0xFF6047D6);
  static const Color darkMuted = Color(0xFF918BAC);

  static Color bg(bool isDark) => isDark ? darkBg : lightBg;
  static Color sheet(bool isDark) => isDark ? darkSheet : lightSheet;
  static Color tile(bool isDark) => isDark ? darkTile : lightTile;
  static Color text(bool isDark) => isDark ? AppColors.text : lightText;
  static Color muted(bool isDark) => isDark ? darkMuted : lightMuted;
  static Color accent(bool isDark) => isDark ? darkAccent : lightAccent;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  static const List<String> _stages = [
    'المرحلة الأولى',
    'المرحلة الثانية',
    'المرحلة الثالثة',
    'المرحلة الرابعة',
    'المرحلة الخامسة',
    'المرحلة السادسة',
    'طالب امتياز',
    'طبيب مقيم',
    'طبيب أخصائي',
    'طبيب استشاري',
  ];

  Future<void> _showChangeStageSheet(BuildContext context, AppProvider provider, String currentStage, bool isDark, bool isTablet) async {
    String? selected = currentStage == 'غير محدد' ? null : currentStage;
    bool isSaving = false;

    final accent = isDark ? _ProfilePalette.darkAccent : _ProfilePalette.lightAccent;
    final sheetBg = isDark ? _ProfilePalette.darkSheet : Colors.white;
    final tileBg = isDark ? _ProfilePalette.darkTile : const Color(0xFFF8FAFC);
    final textColor = isDark ? AppColors.text : _ProfilePalette.lightText;
    final mutedColor = isDark ? _ProfilePalette.darkMuted : _ProfilePalette.lightMuted;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: mutedColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.school_outlined, color: accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'اختر مرحلتك الدراسية',
                          style: TextStyle(
                            color: textColor,
                            fontSize: isTablet ? 20 : 16,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Stages list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _stages.length,
                      itemBuilder: (_, i) {
                        final s = _stages[i];
                        final isSelected = selected == s;
                        return GestureDetector(
                          onTap: () => setSheet(() => selected = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? accent.withValues(alpha: 0.12) : tileBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? accent : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                  color: isSelected ? accent : mutedColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  s,
                                  style: TextStyle(
                                    color: isSelected ? accent : textColor,
                                    fontSize: isTablet ? 16 : 14,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Save button
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (selected == null || isSaving)
                            ? null
                            : () async {
                                setSheet(() => isSaving = true);
                                final ok = await SupabaseService().updateStage(selected!);
                                if (ok && ctx.mounted) {
                                  // Refresh provider cache
                                  final details = await SupabaseService().getUserDetails();
                                  if (details != null) {
                                    provider.refreshUserDetails(details);
                                  }
                                  Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          'تم تحديث مرحلتك بنجاح ✓',
                                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                        ),
                                        backgroundColor: accent,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    );
                                  }
                                } else if (ctx.mounted) {
                                  setSheet(() => isSaving = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: accent.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'حفظ التغييرات',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final userDetails = provider.userDetails;
    final isTablet = MediaQuery.of(context).size.width > 600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Retrieve metadata directly from currentUser auth as fallback
    final user = provider.currentUser;
    final String fullName = userDetails?['name'] ??
        user?.userMetadata?['full_name'] ??
        'طالب ستاجير';
    final String university = userDetails?['university'] ??
        user?.userMetadata?['university'] ??
        'غير محدد';
    final String stage =
        userDetails?['stage'] ?? user?.userMetadata?['stage'] ?? 'غير محدد';

    final int solvedCount = provider.totalAnswered;

    // Split Name for initials avatar
    String initials = 'S';
    if (fullName.trim().isNotEmpty) {
      final parts = fullName.trim().split(' ');
      if (parts.isNotEmpty) {
        initials = parts[0][0];
        if (parts.length > 1 && parts[parts.length - 1].isNotEmpty) {
          initials += parts[parts.length - 1][0];
        }
      }
    }

    return Scaffold(
      backgroundColor: _ProfilePalette.bg(provider.isDarkTheme),
      body: provider.isLoading
          ? const Center(child: LogoSpinner())
          : Column(
              children: [
                // ─── Profile Top Bar ───
                Container(
                  width: double.infinity,
                  color: _ProfilePalette.bg(provider.isDarkTheme),
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 12 : 4,
                    MediaQuery.of(context).padding.top + (isTablet ? 16 : 4),
                    isTablet ? 24 : 16,
                    isTablet ? 20 : 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: isTablet ? 36 : 24),
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            provider.setCurrentTab(2);
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isTablet ? 28 : 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      SizedBox(width: isTablet ? 72 : 48),
                    ],
                  ),
                ),
                // ─── Overlapping White Card & Avatar Stack ───
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // White container sheet for main content
                      Positioned.fill(
                        top: isTablet ? 60.0 : 40.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _ProfilePalette.sheet(provider.isDarkTheme),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                          ),
                          alignment: Alignment.topCenter,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: (isTablet && !isLandscape) ? 650 : double.infinity),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(20, isTablet ? 80 : 60, 20, 90), // top padding for avatar spacing
                              child: Column(
                                children: [
                                  // Full Name
                                  Text(
                                    fullName,
                                    style: TextStyle(
                                      color: _ProfilePalette.text(
                                          provider.isDarkTheme),
                                      fontSize: isTablet ? 28 : 20,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Subtitle points
                                  Text(
                                    '$solvedCount Solved Questions',
                                    style: TextStyle(
                                      color: _ProfilePalette.muted(
                                          provider.isDarkTheme),
                                      fontSize: isTablet ? 16 : 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // ─── Premium Stats Card (Horizontal Row) ───
                                  _buildPremiumStatsRow(solvedCount, university,
                                      stage, provider.isDarkTheme, isTablet),
                                  const SizedBox(height: 24),

                                  // ─── Settings Options List ───
                                  if (provider.isOwner) ...[
                                    _buildOptionTile(
                                      icon: Icons.admin_panel_settings_outlined,
                                      title: 'إدارة الاشتراكات والمستفيدين',
                                      isDark: provider.isDarkTheme,
                                      isTablet: isTablet,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const SubscriptionsManagementScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _buildOptionTile(
                                    icon: Icons.menu_book_outlined,
                                    title: 'تغيير المرحلة الدراسية',
                                    isDark: provider.isDarkTheme,
                                    isTablet: isTablet,
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _ProfilePalette.accent(provider.isDarkTheme).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        stage,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _ProfilePalette.accent(provider.isDarkTheme),
                                        ),
                                      ),
                                    ),
                                    onTap: () => _showChangeStageSheet(
                                      context, provider, stage,
                                      provider.isDarkTheme, isTablet,
                                    ),
                                  ),
                                  _buildOptionTile(
                                    icon: Icons.dark_mode_outlined,
                                    title: 'Dark Mode',
                                    isDark: provider.isDarkTheme,
                                    isTablet: isTablet,
                                    trailing: Switch(
                                      value: provider.isDarkTheme,
                                      onChanged: (val) => provider.toggleTheme(),
                                      activeColor: _ProfilePalette.accent(
                                          provider.isDarkTheme),
                                    ),
                                  ),
                                  _buildOptionTile(
                                    icon: Icons.help_outline_rounded,
                                    title: 'Help Center',
                                    isDark: provider.isDarkTheme,
                                    isTablet: isTablet,
                                    onTap: () async {
                                      final Uri url =
                                          Uri.parse('https://t.me/Subscribemoh');
                                      try {
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url,
                                              mode: LaunchMode.externalApplication);
                                        } else {
                                          await launchUrl(url);
                                        }
                                      } catch (e) {
                                        print('Could not launch Telegram URL: $e');
                                      }
                                    },
                                  ),
                                  if (Theme.of(context).platform != TargetPlatform.iOS)
                                     _buildOptionTile(
                                       icon: Icons.system_update_rounded,
                                       title: 'التحقق من التحديثات',
                                       isDark: provider.isDarkTheme,
                                       isTablet: isTablet,
                                       trailing: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                         decoration: BoxDecoration(
                                           color: const Color(0xFF6B4EFF).withValues(alpha: 0.12),
                                           borderRadius: BorderRadius.circular(8),
                                         ),
                                         child: Text(
                                           'v${AppUpdateService().currentVersionName}',
                                           style: const TextStyle(
                                             fontFamily: 'Cairo',
                                             fontSize: 11,
                                             fontWeight: FontWeight.bold,
                                             color: Color(0xFF6B4EFF),
                                           ),
                                         ),
                                       ),
                                       onTap: () => AppUpdateService().checkForUpdates(
                                         context,
                                         isManualCheck: true,
                                       ),
                                     ),
                                  const SizedBox(height: 24),

                                  // Log Out Button
                                  _buildLogoutButton(provider, context, isTablet),
                                  const SizedBox(height: 12),

                                  // Delete Account Button
                                  _buildDeleteAccountButton(provider, context, isTablet),
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Circular initials avatar badge overlapping the curved edge
                      Positioned(
                        top: 0, // Center on the curved boundary
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: isTablet ? 120 : 80,
                            height: isTablet ? 120 : 80,
                            decoration: BoxDecoration(
                              color: provider.isDarkTheme
                                  ? _ProfilePalette.darkTile2
                                  : const Color(0xFF1D1B84),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: provider.isDarkTheme
                                    ? _ProfilePalette.darkBorder
                                    : Colors.white,
                                width: isTablet ? 4.5 : 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initials.toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isTablet ? 40 : 26,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPremiumStatsRow(
      int solvedCount, String university, String stage, bool isDark, bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 14, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [
                  _ProfilePalette.darkAccentSoft,
                  _ProfilePalette.darkAccentDeep
                ]
              : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isTablet ? 26 : 20),
        boxShadow: [
          BoxShadow(
            color: (isDark
                    ? _ProfilePalette.darkAccentDeep
                    : const Color(0xFF6B4EFF))
                .withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Stage
          Expanded(
            child: _buildPremiumStatColumn(
              icon: Icons.star_outline_rounded,
              label: 'Stage',
              value: stage,
              isTablet: isTablet,
            ),
          ),
          _buildVerticalDivider(isTablet),
          // University
          Expanded(
            child: _buildPremiumStatColumn(
              icon: Icons.school_outlined,
              label: 'University',
              value: university,
              isTablet: isTablet,
            ),
          ),
          _buildVerticalDivider(isTablet),
          // Solved count
          Expanded(
            child: _buildPremiumStatColumn(
              icon: Icons.playlist_add_check_rounded,
              label: 'Solved',
              value: '$solvedCount',
              isTablet: isTablet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(bool isTablet) {
    return Container(
      height: isTablet ? 54 : 36,
      width: 1,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildPremiumStatColumn({
    required IconData icon,
    required String label,
    required String value,
    required bool isTablet,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: isTablet ? 28 : 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: isTablet ? 13 : 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: isTablet ? 16 : 12,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cairo',
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required bool isDark,
    required bool isTablet,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: _ProfilePalette.tile(isDark),
        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: isTablet ? 8 : 2),
        leading: Container(
          padding: EdgeInsets.all(isTablet ? 12 : 8),
          decoration: BoxDecoration(
            color: _ProfilePalette.accent(isDark)
                .withValues(alpha: isDark ? 0.16 : 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _ProfilePalette.accent(isDark), size: isTablet ? 24 : 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: _ProfilePalette.text(isDark),
            fontSize: isTablet ? 18 : 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        trailing: trailing ??
            Icon(Icons.chevron_right_rounded,
                color: _ProfilePalette.muted(isDark), size: isTablet ? 26 : 20),
      ),
    );
  }

  Widget _buildLogoutButton(AppProvider provider, BuildContext context, bool isTablet) {
    final isDark = provider.isDarkTheme;
    return GestureDetector(
      onTap: () async {
        await provider.signOut();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 14),
        decoration: BoxDecoration(
          color: isDark ? _ProfilePalette.darkTile : Colors.white,
          borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
          border: Border.all(
              color: Colors.red.withValues(alpha: isDark ? 0.6 : 0.3)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Colors.red, size: isTablet ? 24 : 18),
            SizedBox(width: isTablet ? 12 : 8),
            Text(
              'Sign Out',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: isTablet ? 18 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteAccountButton(AppProvider provider, BuildContext context, bool isTablet) {
    final isDark = provider.isDarkTheme;
    return GestureDetector(
      onTap: () => _showDeleteAccountDialog(context, provider),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 14),
        decoration: BoxDecoration(
          color: isDark ? _ProfilePalette.darkTile : Colors.white,
          borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
          border: Border.all(
              color: Colors.red.withValues(alpha: isDark ? 0.6 : 0.3)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: isTablet ? 24 : 18),
            SizedBox(width: isTablet ? 12 : 8),
            Text(
              'حذف الحساب',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: isTablet ? 18 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, AppProvider provider) {
    final email = provider.currentUser?.email;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد البريد الإلكتروني للحساب الحالي', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isDeleting = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: !isDeleting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = provider.isDarkTheme;
            final surfaceColor = isDark ? AppColors.surface : Colors.white;
            final textColor = isDark ? AppColors.text : _ProfilePalette.lightText;
            final mutedColor = isDark ? AppColors.textMuted : _ProfilePalette.lightMuted;
            final fieldBgColor = isDark ? AppColors.surface2 : const Color(0xFFF1EEFB);

            return AlertDialog(
              backgroundColor: surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'حذف الحساب',
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'هل أنت متأكد من رغبتك في حذف حسابك نهائياً؟ سيؤدي هذا إلى مسح جميع البيانات والتقدم الخاص بك ولا يمكن التراجع عن هذا الإجراء.',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.9),
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      height: 1.5,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'يرجى إدخال كلمة المرور للتأكيد:',
                    style: TextStyle(
                      color: mutedColor,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    enabled: !isDeleting,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'Cairo',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: fieldBgColor,
                      hintText: 'كلمة المرور',
                      hintStyle: TextStyle(color: mutedColor, fontSize: 13, fontFamily: 'Cairo'),
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: mutedColor, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: mutedColor,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: isDeleting
                            ? null
                            : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: mutedColor.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            color: mutedColor,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isDeleting
                            ? null
                            : () async {
                                final password = passwordController.text.trim();
                                if (password.isEmpty) {
                                  setDialogState(() {
                                    errorMessage = 'يرجى إدخال كلمة المرور';
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isDeleting = true;
                                  errorMessage = null;
                                });

                                try {
                                  // Verify password by attempting to sign in
                                  await SupabaseService().signIn(email, password);
                                  
                                  // Call provider to delete account
                                  await provider.deleteAccount();
                                  
                                  if (context.mounted) {
                                    Navigator.pop(context); // Close dialog
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                                      (route) => false,
                                    );
                                    // Show success message
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تم حذف الحساب بنجاح', style: TextStyle(fontFamily: 'Cairo')),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    isDeleting = false;
                                    final errStr = e.toString();
                                    if (errStr.contains('Invalid login credentials')) {
                                      errorMessage = 'كلمة المرور غير صحيحة';
                                    } else {
                                      errorMessage = 'حدث خطأ: $errStr';
                                    }
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: isDeleting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'حذف نهائي',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).then((_) => passwordController.dispose());
  }

}
