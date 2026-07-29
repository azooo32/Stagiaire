import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/subject.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/app_loader.dart';
import 'subject_topics_screen.dart';

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final iconMapping = <String, Object>{
      'internal medicine': FontAwesomeIcons.stethoscope,
      'Paediatric': FontAwesomeIcons.child,
      'Surgery': FontAwesomeIcons.userDoctor,
      'Obstetric': FontAwesomeIcons.baby,
      'Gynecology': FontAwesomeIcons.venus,
      'Anesthesia': FontAwesomeIcons.vial,
      'Radiology': FontAwesomeIcons.xRay,
      'Psychiatry': FontAwesomeIcons.brain,
      'ENT': Icons.hearing,
      'Ophthalmology': FontAwesomeIcons.eye,
    };

    final pageColor =
        provider.isDarkTheme ? AppColors.bg : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        toolbarHeight: 68,
        flexibleSpace: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: provider.isDarkTheme
                    ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                    : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'medical subjects',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            fontFamily: 'Cairo',
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: provider.isDarkTheme ? 'الوضع الفاتح' : 'الوضع الداكن',
              icon: Icon(
                provider.isDarkTheme
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                color: Colors.white,
                size: 22,
              ),
              onPressed: provider.toggleTheme,
            ),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: LogoSpinner())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 250,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.08,
                    ),
                    itemCount: provider.subjects.length,
                    itemBuilder: (context, index) {
                      final subject = provider.subjects[index];
                      final icon = iconMapping[subject.name] ??
                          FontAwesomeIcons.bookMedical;
                      return _buildSubjectCard(
                        context,
                        subject,
                        icon,
                        const Color(0xFF6B4EFF),
                        provider,
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSubjectCard(
    BuildContext context,
    Subject subject,
    Object icon,
    Color color,
    AppProvider provider,
  ) {
    final total = subject.totalQuestions;
    final answered = provider.userAnswers.values
        .where((answer) => answer['subject'] == subject.name)
        .length;
    final pct = total > 0 ? ((answered / total) * 100).round() : 0;

    const displayNameMapping = <String, String>{
      'internal medicine': 'Internal Medicine',
      'Paediatric': 'Paediatric',
      'Surgery': 'Surgery',
      'Obstetric': 'Obstetric',
      'Gynecology': 'Gynecology',
    };
    final displayName = displayNameMapping[subject.name] ?? subject.name;
    final isLocked = !provider.isSubjectUnlocked(subject.id);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (isLocked) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor:
                  provider.isDarkTheme ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'المادة مغلقة',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
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
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      } else {
                        await launchUrl(url);
                      }
                    } catch (e) {
                      print('Could not launch Telegram: $e');
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.telegram,
                      size: 16, color: Colors.white),
                  label: const Text(
                    'تفعيل الاشتراك',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF229ED9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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
            builder: (_) => SubjectTopicsScreen(subjectName: subject.name),
          ),
        );
      },
      child: Stack(
        children: [
          Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: provider.isDarkTheme ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: provider.isDarkTheme
                      ? AppColors.border
                      : color.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: provider.isDarkTheme
                        ? Colors.black.withValues(alpha: 0.2)
                        : color.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: icon is FaIconData
                        ? FaIcon(icon, color: color, size: 22)
                        : Icon(icon as IconData, color: color, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: provider.isDarkTheme
                          ? AppColors.text
                          : const Color(0xFF1E293B),
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'سؤال $answered / $total',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: provider.isDarkTheme
                          ? AppColors.textMuted
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            minHeight: 6,
                            backgroundColor: provider.isDarkTheme
                                ? AppColors.surface2
                                : const Color(0xFFE8EAF2),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
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
        ],
      ),
    );
  }
}
