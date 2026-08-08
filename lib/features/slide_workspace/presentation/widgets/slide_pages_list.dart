import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'workspace_state_provider.dart';
import 'mobile_slide_page.dart';

const slideCanvasWidth = 1100.0;
const slideCanvasHeight = 608.0;
const kHeaderCompactHeight = 52.0;
const kHeaderDesktopHeight = 64.0;

class _TranslationBounds {
  final double min;
  final double max;

  const _TranslationBounds(this.min, this.max);

  double get center => (min + max) / 2;
}

_TranslationBounds _translationBounds(
  double contentExtent,
  double viewportExtent,
  double scale,
) {
  final scaledExtent = contentExtent * scale;
  if (scaledExtent <= viewportExtent) {
    final centered = (viewportExtent - scaledExtent) / 2;
    return _TranslationBounds(centered, centered);
  }
  return _TranslationBounds(viewportExtent - scaledExtent, 0.0);
}

class WorkspaceListEntry {
  final String subtitle;
  final int? slideIndex;

  const WorkspaceListEntry.header(this.subtitle) : slideIndex = null;
  const WorkspaceListEntry.slide(this.subtitle, int index) : slideIndex = index;

  bool get isHeader => slideIndex == null;
}

String subtitleLabel(String subtitle) =>
    subtitle.trim().isEmpty ? 'Untitled' : subtitle.trim();

String subtitleKey(String subtitle) => subtitleLabel(subtitle).toLowerCase();

List<WorkspaceListEntry> workspaceEntries(List<WorkspaceSlide> slides) {
  final entries = <WorkspaceListEntry>[];
  String? previousKey;
  for (var index = 0; index < slides.length; index++) {
    final subtitle = subtitleLabel(slides[index].subtitle);
    final key = subtitleKey(subtitle);
    if (key != previousKey) {
      entries.add(WorkspaceListEntry.header(subtitle));
      previousKey = key;
    }
    entries.add(WorkspaceListEntry.slide(subtitle, index));
  }
  return entries;
}

List<List<int>> subtitleGroups(List<WorkspaceSlide> slides) {
  final groups = <List<int>>[];
  String? previousKey;
  for (var index = 0; index < slides.length; index++) {
    final key = subtitleKey(slides[index].subtitle);
    if (key != previousKey) {
      groups.add(<int>[]);
      previousKey = key;
    }
    groups.last.add(index);
  }
  return groups;
}

void animateToSlide({
  required TransformationController transformationController,
  required int index,
  required bool compact,
  required bool fillWidth,
  required bool canManageSlides,
  required List<WorkspaceSlide> slides,
  required BuildContext context,
  bool sidebarOpen = false,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final viewportHeight = renderBox.size.height;
    final totalWidth = renderBox.size.width;
    final viewportWidth = sidebarOpen ? (totalWidth - 216.0) : totalWidth;
    final pageWidth = viewportWidth
        .clamp(280.0, double.infinity)
        .toDouble();
    final pageHeight = pageWidth * slideCanvasHeight / slideCanvasWidth;
    final controlsHeight = canManageSlides ? 33.0 : 0.0;
    final pageExtent = pageHeight + controlsHeight;
    final spacing = compact ? 2.0 : 3.0;

    // 1. Build entries list to match exactly how they are rendered
    final entries = <WorkspaceListEntry>[];
    String? previousKey;
    for (var i = 0; i < slides.length; i++) {
      final subtitle = subtitleLabel(slides[i].subtitle);
      final key = subtitleKey(subtitle);
      if (key != previousKey) {
        entries.add(WorkspaceListEntry.header(subtitle));
        previousKey = key;
      }
      entries.add(WorkspaceListEntry.slide(subtitle, i));
    }

    // 2. Compute exact positions for all slides.
    double currentY = 10.0; // topPad
    final Map<int, double> slideTops = {};
    final Map<int, double> slideHeights = {};

    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (entry.isHeader) {
        final isFirst = entryIndex == 0;
        final topMargin = isFirst ? 0.0 : (compact ? 10.0 : 14.0);
        final headerBodyHeight =
            compact ? kHeaderCompactHeight : kHeaderDesktopHeight;
        final bottomMargin = compact ? 6.0 : 8.0;
        currentY += topMargin + headerBodyHeight + bottomMargin;
      } else {
        final slideIdx = entry.slideIndex!;
        slideTops[slideIdx] = currentY;
        slideHeights[slideIdx] = pageExtent;

        final bottomMargin = entryIndex == entries.length - 1 ? 0.0 : spacing;
        currentY += pageExtent + bottomMargin;
      }
    }

    final top = slideTops[index] ?? 10.0;
    final targetPageExtent = slideHeights[index] ?? pageExtent;
    final totalContentHeight = currentY + 10.0; // bottomPad

    final currentScale = transformationController.value.getMaxScaleOnAxis();
    final targetY = -(top * currentScale) +
        (viewportHeight - (targetPageExtent * currentScale)) / 2;
    final horizontalBounds = _translationBounds(
      pageWidth,
      viewportWidth,
      currentScale,
    );
    final verticalBounds = _translationBounds(
      totalContentHeight,
      viewportHeight,
      currentScale,
    );

    final matrix = transformationController.value.clone();
    matrix.setTranslationRaw(
      horizontalBounds.center,
      targetY.clamp(verticalBounds.min, verticalBounds.max).toDouble(),
      0,
    );
    transformationController.value = matrix;
  });
}

