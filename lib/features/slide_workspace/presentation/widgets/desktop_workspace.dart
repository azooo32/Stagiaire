import 'package:flutter/material.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'workspace_state_provider.dart';
import 'slide_pages_list.dart';
import 'mobile_workspace.dart';
import 'slide_content_widgets.dart';

class DesktopWorkspace extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool showSidebar;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onBack;
  final VoidCallback? onAddSlide;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;

  const DesktopWorkspace({
    super.key,
    required this.controller,
    required this.showSidebar,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onZoomChanged,
    required this.onBack,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onAddSlide,
  });

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  bool _sidebarOpen = true;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.value = Matrix4.identity()
      ..scale(widget.zoomScale, widget.zoomScale, 1.0);
  }

  @override
  void didUpdateWidget(covariant DesktopWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomScale != widget.zoomScale) {
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      if ((currentScale - widget.zoomScale).abs() > 0.01) {
        if (widget.zoomScale <= 1.0) {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY.clamp(-double.infinity, 0.0));
        } else {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY)
            ..scale(widget.zoomScale, widget.zoomScale, 1.0);
        }
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _goToSlide(int index) {
    final stateProvider = WorkspaceOutsideStateProvider.of(context);
    if (stateProvider != null && stateProvider.editingSlideIndex != null && stateProvider.editingSlideIndex != index) {
      stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
    }
    widget.controller.goToSlide(index);
    animateToSlide(
      transformationController: _transformationController,
      index: index,
      compact: false,
      fillWidth: true,
      canManageSlides: widget.canManageSlides,
      slides: widget.controller.slides,
      context: context,
      sidebarOpen: _sidebarOpen,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showSidebar) {
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _sidebarOpen ? 216 : 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 216,
                maxWidth: 216,
                child: ThumbnailSidebar(
                  controller: widget.controller,
                  onAddSlide: widget.onAddSlide,
                  onBrandTap: widget.onBack,
                  onSlideTap: _goToSlide,
                  isDark: widget.isDark,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                SlidePagesList(
                  controller: widget.controller,
                  compact: false,
                  canManageSlides: widget.canManageSlides,
                  isDark: widget.isDark,
                  transformationController: _transformationController,
                  fillWidth: true,
                  onEditSlide: widget.onEditSlide,
                  onDeleteSlide: widget.onDeleteSlide,
                  onSlideTap: _goToSlide,
                ),
                Positioned(
                  left: 0,
                  top: 16,
                  child: SidebarHandle(
                    isOpen: _sidebarOpen,
                    isDark: widget.isDark,
                    onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return CollapsibleSlideWorkspace(
      controller: widget.controller,
      compact: false,
      canManageSlides: widget.canManageSlides,
      isDark: widget.isDark,
      zoomScale: widget.zoomScale,
      onEditSlide: widget.onEditSlide,
      onDeleteSlide: widget.onDeleteSlide,
    );
  }
}

class SidebarHandle extends StatelessWidget {
  final bool isOpen;
  final bool isDark;
  final VoidCallback onTap;

  const SidebarHandle({
    super.key,
    required this.isOpen,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF2A2540) : Colors.white,
      elevation: 6,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 54,
          child: Icon(
            isOpen ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: isDark ? Colors.white : workspacePurple,
          ),
        ),
      ),
    );
  }
}

class ThumbnailSidebar extends StatelessWidget {
  final SlideWorkspaceController controller;
  final VoidCallback? onAddSlide;
  final VoidCallback? onBrandTap;
  final ValueChanged<int>? onSlideTap;
  final bool isDark;

