import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/models/subject.dart';
import '../../../../core/models/question.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../practice/presentation/screens/question_viewer_screen.dart';
import '../../../subjects/presentation/screens/subject_topics_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class _HomePalette {
  static const Color lightBg = Color(0xFFF8F9FE);
  static const Color lightMuted = Color(0xFF9E9EBF);
  static const Color lightAccent = Color(0xFF6B4EFF);

  static const Color darkBg = Color(0xFF100F1F);
  static const Color darkSurface = Color(0xFF18162B);
  static const Color darkSurface2 = Color(0xFF211E38);
  static const Color darkSurface3 = Color(0xFF2C2848);
  static const Color darkBorder = Color(0xFF3B365C);
  static const Color darkAccent = Color(0xFF6C58E8);
  static const Color darkAccentDeep = Color(0xFF4930B6);
  static const Color darkAccentSoft = Color(0xFF6047D6);

  static Color bg(bool isDark) => isDark ? darkBg : lightBg;
  static Color surface(bool isDark) => isDark ? darkSurface : Colors.white;
  static Color surface2(bool isDark) => isDark ? darkSurface2 : Colors.white;
  static Color surface3(bool isDark) =>
      isDark ? darkSurface3 : const Color(0xFFE2E2E9);

  static Color accent(bool isDark) => isDark ? darkAccent : lightAccent;

  static Color muted(bool isDark) =>
      isDark ? const Color(0xFFB8B3D6) : lightMuted;
  static Color dim(bool isDark) =>
      isDark ? const Color(0xFF918BAC) : lightMuted;
  static Color shadow(bool isDark) => isDark
      ? darkAccentDeep.withValues(alpha: 0.10)
      : lightAccent.withValues(alpha: 0.04);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _HomePalette.bg(isDark),
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─── Pinned SliverAppBar with Overview Header ───
            SliverAppBar(
              pinned: true,
              expandedHeight:
                  kToolbarHeight + (isTablet ? 94.0 : 72.0),
              backgroundColor: isDark
                  ? _HomePalette.darkAccentDeep
                  : const Color(0xFF5B3EEF),
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              leading: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: isTablet ? 28 : 24,
                    ),
                  ),
                ),
              ),
              centerTitle: true,
              title: Image.asset(
                'assets/Picsart_26-07-13_19-40-06-144.png',
                height: isTablet ? 44 : 36,
                fit: BoxFit.contain,
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Center(
                    child: IconButton(
                      tooltip: isDark ? 'Light mode' : 'Dark mode',
                      icon: Icon(
                        isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        color: Colors.white,
                        size: isTablet ? 26 : 22,
                      ),
                      onPressed: provider.toggleTheme,
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [
                              _HomePalette.darkAccentSoft,
                              _HomePalette.darkAccentDeep
                            ]
                          : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 16 : 6,
                    MediaQuery.of(context).padding.top + kToolbarHeight - 6.0,
                    isTablet ? 16 : 6,
                    10,
                  ),
                  child: _buildHeaderOverview(
                    totalAnswered: provider.totalAnswered,
                    totalCorrect: provider.totalCorrect,
                    accuracy: '${provider.accuracy.round()}%',
                    isDark: isDark,
                    isTablet: isTablet,
                  ),
                ),
              ),
            ),

            // ─── Scrollable Content ───
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                    left: isTablet ? 24.0 : 20.0,
                    right: isTablet ? 24.0 : 20.0,
                    top: isTablet ? 16.0 : 10.0,
                    bottom: 90.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Your Subjects Title ───
                    _buildSectionHeader(
                      title: 'Your Subjects',
                      actionText: 'View All',
                      isDark: isDark,
                      isTablet: isTablet,
                      onActionTap: () {
                        provider.setCurrentTab(0);
                      },
                    ),
                    SizedBox(height: isTablet ? 12 : 8),

                    // ─── Your Subjects Grid ───
                    RepaintBoundary(
                        child: _buildYourSubjectsGrid(context, provider, isTablet)),
                    SizedBox(height: isTablet ? 18 : 12),

                    // ─── Continue Learning Title ───
                    _buildSectionHeader(
                      title: 'Continue Learning',
                      actionText: '',
                      isDark: isDark,
                      isTablet: isTablet,
                    ),
                    SizedBox(height: isTablet ? 12 : 8),

                    // ─── Continue Learning Items ───
                    RepaintBoundary(
                        child: _buildContinueLearningList(context, provider, isTablet)),
                    SizedBox(height: isTablet ? 18 : 12),

                    // ─── Study Plan Card ───
                    _buildStudyPlanCard(context, provider, isTablet),
                    SizedBox(height: isTablet ? 18 : 12),

                    // ─── Top Performers Title ───
                    _buildSectionHeader(
                      title: 'Top Performers',
                      actionText: '',
                      isDark: isDark,
                      isTablet: isTablet,
                    ),
                    SizedBox(height: isTablet ? 12 : 8),

                    // ─── Top Performers Leaderboard ───
                    RepaintBoundary(child: _buildTopPerformersList(isDark, isTablet)),
                    SizedBox(height: isTablet ? 18 : 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderOverview({
    required int totalAnswered,
    required int totalCorrect,
    required String accuracy,
    required bool isDark,
    bool isTablet = false,
  }) {
    final int incorrect = totalAnswered - totalCorrect;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: isTablet
            ? const EdgeInsets.fromLTRB(20, 12, 20, 14)
            : const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.42),
            width: 1.1,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: isTablet ? 30 : 21,
                  height: isTablet ? 30 : 21,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(isTablet ? 9 : 7),
                  ),
                  child: Icon(Icons.insights_rounded,
                      color: Colors.white, size: isTablet ? 18 : 13),
                ),
                SizedBox(width: isTablet ? 10 : 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTablet ? 14 : 10,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Text(
                      'overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTablet ? 14.5 : 10.5,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(width: isTablet ? 20 : 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: _buildOverviewMetrio(
                          value: totalAnswered.toString(),
                          label: 'Quizzes',
                          isDark: isDark,
                          isTablet: isTablet)),
                  _buildOverviewDivider(isTablet),
                  Expanded(
                      child: _buildOverviewMetrio(
                          value: totalCorrect.toString(),
                          label: 'Correct',
                          isDark: isDark,
                          isTablet: isTablet)),
                  _buildOverviewDivider(isTablet),
                  Expanded(
                      child: _buildOverviewMetrio(
                          value: incorrect.toString(),
                          label: 'Incorrect',
                          isDark: isDark,
                          isTablet: isTablet)),
                  _buildOverviewDivider(isTablet),
                  Expanded(
                      child: _buildOverviewMetrio(
                          value: accuracy,
                          label: 'Accuracy',
                          isDark: isDark,
                          isTablet: isTablet)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewMetrio({
    required String value,
    required String label,
    required bool isDark,
    bool isTablet = false,
  }) {
    final int? numberValue =
        int.tryParse(value.replaceAll('%', '').replaceAll(',', ''));
    final String suffix = value.trim().endsWith('%') ? '%' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (numberValue != null)
          _OdometerNumber(
            value: numberValue,
            suffix: suffix,
            fontSize: isTablet ? 22 : 15,
          )
        else
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTablet ? 22 : 15,
              fontWeight: FontWeight.w900,
              fontFamily: 'Inter',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: isTablet ? 12 : 8.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Cairo',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildOverviewDivider(bool isTablet) {
    return Container(
      width: 1,
      height: isTablet ? 34 : 24,
      margin: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 5),
      color: Colors.white.withValues(alpha: 0.28),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String actionText = '',
    required bool isDark,
    bool isTablet = false,
    VoidCallback? onActionTap,
  }) {
    final hasAction = actionText.isNotEmpty && onActionTap != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? AppColors.text : const Color(0xFF1E1E50),
            fontSize: isTablet ? 19 : 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cairo',
          ),
        ),
        if (hasAction)
          GestureDetector(
            onTap: onActionTap,
            child: Row(
              children: [
                Text(
                  actionText,
                  style: TextStyle(
                    color: _HomePalette.accent(isDark),
                    fontSize: isTablet ? 15 : 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: _HomePalette.accent(isDark), size: isTablet ? 18 : 16),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStudyPlanCard(BuildContext context, AppProvider provider, [bool isTablet = false]) {
    final plan = provider.studyPlan;
    final isDark = provider.isDarkTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isDark ? _HomePalette.darkAccentSoft : const Color(0xFF8B6EFF),
            isDark ? _HomePalette.darkAccentDeep : const Color(0xFF5B3EEF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
                (isDark ? _HomePalette.darkAccentDeep : const Color(0xFF5B3EEF))
                    .withValues(alpha: isDark ? 0.12 : 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16, vertical: isTablet ? 18 : 12),
      child: plan == null || plan['isActive'] != true
          ? _buildNoPlanState(context, provider, isTablet)
          : _buildActivePlanState(context, provider, plan, isTablet),
    );
  }

  Widget _buildNoPlanState(BuildContext context, AppProvider provider, [bool isTablet = false]) {
    final isDark = provider.isDarkTheme;

    return Row(
      children: [
        // Left Side: Text Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      color: Colors.white, size: isTablet ? 18 : 14),
                  const SizedBox(width: 4),
                  Text(
                    'Study Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isTablet ? 14 : 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'No Active Study Plan',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: isTablet ? 18 : 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Create a daily target to track your progress.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: isTablet ? 12.5 : 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Right Side: Action Button to Create
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, color: Colors.white, size: isTablet ? 46 : 36),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showCreatePlanDialog(context, provider),
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 14 : 10, vertical: isTablet ? 8 : 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create',
                      style: TextStyle(
                        color: _HomePalette.accent(isDark),
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 13 : 11,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.add,
                        color: _HomePalette.accent(isDark), size: isTablet ? 14 : 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivePlanState(
      BuildContext context, AppProvider provider, Map<String, dynamic> plan, [bool isTablet = false]) {
    final isDark = provider.isDarkTheme;
    final comp = provider.getCompletedTodayQuestions();
    final dailyTarget = plan['questionsPerDay'] ?? 10;
    final double progress = (comp / dailyTarget).clamp(0.0, 1.0);
    final int remDays = (plan['totalDays'] - plan['currentDay'] + 1)
        .clamp(0, plan['totalDays']);

    final displayNameMapping = {
      'Paediatric': 'Pediatrics',
      'Surgery': 'Surgery',
      'Medicine': 'Internal Medicine',
      'OBGYN': 'Obstetrics & Gynecology',
      'Past Papers': 'Past Papers',
    };
    final String subjectDisplayName =
        displayNameMapping[plan['subjectName']] ?? plan['subjectName'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          color: Colors.white, size: isTablet ? 18 : 14),
                      const SizedBox(width: 4),
                      Text(
                        'Study Plan • $subjectDisplayName',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isTablet ? 14 : 11.5,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 8 : 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Day ${plan['currentDay']} of ${plan['totalDays']}',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 10 : 8,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$comp of $dailyTarget Completed Today',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: isTablet ? 18 : 15,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Remaining: ${plan['remainingQuestions']} questions',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: isTablet ? 12.5 : 10,
                            fontFamily: 'Cairo'),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Days left: $remDays',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: isTablet ? 12.5 : 10,
                            fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Delete button at the top-right
            GestureDetector(
              onTap: () => provider.deleteStudyPlan(),
              child: Container(
                padding: EdgeInsets.all(isTablet ? 8 : 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: isTablet ? 20 : 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Left: Progress Indicator + Percentage
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: isTablet ? 8 : 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTablet ? 12 : 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Right: Start Button
            GestureDetector(
              onTap: () {
                provider.selectSubject(plan['subjectName']);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        SubjectTopicsScreen(subjectName: plan['subjectName']),
                  ),
                );
              },
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 10 : 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20), // Pill-shaped button
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Start',
                      style: TextStyle(
                        color: _HomePalette.accent(isDark),
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 13.5 : 11.5,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        color: _HomePalette.accent(isDark), size: isTablet ? 16 : 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showCreatePlanDialog(BuildContext context, AppProvider provider) {
    String? selectedSub =
        provider.subjects.isNotEmpty ? provider.subjects.first.name : null;
    int selectedDays = 5;
    final isDark = provider.isDarkTheme;

    final displayNameMapping = {
      'Paediatric': 'Pediatrics',
      'Surgery': 'Surgery',
      'Medicine': 'Internal Medicine',
      'OBGYN': 'Obstetrics & Gynecology',
      'Past Papers': 'Past Papers',
    };

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Create Study Plan',
                style: TextStyle(
                  color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Subject:',
                    style: TextStyle(
                      color: _HomePalette.muted(isDark),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _HomePalette.darkSurface2
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? _HomePalette.darkBorder
                              : const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedSub,
                        dropdownColor:
                            isDark ? _HomePalette.darkSurface2 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        isExpanded: true,
                        items: provider.subjects.map((sub) {
                          final String label =
                              displayNameMapping[sub.name] ?? sub.name;
                          return DropdownMenuItem<String>(
                            value: sub.name,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedSub = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Duration (Days):',
                    style: TextStyle(
                      color: _HomePalette.muted(isDark),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _HomePalette.darkSurface2
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? _HomePalette.darkBorder
                              : const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedDays,
                        dropdownColor:
                            isDark ? _HomePalette.darkSurface2 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        isExpanded: true,
                        items: [5, 10, 15, 30, 60].map((days) {
                          return DropdownMenuItem<int>(
                            value: days,
                            child: Text(
                              '$days Days',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => selectedDays = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Canoel',
                    style: TextStyle(
                      color: _HomePalette.muted(isDark),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _HomePalette.accent(isDark),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                  ),
                  onPressed: () async {
                    if (selectedSub != null) {
                      Navigator.pop(context);
                      await provider.createStudyPlan(
                          selectedSub!, selectedDays);
                    }
                  },
                  child: const Text(
                    'Create Plan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildContinueLearningList(
      BuildContext context, AppProvider provider, [bool isTablet = false]) {
    const Map<String, String> displayNameMapping = {
      'internal medicine': 'Internal Medicine',
      'Paediatric': 'Pediatrics',
      'Surgery': 'Surgery',
      'Obstetric': 'Obstetrics',
      'Gynecology': 'Gynecology',
    };

    final items = provider.recentTopics.take(2).toList(growable: false);
    final isDark = provider.isDarkTheme;
    final brandColor = _HomePalette.accent(isDark);

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isTablet ? 24 : 16, horizontal: isTablet ? 18 : 14),
        decoration: BoxDecoration(
          color: _HomePalette.surface(isDark),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _HomePalette.shadow(isDark),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: isDark ? 0.18 : 0.08),
                shape: BoxShape.circle,
              ),
              child: FaIcon(FontAwesomeIcons.bookOpen,
                  color: brandColor, size: isTablet ? 30 : 24),
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مواضيع قيد المتابعة حالياً',
              style: TextStyle(
                color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                fontWeight: FontWeight.bold,
                fontSize: isTablet ? 16.5 : 14,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'ابدأ بحل الأسئلة لتظهر المواضيع هنا وتتابع تقدمك!',
              style: TextStyle(
                color: _HomePalette.dim(isDark),
                fontSize: isTablet ? 13 : 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: items.map((item) {
        final topicTitle = item['topic']?.toString() ?? 'غير محدد';
        final subjectKey = item['subject']?.toString() ?? '';
        final subDisplayName = displayNameMapping[subjectKey] ?? subjectKey;
        final total = item['total'] as int? ?? 0;
        final solved = item['solved'] as int? ?? 0;
        final progress = total > 0 ? solved / total : 0.0;
        final pot = '${(progress * 100).round()}%';

        return GestureDetector(
          onTap: () =>
              _openRecentTopic(context, provider, subjectKey, topicTitle),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _HomePalette.surface(isDark),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? _HomePalette.darkBorder
                    : brandColor.withValues(alpha: 0.16),
                width: 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  Container(width: 5, height: isTablet ? 90 : 70, color: brandColor),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 16 : 12, vertical: isTablet ? 13 : 9),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(isTablet ? 11 : 8),
                            decoration: BoxDecoration(
                              color: brandColor.withValues(
                                  alpha: isDark ? 0.2 : 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: FaIcon(FontAwesomeIcons.bookOpen,
                                color: brandColor, size: isTablet ? 20 : 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  topicTitle,
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.text
                                        : const Color(0xFF1E1E50),
                                    fontWeight: FontWeight.bold,
                                    fontSize: isTablet ? 15.0 : 12.5,
                                    fontFamily: 'Cairo',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  subDisplayName,
                                  style: TextStyle(
                                    color: _HomePalette.dim(isDark),
                                    fontSize: isTablet ? 13 : 11,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: isTablet ? 6 : 4,
                                          backgroundColor:
                                              _HomePalette.surface3(isDark),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  brandColor),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      pot,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.text
                                            : const Color(0xFF1E1E50),
                                        fontSize: isTablet ? 12 : 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: isTablet ? 44 : 36,
                            height: isTablet ? 44 : 36,
                            decoration: BoxDecoration(
                              color: brandColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.play_arrow_rounded,
                                color: brandColor, size: isTablet ? 22 : 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openRecentTopic(BuildContext context, AppProvider provider,
      String subjectKey, String topicTitle) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: LogoSpinner()),
    );
    try {
      await provider.selectSubject(subjectKey);
      if (context.mounted) Navigator.pop(context);

      final targetQs =
          provider.questions.where((q) => q.topic == topicTitle).toList();
      if (targetQs.isEmpty) {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubjectTopicsScreen(
              subjectName: subjectKey,
              initialTopicName: topicTitle,
            ),
          ),
        );
        return;
      }

      List<Question> sessionQs;
      int targetIndex = 0;
      if (provider.viewMode == 'ohapter') {
        sessionQs = targetQs;
        final unsolvedIdx = sessionQs.indexWhere((q) => !q.isSolved);
        targetIndex = unsolvedIdx != -1 ? unsolvedIdx : 0;
      } else {
        Question? lastSolved;
        for (final q in targetQs) {
          if (q.isSolved) lastSolved = q;
        }
        final subTopicName =
            lastSolved?.subTopic ?? targetQs.first.subTopic ?? 'غير محدد';
        sessionQs = provider.questions
            .where((q) => q.subTopic == subTopicName)
            .toList();
        final unsolvedIdx = sessionQs.indexWhere((q) => !q.isSolved);
        targetIndex = unsolvedIdx != -1 ? unsolvedIdx : 0;
      }

      provider.startPracticeSession(sessionQs);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) =>
                QuestionViewerScreen(initialIndex: targetIndex)),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading subject: $e')));
      }
    }
  }

  Widget _buildYourSubjectsGrid(BuildContext context, AppProvider provider, [bool isTablet = false]) {
    final Map<String, FaIconData> iconMapping = {
      'internal medicine': FontAwesomeIcons.stethoscope,
      'Paediatric': FontAwesomeIcons.child,
      'Surgery': FontAwesomeIcons.userDoctor,
      'Obstetric': FontAwesomeIcons.baby,
      'Gynecology': FontAwesomeIcons.venus,
    };

    final Map<String, String> displayNameMapping = {
      'internal medicine': 'Internal Medicine',
      'Paediatric': 'Paediatric',
      'Surgery': 'Surgery',
      'Obstetric': 'Obstetric',
      'Gynecology': 'Gynecology',
    };

    Subject findSubject(String name) {
      return provider.subjects.firstWhere(
        (s) => s.name == name,
        orElse: () => Subject(
          id: 0,
          name: name,
          description: '',
          totalQuestions: 0,
        ),
      );
    }

    final Subject medicineSub = findSubject('internal medicine');
    final Subject surgerySub = findSubject('Surgery');
    final Subject paediatrioSub = findSubject('Paediatric');
    final Subject obstetrioSub = findSubject('Obstetric');
    final Subject gyneoologySub = findSubject('Gynecology');

    final isDark = provider.isDarkTheme;
    final Map<String, int> answeredBySubject = {};
    for (final answer in provider.userAnswers.values) {
      final subjectName = answer['subject']?.toString();
      if (subjectName == null || subjectName.isEmpty) continue;
      answeredBySubject[subjectName] =
          (answeredBySubject[subjectName] ?? 0) + 1;
    }

    final double cardHeight = isTablet ? 122.0 : 86.0;

    Widget buildCard(Subject? subject, {double? height}) {
      final effectiveHeight = height ?? cardHeight;
      if (subject == null) return const SizedBox.shrink();
      final FaIconData icon =
          iconMapping[subject.name] ?? FontAwesomeIcons.bookMedical;
      final String displayName =
          displayNameMapping[subject.name] ?? subject.name;
      final int total = subject.totalQuestions;
      final int answered = answeredBySubject[subject.name] ?? 0;
      final int pot = total > 0 ? ((answered / total) * 100).round() : 0;

      final Color color = _HomePalette.accent(isDark);

      final isLocked = !provider.isSubjectUnlocked(subject.id);

      return GestureDetector(
        onTap: () {
          if (isLocked) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text(
                  'المادة مغلقة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                content: const Text(
                  'هذه المادة تتطلب اشتراكاً نشطاً للوصول إليها. يرجى التواصل مع الإدارة لتفعيل الاشتراك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                actionsAlignment: MainAxisAlignment.spaceEvenly,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'إغلاق',
                      style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final Uri url = Uri.parse('https://t.me/Subscribemoh');
                      try {
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          await launchUrl(url);
                        }
                      } catch (e) {
                        print('Could not launch Telegram: $e');
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.telegram, size: 16, color: Colors.white),
                    label: const Text(
                      'تفعيل الاشتراك',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF229ED9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            );
            return;
          }
          provider.selectSubject(subject.name);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  SubjectTopicsScreen(subjectName: subject.name),
            ),
          );
        },
        child: Stack(
          children: [
            Opacity(
              opacity: isLocked ? 0.6 : 1.0,
              child: Container(
                height: effectiveHeight,
                padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16 : 11, vertical: isTablet ? 14 : 9),
                decoration: BoxDecoration(
                  color: _HomePalette.surface(isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? _HomePalette.darkBorder
                        : color.withValues(alpha: 0.12),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.16)
                          : color.withValues(alpha: 0.02),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isTablet ? 10 : 7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: isDark ? 0.2 : 0.08),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: FaIcon(icon, color: color, size: isTablet ? 22 : 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.text
                                      : const Color(0xFF1E1E50),
                                  fontWeight: FontWeight.w900,
                                  fontSize: isTablet ? 15.5 : 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 0),
                              Text(
                                '${subject.totalQuestions.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Questions',
                                style: TextStyle(
                                  color: color,
                                  fontSize: isTablet ? 12 : 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pot / 100,
                              minHeight: isTablet ? 6.5 : 4,
                              backgroundColor: _HomePalette.surface3(isDark),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pot%',
                          style: TextStyle(
                            color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                            fontSize: isTablet ? 12 : 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isLocked)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Row 1: Internal Medicine & Surgery
        Row(
          children: [
            Expanded(child: buildCard(medicineSub)),
            const SizedBox(width: 12),
            Expanded(child: buildCard(surgerySub)),
          ],
        ),
        SizedBox(height: isTablet ? 12 : 8),
        // Row 2: Pediatrics & Gynecology
        Row(
          children: [
            Expanded(child: buildCard(paediatrioSub)),
            const SizedBox(width: 12),
            Expanded(child: buildCard(gyneoologySub)),
          ],
        ),
        SizedBox(height: isTablet ? 12 : 8),
        // Row 3: Obstetrics (Full-width)
        buildCard(obstetrioSub),
      ],
    );
  }

  Widget _buildTopPerformersList(bool isDark, [bool isTablet = false]) {
    final List<Map<String, String>> mockLeaders = [
      {'name': 'Ahmed', 'points': '1,250 pts', 'medal': '🥇'},
      {'name': 'Mohammed', 'points': '1,120 pts', 'medal': '🥈'},
      {'name': 'Ali', 'points': '980 pts', 'medal': '🥉'},
    ];

    return Row(
      children: mockLeaders.map((leader) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: EdgeInsets.all(isTablet ? 18 : 12),
            decoration: BoxDecoration(
              color: _HomePalette.surface2(isDark),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _HomePalette.shadow(isDark),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  leader['medal']!,
                  style: TextStyle(fontSize: isTablet ? 24 : 18),
                ),
                const SizedBox(height: 6),
                CircleAvatar(
                  radius: isTablet ? 24 : 18,
                  backgroundColor: isDark
                      ? _HomePalette.darkSurface3
                      : const Color(0xFFF1EEFF),
                  child: Icon(Icons.person,
                      color: _HomePalette.accent(isDark), size: isTablet ? 22 : 18),
                ),
                const SizedBox(height: 8),
                Text(
                  leader['name']!,
                  style: TextStyle(
                    color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                    fontSize: isTablet ? 14.0 : 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  leader['points']!,
                  style: TextStyle(
                    color: _HomePalette.accent(isDark),
                    fontSize: isTablet ? 12 : 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _OdometerNumber extends StatelessWidget {
  const _OdometerNumber({
    required this.value,
    this.suffix = '',
    this.fontSize = 15,
  });

  final int value;
  final String suffix;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final digits = value.toString().split('');

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < digits.length; i++)
          _OdometerDigit(
            digit: int.parse(digits[i]),
            delay: Duration(milliseconds: i * 70),
            fontSize: fontSize,
          ),
        if (suffix.isNotEmpty)
          Text(
            suffix,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontFamily: 'Inter',
            ),
          ),
      ],
    );
  }
}

class _OdometerDigit extends StatefulWidget {
  const _OdometerDigit({
    required this.digit,
    required this.delay,
    this.fontSize = 15,
  });

  final int digit;
  final Duration delay;
  final double fontSize;

  @override
  State<_OdometerDigit> createState() => _OdometerDigitState();
}

class _OdometerDigitState extends State<_OdometerDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late int _startDigit;
  late int _targetDigit;

  @override
  void initState() {
    super.initState();
    _startDigit = 0;
    _targetDigit = widget.digit;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant _OdometerDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.digit == widget.digit) return;
    _startDigit = oldWidget.digit;
    _targetDigit = widget.digit;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.fontSize;
    final digitHeight = fontSize * 1.2;
    final digitWidth = fontSize * 0.63;

    return SizedBox(
      width: digitWidth,
      height: digitHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: digitHeight * 20,
          maxHeight: digitHeight * 20,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final spring = SpringSimulation(
                const SpringDescription(mass: 1, stiffness: 18, damping: 5),
                0,
                1,
                0,
              );
              final eased = (_animation.value * 0.86) +
                  (spring.x(_animation.value * 2).clamp(0.0, 1.0) * 0.14);
              final distance = ((_targetDigit - _startDigit) % 10) + 10;
              final offset = (eased * distance) % 10;

              return Transform.translate(
                offset: Offset(0, -offset * digitHeight),
                child: Column(
                  children: List.generate(20, (index) {
                    final digit = (_startDigit + index) % 10;
                    return SizedBox(
                      height: digitHeight,
                      child: Text(
                        '$digit',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Inter',
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
