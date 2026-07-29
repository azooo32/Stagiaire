import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/models/question.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../practice/presentation/screens/question_viewer_screen.dart';

class SubjectTopicsScreen extends StatefulWidget {
  final String subjectName;
  final String? initialTopicName;
  const SubjectTopicsScreen({
    super.key,
    required this.subjectName,
    this.initialTopicName,
  });

  @override
  State<SubjectTopicsScreen> createState() => _SubjectTopicsScreenState();
}

class _SubjectTopicsScreenState extends State<SubjectTopicsScreen> {
  final Map<int, bool> _expandedTopics =
      {}; // Expanded state tracked dynamically
  List<String> _selectedSources = ['all'];
  bool _sourcesRestored = false;

  int _compareTopics(String a, String b, Map<String, int> topicOrders) {
    final orderA = topicOrders[a];
    final orderB = topicOrders[b];
    if (orderA != null && orderB != null) {
      final comp = orderA.compareTo(orderB);
      if (comp != 0) return comp;
    } else if (orderA != null) {
      return -1;
    } else if (orderB != null) {
      return 1;
    }
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  int _compareSubTopics(
      String topic, String a, String b, Map<String, int> subTopicOrders) {
    final orderA = subTopicOrders['$topic:$a'];
    final orderB = subTopicOrders['$topic:$b'];
    if (orderA != null && orderB != null) {
      final comp = orderA.compareTo(orderB);
      if (comp != 0) return comp;
    } else if (orderA != null) {
      return -1;
    } else if (orderB != null) {
      return 1;
    }
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  void _showReorderDialog(
      Map<String, Map<String, List<Question>>> topicsGroup, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: provider.isDarkTheme ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
      ),
      builder: (context) {
        return _ReorderTopicsModal(
          subjectName: widget.subjectName,
          topicsGroup: topicsGroup,
        );
      },
    );
  }

