import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/models/subject.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../subjects/presentation/screens/subject_topics_screen.dart';
import 'clinical_subject_screen.dart';
import '../../../../core/theme/colors.dart';

class ClinicalCategory {
  final String title;
  final String dbName;
  final List<String> dbNames;
  final bool isCombined;
  final FaIconData icon;
  final Subject? subject;

  const ClinicalCategory({
    required this.title,
    required this.dbName,
    required this.icon,
    this.dbNames = const [],
    this.isCombined = false,
    this.subject,
  });
}

class ClinicalScreen extends StatelessWidget {
  const ClinicalScreen({super.key});
  FaIconData _getIconDataForSubject(String description) {
    final desc = description.toLowerCase().trim();
    if (desc.startsWith('heartbeat') || desc.contains('heart'))
      return FontAwesomeIcons.heartPulse;
    if (desc.startsWith('brain') || desc.contains('neuro'))
      return FontAwesomeIcons.brain;
    if (desc.startsWith('eye') || desc.contains('ophtal'))
      return FontAwesomeIcons.eye;
    if (desc.startsWith('bone') || desc.contains('ortho'))
      return FontAwesomeIcons.bone;
    if (desc.startsWith('lungs') || desc.contains('pulmo'))
      return FontAwesomeIcons.lungs;
    if (desc.startsWith('baby') ||
        desc.contains('obstetric') ||
        desc.contains('gyne')) return FontAwesomeIcons.baby;
    if (desc.startsWith('child') || desc.contains('pedi'))
      return FontAwesomeIcons.child;
    if (desc.startsWith('usermd') || desc.contains('surgery'))
      return FontAwesomeIcons.userDoctor;
    if (desc.startsWith('siren')) return FontAwesomeIcons.truckMedical;
    return FontAwesomeIcons.stethoscope;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    final List<ClinicalCategory> categories = [];
    final user = provider.currentUser;
    final userStage = (provider.userDetails?['stage'] ??
        user?.userMetadata?['stage']) as String?;
    final userUniv = (provider.userDetails?['university'] ??
        user?.userMetadata?['university']) as String?;

    for (var subject in provider.clinicalSubjects) {
      if (!provider.isAdminOrOwner) {
        // Stage Filter
        if (subject.stage != null && subject.stage!.trim().isNotEmpty) {
          if (userStage == null || userStage.trim().isEmpty) {
            continue;
          }
          final subStage = subject.stage!.trim().toLowerCase();
          final uStage = userStage.trim().toLowerCase();
          if (subStage != uStage &&
              !subStage.contains(uStage) &&
              !uStage.contains(subStage)) {
            continue;
          }
        }
        // University Filter
        if (subject.university != null &&
            subject.university!.trim().isNotEmpty) {
          if (userUniv == null || userUniv.trim().isEmpty) {
            continue;
          }
          final subUniv = subject.university!.trim().toLowerCase();
          final uUniv = userUniv.trim().toLowerCase();
          if (subUniv != uUniv &&
              !subUniv.contains(uUniv) &&
              !uUniv.contains(subUniv)) {
            continue;
          }
        }
      }

      final nameLower = subject.name.toLowerCase().trim();
      final isCombined =
          nameLower.contains('obstetric') || nameLower.contains('gyne');
      final dbNames = isCombined ? ['Obstetric', 'Gynecology'] : [subject.name];

      String iconName = '';
      if (subject.description.contains('-')) {
        iconName = subject.description.split('-').first.trim().toLowerCase();
      } else {
        iconName = subject.description.toLowerCase().trim();
      }

      categories.add(ClinicalCategory(
        title: subject.name,
        dbName: subject.name,
        dbNames: dbNames,
        isCombined: isCombined,
        icon:
            _getIconDataForSubject(iconName.isEmpty ? subject.name : iconName),
        subject: subject,
      ));
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor:
            provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8F9FE),
        floatingActionButton: !provider.isAdminOrOwner
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 72.0),
                child: FloatingActionButton(
                  onPressed: () => showAddSubjectDialog(context, provider),
                  backgroundColor: provider.isDarkTheme
                      ? AppColors.indigo
                      : const Color(0xFF6B4EFF),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
        body: provider.isLoading
            ? const Center(child: LogoSpinner())
            : Column(
                children: [
                  // Curved Gradient Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      top: statusBarHeight + 8,
                      bottom: 14,
                      left: 16,
                      right: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: provider.isDarkTheme
                            ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                            : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () {
                                // Reset active tab to Home (Index 2)
                                provider.setCurrentTab(2);
                              },
                            ),
                            const Text(
                              'Clinical',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(
                                width:
                                    48), // Equal balancing width for back button
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Grid content
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: GridView.builder(
                          padding: const EdgeInsets.only(
                            left: 20.0,
                            right: 20.0,
                            top: 24.0,
                            bottom: 100.0, // Clear the floating navigation bar
                          ),
                          physics: const BouncingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.92,
                          ),
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            return _buildCategoryCard(
                                context, category, provider);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    ClinicalCategory category,
    AppProvider provider,
  ) {
    final List<String> subjectsToQuery =
        category.isCombined ? category.dbNames : [category.dbName];
    final double progressFraction =
        provider.getClinicalSubjectProgress(subjectsToQuery);
    final int pct = (progressFraction * 100).round();
    const Color brandColor = Color(0xFF6B4EFF);

    final isLocked = category.subject != null && !provider.isClinicalSubjectUnlocked(category.subject!.id);

    return Stack(
      children: [
        Opacity(
          opacity: isLocked ? 0.6 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: provider.isDarkTheme ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: provider.isDarkTheme
                    ? AppColors.border
                    : brandColor.withValues(alpha: 0.06),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: provider.isDarkTheme
                      ? Colors.black.withValues(alpha: 0.2)
                      : brandColor.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () =>
                    _handleCategoryNavigation(context, category, provider),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Large Centered Icon Container on top
                      Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: brandColor.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: FaIcon(
                            category.icon,
                            color: brandColor,
                            size: 24, // Large Icon
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Title/Name
                      Text(
                        category.title,
                        style: TextStyle(
                          color: provider.isDarkTheme
                              ? AppColors.text
                              : const Color(0xFF1E1E50),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 12),

                      // Bottom part: Progress Bar on left/center, Arrow on right
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct / 100.0,
                                    backgroundColor: provider.isDarkTheme
                                        ? AppColors.surface2
                                        : const Color(0xFFF1F5F9),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            brandColor),
                                    minHeight: 5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$pct%',
                                  style: const TextStyle(
                                    color: brandColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Arrow Icon at the bottom right corner
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: provider.isDarkTheme
                                  ? AppColors.surface2
                                  : const Color(0xFFF8FAFC),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: provider.isDarkTheme
                                    ? AppColors.border
                                    : brandColor.withValues(alpha: 0.1),
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: brandColor,
                              size: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isLocked)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        if (provider.isAdminOrOwner && category.subject != null)
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    showEditSubjectDialog(context, category.subject!, provider),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: provider.isDarkTheme
                        ? AppColors.surface2
                        : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: brandColor,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _handleCategoryNavigation(
    BuildContext context,
    ClinicalCategory category,
    AppProvider provider,
  ) {
    final isLocked = category.subject != null && !provider.isClinicalSubjectUnlocked(category.subject!.id);
    if (isLocked) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'المادة العملية مغلقة',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'هذه المادة العملية تتطلب اشتراكاً نشطاً للوصول إليها. يرجى التواصل مع الإدارة لتفعيل الاشتراك.',
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClinicalSubjectScreen(subject: category.title),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildBottomSheetOption(
    BuildContext context, {
    required String title,
    required String subjectName,
    required FaIconData icon,
    required AppProvider provider,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close bottom sheet
        provider.selectSubject(subjectName);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubjectTopicsScreen(subjectName: subjectName),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: provider.isDarkTheme ? AppColors.surface2 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: provider.isDarkTheme
                ? AppColors.border
                : const Color(0xFF6B4EFF).withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6B4EFF).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: FaIcon(icon, color: const Color(0xFF6B4EFF), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: provider.isDarkTheme
                      ? AppColors.text
                      : const Color(0xFF1E1E50),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6B4EFF),
            ),
          ],
        ),
      ),
    );
  }
}

void showAddSubjectDialog(BuildContext context, AppProvider provider) {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  String selectedIcon = 'stethoscope';
  String? selectedStage;
  String? selectedUniversity;

  final List<Map<String, dynamic>> iconOptions = [
    {'name': 'stethoscope', 'icon': FontAwesomeIcons.stethoscope},
    {'name': 'heartbeat', 'icon': FontAwesomeIcons.heartPulse},
    {'name': 'brain', 'icon': FontAwesomeIcons.brain},
    {'name': 'eye', 'icon': FontAwesomeIcons.eye},
    {'name': 'lungs', 'icon': FontAwesomeIcons.lungs},
    {'name': 'bone', 'icon': FontAwesomeIcons.bone},
    {'name': 'child', 'icon': FontAwesomeIcons.child},
    {'name': 'baby', 'icon': FontAwesomeIcons.baby},
    {'name': 'usermd', 'icon': FontAwesomeIcons.userDoctor},
    {'name': 'siren', 'icon': FontAwesomeIcons.truckMedical},
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add New Subject',
                  style: TextStyle(
                    color: provider.isDarkTheme
                        ? AppColors.text
                        : const Color(0xFF1E1E50),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Name/Title
                Text(
                  'Subject Name',
                  style: TextStyle(
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  decoration: _buildInputDecoration(
                      'e.g., Cardiology, Ophthalmology',
                      isDark: provider.isDarkTheme),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Description
                Text(
                  'Description',
                  style: TextStyle(
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: descriptionController,
                  decoration: _buildInputDecoration('Enter a short description',
                      isDark: provider.isDarkTheme),
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          provider.isDarkTheme ? AppColors.text : Colors.black),
                ),
                const SizedBox(height: 16),

                // Stage Selection Dropdown
                Text(
                  'Stage / Year',
                  style: TextStyle(
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedStage,
                  dropdownColor:
                      provider.isDarkTheme ? AppColors.surface2 : Colors.white,
                  hint: const Text('Select a stage (Optional)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  decoration:
                      _buildInputDecoration('', isDark: provider.isDarkTheme),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF6B4EFF)),
                  items: [
                    DropdownMenuItem(
                        value: 'المرحلة الأولى',
                        child: Text('المرحلة الأولى',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'المرحلة الثانية',
                        child: Text('المرحلة الثانية',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'المرحلة الثالثة',
                        child: Text('المرحلة الثالثة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'المرحلة الرابعة',
                        child: Text('المرحلة الرابعة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'المرحلة الخامسة',
                        child: Text('المرحلة الخامسة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'المرحلة السادسة',
                        child: Text('المرحلة السادسة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'طالب امتياز',
                        child: Text('طالب امتياز',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'طبيب مقيم',
                        child: Text('طبيب مقيم',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'طبيب أخصائي',
                        child: Text('طبيب أخصائي',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'أستاذ مساعد',
                        child: Text('أستاذ مساعد',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                  ],
                  onChanged: (val) {
                    setModalState(() {
                      selectedStage = val;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // University Selection Dropdown
                Text(
                  'University',
                  style: TextStyle(
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedUniversity,
                  dropdownColor:
                      provider.isDarkTheme ? AppColors.surface2 : Colors.white,
                  hint: const Text('Select a university (Optional)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  decoration:
                      _buildInputDecoration('', isDark: provider.isDarkTheme),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF6B4EFF)),
                  items: [
                    DropdownMenuItem(
                        value: 'كلية طب بغداد',
                        child: Text('كلية طب بغداد',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب المستنصرية',
                        child: Text('كلية طب المستنصرية',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب الكوفة',
                        child: Text('كلية طب الكوفة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب البصرة',
                        child: Text('كلية طب البصرة',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب بابل',
                        child: Text('كلية طب بابل',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب كربلاء',
                        child: Text('كلية طب كربلاء',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب القادسية',
                        child: Text('كلية طب القادسية',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب ميسان',
                        child: Text('كلية طب ميسان',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب واسط',
                        child: Text('كلية طب واسط',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب جابر بن حيان',
                        child: Text('كلية طب جابر بن حيان',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب صلاح الدين',
                        child: Text('كلية طب صلاح الدين',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب الموصل',
                        child: Text('كلية طب الموصل',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب المثنى',
                        child: Text('كلية طب المثنى',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب نينوى',
                        child: Text('كلية طب نينوى',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب كركوك',
                        child: Text('كلية طب كركوك',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب الأنبار',
                        child: Text('كلية طب الأنبار',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب الكندي',
                        child: Text('كلية طب الكندي',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب العميد',
                        child: Text('كلية طب العميد',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب حمورابي',
                        child: Text('كلية طب حمورابي',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب ذي قار',
                        child: Text('كلية طب ذي قار',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب ديالى',
                        child: Text('كلية طب ديالى',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب ابن سينا',
                        child: Text('كلية طب ابن سينا',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب النهرين',
                        child: Text('كلية طب النهرين',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب تكريت',
                        child: Text('كلية طب تكريت',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                    DropdownMenuItem(
                        value: 'كلية طب الجامعة العراقية',
                        child: Text('كلية طب الجامعة العراقية',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color: provider.isDarkTheme
                                    ? AppColors.text
                                    : const Color(0xFF1E1E50)))),
                  ],
                  onChanged: (val) {
                    setModalState(() {
                      selectedUniversity = val;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Icon Selector
                Text(
                  'Subject Icon',
                  style: TextStyle(
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: iconOptions.length,
                    itemBuilder: (context, index) {
                      final item = iconOptions[index];
                      final isSelected = selectedIcon == item['name'];
                      return GestureDetector(
                        onTap: () => setModalState(
                            () => selectedIcon = item['name'] as String),
                        child: Container(
                          width: 50,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (provider.isDarkTheme
                                    ? AppColors.surface2
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6B4EFF)
                                  : (provider.isDarkTheme
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: FaIcon(
                            item['icon'] as FaIconData,
                            color: isSelected
                                ? const Color(0xFF6B4EFF)
                                : const Color(0xFF9E9EBF),
                            size: 18,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final description = descriptionController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a subject name')),
                      );
                      return;
                    }

                    provider.addClinicalSubject(
                      name,
                      description,
                      selectedIcon,
                      stage: selectedStage,
                      university: selectedUniversity,
                    );

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added $name successfully!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: provider.isDarkTheme
                        ? AppColors.indigo
                        : const Color(0xFF6B4EFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Subject',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
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

InputDecoration _buildInputDecoration(String hintText, {bool isDark = false}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    filled: true,
    fillColor: isDark ? AppColors.surface2 : const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
          width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF6B4EFF), width: 2),
    ),
  );
}

void showEditSubjectDialog(
    BuildContext context, Subject subject, AppProvider provider) {
  final nameController = TextEditingController(text: subject.name);
  String? selectedStage = subject.stage;
  String? selectedUniversity = subject.university;

  // Extract icon and description
  String currentIcon = 'stethoscope';
  String currentDesc = subject.description;
  if (subject.description.contains('-')) {
    final parts = subject.description.split('-');
    currentIcon = parts.first.trim();
    currentDesc = parts.sublist(1).join('-').trim();
  }

  final descriptionController = TextEditingController(text: currentDesc);
  String selectedIcon = currentIcon;

  final List<Map<String, dynamic>> iconOptions = [
    {'name': 'stethoscope', 'icon': FontAwesomeIcons.stethoscope},
    {'name': 'heartbeat', 'icon': FontAwesomeIcons.heartPulse},
    {'name': 'brain', 'icon': FontAwesomeIcons.brain},
    {'name': 'eye', 'icon': FontAwesomeIcons.eye},
    {'name': 'lungs', 'icon': FontAwesomeIcons.lungs},
    {'name': 'bone', 'icon': FontAwesomeIcons.bone},
    {'name': 'child', 'icon': FontAwesomeIcons.child},
    {'name': 'baby', 'icon': FontAwesomeIcons.baby},
    {'name': 'usermd', 'icon': FontAwesomeIcons.userDoctor},
    {'name': 'siren', 'icon': FontAwesomeIcons.truckMedical},
  ];

  final isDark = provider.isDarkTheme;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 24,
              right: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Edit Subject',
                  style: TextStyle(
                    color: Color(0xFF1E1E50),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Name/Title
                const Text(
                  'Subject Name',
                  style: TextStyle(
                      color: Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  decoration:
                      _buildInputDecoration('e.g., Cardiology, Ophthalmology'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Description
                const Text(
                  'Description',
                  style: TextStyle(
                      color: Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: descriptionController,
                  decoration:
                      _buildInputDecoration('Enter a short description'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Stage Selection Dropdown
                const Text(
                  'Stage / Year',
                  style: TextStyle(
                      color: Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedStage,
                  hint: const Text('Select a stage (Optional)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  decoration: _buildInputDecoration(''),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF6B4EFF)),
                  items: const [
                    DropdownMenuItem(
                        value: 'المرحلة الأولى',
                        child: Text('المرحلة الأولى',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'المرحلة الثانية',
                        child: Text('المرحلة الثانية',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'المرحلة الثالثة',
                        child: Text('المرحلة الثالثة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'المرحلة الرابعة',
                        child: Text('المرحلة الرابعة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'المرحلة الخامسة',
                        child: Text('المرحلة الخامسة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'المرحلة السادسة',
                        child: Text('المرحلة السادسة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'طالب امتياز',
                        child: Text('طالب امتياز',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'طبيب مقيم',
                        child: Text('طبيب مقيم',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'طبيب أخصائي',
                        child: Text('طبيب أخصائي',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'أستاذ مساعد',
                        child: Text('أستاذ مساعد',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                  ],
                  onChanged: (val) {
                    setModalState(() {
                      selectedStage = val;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // University Selection Dropdown
                const Text(
                  'University',
                  style: TextStyle(
                      color: Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedUniversity,
                  hint: const Text('Select a university (Optional)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  decoration: _buildInputDecoration(''),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF6B4EFF)),
                  items: const [
                    DropdownMenuItem(
                        value: 'كلية طب بغداد',
                        child: Text('كلية طب بغداد',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب المستنصرية',
                        child: Text('كلية طب المستنصرية',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب الكوفة',
                        child: Text('كلية طب الكوفة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب البصرة',
                        child: Text('كلية طب البصرة',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب بابل',
                        child: Text('كلية طب بابل',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب كربلاء',
                        child: Text('كلية طب كربلاء',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب القادسية',
                        child: Text('كلية طب القادسية',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب ميسان',
                        child: Text('كلية طب ميسان',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب واسط',
                        child: Text('كلية طب واسط',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب جابر بن حيان',
                        child: Text('كلية طب جابر بن حيان',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب صلاح الدين',
                        child: Text('كلية طب صلاح الدين',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب الموصل',
                        child: Text('كلية طب الموصل',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب المثنى',
                        child: Text('كلية طب المثنى',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب نينوى',
                        child: Text('كلية طب نينوى',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب كركوك',
                        child: Text('كلية طب كركوك',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب الأنبار',
                        child: Text('كلية طب الأنبار',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب الكندي',
                        child: Text('كلية طب الكندي',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب العميد',
                        child: Text('كلية طب العميد',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب حمورابي',
                        child: Text('كلية طب حمورابي',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب ذي قار',
                        child: Text('كلية طب ذي قار',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب ديالى',
                        child: Text('كلية طب ديالى',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب ابن سينا',
                        child: Text('كلية طب ابن سينا',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب النهرين',
                        child: Text('كلية طب النهرين',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب تكريت',
                        child: Text('كلية طب تكريت',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'كلية طب الجامعة العراقية',
                        child: Text('كلية طب الجامعة العراقية',
                            style:
                                TextStyle(fontSize: 14, fontFamily: 'Cairo'))),
                  ],
                  onChanged: (val) {
                    setModalState(() {
                      selectedUniversity = val;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Icon Selector
                const Text(
                  'Subject Icon',
                  style: TextStyle(
                      color: Color(0xFF1E1E50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: iconOptions.length,
                    itemBuilder: (context, index) {
                      final item = iconOptions[index];
                      final isSelected = selectedIcon == item['name'];
                      return GestureDetector(
                        onTap: () => setModalState(
                            () => selectedIcon = item['name'] as String),
                        child: Container(
                          width: 50,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6B4EFF)
                                    .withValues(alpha: 0.08)
                                : (isDark
                                    ? AppColors.surface2
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6B4EFF)
                                  : (isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: FaIcon(
                            item['icon'] as FaIconData,
                            color: isSelected
                                ? const Color(0xFF6B4EFF)
                                : const Color(0xFF9E9EBF),
                            size: 18,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final description = descriptionController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a subject name')),
                      );
                      return;
                    }

                    provider.editClinicalSubject(
                      subject.id,
                      name,
                      selectedIcon,
                      description,
                      stage: selectedStage,
                      university: selectedUniversity,
                    );

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Updated $name successfully!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: provider.isDarkTheme
                        ? AppColors.indigo
                        : const Color(0xFF6B4EFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
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
