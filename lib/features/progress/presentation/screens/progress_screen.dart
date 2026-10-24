import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppProvider>().loadCommunityAverage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = provider.isDarkTheme;
    final palette = _Palette(isDark);
    final subject = provider.selectedSubject ??
        (provider.subjects.isNotEmpty
            ? provider.subjects.first.name
            : 'Internal Medicine');
    final analysis = _AnalysisData.fromProvider(provider, subject);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: palette.bg,
        body: RefreshIndicator(
          color: const Color(0xFF6B4EFF),
          backgroundColor: palette.card,
          displacement: 40,
          onRefresh: () => provider.initializeData(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 132,
              elevation: 0,
              backgroundColor: palette.deep,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => provider.setCurrentTab(2),
              ),
              titleSpacing: 0,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Analysis',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900)),
                  Text('Performance Analysis',
                      style: TextStyle(
                          color: Color(0xFFE8E2FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0x26FFFFFF),
                    child: Icon(Icons.menu_book_rounded, color: Colors.white),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [palette.soft, palette.deep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(22)),
                  ),
                  padding:
                      const EdgeInsets.fromLTRB(18, kToolbarHeight + 6, 18, 8),
                  alignment: Alignment.bottomCenter,
                  child: _SubjectPicker(
                    palette: palette,
                    subject: subject,
                    subjects: {
                      ...provider.filteredSubjects.map((e) => e.name),
                      subject,
                    }.toList(),
                    onSelected: provider.selectSubject,
                    compactOnHeader: true,
                  ),
                ),
              ),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(22),
                      bottomRight: Radius.circular(22))),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 104),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Last updated: Today',
                          style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          provider.initializeData();
                          provider.loadCommunityAverage(force: true);
                        },
                        child: Icon(Icons.refresh_rounded,
                            color: palette.muted, size: 17),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _SectionTitle('Overview Stats', palette),
                    const SizedBox(height: 12),
                    _StatsGrid(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Progress & Accuracy', palette),
                    const SizedBox(height: 12),
                    _ProgressCard(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Topics Analysis', palette),
                    const SizedBox(height: 12),
                    _TopicList(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _StrengthWeakness(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Time Analysis', palette),
                    const SizedBox(height: 12),
                    _TimeCard(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Source Analysis', palette),
                    const SizedBox(height: 12),
                    _SourceList(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Mistakes Analysis', palette),
                    const SizedBox(height: 12),
                    _MistakesCard(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    if (analysis.communityAccuracy != null) ...[
                      _SectionTitle('Comparison', palette),
                      const SizedBox(height: 12),
                      _ComparisonCard(data: analysis, palette: palette),
                      const SizedBox(height: 24),
                    ],
                    _SectionTitle('Recommendations', palette),
                    const SizedBox(height: 12),
                    _Recommendations(data: analysis, palette: palette),
                    const SizedBox(height: 24),
                    _SectionTitle('Achievements', palette),
                    const SizedBox(height: 12),
                    _Achievements(data: analysis, palette: palette),
                    const SizedBox(height: 14),
                    _AiCard(palette: palette),
                  ],
                ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _Palette {
  final bool isDark;
  const _Palette(this.isDark);
  Color get bg => isDark ? AppColors.bg : const Color(0xFFF8F9FE);
  Color get card => isDark ? AppColors.surface : Colors.white;
  Color get card2 => isDark ? AppColors.surface2 : Colors.white;
  Color get track => isDark ? AppColors.surface3 : const Color(0xFFE9E7F2);
  Color get border =>
      isDark ? AppColors.border : AppColors.indigo.withValues(alpha: .13);
  Color get text => isDark ? AppColors.text : const Color(0xFF1E1E50);
  Color get muted => isDark ? AppColors.textMuted : const Color(0xFF7B7797);
  Color get accent => AppColors.indigo;
  Color get deep => isDark ? const Color(0xFF4930B6) : const Color(0xFF5B3EEF);
  Color get soft => isDark ? const Color(0xFF6047D6) : const Color(0xFF8B6EFF);
  Color get shadow => isDark
      ? Colors.black.withValues(alpha: .18)
      : AppColors.indigo.withValues(alpha: .05);
}

BoxDecoration _card(_Palette p, {double radius = 16}) => BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border, width: 1.1),
      boxShadow: [
        BoxShadow(color: p.shadow, blurRadius: 12, offset: const Offset(0, 4))
      ],
    );

class _SubjectPicker extends StatelessWidget {
  final _Palette palette;
  final String subject;
  final List<String> subjects;
  final ValueChanged<String> onSelected;
  final bool compactOnHeader;
  const _SubjectPicker(
      {required this.palette,
      required this.subject,
      required this.subjects,
      required this.onSelected,
      this.compactOnHeader = false});

  @override
  Widget build(BuildContext context) => Container(
        height: compactOnHeader ? 48 : 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: compactOnHeader
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: .34)),
              )
            : _card(palette),
        child: Row(children: [
          _IconBox(
              icon: Icons.auto_stories_rounded,
              color: Colors.white,
              palette: palette,
              onHeader: compactOnHeader),
          const SizedBox(width: 12),
          Expanded(
              child: Text(subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: compactOnHeader ? Colors.white : palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900))),
          PopupMenuButton<String>(
            color: palette.card2,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: compactOnHeader ? Colors.white : palette.text),
            onSelected: onSelected,
            itemBuilder: (_) => subjects
                .map((s) => PopupMenuItem(
                    value: s,
                    child: Text(s, style: TextStyle(color: palette.text))))
                .toList(),
          ),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final _Palette palette;
  const _SectionTitle(this.title, this.palette);
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(title,
                style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900))),
      ]);
}