class SubtitleHeader extends StatelessWidget {
  final String subtitle;
  final bool isDark;
  final bool compact;

  const SubtitleHeader({
    super.key,
    required this.subtitle,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252039) : workspacePurple;
    final textColor = isDark ? const Color(0xFF9F8AFF) : Colors.white;
    final borderColor = isDark ? const Color(0xFF383153) : workspacePurple;

    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: workspacePurple.withValues(alpha: 0.20),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Text(
        subtitle,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 18 : 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class SlidePagesList extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final TransformationController transformationController;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;
  final ValueChanged<int>? onSlideTap;
  final bool fillWidth;

  const SlidePagesList({
    super.key,
    required this.controller,
    required this.compact,
    required this.canManageSlides,
    this.isDark = false,
    required this.transformationController,
    this.fillWidth = false,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onSlideTap,
  });

  @override
  State<SlidePagesList> createState() => _SlidePagesListState();
}

class _SlidePagesListState extends State<SlidePagesList>
    with SingleTickerProviderStateMixin {
  final Map<int, GlobalKey> _slideKeys = {};
  final Set<int> _activeStylusPointers = {};
  final GlobalKey _contentKey = GlobalKey();

  late final AnimationController _flingAnimationController;
  bool _wasZoomed = false;
  double _lastViewportHeight = 0.0;
  double _lastPageWidth = 0.0;
  double _lastTransformScale = double.nan;

  bool get _isDrawingTool =>
      widget.controller.selectedTool == WorkspaceTool.pen ||
      widget.controller.selectedTool == WorkspaceTool.highlighter ||
      widget.controller.selectedTool == WorkspaceTool.eraser;

  bool get _phoneDrawingMode =>
      MediaQuery.sizeOf(context).width < 600 && _isDrawingTool;

  bool _isStylus(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool get _customPanEnabled =>
      !_phoneDrawingMode &&
      !(_isDrawingTool && _activeStylusPointers.isNotEmpty);

  GlobalKey _slideKeyFor(int index) =>
      _slideKeys.putIfAbsent(index, GlobalKey.new);

  bool _initialScrollAligned = false;

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
    _flingAnimationController = AnimationController.unbounded(vsync: this);
    _flingAnimationController.addListener(_onFlingTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _alignToCurrentSlide();
      }
    });
  }

