import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'workspace_state_provider.dart';
import 'mobile_slide_page.dart';
import '../../../../core/services/image_cache_service.dart';
import '../../../practice/presentation/widgets/audio_explanation_player.dart';

class SlidePaper extends StatelessWidget {
  final WorkspaceSlide slide;
  final bool compact;
  final bool isDark;
  final bool studyMode;
  final bool isCurrent;
  final bool isThumbnail;
  final SlideWorkspaceController? controller;
  final bool? loadRealImage;
  final int? slideIndex;
  /// When provided, the in-slide scroll offset (in canvas logical pixels)
  /// is written here so that the drawing-layer overlay can follow the scroll.
  final ValueNotifier<double>? scrollOffsetNotifier;

  const SlidePaper({
    super.key,
    required this.slide,
    required this.compact,
    required this.isDark,
    required this.studyMode,
    required this.isCurrent,
    this.isThumbnail = false,
    this.controller,
    this.loadRealImage,
    this.slideIndex,
    this.scrollOffsetNotifier,
  });

  bool get _shouldLoadImage {
    // The controller preloads every slide image into the persistent local
    // cache before the page is marked ready. Keeping this unconditional is
    // important: a previously cached slide must not turn back into a
    // placeholder just because it is far from the current slide.
    return loadRealImage ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242039) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3258) : const Color(0xFFE2E0EF),
          width: 1.5,
        ),
        boxShadow: [
          if (isCurrent) ...[
            BoxShadow(
              color: workspacePurple.withValues(alpha: 0.45),
              blurRadius: 28,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: workspacePurple.withValues(alpha: 0.18),
              blurRadius: 56,
              spreadRadius: 10,
            ),
          ] else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Opacity(
              opacity: .035,
              child: Text(
                '.Stagiaire',
                style: TextStyle(
                  fontSize: 118,
                  color: isDark ? const Color(0xFF6F55FF) : workspacePurple,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: BrandTab(isDark: isDark)),
          ),
          if (slide.isHidden)
            Positioned(
              top: 12,
              right: 16,
              child: HiddenSlideBadge(isDark: isDark),
            ),
          Positioned.fill(
            top: 44,
            child: AdaptiveSlideContent(
              slide: slide,
              compact: compact,
              isDark: isDark,
              studyMode: studyMode,
              isThumbnail: isThumbnail,
              loadRealImage: _shouldLoadImage,
              slideIndex: slideIndex,
              scrollOffsetNotifier: scrollOffsetNotifier,
            ),
          ),
        ],
      ),
    );
  }
}

class AdaptiveSlideContent extends StatefulWidget {
  final WorkspaceSlide slide;
  final bool compact;
  final bool isDark;
  final bool studyMode;
  final bool isThumbnail;
  final bool loadRealImage;
  final int? slideIndex;
  final ValueNotifier<double>? scrollOffsetNotifier;

  const AdaptiveSlideContent({
    super.key,
    required this.slide,
    required this.compact,
    required this.isDark,
    required this.studyMode,
    this.isThumbnail = false,
    this.loadRealImage = true,
    this.slideIndex,
    this.scrollOffsetNotifier,
  });

  @override
  State<AdaptiveSlideContent> createState() => _AdaptiveSlideContentState();
}