class _StatsGrid extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _StatsGrid({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    final items = [
      _Stat('Total Questions', '${data.total}', Icons.assignment_outlined,
          palette.accent),
      _Stat('Answered', '${data.answered}', Icons.check_circle_outline_rounded,
          palette.accent),
      _Stat('Unanswered', '${math.max(0, data.total - data.answered)}',
          Icons.radio_button_unchecked_rounded, palette.accent),
      _Stat('Correct', '${data.correct}', Icons.done_rounded, AppColors.green),
      _Stat(
          'Incorrect', '${data.incorrect}', Icons.close_rounded, AppColors.red),
      _Stat('Accuracy', '${data.accuracy.round()}%',
          Icons.track_changes_rounded, palette.accent),
    ];
    return Column(children: [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .96),
        itemBuilder: (_, i) => _StatCard(stat: items[i], palette: palette),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _WideStat(
                icon: Icons.trending_up_rounded,
                label: 'Progress',
                value: '${data.progress.round()}%',
                color: palette.accent,
                palette: palette)),
        const SizedBox(width: 10),
        Expanded(
            child: _WideStat(
                icon: Icons.local_fire_department_rounded,
                label: 'Streak',
                value: '${data.streak} Days',
                color: AppColors.amber,
                palette: palette)),
      ]),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final _Stat stat;
  final _Palette palette;
  const _StatCard({required this.stat, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: _card(palette, radius: 15),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _IconBox(
                  icon: stat.icon,
                  color: stat.color,
                  palette: palette,
                  size: 34),
              Text(stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              Text(stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ]),
      );
}

