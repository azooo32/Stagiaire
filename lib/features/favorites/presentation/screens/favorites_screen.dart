import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/models/question.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../practice/presentation/screens/question_viewer_screen.dart';
import '../../../clinical/presentation/screens/voice_screen.dart';
import '../../../clinical/presentation/screens/video_screen.dart';
import '../../../slide_workspace/presentation/screens/slide_workspace_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _ClinicalFavoriteItem {
  final String id;
  final String type;
  final String title;
  final String subject;
  final String? sectionId;
  final String? sectionTitle;
  final String? durationText;
  final String? subtitle;

  const _ClinicalFavoriteItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subject,
    this.sectionId,
    this.sectionTitle,
    this.durationText,
    this.subtitle,
  });
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final Map<int, bool> _expandedTopics = {};
  List<Question> _favQuestions = [];
  List<_ClinicalFavoriteItem> _clinicalItems = [];
  bool _loadingQuestions = false;
  bool _loadingClinical = false;
  String _mode = 'theory';
  String? _selectedTheorySubject;
  String? _selectedClinicalSubject;
  bool _didInitialLoad = false;
  bool _isLoadingFavorites = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadFavorites() async {
    if (_isLoadingFavorites) return;
    _isLoadingFavorites = true;
    try {
      await Future.wait([
        _loadTheoryFavorites(),
        _loadClinicalFavorites(),
      ]);
    } finally {
      _isLoadingFavorites = false;
    }
  }

  Future<void> _loadTheoryFavorites() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.favorites.isEmpty) {
      if (mounted) setState(() => _favQuestions = []);
      return;
    }

    if (mounted) setState(() => _loadingQuestions = true);
    try {
      final response = await SupabaseService()
          .client
          .from('questions')
          .select('*')
          .inFilter('id', provider.favorites);

      final  fetched = List<Map<String, dynamic>>.from(response)
          .map((q) => Question.fromJson(q))
          .toList();

      for (final q in  fetched) {
        if (provider.userAnswers.containsKey(q.id.toString())) {
          final userAns = provider.userAnswers[q.id.toString()];
          q.isSolved = true;
          final storedAns = userAns['answer'] as int?;
          if (storedAns != null) q.userAnswer = storedAns - 1;
        }
      }

      if (mounted) {
        setState(() {
          _favQuestions =  fetched;
          final subjects = _theorySubjects;
          if (subjects.isNotEmpty &&
              (_selectedTheorySubject == null ||
                  !subjects.contains(_selectedTheorySubject))) {
            _selectedTheorySubject = subjects.first;
          }
        });
      }
    } catch (e) {
      print('Error loading favorite questions: $e');
    } finally {
      if (mounted) setState(() => _loadingQuestions = false);
    }
  }

  Future<void> _loadClinicalFavorites() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final user = provider.currentUser;
    if (user == null) return;

    if (mounted) setState(() => _loadingClinical = true);
    try {
      final bookmarkRows = await SupabaseService()
          .client
          .from('user_bookmarks')
          .select('item_type, item_id')
          .eq('user_id', user.id);

      final rows = List<Map<String, dynamic>>.from(bookmarkRows);
      final voiceIds = rows
          .where((r) => r['item_type'] == 'voice_note')
          .map((r) => r['item_id'].toString())
          .toList();
      final videoIds = rows
          .where((r) => r['item_type'] == 'video')
          .map((r) => r['item_id'].toString())
          .toList();
      final stationIds = rows
          .where((r) => r['item_type'] == 'station')
          .map((r) => r['item_id'].toString())
          .toList();

      final subjectNamesById = {
        for (final subject in provider.clinicalSubjects)
          subject.id: subject.name
      };
      final List<_ClinicalFavoriteItem> items = [];
      final sectionIds = <String>{};
      List<Map<String, dynamic>> voices = [];
      List<Map<String, dynamic>> videos = [];
      List<Map<String, dynamic>> stations = [];

      if (voiceIds.isNotEmpty) {
        voices = List<Map<String, dynamic>>.from(await SupabaseService()
            .client
            .from('voice_notes')
            .select('*')
            .inFilter('id', voiceIds));
        sectionIds.addAll(
            voices.map((v) => v['section_id']?.toString()).whereType<String>());
      }
      if (videoIds.isNotEmpty) {
        videos = List<Map<String, dynamic>>.from(await SupabaseService()
            .client
            .from('videos')
            .select('*')
            .inFilter('id', videoIds));
        sectionIds.addAll(
            videos.map((v) => v['section_id']?.toString()).whereType<String>());
      }
      if (stationIds.isNotEmpty) {
        stations = List<Map<String, dynamic>>.from(await SupabaseService()
            .client
            .from('slide_stations')
            .select('*')
            .inFilter('id', stationIds));
        sectionIds.addAll(stations
            .map((s) => s['section_id']?.toString())
            .whereType<String>());
      }

      final sectionTitles = <String, String>{};
      if (sectionIds.isNotEmpty) {
        final sectionRows = List<Map<String, dynamic>>.from(
            await SupabaseService()
                .client
                .from('clinical_sections')
                .select('id, title')
                .inFilter('id', sectionIds.toList()));
        for (final section in sectionRows) {
          sectionTitles[section['id'].toString()] =
              section['title']?.toString() ?? '';
        }
      }

      for (final row in voices) {
        final sectionId = row['section_id']?.toString();
        items.add(_ClinicalFavoriteItem(
          id: row['id'].toString(),
          type: 'voice_note',
          title: row['title']?.toString() ?? 'Voice note',
          subject: subjectNamesById[row['subject_id']] ?? 'Clinical',
          sectionId: sectionId,
          sectionTitle: sectionId != null
              ? (sectionTitles[sectionId] ?? row['category']?.toString())
              : row['category']?.toString(),
          durationText: row['duration_text']?.toString(),
          subtitle: row['category']?.toString(),
        ));
      }
      for (final row in videos) {
        final sectionId = row['section_id']?.toString();
        items.add(_ClinicalFavoriteItem(
          id: row['id'].toString(),
          type: 'video',
          title: row['title']?.toString() ?? 'Video',
          subject: subjectNamesById[row['subject_id']] ?? 'Clinical',
          sectionId: sectionId,
          sectionTitle: sectionId != null ? sectionTitles[sectionId] : null,
          durationText: row['duration_text']?.toString(),
        ));
      }
      for (final row in stations) {
        final sectionId = row['section_id']?.toString();
        items.add(_ClinicalFavoriteItem(
          id: row['id'].toString(),
          type: 'station',
          title: row['title']?.toString() ?? 'Station',
          subject: subjectNamesById[row['subject_id']] ?? 'Clinical',
          sectionId: sectionId,
          sectionTitle: sectionId != null ? sectionTitles[sectionId] : null,
          subtitle: '${row['slides_count'] ?? 0} slides',
        ));
      }

      if (mounted) {
        setState(() {
          _clinicalItems = items;
          final subjects = _clinicalSubjects(provider);
          if (subjects.isNotEmpty &&
              (_selectedClinicalSubject == null ||
                  !subjects.contains(_selectedClinicalSubject))) {
            _selectedClinicalSubject = subjects.first;
          }
        });
      }
    } catch (e) {
      print('Error loading clinical favorites: $e');
    } finally {
      if (mounted) setState(() => _loadingClinical = false);
    }
  }

  List<String> get _theorySubjects =>
      _favQuestions.map((q) => q.subject).toSet().toList()..sort();

  List<String> _clinicalSubjects(AppProvider provider) {
    final withBookmarks =
        _clinicalItems.map((item) => item.subject).toSet().toList()..sort();
    if (withBookmarks.isNotEmpty) return withBookmarks;
    return provider.clinicalSubjects.map((s) => s.name).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final title = _mode == 'theory'
        ? (_selectedTheorySubject ??
            (_theorySubjects.isNotEmpty ? _theorySubjects.first : 'المفضلة'))
        : (_selectedClinicalSubject ??
            (_clinicalSubjects(provider).isNotEmpty
                ? _clinicalSubjects(provider).first
                : 'العملي'));

    if (provider.currentTab == 1 && !_didInitialLoad) {
      _didInitialLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFavorites();
      });
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : const Color(0xFF5B3EEF),
      body: Column(
        children: [
          _buildHeader(provider, title),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.bg : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  _buildModeSwitoh(isDark),
                  const SizedBox(height: 12),
                  if (_mode == 'theory') _buildTheoryTools(provider, isDark),
                  if (_mode == 'theory') const SizedBox(height: 10),
                  Expanded(
                      child: _mode == 'theory'
                          ? _buildTheoryBody(provider, isDark)
                          : _buildClinicalBody(provider, isDark)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppProvider provider, String title) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDark = provider.isDarkTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
          top: statusBarHeight + 2, bottom: 8, left: 16, right: 16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
              : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48),
          PopupMenuButton<String>(
            tooltip: 'تغيير المادة',
            color: isDark ? AppColors.surface2 : Colors.white,
            offset: const Offset(0, 38),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              setState(() {
                if (_mode == 'theory') {
                  _selectedTheorySubject = value;
                  _expandedTopics.clear();
                } else {
                  _selectedClinicalSubject = value;
                }
              });
            },
            itemBuilder: (_) {
              final subjects = _mode == 'theory'
                  ? _theorySubjects
                  : _clinicalSubjects(provider);
              return subjects.map((subject) {
                final current = subject == title;
                return PopupMenuItem<String>(
                  value: subject,
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(
                          current
                              ? Icons.check_rounded
                              : Icons.menu_book_rounded,
                          size: 17,
                          color: current
                              ? const Color(0xFFA78BFA)
                              : (isDark
                                  ? AppColors.textMuted
                                  : const Color(0xFF64748B))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight:
                                    current ? FontWeight.w900 : FontWeight.w700,
                                color: isDark
                                    ? AppColors.text
                                    : const Color(0xFF1E293B))),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          fontFamily: 'Cairo')),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
          IconButton(
            tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
            icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: Colors.white,
                size: 22),
            onPressed: () => provider.toggleTheme(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitoh(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.border : const Color(0xFFE2E8F0))),
        child: Row(
          children: [
            _modeButton('theory', 'نظري', Icons.menu_book_rounded, isDark),
            _modeButton(
                'clinical', 'عملي', Icons.medical_services_outlined, isDark),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(String value, String label, IconData icon, bool isDark) {
    final active = _mode == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              color: active ? AppColors.indigo : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: active
                      ? Colors.white
                      : (isDark ? AppColors.textDim : const Color(0xFF64748B))),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? Colors.white
                          : (isDark
                              ? AppColors.textDim
                              : const Color(0xFF64748B)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTheoryTools(AppProvider provider, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text('المواضيع',
              style: TextStyle(
                  color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo')),
          const Spacer(),
          GestureDetector(
            onTap: () =>
                provider.toggleAnswersRevealed(!provider.isAnswersRevealed),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: provider.isAnswersRevealed
                    ? AppColors.indigo.withValues(alpha: 0.16)
                    : (isDark ? AppColors.surface : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: provider.isAnswersRevealed
                        ? AppColors.indigo
                        : (isDark
                            ? AppColors.border
                            : const Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Icon(
                      provider.isAnswersRevealed
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_outlined,
                      color: provider.isAnswersRevealed
                          ? AppColors.indigo
                          : (isDark
                              ? AppColors.textDim
                              : const Color(0xFF64748B)),
                      size: 15),
                  const SizedBox(width: 5),
                  Text('الحلول',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: provider.isAnswersRevealed
                              ? AppColors.indigo
                              : (isDark
                                  ? AppColors.textDim
                                  : const Color(0xFF64748B)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTheoryBody(AppProvider provider, bool isDark) {
    if (_loadingQuestions) return const Center(child: LogoSpinner());
    final subjects = _theorySubjects;
    if (subjects.isEmpty) return _emptyState(isDark, 'لا توجد أسئلة مفضلة');
    final selected = _selectedTheorySubject ?? subjects.first;
    final questions =
        _favQuestions.where((q) => q.subject == selected).toList();
    final topicsGroup = <String, Map<String, List<Question>>>{};
    for (final q in questions) {
      final topic = q.topic ?? 'غير محدد';
      final subTopic = q.subTopic ?? 'غير محدد';
      topicsGroup
          .putIfAbsent(topic, () => <String, List<Question>>{})
          .putIfAbsent(subTopic, () => <Question>[])
          .add(q);
    }
    if (topicsGroup.isEmpty)
      return _emptyState(isDark, 'لا توجد أسئلة مفضلة لهذه المادة');

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 92),
      itemCount: topicsGroup.keys.length,
      itemBuilder: (_, index) {
        final topicTitle = topicsGroup.keys.elementAt(index);
        final subTopics = topicsGroup[topicTitle]!;
        final allTopicQs = subTopics.values.expand((items) => items).toList();
        final isExpanded = _expandedTopics[index] ?? index == 0;
        return _topicCard(provider, isDark, index, topicTitle, subTopics,
            allTopicQs, isExpanded);
      },
    );
  }

  Widget _topicCard(
      AppProvider provider,
      bool isDark,
      int index,
      String title,
      Map<String, List<Question>> subTopics,
      List<Question> allQuestions,
      bool isExpanded) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark
                  ? AppColors.border
                  : const Color(0xFFE2E8F0).withValues(alpha: 0.7))),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expandedTopics[index] = !isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: AppColors.indigo.withValues(alpha: 0.12),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.folder_open_rounded,
                            color: AppColors.indigo, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.text
                                      : const Color(0xFF1E293B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  fontFamily: 'Cairo')),
                          const SizedBox(height: 4),
                          Row(children: [
                            Text('${subTopics.keys.length} مواضيع',
                                style: TextStyle(
                                    color: isDark
                                        ? AppColors.textMuted
                                        : const Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                            const Spacer(),
                            Text('${allQuestions.length} سؤال',
                                style: TextStyle(
                                    color: isDark
                                        ? AppColors.textMuted
                                        : const Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: const Color(0xFF94A3B8),
                        size: 22),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: subTopics.entries
                    .map((entry) =>
                        _subTopicCard(provider, isDark, entry.key, entry.value))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subTopicCard(AppProvider provider, bool isDark, String title,
      List<Question> questions) {
    return GestureDetector(
      onTap: () {
        final reviewQuestions =
            questions.map((q) => Question.fromJson(q.toJson())).toList();
        provider.startPracticeSession(reviewQuestions, recordProgress: false);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const QuestionViewerScreen()));
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
            color: isDark ? AppColors.surface2 : const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppColors.border
                    : const Color(0xFF4F46E5).withValues(alpha: 0.12))),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    shape: BoxShape.circle),
                child: const Icon(Icons.article_outlined,
                    color: AppColors.indigo, size: 18)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color:
                            isDark ? AppColors.text : const Color(0xFF1E293B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo'))),
            const SizedBox(width: 8),
            Text('${questions.length} سؤال',
                style: TextStyle(
                    color:
                        isDark ? AppColors.textMuted : const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicalBody(AppProvider provider, bool isDark) {
    if (_loadingClinical) return const Center(child: LogoSpinner());
    final subjects = _clinicalSubjects(provider);
    if (subjects.isEmpty)
      return _emptyState(isDark, 'لا توجد عناصر عملية محفوظة');
    final selected = _selectedClinicalSubject ?? subjects.first;
    final items =
        _clinicalItems.where((item) => item.subject == selected).toList();
    if (items.isEmpty)
      return _emptyState(isDark, 'لا توجد عناصر محفوظة لهذه المادة');

    final voiceCount = items.where((item) => item.type == 'voice_note').length;
    final videoCount = items.where((item) => item.type == 'video').length;
    final stationItems = items.where((item) => item.type == 'station').toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 92),
      children: [
        if (voiceCount > 0)
          _clinicalEntryCard(
            isDark: isDark,
            title: 'Voice',
            subtitle: '$voiceCount محفوظة',
            icon: Icons.mic_none_rounded,
            color: const Color(0xFF10B981),
            onTap: () => _openClinicalSection(provider, selected, 'voice_note'),
          ),
        if (videoCount > 0)
          _clinicalEntryCard(
            isDark: isDark,
            title: 'Video',
            subtitle: '$videoCount محفوظة',
            icon: Icons.play_circle_outline_rounded,
            color: const Color(0xFFEF4444),
            onTap: () => _openClinicalSection(provider, selected, 'video'),
          ),
        if (stationItems.isNotEmpty)
          _clinicalEntryCard(
            isDark: isDark,
            title: 'Slide',
            subtitle: '${stationItems.length} محفوظة',
            icon: Icons.view_carousel_outlined,
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _FavoriteSlidesScreen(
                        subject: selected, items: stationItems))),
          ),
      ],
    );
  }

  Widget _clinicalEntryCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: isDark ? AppColors.border : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.text
                              : const Color(0xFF111827))),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textDim
                              : const Color(0xFF64748B))),
                ])),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8), size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openClinicalSection(
      AppProvider provider, String subject, String type) async {
    await provider.loadClinicalData(subject);
    if (!mounted) return;
    final item = _clinicalItems.firstWhere((item) =>
        item.subject == subject && item.type == type && item.sectionId != null);
    if (type == 'voice_note') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VoiceScreen(
                  subject: subject,
                  sectionId: item.sectionId!,
                  sectionTitle: item.sectionTitle ?? 'Voice',
                  favoriteOnly: true)));
    } else if (type == 'video') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VideoScreen(
                  subject: subject,
                  sectionId: item.sectionId!,
                  sectionTitle: item.sectionTitle ?? 'Video',
                  favoriteOnly: true)));
    }
  }

  Widget _emptyState(bool isDark, String title) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bookmark_border_rounded,
            size: 76,
            color: isDark ? AppColors.textMuted : const Color(0xFFCBD5E1)),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.text : const Color(0xFF111827))),
      ]),
    );
  }

}

class _FavoriteSlidesScreen extends StatelessWidget {
  final String subject;
  final List<_ClinicalFavoriteItem> items;

  const _FavoriteSlidesScreen({required this.subject, required this.items});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bg : const Color(0xFFF8FAFC),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                  top: statusBarHeight + 8, bottom: 12, left: 16, right: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                      : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Slide - $subject',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              fontFamily: 'Cairo'))),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SlideWorkspaceScreen(
                                stationName: item.title,
                                stationDbId: item.id))),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surface : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: isDark
                                ? AppColors.border
                                : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.view_carousel_outlined,
                                  color: Color(0xFF7C3AED), size: 28)),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: isDark
                                            ? AppColors.text
                                            : const Color(0xFF111827))),
                                const SizedBox(height: 4),
                                Text(
                                    [item.sectionTitle, item.subtitle]
                                        .where(
                                            (v) => v != null && v.isNotEmpty)
                                        .join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppColors.textDim
                                            : const Color(0xFF64748B))),
                              ])),
                          const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFF94A3B8), size: 24),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}