class _AdaptiveSlideContentState extends State<AdaptiveSlideContent> {
  bool _hasLoadedRealImage = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    if (widget.loadRealImage) {
      _hasLoadedRealImage = true;
    }
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    widget.scrollOffsetNotifier?.value = _scrollController.offset;
  }

  @override
  void didUpdateWidget(covariant AdaptiveSlideContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadRealImage) {
      _hasLoadedRealImage = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateProvider = WorkspaceOutsideStateProvider.of(context);
    final isEditingInPlace = stateProvider != null &&
        widget.slideIndex != null &&
        stateProvider.editingSlideIndex == widget.slideIndex;

    const totalFlex = 3;
    final loadReal = widget.loadRealImage || _hasLoadedRealImage;
    const imageFlex = 1;
    const questionFlex = totalFlex - imageFlex;
    final slide = widget.slide;
    final compact = widget.compact;
    final isDark = widget.isDark;

    return Row(
      children: [
        Expanded(
          flex: imageFlex,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 44 : 56,
              30,
              compact ? 20 : 34,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: loadReal
                        ? SlideImagePanel(imageUrl: slide.imageAsset)
                        : Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1F1C33)
                                  : const Color(0xFFF7F5FE),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF383154)
                                      : const Color(0xFFE6E3F4)),
                            ),
                            child: const Icon(Icons.image_outlined,
                                color: workspaceMuted, size: 54),
                          ),
                  ),
                ),
                if (widget.studyMode &&
                    (slide.title.trim().isNotEmpty ||
                        slide.audioUrl.trim().isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  if (slide.title.trim().isNotEmpty)
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : workspaceInk,
                        fontSize: compact ? 22 : 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  if (slide.audioUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    AudioExplanationPlayer(
                      audioUrl: slide.audioUrl,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 32),
          color: isDark ? const Color(0xFF3C3654) : const Color(0xFFE0DEF1),
        ),
        Expanded(
          flex: questionFlex,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 18,
              12,
              compact ? 32 : 48,
              12,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SelectionArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < slide.questions.length; i++)
                        QuestionBlock(
                          number: i + 1,
                          question: slide.questions[i],
                          isDark: isDark,
                          showAnswer: widget.studyMode,
                          isEditingInPlace: isEditingInPlace,
                          promptController: isEditingInPlace &&
                                  i <
                                      stateProvider
                                          .inPlacePromptControllers.length
                              ? stateProvider.inPlacePromptControllers[i]
                              : null,
                          answerController: isEditingInPlace &&
                                  i <
                                      stateProvider
                                          .inPlaceAnswerControllers.length
                              ? stateProvider.inPlaceAnswerControllers[i]
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SlideImagePanel extends StatefulWidget {
  final String imageUrl;

  const SlideImagePanel({super.key, required this.imageUrl});

  @override
  State<SlideImagePanel> createState() => _SlideImagePanelState();
}

class _SlideImagePanelState extends State<SlideImagePanel> {
  late Future<String?> _imagePath;
  String? _syncPath;

  @override
  void initState() {
    super.initState();
    _syncPath = ImageCacheService().getCachedPathSync(widget.imageUrl);
    _imagePath = _loadImage();
  }

  @override
  void didUpdateWidget(covariant SlideImagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _syncPath = ImageCacheService().getCachedPathSync(widget.imageUrl);
      _imagePath = _loadImage();
    }
  }

  Future<String?> _loadImage() async {
    final url = widget.imageUrl.trim();
    if (url.isEmpty || kIsWeb || !url.startsWith('http')) {
      return url;
    }
    final path = await ImageCacheService().getOrDownload(url);
    if (mounted && path != _syncPath) {
      setState(() {
        _syncPath = path;
      });
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.imageUrl.trim();
    if (imageUrl.isEmpty) return _placeholder();

    if (_syncPath != null &&
        _syncPath!.isNotEmpty &&
        _syncPath != imageUrl &&
        !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(_syncPath!),
          fit: BoxFit.contain,
          cacheWidth: 1100,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _brokenImage(),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _imagePath,
      builder: (context, snapshot) {
        final path = snapshot.data?.trim() ?? _syncPath ?? '';
        final image = path.isNotEmpty && path != imageUrl && !kIsWeb
            ? Image.file(
                File(path),
                fit: BoxFit.contain,
                cacheWidth: 1100,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _brokenImage(),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                cacheWidth: 1100,
                errorBuilder: (_, __, ___) => _brokenImage(),
              );
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: image,
        );
      },
    );
  }

  Widget _placeholder() => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5FE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E3F4)),
        ),
        child:
            const Icon(Icons.image_outlined, color: workspaceMuted, size: 54),
      );

  Widget _brokenImage() => const Center(
        child:
            Icon(Icons.broken_image_outlined, color: workspaceMuted, size: 48),
      );
}

class QuestionBlock extends StatelessWidget {
  final int number;
  final WorkspaceQuestion question;
  final bool isDark;
  final bool showAnswer;
  final bool isEditingInPlace;
  final TextEditingController? promptController;
  final TextEditingController? answerController;

  const QuestionBlock({
    super.key,
    required this.number,
    required this.question,
    required this.isDark,
    required this.showAnswer,
    this.isEditingInPlace = false,
    this.promptController,
    this.answerController,
  });

  @override
  Widget build(BuildContext context) {
    final softLightPurple = isDark
        ? const Color(0xFFC7B8EA).withValues(alpha: 0.55)
        : const Color(0xFFB39DDB).withValues(alpha: 0.65);

    if (isEditingInPlace &&
        promptController != null &&
        answerController != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number.  ',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: promptController,
                    enableInteractiveSelection: true,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Question prompt...',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 28.0),
              child: TextField(
                controller: answerController,
                enableInteractiveSelection: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  color: isDark ? Colors.white : workspaceInk,
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Answer explanation...',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$number.  ${question.prompt}',
              style: TextStyle(
                  color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          const SizedBox(height: 12),
          if (showAnswer && question.answer.trim().isNotEmpty)
            Text(question.answer,
                style: TextStyle(
                    color: isDark ? Colors.white : workspaceInk,
                    fontSize: 20,
                    fontWeight: FontWeight.normal,
                    height: 1.5))
          else
            for (var i = 0; i < question.answerLines; i++)
              Container(
                  height: 2.0,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: softLightPurple,
                    borderRadius: BorderRadius.circular(1),
                  )),
        ],
      ),
    );
  }
}
