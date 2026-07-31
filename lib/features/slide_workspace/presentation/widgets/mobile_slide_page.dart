import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'workspace_state_provider.dart';
import 'slide_content_widgets.dart';
import 'workspace_object_renderers.dart';
import 'stagiaire_slide_painters.dart';
import 'workspace_top_toolbar.dart';

class MobileSlidePage extends StatefulWidget {
  final SlideWorkspaceController controller;
  final int index;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int>? onSlideTap;

  const MobileSlidePage({
    super.key,
    required this.controller,
    required this.index,
    required this.compact,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEdit,
    required this.onDelete,
    this.onSlideTap,
  });

  @override
  State<MobileSlidePage> createState() => _MobileSlidePageState();
}

class _MobileSlidePageState extends State<MobileSlidePage> {
  final GlobalKey _canvasKey = GlobalKey();
  int? _activePointer;
  PointerDeviceKind? _activeKind;

  SlideWorkspaceController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final slide = controller.slides[widget.index];
    final isCurrent = widget.index == controller.currentIndex;
    final page = AspectRatio(
      aspectRatio: 1100.0 / 608.0,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Listener(
          onPointerDown: (event) => _handlePointerDown(event),
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerUp,
          child: SizedBox(
            key: _canvasKey,
            width: 1100.0,
            height: 608.0,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onSlideTap?.call(widget.index);
                    controller.selectObject(null);
                  },
                  onLongPress: () {
                    widget.onSlideTap?.call(widget.index);
                    controller.selectObject(null);
                  },
                  onDoubleTap: () {
                    final stateProvider = WorkspaceOutsideStateProvider.of(context);
                    if (stateProvider != null && widget.canManageSlides) {
                      stateProvider.startInPlaceEdit(widget.index);
                    }
                  },
                  child: SlidePaper(
                    slide: slide,
                    compact: widget.compact,
                    isDark: widget.isDark,
                    studyMode: controller.isStudyMode,
                    isCurrent: isCurrent,
                    controller: controller,
                    slideIndex: widget.index,
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final obj in ((controller.isStudyMode ? slide.strokes : slide.examStrokes)
                            .toList()
                          ..sort((a, b) {
                            final cmp = a.zIndex.compareTo(b.zIndex);
                            if (cmp != 0) return cmp;
                            return a.creationTime.compareTo(b.creationTime);
                          })))
                          WorkspaceRendererRegistry.render(
                            context: context,
                            object: obj,
                            controller: controller,
                            isSelected: isCurrent && controller.selectedObjectId == obj.id,
                            onSelected: () {
                              widget.onSlideTap?.call(widget.index);
                              controller.selectObject(obj.id);
                            },
                            onUpdate: (updated) {
                              controller.onInteractionFinished(updated);
                            },
                            onDelete: () {
                              controller.deleteWorkspaceObject(obj.id);
                              controller.selectObject(null);
                            },
                          ),
                        if (isCurrent)
                          IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: DrawingLayerPainter(
                                  strokes: const [],
                                  activeStroke: controller.activeStroke,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.canManageSlides && controller.isStudyMode)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 3),
            child: ObjectControls(
              index: widget.index,
              total: controller.slides.length,
              onEdit: widget.onEdit,
              onDuplicate: () => controller.duplicateSlideAt(widget.index),
              onDelete: widget.onDelete,
              onMoveUp: () => controller.moveSlideUp(widget.index),
              onMoveDown: () => controller.moveSlideDown(widget.index),
              isHidden: slide.isHidden,
              isDark: widget.isDark,
              onHide: () => controller.toggleSlideHidden(widget.index),
              controller: controller,
            ),
          ),
        page,
      ],
    );
  }

  Future<void> _handlePointerDown(PointerDownEvent event) async {
    if (!_canDraw || !_isPrimaryMouseButton(event)) return;
    final fingerDrawing = MediaQuery.sizeOf(context).width < 600 &&
        event.kind == PointerDeviceKind.touch;
    if (!_isStylus(event.kind) &&
        event.kind != PointerDeviceKind.mouse &&
        !fingerDrawing) {
      return;
    }
    if (widget.index != controller.currentIndex) {
      controller.goToSlide(widget.index);
    }

    final incomingIsStylus = _isStylus(event.kind);
    final activeIsStylus = _isStylus(_activeKind);
    if (_activePointer != null) {
      if (incomingIsStylus && !activeIsStylus) {
        await controller.endStroke();
      } else {
        return;
      }
    }

    _activePointer = event.pointer;
    _activeKind = event.kind;
    controller.startStroke(
      _toSlidePoint(event.position),
      event.kind,
      pressure: event.pressure,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    controller.appendStrokePoint(_toSlidePoint(event.position), event.pressure);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _activeKind = null;
    controller.endStroke();
  }

  bool get _canDraw =>
      controller.selectedTool == WorkspaceTool.pen ||
      controller.selectedTool == WorkspaceTool.highlighter ||
      controller.selectedTool == WorkspaceTool.eraser;

  bool _isPrimaryMouseButton(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.mouse ||
      event.buttons == kPrimaryMouseButton;

  bool _isStylus(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  Offset _toSlidePoint(Offset globalPosition) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(globalPosition) ?? Offset.zero;
  }
}

class ObjectControls extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool isHidden;
  final bool isDark;
  final VoidCallback onHide;
  final SlideWorkspaceController? controller;

  const ObjectControls({
    super.key,
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.isHidden,
    required this.isDark,
    required this.onHide,
    this.controller,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final stateProvider = WorkspaceOutsideStateProvider.of(context);
    final slide = controller != null && index >= 0 && index < controller!.slides.length
        ? controller!.slides[index]
        : null;

    final isRecordingThisSlide = stateProvider != null &&
        slide != null &&
        stateProvider.activeRecordingSlideId == slide.id;

    if (isRecordingThisSlide) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, color: Colors.red, size: 10),
            const SizedBox(width: 8),
            Text(
              'Rec: ${_formatDuration(stateProvider.outsideRecordDuration)}',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                stateProvider.isOutsidePaused ? Icons.play_arrow : Icons.pause,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: stateProvider.pauseResumeRecording,
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(
                Icons.stop,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => stateProvider.stopRecording(slide),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(
                Icons.close,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: stateProvider.cancelRecording,
            ),
          ],
        ),
      );
    }

    final items = [
      (
        isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        isHidden ? 'Show' : 'Hide',
        onHide,
        true,
      ),
      if (slide != null && stateProvider != null) ...[
        if (slide.audioUrl.isNotEmpty)
          (
            Icons.music_off_outlined,
            'Clear voice',
            () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Delete audio?'),
                  content: const Text('Are you sure you want to delete the audio explanation for this slide?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && controller != null) {
                await controller!.updateSlide(
                  slideId: slide.id,
                  title: slide.title,
                  subtitle: slide.subtitle,
                  questions: slide.questions,
                  audioPath: 'clear_audio',
                );
              }
            },
            !stateProvider.isOutsideRecording,
          ),
        (
          Icons.mic_none_outlined,
          'Record voice',
          () => stateProvider.startRecording(slide),
          !stateProvider.isOutsideRecording,
        ),
      ],
      (Icons.edit_outlined, 'Edit', onEdit, true),
      (Icons.control_point_duplicate_rounded, 'Duplicate', onDuplicate, true),
      (Icons.delete_outline_rounded, 'Delete', onDelete, true),
    ];

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in items)
          SlideActionIcon(
            icon: item.$1,
            tooltip: item.$2,
            isDark: isDark,
            onTap: item.$4 ? item.$3 : null,
          ),
      ],
    );
  }
}

class SlideActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback? onTap;

  const SlideActionIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = isDark ? Colors.white : workspaceInk;
    final muted = isDark ? Colors.white : workspaceMuted;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 21,
            color: enabled
                ? base.withValues(alpha: .84)
                : muted.withValues(alpha: .35),
          ),
        ),
      ),
    );
  }
}

class HiddenSlideBadge extends StatelessWidget {
  final bool isDark;

  const HiddenSlideBadge({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF332C55) : const Color(0xFFF3EFFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF4B4171) : const Color(0xFFE0D8FA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined,
              color: isDark ? Colors.white : workspacePurple, size: 16),
          const SizedBox(width: 6),
          Text(
            'Hidden',
            style: TextStyle(
              color: isDark ? Colors.white : workspacePurple,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BrandTab extends StatelessWidget {
  final bool isDark;

  const BrandTab({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6F55FF) : workspacePurple,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: const WorkspaceLogo(
        color: Colors.white,
        width: 106,
        height: 27,
      ),
    );
  }
}