class _WideStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final _Palette palette;
  const _WideStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _card(palette, radius: 15),
        child: Row(children: [
          _IconBox(icon: icon, color: color, palette: palette, size: 36),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: palette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
          Text(value,
              style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}

class _ProgressCard extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _ProgressCard({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(palette, radius: 18),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: _Ring(
                    title: 'Progress',
                    value: data.progress,
                    caption:
                        '${data.answered} / ${data.total}\nQuestions Answered',
                    palette: palette)),
            Expanded(
                child: _Ring(
                    title: 'Accuracy',
                    value: data.accuracy,
                    caption:
                        '${data.correct} / ${math.max(1, data.answered)}\nCorrect Answers',
                    palette: palette)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _Pill(
                    text:
                        data.progress >= 50 ? 'Halfway there!' : 'Keep going!',
                    color: palette.accent,
                    palette: palette)),
            const SizedBox(width: 10),
            Expanded(
                child: _Pill(
                    text: data.answered == 0
                        ? 'Start solving'
                        : (data.accuracy >= 70 ? 'Good job!' : 'Review more'),
                    color: AppColors.green,
                    palette: palette)),
          ]),
        ]),
      );
}

class _Ring extends StatelessWidget {
  final String title;
  final double value;
  final String caption;
  final _Palette palette;
  const _Ring(
      {required this.title,
      required this.value,
      required this.caption,
      required this.palette});
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
            width: 104,
            height: 104,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                  width: 104,
                  height: 104,
                  child: CircularProgressIndicator(
                      value: (value / 100).clamp(0, 1),
                      strokeWidth: 11,
                      color: palette.accent,
                      backgroundColor: palette.track,
                      strokeCap: StrokeCap.round)),
              Text('${value.round()}%',
                  style: TextStyle(
                      color: palette.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
            ])),
        const SizedBox(height: 8),
        Text(title,
            style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(caption,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: palette.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.35)),
      ]);
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final _Palette palette;
  const _Pill({required this.text, required this.color, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w900)),
      );
}

class _TopicList extends StatefulWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _TopicList({required this.data, required this.palette});
  @override
  State<_TopicList> createState() => _TopicListState();
}

class _TopicListState extends State<_TopicList> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final all = widget.data.topics;
    final topics = _expanded ? all : all.take(5).toList();
    if (topics.isEmpty) return _EmptyCard('No topics loaded yet.', palette);
    return Column(children: [
      for (final t in topics)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TopicTile(topic: t, palette: palette)),
      if (all.length > 5)
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: _card(palette, radius: 15),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_expanded ? 'Show less' : 'View all topics',
                  style: TextStyle(
                      color: palette.accent, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: palette.accent),
            ]),
          ),
        ),
    ]);
  }
}

class _TopicTile extends StatelessWidget {
  final _Topic topic;
  final _Palette palette;
  const _TopicTile({required this.topic, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _card(palette, radius: 15),
        child: Row(children: [
          _IconBox(
              icon: Icons.folder_rounded,
              color: palette.accent,
              palette: palette,
              size: 40),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(topic.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                Row(children: [
                  Text('${topic.total} Qs',
                      style: TextStyle(
                          color: palette.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _Bar(
                          value: topic.progress,
                          color: palette.accent,
                          palette: palette)),
                  const SizedBox(width: 8),
                  Text('${topic.correct}',
                      style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Text('${topic.incorrect}',
                      style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ]),
              ])),
          const SizedBox(width: 8),
          _PercentBadge(value: topic.accuracy, palette: palette),
        ]),
      );
}

class _StrengthWeakness extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _StrengthWeakness({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    final strengths = data.topics.where((t) => t.answered > 0).toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final weaknesses = data.topics.where((t) => t.answered > 0).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return Row(children: [
      Expanded(
          child: _MiniPanel(
              title: 'Strengths',
              color: AppColors.green,
              icon: Icons.track_changes_rounded,
              topics: strengths.take(3).toList(),
              palette: palette)),
      const SizedBox(width: 10),
      Expanded(
          child: _MiniPanel(
              title: 'Weaknesses',
              color: AppColors.red,
              icon: Icons.trending_up_rounded,
              topics: weaknesses.take(3).toList(),
              palette: palette)),
    ]);
  }
}

class _MiniPanel extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<_Topic> topics;
  final _Palette palette;
  const _MiniPanel(
      {required this.title,
      required this.color,
      required this.icon,
      required this.topics,
      required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: _card(palette, radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900))),
            _IconBox(icon: icon, color: color, palette: palette, size: 34),
          ]),
          const SizedBox(height: 12),
          if (topics.isEmpty)
            Text('Not enough data',
                style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          for (final t in topics)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    child: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: palette.text,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700))),
                Text('${t.accuracy.round()}%',
                    style: TextStyle(
                        color: palette.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ]),
            ),
        ]),
      );
}