  void _alignToCurrentSlide() {
    animateToSlide(
      transformationController: widget.transformationController,
      index: widget.controller.currentIndex,
      compact: widget.compact,
      fillWidth: widget.fillWidth,
      canManageSlides: widget.canManageSlides,
      slides: widget.controller.slides,
      context: context,
    );
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _initialScrollAligned = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant SlidePagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController.removeListener(_onTransformChanged);
      widget.transformationController.addListener(_onTransformChanged);
    }
  }

  void _onTransformChanged() {
    final matrix = widget.transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final scaleChanged = !_lastTransformScale.isFinite ||
        (scale - _lastTransformScale).abs() > 0.001;
    _lastTransformScale = scale;

    if ((widget.controller.zoom - scale).abs() > 0.01) {
      widget.controller.setZoom(scale);
    }

    final isZoomedNow = scale > 1.01;
    if (isZoomedNow != _wasZoomed) {
      setState(() {
        _wasZoomed = isZoomedNow;
      });
    }

    if (_lastViewportHeight > 0 && _lastPageWidth > 0) {
      final contentHeight = _contentHeight(_lastPageWidth);
      final horizontalBounds = _translationBounds(
        _lastPageWidth,
        _lastPageWidth,
        scale,
      );
      final verticalBounds = _translationBounds(
        contentHeight,
        _lastViewportHeight,
        scale,
      );
      final translation = matrix.getTranslation();
      final targetX = scaleChanged
          ? horizontalBounds.center
          : translation.x
              .clamp(horizontalBounds.min, horizontalBounds.max)
              .toDouble();
      final targetY = translation.y
          .clamp(verticalBounds.min, verticalBounds.max)
          .toDouble();

      if ((translation.x - targetX).abs() > 0.01 ||
          (translation.y - targetY).abs() > 0.01) {
        final constrained = Matrix4.copy(matrix)
          ..setTranslationRaw(targetX, targetY, translation.z);
        widget.transformationController.value = constrained;
        return;
      }
    }

    if (_initialScrollAligned &&
        _lastViewportHeight > 0 &&
        _lastPageWidth > 0 &&
        widget.controller.hasSlides) {
      final translation = matrix.getTranslation();
      final centerY = (-translation.y + _lastViewportHeight / 2) / scale;

      const topPad = 10.0;
      double currentY = topPad;
      double bestDistance = double.infinity;
      int bestIndex = widget.controller.currentIndex;
      final entries = workspaceEntries(widget.controller.slides);

      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        final entry = entries[entryIndex];
        double entryHeight = 0.0;
        if (entry.isHeader) {
          final isFirst = entryIndex == 0;
          entryHeight =
              (isFirst ? 0.0 : (widget.compact ? 10.0 : 14.0)) +
                  (widget.compact
                      ? kHeaderCompactHeight
                      : kHeaderDesktopHeight) +
                  (widget.compact ? 6.0 : 8.0);
        } else {
          final isLast = entryIndex == entries.length - 1;
          entryHeight =
              _lastPageWidth * slideCanvasHeight / slideCanvasWidth +
                  (widget.canManageSlides ? 33.0 : 0.0) +
                  (isLast ? 0.0 : (widget.compact ? 2.0 : 3.0));
        }

        if (!entry.isHeader) {
          final slideIndex = entry.slideIndex!;
          final slideCenterY = currentY + entryHeight / 2;
          final distance = (slideCenterY - centerY).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = slideIndex;
          }
        }
        currentY += entryHeight;
      }

      if (bestIndex != widget.controller.currentIndex) {
        final stateProvider = WorkspaceOutsideStateProvider.of(context);
        if (stateProvider != null &&
            stateProvider.editingSlideIndex != null &&
            stateProvider.editingSlideIndex != bestIndex) {
          stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
        }
        widget.controller.goToSlide(bestIndex);
      }
    }
  }

  double _contentHeight(double pageWidth) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize == true
        ? box!.size.height
        : _calculateFallbackHeight(pageWidth);
  }

  double _calculateFallbackHeight(double pageWidth) {
    const topPad = 10.0;
    const bottomPad = 10.0;
    final entries = workspaceEntries(widget.controller.slides);

    double totalContentHeight = topPad + bottomPad;
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (entry.isHeader) {
        final isFirst = entryIndex == 0;
        final topMargin = isFirst ? 0.0 : (widget.compact ? 10.0 : 14.0);
        final headerBodyHeight =
            widget.compact ? kHeaderCompactHeight : kHeaderDesktopHeight;
        final bottomMargin = widget.compact ? 6.0 : 8.0;
        totalContentHeight += topMargin + headerBodyHeight + bottomMargin;
      } else {
        final pageExtent = pageWidth * slideCanvasHeight / slideCanvasWidth +
            (widget.canManageSlides ? 33.0 : 0.0);
        final spacing = widget.compact ? 2.0 : 3.0;
        final bottomMargin = entryIndex == entries.length - 1 ? 0.0 : spacing;
        totalContentHeight += pageExtent + bottomMargin;
      }
    }
    return totalContentHeight;
  }

  void _onFlingTick() {
    if (!_flingAnimationController.isAnimating) return;
    final currentMatrix = widget.transformationController.value;
    final scale = currentMatrix.getMaxScaleOnAxis();

    final contentHeight = _contentHeight(_lastPageWidth);
    final verticalBounds = _translationBounds(
      contentHeight,
      _lastViewportHeight,
      scale,
    );
    final double newY = _flingAnimationController.value
        .clamp(verticalBounds.min, verticalBounds.max)
        .toDouble();

    final newMatrix = Matrix4.copy(currentMatrix)
      ..setTranslationRaw(
          currentMatrix.getTranslation().x, newY, currentMatrix.getTranslation().z);

    widget.transformationController.value = newMatrix;
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    _flingAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = workspaceEntries(widget.controller.slides);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const sidePad = 0.0;
          const topPad = 10.0;
          const bottomPad = 10.0;

          final pageWidth = constraints.maxWidth
              .clamp(280.0, double.infinity)
              .toDouble();

          final oldHeight = _lastViewportHeight;
          final oldWidth = _lastPageWidth;

          _lastViewportHeight = constraints.maxHeight;
          _lastPageWidth = pageWidth;

          final double deltaH = (oldHeight - constraints.maxHeight).abs();
          final double deltaW = (oldWidth - pageWidth).abs();
          if (oldHeight > 0 && oldWidth > 0 && (deltaH > 2.0 || deltaW > 2.0)) {
            _initialScrollAligned = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _alignToCurrentSlide();
              }
            });
          }

          final gestures = <Type, GestureRecognizerFactory>{};
          if (_customPanEnabled) {
            gestures[WorkspaceScrollGestureRecognizer] =
                GestureRecognizerFactoryWithHandlers<
                    WorkspaceScrollGestureRecognizer>(
              () => WorkspaceScrollGestureRecognizer(),
              (WorkspaceScrollGestureRecognizer instance) {
                instance
                  ..onStart = () {
                    _flingAnimationController.stop();
                  }
                  ..onUpdate = (delta) {
                    final currentMatrix = widget.transformationController.value;
                    final translation = currentMatrix.getTranslation();
                    final scale = currentMatrix.getMaxScaleOnAxis();

                    final double viewportWidth = constraints.maxWidth;
                    final double viewportHeight = constraints.maxHeight;

                    final double totalContentWidth = pageWidth + sidePad * 2;
                    final box = _contentKey.currentContext?.findRenderObject()
                        as RenderBox?;
                    final double contentHeight = box?.hasSize == true
                        ? box!.size.height
                        : _calculateFallbackHeight(pageWidth);

                    final verticalBounds = _translationBounds(
                      contentHeight,
                      viewportHeight,
                      scale,
                    );
                    final horizontalBounds = _translationBounds(
                      totalContentWidth,
                      viewportWidth,
                      scale,
                    );

                    final double newY =
                        (translation.y + delta.dy)
                            .clamp(verticalBounds.min, verticalBounds.max)
                            .toDouble();
                    final double newX =
                        (translation.x + delta.dx)
                            .clamp(horizontalBounds.min, horizontalBounds.max)
                            .toDouble();

                    final newMatrix = Matrix4.copy(currentMatrix)
                      ..setTranslationRaw(newX, newY, translation.z);

                    widget.transformationController.value = newMatrix;
                  }
                  ..onEnd = (velocity) {
                    final double velocityY = velocity.pixelsPerSecond.dy;
                    if (velocityY.abs() > 100) {
                      final currentMatrix =
                          widget.transformationController.value;
                      final translation = currentMatrix.getTranslation();
                      final simulation = ClampingScrollSimulation(
                        position: translation.y,
                        velocity: velocityY,
                        tolerance: Tolerance.defaultTolerance,
                      );
                      _flingAnimationController.animateWith(simulation);
                    }
                  }
                  ..onStylusDetected = () {};
              },
            );
          }

          return RawGestureDetector(
            gestures: gestures,
            child: Listener(
              onPointerDown: (event) {
                if (_isStylus(event.kind)) {
                  setState(() {
                    _activeStylusPointers.add(event.pointer);
                  });
                }
              },
              onPointerUp: (event) {
                if (_activeStylusPointers.contains(event.pointer)) {
                  setState(() {
                    _activeStylusPointers.remove(event.pointer);
                  });
                }
              },
              onPointerCancel: (event) {
                if (_activeStylusPointers.contains(event.pointer)) {
                  setState(() {
                    _activeStylusPointers.remove(event.pointer);
                  });
                }
              },
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver
                      .register(pointerSignal, (event) {
                    if (event is PointerScrollEvent) {
                      final double scrollDeltaY = event.scrollDelta.dy;
                      final double scrollDeltaX = event.scrollDelta.dx;
                      if (scrollDeltaY != 0 || scrollDeltaX != 0) {
                        final currentMatrix =
                            widget.transformationController.value;
                        final translation = currentMatrix.getTranslation();
                        final scale = currentMatrix.getMaxScaleOnAxis();

                        final double viewportWidth = constraints.maxWidth;
                        final double viewportHeight = constraints.maxHeight;

                        final double totalContentWidth =
                            pageWidth + sidePad * 2;
                        final box = _contentKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        final double contentHeight = box?.hasSize == true
                            ? box!.size.height
                            : _calculateFallbackHeight(pageWidth);

                        final verticalBounds = _translationBounds(
                          contentHeight,
                          viewportHeight,
                          scale,
                        );
                        final horizontalBounds = _translationBounds(
                          totalContentWidth,
                          viewportWidth,
                          scale,
                        );

                        final double newY = (translation.y - scrollDeltaY)
                            .clamp(verticalBounds.min, verticalBounds.max)
                            .toDouble();
                        final double newX = (translation.x - scrollDeltaX)
                            .clamp(horizontalBounds.min, horizontalBounds.max)
                            .toDouble();

                        final newMatrix = Matrix4.copy(currentMatrix)
                          ..setTranslationRaw(newX, newY, translation.z);

                        widget.transformationController.value = newMatrix;
                      }
                    }
                  });
                }
              },
              child: InteractiveViewer(
                transformationController: widget.transformationController,
                panEnabled: false,
                scaleEnabled: !_phoneDrawingMode &&
                    !(_isDrawingTool && _activeStylusPointers.isNotEmpty),
                boundaryMargin: EdgeInsets.zero,
                minScale: 0.5,
                maxScale: 2.5,
                alignment: Alignment.topLeft,
                constrained: false,
                child: Padding(
                  key: _contentKey,
                  padding: const EdgeInsets.fromLTRB(
                      sidePad, topPad, sidePad, bottomPad),
                  child: SizedBox(
                    width: pageWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var entryIndex = 0;
                            entryIndex < entries.length;
                            entryIndex++)
                          _buildEntry(entries[entryIndex], entryIndex,
                              entries.length, pageWidth),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntry(WorkspaceListEntry entry, int entryIndex, int totalEntries,
      double pageWidth) {
    final isLast = entryIndex == totalEntries - 1;
    if (entry.isHeader) {
      final isFirst = entryIndex == 0;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          isFirst ? 0 : (widget.compact ? 10 : 14),
          0,
          widget.compact ? 6 : 8,
        ),
        child: SubtitleHeader(
          subtitle: entry.subtitle,
          isDark: widget.isDark,
          compact: widget.compact,
        ),
      );
    }

    final index = entry.slideIndex!;
    final baseHeight = pageWidth * slideCanvasHeight / slideCanvasWidth +
        (widget.canManageSlides ? 33 : 0);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : (widget.compact ? 2 : 3)),
      child: SizedBox(
        height: baseHeight,
        child: MobileSlidePage(
          key: _slideKeyFor(index),
          controller: widget.controller,
          index: index,
          compact: widget.compact,
          canManageSlides: widget.canManageSlides,
          isDark: widget.isDark,
          zoomScale: 1.0,
          onEdit: () => widget.onEditSlide(index),
          onDelete: () => widget.onDeleteSlide(index),
          onSlideTap: widget.onSlideTap,
        ),
      ),
    );
  }
}

