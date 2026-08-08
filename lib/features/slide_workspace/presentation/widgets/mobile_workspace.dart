import 'package:flutter/material.dart';

import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'workspace_state_provider.dart';
import 'slide_pages_list.dart';
import 'desktop_workspace.dart';

class MobileWorkspace extends StatelessWidget {
  final SlideWorkspaceController controller;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;
  final ValueChanged<int>? onAddSlideAfter;

  const MobileWorkspace({
    super.key,
    required this.controller,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onAddSlideAfter,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleSlideWorkspace(
      controller: controller,
      compact: true,
      canManageSlides: canManageSlides,
      isDark: isDark,
      zoomScale: zoomScale,
      onEditSlide: onEditSlide,
      onDeleteSlide: onDeleteSlide,
      onAddSlideAfter: onAddSlideAfter,
    );
  }
}

class CollapsibleSlideWorkspace extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;
  final ValueChanged<int>? onAddSlideAfter;

  const CollapsibleSlideWorkspace({
    super.key,
    required this.controller,
    required this.compact,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onAddSlideAfter,
  });

  @override
  State<CollapsibleSlideWorkspace> createState() =>
      _CollapsibleSlideWorkspaceState();
}

class _CollapsibleSlideWorkspaceState extends State<CollapsibleSlideWorkspace> {
  bool _showThumbnails = false;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.value =
        Matrix4.diagonal3Values(widget.zoomScale, widget.zoomScale, 1.0);
  }

  @override
  void didUpdateWidget(covariant CollapsibleSlideWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomScale != widget.zoomScale) {
      final currentTranslation =
          _transformationController.value.getTranslation();
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      if ((currentScale - widget.zoomScale).abs() > 0.01) {
        _transformationController.value = Matrix4.translationValues(
              currentTranslation.x,
              currentTranslation.y,
              currentTranslation.z,
            ) *
            Matrix4.diagonal3Values(widget.zoomScale, widget.zoomScale, 1.0);
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _selectSlideWithoutScroll(int index) {
    final stateProvider = WorkspaceOutsideStateProvider.of(context);
    if (stateProvider != null &&
        stateProvider.editingSlideIndex != null &&
        stateProvider.editingSlideIndex != index) {
      stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
    }
    if (index != widget.controller.currentIndex) {
      widget.controller.goToSlide(index);
    }
  }

  void _goToSlide(int index) {
    final stateProvider = WorkspaceOutsideStateProvider.of(context);
    if (stateProvider != null &&
        stateProvider.editingSlideIndex != null &&
        stateProvider.editingSlideIndex != index) {
      stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
    }
    widget.controller.goToSlide(index);
    animateToSlide(
      transformationController: _transformationController,
      index: index,
      compact: widget.compact,
      fillWidth: false,
      canManageSlides: widget.canManageSlides,
      slides: widget.controller.slides,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SlidePagesList(
          controller: widget.controller,
          compact: widget.compact,
          canManageSlides: widget.canManageSlides,
          isDark: widget.isDark,
          transformationController: _transformationController,
          onEditSlide: widget.onEditSlide,
          onDeleteSlide: widget.onDeleteSlide,
          onAddSlideAfter: widget.onAddSlideAfter,
          onSlideTap: _selectSlideWithoutScroll,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: ToolbarCapsule(
                    isDark: widget.isDark,
                    child: WorkspaceIconButton(
                      icon: _showThumbnails
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      tooltip: 'Slides',
                      onTap: () =>
                          setState(() => _showThumbnails = !_showThumbnails),
                    ),
                  ),
                ),
              ),
              if (_showThumbnails)
                SizedBox(
                  height: widget.compact ? 148 : 160,
                  child: HorizontalThumbnails(
                    controller: widget.controller,
                    isDark: widget.isDark,
                    onSlideTap: _goToSlide,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