class _TimeCard extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _TimeCard({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    final days = data.daily;
    if (days.isEmpty) {
      return _EmptyCard(
          'No activity yet. Solve questions to see your daily chart.', palette);
    }
    final maxTotal = days.fold<int>(1, (m, d) => math.max(m, d.total));
    final selected = days.last;
    return Column(children: [
      Container(
        height: 210,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: _card(palette, radius: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child:
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                    child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (d.total / maxTotal).clamp(.08, 1),
                          child: Container(
                              width: 12,
                              decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(8))),
                        ))),
                const SizedBox(height: 8),
                Text(d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ]),
            )),
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _card(palette, radius: 15),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _SmallMetric(selected.label, '', palette),
          _SmallMetric('Answered', '${selected.total}', palette),
          _SmallMetric('Correct', '${selected.correct}', palette),
          _SmallMetric('Accuracy', '${selected.accuracy.round()}%', palette),
        ]),
      ),
    ]);
  }
}

class _SourceList extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _SourceList({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    if (data.sources.isEmpty) {
      return _EmptyCard('No source data for this subject.', palette);
    }
    final sources = data.sources.take(4).toList();
    return Column(children: [
      for (final s in sources)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SourceTile(source: s, palette: palette))
    ]);
  }
}

class _SourceTile extends StatelessWidget {
  final _Source source;
  final _Palette palette;
  const _SourceTile({required this.source, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _card(palette, radius: 15),
        child: Row(children: [
          _IconBox(
              icon: Icons.description_rounded,
              color: palette.accent,
              palette: palette,
              size: 40),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${source.total} Qs',
                    style: TextStyle(
                        color: palette.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                _Bar(
                    value: source.progress,
                    color: palette.accent,
                    palette: palette),
              ])),
          const SizedBox(width: 10),
          Text('${source.accuracy.round()}%',
              style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}

class _MistakesCard extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _MistakesCard({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    if (data.mistakes.isEmpty)
      return _EmptyCard('No mistakes yet. Nice work.', palette);
    final maxCount = data.mistakes.fold<int>(1, (m, e) => math.max(m, e.count));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(palette, radius: 18),
      child: Column(children: [
        for (final m in data.mistakes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(m.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w800))),
                Text('${m.count}',
                    style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 7),
              _Bar(
                  value: m.count / maxCount * 100,
                  color: AppColors.red,
                  palette: palette),
            ]),
          ),
      ]),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _ComparisonCard({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [palette.soft, palette.deep]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: palette.accent.withValues(alpha: .18),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(children: [
              Expanded(
                  child: _CompareSide(
                      title: 'You', value: '${data.accuracy.round()}%')),
              Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      shape: BoxShape.circle),
                  child: const Text('VS.',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900))),
              Expanded(
                  child: _CompareSide(
                      title: 'Average',
                      value: '${(data.communityAccuracy ?? 0).round()}%')),
            ]),
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: palette.card,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18))),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Answered: ${data.answered}',
                      style: TextStyle(
                          color: palette.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                  Container(width: 1, height: 18, color: palette.border),
                  Text(
                      data.answered == 0
                          ? 'Solve questions to compare'
                          : () {
                              final diff = (data.accuracy -
                                      (data.communityAccuracy ?? 0))
                                  .round();
                              return diff >= 0
                                  ? 'Above average +$diff%'
                                  : 'Below average $diff%';
                            }(),
                      style: TextStyle(
                          color: palette.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ]),
          ),
        ]),
      );
}