  // Map to get custom colors for dynamic sources based on their names
  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'uworld':
        return const Color(0xFF3897FF);
      case 'dara':
        return const Color(0xFF6B4EFF);
      case 'amboss':
        return const Color(0xFF3DD68C);
      case 'past papers':
      case 'past_papers':
        return const Color(0xFFFF9F43);
      case 'osce':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF8B6EFF);
    }
  }

  // Get custom icons for dynamic sources
  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'uworld':
        return Icons.public;
      case 'dara':
        return Icons.donut_large;
      case 'amboss':
        return Icons.change_history;
      case 'past papers':
      case 'past_papers':
        return Icons.description_outlined;
      case 'osce':
        return Icons.check_circle_outline;
      default:
        return Icons.extension;
    }
  }

  List<String> _normalizedSources(
      List<String> sources, List<String> allPossibleSources) {
    final validSources = allPossibleSources.toSet();
    final selected = sources
        .where((s) => s == 'all' || validSources.contains(s))
        .toSet()
        .toList();

    if (selected.isEmpty) return ['all', ...allPossibleSources];
    if (selected.contains('all')) return ['all', ...allPossibleSources];

    final individualOnly = selected.where((s) => s != 'all').toList();
    if (individualOnly.isEmpty ||
        individualOnly.length == allPossibleSources.length) {
      return ['all', ...allPossibleSources];
    }
    return individualOnly;
  }

  void _restoreSavedSources(
      AppProvider provider, List<String> allPossibleSources) {
    if (_sourcesRestored || allPossibleSources.isEmpty) return;
    _sourcesRestored = true;

    final saved = provider.getSavedSourceFilters(widget.subjectName);
    if (saved != null && saved.isNotEmpty) {
      _selectedSources = _normalizedSources(saved, allPossibleSources);
    } else if (_selectedSources.contains('all') &&
        _selectedSources.length == 1) {
      _selectedSources = ['all', ...allPossibleSources];
    }
  }

  void _filterBySource(
      String value, List<String> allPossibleSources, AppProvider provider) {
    setState(() {
      if (value == 'all') {
        _selectedSources = ['all', ...allPossibleSources];
      } else {
        if (_selectedSources.contains(value)) {
          _selectedSources =
              _selectedSources.where((s) => s != value && s != 'all').toList();
        } else {
          _selectedSources.add(value);
        }
        _selectedSources =
            _normalizedSources(_selectedSources, allPossibleSources);
      }
    });
    provider.saveSourceFilters(widget.subjectName, _selectedSources);
  }

  void _showResetProgressDialog(
      Map<String, Map<String, List<Question>>> topicsGroup,
      AppProvider provider) {
    final selectedTitles = <String>{};
    bool resetAll = true;

    final isDark = provider.isDarkTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final bottomInset = MediaQuery.of(context).padding.bottom;
            final canConfirm = resetAll || selectedTitles.isNotEmpty;
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.74,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.borderBright
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Text(
                        'تصفير التقدم وإعادة التعيين',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? AppColors.text : const Color(0xFF1E1E50),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'اختر الكل أو أكثر من جابتر لإعادة تعيين تقدمه.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textMuted
                              : const Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              CheckboxListTile(
                                value: resetAll,
                                activeColor: const Color(0xFFEF4444),
                                checkColor: Colors.white,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (bool? val) {
                                  setModalState(() {
                                    resetAll = val ?? false;
                                    if (resetAll) selectedTitles.clear();
                                  });
                                },
                                title: const Text(
                                  'إعادة تعيين الكل (كامل المادة)',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                              Divider(
                                  height: 1,
                                  color: isDark
                                      ? AppColors.border
                                      : const Color(0xFFE2E8F0)),
                              ...(topicsGroup.keys.toList()
                                    ..sort((a, b) => _compareTopics(
                                        a, b, provider.topicOrders)))
                                  .map((title) {
                                final checked = selectedTitles.contains(title);
                                return CheckboxListTile(
                                  value: resetAll || checked,
                                  enabled: !resetAll,
                                  activeColor: const Color(0xFFA78BFA),
                                  checkColor:
                                      isDark ? AppColors.bg : Colors.white,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged: (bool? val) {
                                    setModalState(() {
                                      resetAll = false;
                                      if (val == true) {
                                        selectedTitles.add(title);
                                      } else {
                                        selectedTitles.remove(title);
                                      }
                                    });
                                  },
                                  title: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: checked
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: resetAll
                                          ? (isDark
                                              ? AppColors.textMuted
                                              : const Color(0xFF94A3B8))
                                          : (isDark
                                              ? AppColors.text
                                              : const Color(0xFF1E293B)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFE2E8F0),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(0, 44),
                              ),
                              child: Text(
                                'إلغاء',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.textDim
                                      : const Color(0xFF475569),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: canConfirm
                                  ? () async {
                                      Navigator.pop(context);
                                      showDialog(
                                        context: this.context,
                                        barrierDismissible: false,
                                        builder: (BuildContext context) =>
                                            const Center(
                                                child: LogoSpinner(
                                                    size: 80, logoSize: 50)),
                                      );

                                      if (resetAll) {
                                        await provider.resetProgress(
                                            topicName: '__ALL__');
                                      } else {
                                        for (final title in selectedTitles) {
                                          await provider.resetProgress(
                                              topicName: title);
                                        }
                                      }

                                      if (Navigator.canPop(this.context))
                                        Navigator.pop(this.context);
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'تم إعادة تعيين التقدم بنجاح!',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo')),
                                          backgroundColor: Color(0xFF10B981),
                                        ),
                                      );
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                disabledBackgroundColor: isDark
                                    ? AppColors.surface3
                                    : const Color(0xFFE5E7EB),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(0, 44),
                              ),
                              child: const Text(
                                'تأكيد مسح التقدم',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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

    final isLocked = !provider.isSubjectUnlockedByName(widget.subjectName);
    if (isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'عذراً، هذه المادة تتطلب اشتراكاً نشطاً.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            duration: Duration(seconds: 3),
          ),
        );
      });
      return const Scaffold(
        body: Center(child: LogoSpinner()),
      );
    }

    // Dynamic sources list from database questions matching buildSourcesBar()
    final List<String> allPossibleSources = provider.questions
        .map((q) => q.ref ?? '')
        .where((ref) => ref.trim().isNotEmpty)
        .toSet()
        .toList();

    _restoreSavedSources(provider, allPossibleSources);

    // Filter questions list dynamically based on multi-selected sources
    final List<Question> filteredQuestions = _selectedSources.contains('all')
        ? provider.questions
        : provider.questions
            .where((q) => _selectedSources.contains(q.ref))
            .toList();

    // Group filtered questions by main topic (q.topic) and subtopic (q.subTopic)
    final Map<String, Map<String, List<Question>>> topicsGroup = {};
    for (var q in filteredQuestions) {
      final t = q.topic ?? 'غير محدد';
      final s = q.subTopic ?? 'غير محدد';
      topicsGroup[t] = topicsGroup[t] ?? {};
      topicsGroup[t]![s] = topicsGroup[t]![s] ?? [];
      topicsGroup[t]![s]!.add(q);
    }
    final sortedTopicTitles = topicsGroup.keys.toList()
      ..sort((a, b) => _compareTopics(a, b, provider.topicOrders));

    // Build dynamic list of sources for UI cards
    final List<Map<String, dynamic>> dynamicSources = [
      {
        'name': 'الكل',
        'value': 'all',
        'icon': Icons.apps,
        'color': const Color(0xFF6B4EFF),
        'qs': provider.questions,
      },
      ...allPossibleSources.map((src) {
        return {
          'name': src.toUpperCase(),
          'value': src,
          'icon': _getSourceIcon(src),
          'color': _getSourceColor(src),
          'qs': provider.questions.where((q) => q.ref == src).toList(),
        };
      })
    ];

    return Scaffold(
      backgroundColor: provider.isDarkTheme
          ? AppColors.bg
          : const Color(0xFF5B3EEF), // Purple background to match header
      appBar: AppBar(
        flexibleSpace: Container(
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: PopupMenuButton<String>(
          tooltip: 'تغيير المادة',
          color: provider.isDarkTheme ? AppColors.surface2 : Colors.white,
          elevation: 10,
          offset: const Offset(0, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: provider.isDarkTheme
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.28)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          onSelected: (String subjectName) async {
            if (subjectName == widget.subjectName) return;
            await provider.selectSubject(subjectName);
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SubjectTopicsScreen(subjectName: subjectName),
              ),
            );
          },
          itemBuilder: (BuildContext context) {
            return provider.subjects.map((subject) {
              final bool isCurrent = subject.name == widget.subjectName;
              return PopupMenuItem<String>(
                value: subject.name,
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFFA78BFA).withValues(
                                alpha: provider.isDarkTheme ? 0.20 : 0.12)
                            : (provider.isDarkTheme
                                ? AppColors.surface3
                                : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCurrent
                            ? Icons.check_rounded
                            : Icons.menu_book_rounded,
                        size: 17,
                        color: isCurrent
                            ? const Color(0xFFA78BFA)
                            : (provider.isDarkTheme
                                ? AppColors.textMuted
                                : const Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: provider.isDarkTheme
                              ? AppColors.text
                              : const Color(0xFF1E293B),
                          fontWeight:
                              isCurrent ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
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
                child: Text(
                  widget.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: provider.isDarkTheme ? 'الوضع النهاري' : 'الوضع الليلي',
              icon: Icon(
                provider.isDarkTheme
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => provider.toggleTheme(),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: provider.isDarkTheme
                ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: provider.isDarkTheme
                      ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                      : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    // Reset Button
                    GestureDetector(
                      onTap: () =>
                          _showResetProgressDialog(topicsGroup, provider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'إعادة التعيين',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (provider.isAdminOrOwner) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            _showReorderDialog(topicsGroup, provider),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA78BFA)
                                .withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFA78BFA)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.swap_vert_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 5),
                              Text(
                                'ترتيب العناوين',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),

                    GestureDetector(
                      onTap: () {
                        final val = !provider.isAnswersRevealed;
                        provider.toggleAnswersRevealed(val);
                        setState(() {
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: provider.isAnswersRevealed
                              ? Colors.white.withValues(alpha: 0.24)
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: provider.isAnswersRevealed
                                ? const Color(0xFFA78BFA)
                                    .withValues(alpha: 0.85)
                                : Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              provider.isAnswersRevealed
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_outlined,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'الحلول',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    PopupMenuButton<String>(
                      initialValue: provider.viewMode,
                      onSelected: (String val) {
                        provider.setViewMode(val);
                      },
                      offset: const Offset(0, 32),
                      color: provider.isDarkTheme
                          ? AppColors.surface2
                          : Colors.white,
                      elevation: 10,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: provider.isDarkTheme
                              ? const Color(0xFFA78BFA).withValues(alpha: 0.26)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem<String>(
                          value: 'chapter',
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              Icon(
                                provider.viewMode == 'chapter'
                                    ? Icons.check_rounded
                                    : Icons.folder_rounded,
                                size: 17,
                                color: provider.viewMode == 'chapter'
                                    ? const Color(0xFFA78BFA)
                                    : (provider.isDarkTheme
                                        ? AppColors.textMuted
                                        : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'حسب الجابتر',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: provider.isDarkTheme
                                      ? AppColors.text
                                      : const Color(0xFF1E1E50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'topic',
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              Icon(
                                provider.viewMode == 'topic'
                                    ? Icons.check_rounded
                                    : Icons.layers_rounded,
                                size: 17,
                                color: provider.viewMode == 'topic'
                                    ? const Color(0xFFA78BFA)
                                    : (provider.isDarkTheme
                                        ? AppColors.textMuted
                                        : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'حسب الموضوع',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: provider.isDarkTheme
                                      ? AppColors.text
                                      : const Color(0xFF1E1E50),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              provider.viewMode == 'chapter'
                                  ? Icons.folder_rounded
                                  : Icons.layers_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              provider.viewMode == 'chapter'
                                  ? 'الجابتر'
                                  : 'الموضوع',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.white, size: 15),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Curved Content Container
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: provider.isDarkTheme
                      ? AppColors.surface
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                  ),
                  border: Border.all(
                    color: provider.isDarkTheme
                        ? const Color(0xFF6047D6).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.70),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: provider.isDarkTheme
                          ? Colors.black.withValues(alpha: 0.18)
                          : const Color(0xFF4F46E5).withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: provider.isQuestionsLoading
                      ? const Center(child: LogoSpinner(size: 85, logoSize: 50))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),

                            // ─── Available Sources Title ───
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'المصادر المتاحة',
                                  style: TextStyle(
                                    color: provider.isDarkTheme
                                        ? AppColors.text
                                        : const Color(0xFF1E1E50),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // ─── Available Sources Scroll ───
                            SizedBox(
                              height: 80,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: dynamicSources.length,
                                itemBuilder: (context, index) {
                                  final src = dynamicSources[index];
                                  final String val = src['value'];
                                  final List<Question> srcQs = src['qs'];

                                  // Calculate dynamic solved and total matching buildSourcesBar()
                                  final int total = srcQs.length;
                                  final int answered =
                                      srcQs.where((q) => q.isSolved).length;
                                  final int pct = total > 0
                                      ? ((answered / total) * 100).round()
                                      : 0;

                                  // Check active state mirroring buildSourcesBar() active logic
                                  bool active = false;
                                  if (_selectedSources.contains('all')) {
                                    active = (val == 'all' ||
                                        _selectedSources.contains(val));
                                  } else {
                                    active = _selectedSources.contains(val);
                                  }

                                  return GestureDetector(
                                    onTap: () => _filterBySource(
                                        val, allPossibleSources, provider),
                                    child: Container(
                                      width: 100,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 6),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? (provider.isDarkTheme
                                                ? const Color(0xFF1E2030)
                                                : const Color(0xFFEEF2FF))
                                            : (provider.isDarkTheme
                                                ? AppColors.surface
                                                : Colors
                                                    .white), // Inward light indigo fill when active
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: active
                                              ? (provider.isDarkTheme
                                                  ? const Color(0xFF6047D6)
                                                  : const Color(0xFF4F46E5))
                                              : (provider.isDarkTheme
                                                  ? AppColors.border
                                                  : Colors.transparent),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: active
                                                ? Colors
                                                    .transparent // No outward glow when active
                                                : (provider.isDarkTheme
                                                    ? Colors.transparent
                                                    : const Color(0xFF4F46E5)
                                                        .withValues(
                                                            alpha: 0.04)),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            src['name'],
                                            style: TextStyle(
                                              color: provider.isDarkTheme
                                                  ? AppColors.text
                                                  : const Color(0xFF1E1E50),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '$answered/$total',
                                                style: const TextStyle(
                                                    color: Color(0xFF9E9EBF),
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Cairo'),
                                              ),
                                              if (active) ...[
                                                const SizedBox(width: 4),
                                                Icon(Icons.check_circle,
                                                    color: provider.isDarkTheme
                                                        ? const Color(
                                                            0xFF6047D6)
                                                        : const Color(
                                                            0xFF4F46E5),
                                                    size: 10),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(2),
                                            child: SizedBox(
                                              width: 50,
                                              height: 4,
                                              child: LinearProgressIndicator(
                                                value: pct / 100,
                                                backgroundColor:
                                                    const Color(0xFFE2E2E9),
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                            Color>(
                                                        provider.isDarkTheme
                                                            ? const Color(
                                                                0xFF6047D6)
                                                            : src['color']),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ─── Topics Title ───
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'المواضيع',
                                  style: TextStyle(
                                    color: provider.isDarkTheme
                                        ? AppColors.text
                                        : const Color(0xFF1E1E50),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // ─── Topics Accordion List ───
                            Expanded(
                              child: topicsGroup.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'لا توجد مواضيع متاحة للمصدر المحدّد.'))
                                  : ListView.builder(
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.only(
                                          left: 20.0,
                                          right: 20.0,
                                          top: 0,
                                          bottom: 90.0),
                                      itemCount: sortedTopicTitles.length,
                                      itemBuilder: (context, index) {
                                        final topicTitle =
                                            sortedTopicTitles[index];
                                        final subTopics =
                                            topicsGroup[topicTitle]!;
                                        final List<Question> allTopicQs =
                                            subTopics.values
                                                .expand((element) => element)
                                                .toList();

                                        final int total = allTopicQs.length;
                                        final int solved = allTopicQs
                                            .where((q) => q.isSolved)
                                            .length;
                                        final int pct = total > 0
                                            ? ((solved / total) * 100).round()
                                            : 0;

                                        final isExpanded =
                                            _expandedTopics[index] ??
                                                (widget.initialTopicName !=
                                                        null &&
                                                    widget.initialTopicName ==
                                                        topicTitle);

                                        return Container(
                                          margin: const EdgeInsets.only(
                                              bottom:
                                                  8.0), // Reduced spacing between main topic cards
                                          decoration: BoxDecoration(
                                            color: provider.isDarkTheme
                                                ? AppColors.surface
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: provider.isDarkTheme
                                                  ? AppColors.border
                                                  : const Color(0xFFE2E8F0)
                                                      .withValues(alpha: 0.7),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: provider.isDarkTheme
                                                    ? Colors.black
                                                        .withValues(alpha: 0.2)
                                                    : const Color(0xFF4F46E5)
                                                        .withValues(
                                                            alpha: 0.06),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  if (provider.viewMode ==
                                                      'chapter') {
                                                    provider
                                                        .startPracticeSession(
                                                            allTopicQs);
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            const QuestionViewerScreen(),
                                                      ),
                                                    );
                                                  } else {
                                                    setState(() {
                                                      _expandedTopics[index] =
                                                          !isExpanded;
                                                    });
                                                  }
                                                },
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                child: Directionality(
                                                  textDirection: TextDirection
                                                      .ltr, // Enforce LTR for consistent left-to-right flow
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16.0,
                                                        vertical: 12.0),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        // 1. Large Circle Progress on the far left (height of two lines)
                                                        Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            SizedBox(
                                                              width: 44,
                                                              height: 44,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                value:
                                                                    pct / 100,
                                                                strokeWidth: 4,
                                                                backgroundColor: provider
                                                                        .isDarkTheme
                                                                    ? AppColors
                                                                        .surface2
                                                                    : const Color(
                                                                        0xFFF1F5F9),
                                                                valueColor: AlwaysStoppedAnimation<
                                                                    Color>(provider
                                                                        .isDarkTheme
                                                                    ? const Color(
                                                                        0xFF6047D6)
                                                                    : const Color(
                                                                        0xFF4F46E5)),
                                                              ),
                                                            ),
                                                            Text(
                                                              '$pct%',
                                                              style: TextStyle(
                                                                color: provider
                                                                        .isDarkTheme
                                                                    ? AppColors
                                                                        .text
                                                                    : const Color(
                                                                        0xFF1E293B),
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontFamily:
                                                                    'Inter',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            width: 12),

                                                        // 2. Title and stats in the middle, starting after the circle
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              // Title Row
                                                              Text(
                                                                topicTitle,
                                                                style:
                                                                    TextStyle(
                                                                  color: provider
                                                                          .isDarkTheme
                                                                      ? AppColors
                                                                          .text
                                                                      : const Color(
                                                                          0xFF1E293B),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      13.5,
                                                                  fontFamily:
                                                                      'Cairo',
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 4),
                                                              // Stats Row
                                                              Row(
                                                                children: [
                                                                  Text(
                                                                    '${subTopics.keys.length} مواضيع',
                                                                    style:
                                                                        TextStyle(
                                                                      color: provider.isDarkTheme
                                                                          ? AppColors
                                                                              .textMuted
                                                                          : const Color(
                                                                              0xFF64748B),
                                                                      fontSize:
                                                                          11,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontFamily:
                                                                          'Cairo',
                                                                    ),
                                                                  ),
                                                                  const Spacer(), // Pushes the questions count to the far right side
                                                                  Text(
                                                                    'سؤال $solved / $total',
                                                                    style:
                                                                        TextStyle(
                                                                      color: provider.isDarkTheme
                                                                          ? AppColors
                                                                              .textMuted
                                                                          : const Color(
                                                                              0xFF64748B),
                                                                      fontSize:
                                                                          11,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontFamily:
                                                                          'Cairo',
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 4),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),

                                                        // 3. Arrow Icon on the far right, vertically centered
                                                        if (provider.viewMode !=
                                                            'chapter')
                                                          Icon(
                                                            isExpanded
                                                                ? Icons
                                                                    .keyboard_arrow_up
                                                                : Icons
                                                                    .keyboard_arrow_down,
                                                            color: const Color(
                                                                0xFF94A3B8),
                                                            size: 22,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              // Expanded Subtopics
                                              if (provider.viewMode !=
                                                      'chapter' &&
                                                  isExpanded) ...[
                                                const Divider(
                                                    height: 1,
                                                    color: Colors.transparent),
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8.0,
                                                      vertical: 6.0),
                                                  child: Column(
                                                    children: (subTopics.entries
                                                            .toList()
                                                          ..sort((a, b) =>
                                                              _compareSubTopics(
                                                                  topicTitle,
                                                                  a.key,
                                                                  b.key,
                                                                  provider
                                                                      .subTopicOrders)))
                                                        .map((entry) {
                                                      final subTitle =
                                                          entry.key;
                                                      final subQs = entry.value;

                                                      final int subTotal =
                                                          subQs.length;
                                                      final int subCorrect =
                                                          subQs
                                                              .where((q) =>
                                                                  q.isSolved &&
                                                                  q.userAnswer ==
                                                                      q.correct)
                                                              .length;
                                                      final int subIncorrect =
                                                          subQs
                                                              .where((q) =>
                                                                  q.isSolved &&
                                                                  q.userAnswer !=
                                                                      q.correct)
                                                              .length;
                                                      final int subSolved =
                                                          subCorrect +
                                                              subIncorrect;
                                                      final int subPct = subTotal >
                                                              0
                                                          ? ((subSolved /
                                                                      subTotal) *
                                                                  100)
                                                              .round()
                                                          : 0;

                                                      return GestureDetector(
                                                        onTap: () {
                                                          provider
                                                              .startPracticeSession(
                                                                  subQs);
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) =>
                                                                  const QuestionViewerScreen(),
                                                            ),
                                                          );
                                                        },
                                                        behavior:
                                                            HitTestBehavior
                                                                .opaque,
                                                        child: Directionality(
                                                          textDirection:
                                                              TextDirection
                                                                  .ltr, // Enforce LTR layout for subtopics
                                                          child: Container(
                                                            margin:
                                                                const EdgeInsets
                                                                    .only(
                                                                    bottom: 5),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        14,
                                                                    vertical:
                                                                        10), // Tighter padding
                                                            decoration:
                                                                BoxDecoration(
                                                              color: provider
                                                                      .isDarkTheme
                                                                  ? AppColors
                                                                      .surface2
                                                                  : const Color(
                                                                      0xFFF5F3FF), // Soft lavender/purple tint to match the app theme
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16),
                                                              border:
                                                                  Border.all(
                                                                color: provider
                                                                        .isDarkTheme
                                                                    ? AppColors
                                                                        .border
                                                                    : const Color(
                                                                            0xFF4F46E5)
                                                                        .withValues(
                                                                            alpha:
                                                                                0.12),
                                                                width: 1,
                                                              ),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: provider
                                                                          .isDarkTheme
                                                                      ? Colors
                                                                          .transparent
                                                                      : const Color(
                                                                              0xFF4F46E5)
                                                                          .withValues(
                                                                              alpha: 0.03),
                                                                  blurRadius: 8,
                                                                  offset:
                                                                      const Offset(
                                                                          0, 3),
                                                                ),
                                                              ],
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                // 1. Circular Progress Indicator (on the far left)
                                                                Stack(
                                                                  alignment:
                                                                      Alignment
                                                                          .center,
                                                                  children: [
                                                                    SizedBox(
                                                                      width: 38,
                                                                      height:
                                                                          38,
                                                                      child:
                                                                          CircularProgressIndicator(
                                                                        value: subPct /
                                                                            100,
                                                                        strokeWidth:
                                                                            3.5,
                                                                        backgroundColor: provider.isDarkTheme
                                                                            ? AppColors.surface
                                                                            : Colors.white, // White track inside grey container
                                                                        valueColor: AlwaysStoppedAnimation<
                                                                            Color>(provider
                                                                                .isDarkTheme
                                                                            ? const Color(0xFF6047D6)
                                                                            : const Color(0xFF3525CD)),
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      '$subPct%',
                                                                      style:
                                                                          TextStyle(
                                                                        color: provider.isDarkTheme
                                                                            ? AppColors.text
                                                                            : const Color(0xFF1E293B),
                                                                        fontSize:
                                                                            9.5,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontFamily:
                                                                            'Inter',
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(
                                                                    width: 12),

                                                                // 2. Middle Content Column (Title & Stats Row)
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      // Subtopic Title
                                                                      Text(
                                                                        subTitle,
                                                                        style:
                                                                            TextStyle(
                                                                          color: provider.isDarkTheme
                                                                              ? AppColors.text
                                                                              : const Color(0xFF1E293B),
                                                                          fontSize:
                                                                              12,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                          fontFamily:
                                                                              'Cairo',
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              6),

                                                                      // Stats Row (Count + Spacer + Badges on far right)
                                                                      Row(
                                                                        children: [
                                                                          Text(
                                                                            'سؤال $subSolved / $subTotal',
                                                                            style:
                                                                                TextStyle(
                                                                              color: provider.isDarkTheme ? AppColors.textMuted : const Color(0xFF64748B),
                                                                              fontSize: 11,
                                                                              fontWeight: FontWeight.bold,
                                                                              fontFamily: 'Cairo',
                                                                            ),
                                                                          ),
                                                                          const Spacer(), // Pushes correct/incorrect badges to the far right!

                                                                          // Soft Green Badge (Correct)
                                                                          Container(
                                                                            padding:
                                                                                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                            decoration:
                                                                                BoxDecoration(
                                                                              color: provider.isDarkTheme ? const Color(0x1F10B981) : const Color(0xFFECFDF5),
                                                                              borderRadius: BorderRadius.circular(6),
                                                                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.24)),
                                                                            ),
                                                                            child:
                                                                                Row(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              children: [
                                                                                const Icon(Icons.check, color: Color(0xFF10B981), size: 11),
                                                                                const SizedBox(width: 3),
                                                                                Text(
                                                                                  '$subCorrect',
                                                                                  style: const TextStyle(
                                                                                    color: Color(0xFF047857),
                                                                                    fontSize: 10,
                                                                                    fontWeight: FontWeight.bold,
                                                                                    fontFamily: 'Inter',
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                          const SizedBox(
                                                                              width: 6),

                                                                          // Soft Red Badge (Incorrect)
                                                                          Container(
                                                                            padding:
                                                                                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                            decoration:
                                                                                BoxDecoration(
                                                                              color: provider.isDarkTheme ? const Color(0x1FEF4444) : const Color(0xFFFEF2F2),
                                                                              borderRadius: BorderRadius.circular(6),
                                                                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.24)),
                                                                            ),
                                                                            child:
                                                                                Row(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              children: [
                                                                                const Icon(Icons.close, color: Color(0xFFEF4444), size: 11),
                                                                                const SizedBox(width: 3),
                                                                                Text(
                                                                                  '$subIncorrect',
                                                                                  style: const TextStyle(
                                                                                    color: Color(0xFFB91C1C),
                                                                                    fontSize: 10,
                                                                                    fontWeight: FontWeight.bold,
                                                                                    fontFamily: 'Inter',
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderTopicsModal extends StatefulWidget {
  final String subjectName;
  final Map<String, Map<String, List<Question>>> topicsGroup;

  const _ReorderTopicsModal({
    required this.subjectName,
    required this.topicsGroup,
  });

  @override
  State<_ReorderTopicsModal> createState() => _ReorderTopicsModalState();
}

class _ReorderTopicsModalState extends State<_ReorderTopicsModal> {
  late List<String> _topics;
  late Map<String, List<String>> _subTopicsMap;
  final Set<String> _expandedTopics = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AppProvider>(context, listen: false);

    _topics = widget.topicsGroup.keys.toList()
      ..sort((a, b) => _compareTopics(a, b, provider.topicOrders));

    _subTopicsMap = {};
    for (final topic in _topics) {
      final subs = (widget.topicsGroup[topic]?.keys.toList() ?? [])
        ..sort((a, b) =>
            _compareSubTopics(topic, a, b, provider.subTopicOrders));
      _subTopicsMap[topic] = subs;
    }
  }

  int _compareTopics(String a, String b, Map<String, int> topicOrders) {
    final orderA = topicOrders[a];
    final orderB = topicOrders[b];
    if (orderA != null && orderB != null) {
      final comp = orderA.compareTo(orderB);
      if (comp != 0) return comp;
    } else if (orderA != null) {
      return -1;
    } else if (orderB != null) {
      return 1;
    }
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  int _compareSubTopics(
      String topic, String a, String b, Map<String, int> subTopicOrders) {
    final orderA = subTopicOrders['$topic:$a'];
    final orderB = subTopicOrders['$topic:$b'];
    if (orderA != null && orderB != null) {
      final comp = orderA.compareTo(orderB);
      if (comp != 0) return comp;
    } else if (orderA != null) {
      return -1;
    } else if (orderB != null) {
      return 1;
    }
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  Future<void> _handleSave() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final List<Map<String, dynamic>> updates = [];

      for (int i = 0; i < _topics.length; i++) {
        final topic = _topics[i];
        final titleOrder = i + 1;
        final subs = _subTopicsMap[topic] ?? [];

        if (subs.isEmpty) {
          updates.add({
            'name': topic,
            'sub_title': null,
            'title_order': titleOrder,
            'subtitle_order': 0,
          });
        } else {
          for (int j = 0; j < subs.length; j++) {
            final sub = subs[j];
            final subOrder = j + 1;
            updates.add({
              'name': topic,
              'sub_title': sub,
              'title_order': titleOrder,
              'subtitle_order': subOrder,
            });
          }
        }
      }

      await provider.saveTitlesOrder(
        subjectName: widget.subjectName,
        updates: updates,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ ترتيب العناوين بنجاح!',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل حفظ الترتيب: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.borderBright
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إعادة ترتيب العناوين (Drag & Drop)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.text : const Color(0xFF1E1E50),
                    ),
                  ),
                  const Icon(Icons.drag_indicator_rounded,
                      color: Color(0xFFA78BFA), size: 22),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'اسحب العناوين للأعلى أو الأسفل لترتيبها، وافتح العنوان لترتيب عناوين الفرعية.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: isDark
                      ? AppColors.textMuted
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ReorderableListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _topics.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _topics.removeAt(oldIndex);
                      _topics.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final topic = _topics[index];
                    final subs = _subTopicsMap[topic] ?? [];
                    final isExpanded = _expandedTopics.contains(topic);

                    return Container(
                      key: ValueKey('topic_$topic'),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surface2 : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppColors.border
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.reorder_rounded,
                                  color: isDark
                                      ? AppColors.textMuted
                                      : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: const Color(0xFFA78BFA)
                                      .withValues(alpha: 0.15),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFA78BFA),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              topic,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.text
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            subtitle: subs.isNotEmpty
                                ? Text(
                                    '${subs.length} عناوين فرعية',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: isDark
                                          ? AppColors.textMuted
                                          : const Color(0xFF64748B),
                                    ),
                                  )
                                : null,
                            trailing: subs.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: const Color(0xFFA78BFA),
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedTopics.remove(topic);
                                        } else {
                                          _expandedTopics.add(topic);
                                        }
                                      });
                                    },
                                  )
                                : null,
                          ),
                          if (subs.isNotEmpty && isExpanded) ...[
                            Divider(
                              height: 1,
                              color: isDark
                                  ? AppColors.border
                                  : const Color(0xFFF1F5F9),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surface
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: subs.length,
                                  onReorder: (oldSubIndex, newSubIndex) {
                                    setState(() {
                                      if (newSubIndex > oldSubIndex) {
                                        newSubIndex -= 1;
                                      }
                                      final subItem =
                                          subs.removeAt(oldSubIndex);
                                      subs.insert(newSubIndex, subItem);
                                    });
                                  },
                                  itemBuilder: (context, subIndex) {
                                    final sub = subs[subIndex];
                                    return Container(
                                      key: ValueKey('sub_${topic}_$sub'),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      margin: const EdgeInsets.only(bottom: 4),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? AppColors.surface2
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark
                                              ? AppColors.border
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.drag_handle_rounded,
                                            color: isDark
                                                ? AppColors.textMuted
                                                : const Color(0xFFCBD5E1),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${subIndex + 1}.',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFA78BFA),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              sub,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? AppColors.text
                                                    : const Color(0xFF334155),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.surface3
                            : const Color(0xFFE2E8F0),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 46),
                      ),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textDim
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B4EFF),
                        disabledBackgroundColor: isDark
                            ? AppColors.surface3
                            : const Color(0xFFE5E7EB),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 46),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'حفظ الترتيب',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