class WorkspaceScrollGestureRecognizer extends OneSequenceGestureRecognizer {
  WorkspaceScrollGestureRecognizer({
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onStylusDetected,
  });

  VoidCallback? onStart;
  ValueChanged<Offset>? onUpdate;
  ValueChanged<Velocity>? onEnd;
  VoidCallback? onStylusDetected;

  final Map<int, VelocityTracker> _velocityTrackers = {};
  final Set<int> _touchPointers = {};
  bool _hasStarted = false;
  bool _isRejected = false;
  Offset? _lastPosition;

  @override
  void addPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      onStylusDetected?.call();
      _isRejected = true;
      resolve(GestureDisposition.rejected);
      return;
    }

    startTrackingPointer(event.pointer, event.transform);
    _velocityTrackers[event.pointer] = VelocityTracker.withKind(event.kind);
    _touchPointers.add(event.pointer);

    if (_touchPointers.length > 1) {
      _isRejected = true;
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    final tracker = _velocityTrackers[event.pointer];
    if (tracker != null && event is PointerMoveEvent) {
      tracker.addPosition(event.timeStamp, event.position);
    }

    if (event is PointerMoveEvent && _touchPointers.length == 1) {
      final Offset currentPos = event.position;
      if (_lastPosition != null) {
        final Offset delta = currentPos - _lastPosition!;
        if (!_hasStarted) {
          _hasStarted = true;
          onStart?.call();
        }
        onUpdate?.call(delta);
      }
      _lastPosition = currentPos;
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_hasStarted && !_isRejected) {
      final tracker = _velocityTrackers[pointer];
      final velocity = tracker?.getVelocity() ?? Velocity.zero;
      onEnd?.call(velocity);
    }
    _reset();
  }

  void _reset() {
    _hasStarted = false;
    _isRejected = false;
    _lastPosition = null;
    _touchPointers.clear();
    _velocityTrackers.clear();
  }

  @override
  String get debugDescription => 'WorkspaceScrollGestureRecognizer';
}