class _CompareSide extends StatelessWidget {
  final String title;
  final String value;
  const _CompareSide({required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900)),
        const Text('Accuracy',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]);
}

class _Recommendations extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _Recommendations({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final r in data.recommendations.take(4))
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: _card(palette, radius: 15),
                child: Row(children: [
                  _IconBox(
                      icon: Icons.verified_outlined,
                      color: AppColors.green,
                      palette: palette,
                      size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(r,
                          style: TextStyle(
                              color: palette.text,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25))),
                  Icon(Icons.chevron_right_rounded, color: palette.muted),
                ]),
              )),
      ]);
}

class _Achievements extends StatelessWidget {
  final _AnalysisData data;
  final _Palette palette;
  const _Achievements({required this.data, required this.palette});
  @override
  Widget build(BuildContext context) {
    final items = [
      _Ach('Question Master', 'Answered ${data.answered} questions',
          Icons.workspace_premium_outlined, AppColors.red,
          earned: data.answered >= 100),
      _Ach('Accuracy Pro', 'Achieved ${data.accuracy.round()}% accuracy',
          Icons.check_circle_outline, Colors.blue,
          earned: data.answered >= 20 && data.accuracy >= 70),
      _Ach('Study Streak', '${data.streak} days in a row',
          Icons.star_border_rounded, AppColors.amber,
          earned: data.streak >= 3),
      _Ach('Halfway Hero', 'Reached ${data.progress.round()}% progress',
          Icons.shield_outlined, palette.accent,
          earned: data.progress >= 50),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.35),
      itemBuilder: (_, i) => Opacity(
        opacity: items[i].earned ? 1 : .5,
        child: Container(
        padding: const EdgeInsets.all(11),
        decoration: _card(palette, radius: 15),
        child: Row(children: [
          _IconBox(
              icon: items[i].icon,
              color: items[i].color,
              palette: palette,
              size: 34),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(items[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(items[i].subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600)),
              ])),
        ]),
        ),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  final _Palette palette;
  const _AiCard({required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [palette.soft, palette.deep]),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text('AI Topic Analysis',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('Get AI insights for any topic',
                    style: TextStyle(
                        color: Color(0xFFE8E2FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text('NEW',
                  style: TextStyle(
                      color: palette.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900))),
        ]),
      );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final _Palette palette;
  final bool onHeader;
  const _IconBox(
      {required this.icon,
      required this.color,
      required this.palette,
      this.size = 38,
      this.onHeader = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onHeader
              ? Colors.white.withValues(alpha: .18)
              : color.withValues(alpha: palette.isDark ? .18 : .10),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color, size: size * .52),
      );
}

class _Bar extends StatelessWidget {
  final double value;
  final Color color;
  final _Palette palette;
  const _Bar({required this.value, required this.color, required this.palette});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
            minHeight: 4.5,
            value: (value / 100).clamp(0, 1),
            color: color,
            backgroundColor: palette.track),
      );
}

class _PercentBadge extends StatelessWidget {
  final double value;
  final _Palette palette;
  const _PercentBadge({required this.value, required this.palette});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(12)),
        child: Text('${value.round()}%',
            style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      );
}

class _SmallMetric extends StatelessWidget {
  final String label;
  final String value;
  final _Palette palette;
  const _SmallMetric(this.label, this.value, this.palette);
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            style: TextStyle(
                color: value.isEmpty ? palette.text : palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
        if (value.isNotEmpty)
          Text(value,
              style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
      ]);
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final _Palette palette;
  const _EmptyCard(this.text, this.palette);
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _card(palette),
      child: Text(text,
          style: TextStyle(color: palette.muted, fontWeight: FontWeight.w700)));
}

class _Stat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);
}