  const ThumbnailSidebar({
    super.key,
    required this.controller,
    this.onAddSlide,
    this.onBrandTap,
    this.onSlideTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1930) : const Color(0xFFFBFAFF),
        border: Border(
            right: BorderSide(
                color: isDark
                    ? const Color(0xFF312B49)
                    : const Color(0xFFECE9F7))),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: ListView(
                children: [
                  for (var index = 0;
                      index < controller.slides.length;
                      index++) ...[
                    if (index == 0 ||
                        subtitleKey(controller.slides[index].subtitle) !=
                            subtitleKey(controller.slides[index - 1].subtitle))
                      Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : 18,
                          bottom: 10,
                        ),
                        child: Transform.scale(
                          scale: 0.7,
                          alignment: Alignment.topCenter,
                          child: SubtitleHeader(
                            subtitle: subtitleLabel(
                                controller.slides[index].subtitle),
                            isDark: isDark,
                            compact: true,
                          ),
                        ),
                      ),
                    ThumbCard(
                      controller: controller,
                      index: index,
                      isDark: isDark,
                      onTap:
                          onSlideTap == null ? null : () => onSlideTap!(index),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onAddSlide != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 38,
                child: PopupMenuButton<int>(
                  tooltip: 'Choose slide subtitle',
                  onSelected: (index) {
                    controller.goToSlide(index);
                    onSlideTap?.call(index);
                  },
                  itemBuilder: (context) {
                    final groups = subtitleGroups(controller.slides);
                    return [
                      for (final group in groups)
                        PopupMenuItem<int>(
                          value: group.first,
                          child: Text(
                            subtitleLabel(
                                controller.slides[group.first].subtitle),
                          ),
                        ),
                    ];
                  },
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0ECFF),
                      foregroundColor: workspacePurple,
                      elevation: 0,
                    ),
                    onPressed: null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            controller.currentSlide.subtitle.trim().isEmpty
                                ? 'Untitled'
                                : controller.currentSlide.subtitle.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HorizontalThumbnails extends StatelessWidget {
  final SlideWorkspaceController controller;
  final bool isDark;
  final ValueChanged<int>? onSlideTap;

  const HorizontalThumbnails({
    super.key,
    required this.controller,
    required this.isDark,
    this.onSlideTap,
  });

  @override
  Widget build(BuildContext context) {
    final groups = subtitleGroups(controller.slides);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final group in groups)
          SizedBox(
            width: group.length * 136,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.scale(
                    scale: 0.65,
                    alignment: Alignment.topCenter,
                    child: SubtitleHeader(
                      subtitle: subtitleLabel(
                          controller.slides[group.first].subtitle),
                      isDark: isDark,
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Expanded(
                    child: Row(
                      children: [
                        for (final index in group)
                          Expanded(
                            child: ThumbCard(
                              controller: controller,
                              index: index,
                              isDark: isDark,
                              horizontal: true,
                              onTap: onSlideTap == null
                                  ? null
                                  : () => onSlideTap!(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ThumbCard extends StatelessWidget {
  final SlideWorkspaceController controller;
  final int index;
  final bool isDark;
  final bool horizontal;
  final VoidCallback? onTap;

  const ThumbCard({
    super.key,
    required this.controller,
    required this.index,
    this.isDark = false,
    this.horizontal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slide = controller.slides[index];
    final selected = index == controller.currentIndex;
    final muted = isDark ? const Color(0xFFCBC4EA) : workspaceMuted;
    const loadRealImage = true;

    return GestureDetector(
      onTap: onTap ?? () => controller.goToSlide(index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: horizontal ? 78 : 108,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252039) : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6B4EFF)
                      : (isDark
                          ? const Color(0xFF312B49)
                          : const Color(0xFFE6E3F4)),
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? const Color(0xFF6B4EFF).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: selected ? 12 : 5,
                    spreadRadius: selected ? 1.5 : 0,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SlideMiniature(
                slide: slide,
                isDark: isDark,
                loadRealImage: loadRealImage,
                slideIndex: index,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${index + 1}',
              style: TextStyle(
                color:
                    selected ? workspacePurple : muted.withValues(alpha: .72),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SlideMiniature extends StatelessWidget {
  final WorkspaceSlide slide;
  final bool isDark;
  final bool loadRealImage;
  final int? slideIndex;

  const SlideMiniature({
    super.key,
    required this.slide,
    required this.isDark,
    this.loadRealImage = true,
    this.slideIndex,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 1100.0,
            height: 608.0,
            child: SlidePaper(
              slide: slide,
              compact: false,
              isDark: isDark,
              studyMode: true,
              isCurrent: false,
              isThumbnail: true,
              controller: null,
              loadRealImage: loadRealImage,
              slideIndex: slideIndex,
            ),
          ),
        ),
      );
}