class _Ach {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool earned;
  const _Ach(this.title, this.subtitle, this.icon, this.color,
      {this.earned = true});
}

class _AnalysisData {
  final String subject;
  final int total;
  final int answered;
  final int correct;
  final int incorrect;
  final double accuracy;
  final double progress;
  final int streak;
  final List<_Topic> topics;
  final List<_Source> sources;
  final List<_Day> daily;
  final List<_Mistake> mistakes;
  final double? communityAccuracy;

  const _AnalysisData(
      {required this.subject,
      required this.total,
      required this.answered,
      required this.correct,
      required this.incorrect,
      required this.accuracy,
      required this.progress,
      required this.streak,
      required this.topics,
      required this.sources,
      required this.daily,
      required this.mistakes,
      this.communityAccuracy});

  factory _AnalysisData.fromProvider(AppProvider provider, String subject) {
    final questions =
        provider.questions.where((q) => q.subject == subject).toList();
    final subjectMatches =
        provider.subjects.where((s) => s.name == subject).toList();
    final total = questions.isNotEmpty
        ? questions.length
        : (subjectMatches.isEmpty ? 0 : subjectMatches.first.totalQuestions);
    final ids = questions.map((q) => q.id.toString()).toSet();
    // Only answers of the questions shown to this student (stage + university);
    // before the questions are loaded, fall back to the subject name.
    final answerEntries = provider.userAnswers.entries.where((e) {
      final value = e.value;
      if (value is! Map) return false;
      return ids.isNotEmpty ? ids.contains(e.key) : value['subject'] == subject;
    }).toList();
    final answerMap = <String, Map>{
      for (final e in answerEntries) e.key: e.value as Map
    };
    final answered = answerEntries.length;
    final correct = answerEntries
        .where((e) => (e.value as Map)['is_correct'] == true)
        .length;
    final incorrect = math.max(0, answered - correct);
    final accuracy = answered == 0 ? 0.0 : correct / answered * 100;
    final progress = total == 0 ? 0.0 : answered / total * 100;

    return _AnalysisData(
      subject: subject,
      total: total,
      answered: answered,
      correct: correct,
      incorrect: incorrect,
      accuracy: accuracy,
      progress: progress.clamp(0, 100),
      streak: _streak(provider.userAnswers.values),
      topics: _topics(questions, answerMap),
      sources: _sources(questions, answerMap),
      daily: _daily(answerMap),
      mistakes: _mistakes(questions, answerMap),
      communityAccuracy: provider.communityAvgAccuracy,
    );
  }

  List<String> get recommendations {
    final weak = topics.where((t) => t.answered > 0).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return [
      if (answered == 0)
        'Start solving questions to get personalised recommendations.',
      if (weak.isNotEmpty && weak.first.accuracy < 70)
        'Increase your accuracy in ${weak.first.name}. Focus on weak topics and review explanations.',
      if (answered > 0 && streak < 3)
        'Solve more questions daily. Keep the streak going.',
      if (mistakes.isNotEmpty)
        'Review ${mistakes.first.topic} mistakes. ${mistakes.first.count} incorrect answers need more practice.',
      if (answered > 0 && accuracy >= 70)
        'Great work. Keep it up and protect your progress.',
    ];
  }

  static List<_Topic> _topics(
      List<dynamic> questions, Map<String, Map> answers) {
    final grouped = <String, List<dynamic>>{};
    for (final q in questions) {
      grouped.putIfAbsent(_clean(q.topic), () => []).add(q);
    }
    final list = grouped.entries
        .map((e) => _Topic.fromQuestions(e.key, e.value, answers))
        .toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  static List<_Source> _sources(
      List<dynamic> questions, Map<String, Map> answers) {
    final grouped = <String, List<dynamic>>{};
    for (final q in questions) {
      final ref = _clean(q.ref);
      if (ref != 'Unknown') grouped.putIfAbsent(ref, () => []).add(q);
    }
    final list = grouped.entries
        .map((e) => _Source.fromQuestions(e.key, e.value, answers))
        .toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  static List<_Day> _daily(Map<String, Map> answers) {
    final map = <DateTime, _MutableDay>{};
    for (final a in answers.values) {
      final parsed =
          DateTime.tryParse(a['answered_at']?.toString() ?? '')?.toLocal();
      if (parsed == null) continue;
      final key = DateTime(parsed.year, parsed.month, parsed.day);
      final item = map.putIfAbsent(
          key, () => _MutableDay('${key.month}/${key.day}'));
      item.total++;
      if (a['is_correct'] == true) item.correct++;
    }
    final keys = map.keys.toList()..sort();
    final last = keys.length > 7 ? keys.sublist(keys.length - 7) : keys;
    return [for (final k in last) map[k]!.toDay()];
  }

  static List<_Mistake> _mistakes(
      List<dynamic> questions, Map<String, Map> answers) {
    final counts = <String, int>{};
    for (final q in questions) {
      if (answers[q.id.toString()]?['is_correct'] == false) {
        final topic = _clean(q.topic);
        counts[topic] = (counts[topic] ?? 0) + 1;
      }
    }
    final list = counts.entries.map((e) => _Mistake(e.key, e.value)).toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  /// Consecutive days with at least one answer (all subjects). Today may still be
  /// empty (the day is not over), but a fully missed day resets the streak to 0.
  static int _streak(Iterable<dynamic> answers) {
    final days = <int>{};
    for (final a in answers) {
      if (a is! Map) continue;
      final d =
          DateTime.tryParse(a['answered_at']?.toString() ?? '')?.toLocal();
      if (d == null) continue;
      days.add(DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
    }
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(day.millisecondsSinceEpoch)) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var streak = 0;
    while (days.contains(day.millisecondsSinceEpoch)) {
      streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  static String _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? 'Unknown' : text;
  }
}

class _Topic {
  final String name;
  final int total;
  final int answered;
  final int correct;
  const _Topic(
      {required this.name,
      required this.total,
      required this.answered,
      required this.correct});
  factory _Topic.fromQuestions(
      String name, List<dynamic> questions, Map<String, Map> answers) {
    final answered =
        questions.where((q) => answers.containsKey(q.id.toString())).length;
    final correct = questions
        .where((q) => answers[q.id.toString()]?['is_correct'] == true)
        .length;
    return _Topic(
        name: name,
        total: questions.length,
        answered: answered,
        correct: correct);
  }
  int get incorrect => math.max(0, answered - correct);
  double get accuracy => answered == 0 ? 0 : correct / answered * 100;
  double get progress => total == 0 ? 0 : answered / total * 100;
}

class _Source {
  final String name;
  final int total;
  final int answered;
  final int correct;
  const _Source(
      {required this.name,
      required this.total,
      required this.answered,
      required this.correct});
  factory _Source.fromQuestions(
      String name, List<dynamic> questions, Map<String, Map> answers) {
    final answered =
        questions.where((q) => answers.containsKey(q.id.toString())).length;
    final correct = questions
        .where((q) => answers[q.id.toString()]?['is_correct'] == true)
        .length;
    return _Source(
        name: name,
        total: questions.length,
        answered: answered,
        correct: correct);
  }
  double get progress => total == 0 ? 0 : answered / total * 100;
  double get accuracy => answered == 0 ? 0 : correct / answered * 100;
}

class _Day {
  final String label;
  final int total;
  final int correct;
  const _Day(this.label, this.total, this.correct);
  double get accuracy => total == 0 ? 0 : correct / total * 100;
}

class _MutableDay {
  final String label;
  int total = 0;
  int correct = 0;
  _MutableDay(this.label);
  _Day toDay() => _Day(label, total, correct);
}

class _Mistake {
  final String topic;
  final int count;
  const _Mistake(this.topic, this.count);
}
