import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import '../../../../core/services/image_cache_service.dart';
import 'stagiaire_slide_painters.dart';

abstract class WorkspaceObjectRenderer<T extends WorkspaceObject> {
  Widget buildRenderer({
    required BuildContext context,
    required T object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  });
}

class WorkspaceRendererRegistry {
  static final Map<String, WorkspaceObjectRenderer> _renderers = {};

  static void register(String type, WorkspaceObjectRenderer renderer) {
    _renderers[type] = renderer;
  }

  static void _ensureInitialized() {
    if (_renderers.isEmpty) {
      register('stroke', SlideStrokeRenderer());
      register('image', ImageObjectRenderer());
    }
  }

  static Widget render({
    required BuildContext context,
    required WorkspaceObject object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    _ensureInitialized();
    final renderer = _renderers[object.type];
    if (renderer == null) return const SizedBox.shrink();
    return renderer.buildRenderer(
      context: context,
      object: object,
      controller: controller,
      isSelected: isSelected,
      onSelected: onSelected,
      onUpdate: onUpdate,
      onDelete: onDelete,
    );
  }
}

class SlideStrokeRenderer extends WorkspaceObjectRenderer<SlideStroke> {
  @override
  Widget buildRenderer({
    required BuildContext context,
    required SlideStroke object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: DrawingLayerPainter(
              strokes: [object],
              activeStroke: null,
            ),
          ),
        ),
      ),
    );
  }
}

class ImageObjectRenderer extends WorkspaceObjectRenderer<ImageObject> {
  @override
  Widget buildRenderer({
    required BuildContext context,
    required ImageObject object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    return InteractiveImageWidget(
      image: object,
      isSelected: isSelected,
      onSelected: onSelected,
      onUpdate: (val) => onUpdate(val),
      onDelete: onDelete,
      controller: controller,
    );
  }
}

class InteractiveImageWidget extends StatefulWidget {
  final ImageObject image;
  final bool isSelected;
  final VoidCallback onSelected;
  final ValueChanged<ImageObject> onUpdate;
  final VoidCallback onDelete;
  final SlideWorkspaceController controller;

  const InteractiveImageWidget({
    super.key,
    required this.image,
    required this.isSelected,
    required this.onSelected,
    required this.onUpdate,
    required this.onDelete,
    required this.controller,
  });

  @override
  State<InteractiveImageWidget> createState() => _InteractiveImageWidgetState();
}

class _InteractiveImageWidgetState extends State<InteractiveImageWidget> {
  late double _x;
  late double _y;
  late double _width;
  late double _height;
  bool _isLoadingBytes = false;

  // In-place cropping state
  bool _isCropping = false;
  Rect _cropRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _x = widget.image.x;
    _y = widget.image.y;
    _width = widget.image.width;
    _height = widget.image.height;
  }

  @override
  void didUpdateWidget(InteractiveImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.x != widget.image.x ||
        oldWidget.image.y != widget.image.y ||
        oldWidget.image.width != widget.image.width ||
        oldWidget.image.height != widget.image.height) {
      _x = widget.image.x;
      _y = widget.image.y;
      _width = widget.image.width;
      _height = widget.image.height;
    }
  }

  Future<Uint8List?> _loadOriginalBytes() async {
    final image = widget.image;
    Uint8List? bytes;
    if (image.localPath != null) {
      bytes = SlideWorkspaceController.localImageCache[image.localPath!];
      if (bytes == null) {
        final file = File(image.localPath!);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }
    }
    if (bytes == null && image.imageUrl != null) {
      final cachedPath = await ImageCacheService().getOrDownload(image.imageUrl!);
      if (cachedPath != null) {
        bytes = await File(cachedPath).readAsBytes();
      }
    }
    return bytes;
  }

  static Future<Uint8List?> _cropBytesWithDartUi(
    Uint8List originalBytes, {
    required double cropLeftFrac,
    required double cropTopFrac,
    required double cropWidthFrac,
    required double cropHeightFrac,
  }) async {
    final codec = await ui.instantiateImageCodec(originalBytes);
    final frame = await codec.getNextFrame();
    final ui.Image fullImage = frame.image;

    final int srcX =
        (cropLeftFrac * fullImage.width).round().clamp(0, fullImage.width - 1);
    final int srcY =
        (cropTopFrac * fullImage.height).round().clamp(0, fullImage.height - 1);
    final int srcW =
        (cropWidthFrac * fullImage.width).round().clamp(1, fullImage.width - srcX);
    final int srcH =
        (cropHeightFrac * fullImage.height).round().clamp(1, fullImage.height - srcY);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcRect = Rect.fromLTWH(
      srcX.toDouble(),
      srcY.toDouble(),
      srcW.toDouble(),
      srcH.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble());
    canvas.drawImageRect(
      fullImage,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    final croppedUi = await recorder.endRecording().toImage(srcW, srcH);
    final byteData = await croppedUi.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _startInPlaceCrop() {
    setState(() {
      _isCropping = true;
      _cropRect = Rect.fromLTWH(0, 0, _width, _height);
    });
  }

  void _cancelCrop() {
    setState(() {
      _isCropping = false;
      _cropRect = Rect.zero;
    });
  }

  Future<void> _confirmCrop() async {
    if (_isLoadingBytes) return;
    setState(() {
      _isLoadingBytes = true;
    });

    try {
      final bytes = await _loadOriginalBytes();
      if (bytes == null) {
        throw Exception('Could not load image bytes for cropping');
      }

      final croppedBytes = await _cropBytesWithDartUi(
        bytes,
        cropLeftFrac: _cropRect.left / _width,
        cropTopFrac: _cropRect.top / _height,
        cropWidthFrac: _cropRect.width / _width,
        cropHeightFrac: _cropRect.height / _height,
      );

      if (croppedBytes != null && mounted) {
        final isExam = !widget.controller.isStudyMode;
        final tempId = 'picked_${DateTime.now().microsecondsSinceEpoch}';

        final docDir = await getApplicationDocumentsDirectory();
        final uploadsDir = Directory('${docDir.path}/workspace_uploads');
        if (!await uploadsDir.exists()) {
          await uploadsDir.create(recursive: true);
        }
        final file = File('${uploadsDir.path}/$tempId.png');
        await file.writeAsBytes(croppedBytes);
        final newLocalPath = file.path;

        SlideWorkspaceController.localImageCache[newLocalPath] = croppedBytes;

        final newX = _x + _cropRect.left;
        final newY = _y + _cropRect.top;
        final newW = _cropRect.width;
        final newH = _cropRect.height;

        setState(() {
          _x = newX;
          _y = newY;
          _width = newW;
          _height = newH;
          _isCropping = false;
          _cropRect = Rect.zero;
        });

        final updatedImage = widget.image.copyWith(
          x: newX,
          y: newY,
          width: newW,
          height: newH,
          localPath: newLocalPath,
          imageUrl: null,
          storagePath: null,
          state: ImageState.local,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        widget.controller.mutateObject(
          widget.controller.currentSlide.id,
          widget.image.id,
          isExam,
          (_) => updatedImage,
        );
        widget.controller.triggerUploadForObject(
          widget.controller.currentSlide.id,
          updatedImage,
          isExam,
        );
        widget.controller.scheduleSave(widget.controller.currentSlide.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cropping image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBytes = false;
        });
      }
    }
  }

  void _onInteractionEnd() {
    final oldX = widget.image.x;
    final oldY = widget.image.y;
    final oldW = widget.image.width;
    final oldH = widget.image.height;

    if (oldX != _x || oldY != _y || oldW != _width || oldH != _height) {
      final isExam = !widget.controller.isStudyMode;
      if (oldW == _width && oldH == _height) {
        widget.controller.executeCommand(
          MoveObjectCommand(
            controller: widget.controller,
            slideId: widget.controller.currentSlide.id,
            objectId: widget.image.id,
            isExam: isExam,
            oldX: oldX,
            oldY: oldY,
            newX: _x,
            newY: _y,
          ),
        );
      } else {
        widget.controller.executeCommand(
          ResizeObjectCommand(
            controller: widget.controller,
            slideId: widget.controller.currentSlide.id,
            objectId: widget.image.id,
            isExam: isExam,
            oldX: oldX,
            oldY: oldY,
            oldW: oldW,
            oldH: oldH,
            newX: _x,
            newY: _y,
            newW: _width,
            newH: _height,
          ),
        );
      }
    }
  }

  Widget _buildCornerHandle(Alignment alignment, double aspect, double padSide, double padTop) {
    double left = (alignment.x == -1) ? (padSide - 36) : (padSide + _width - 36);
    double top = (alignment.y == -1) ? (padTop - 36) : (padTop + _height - 36);

    return Positioned(
      left: left,
      top: top,
      width: 72,
      height: 72,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          widget.controller.isInteractingWithObject.value = true;
        },
        onPanUpdate: (details) {
          setState(() {
            final deltaX = details.delta.dx;

            if (alignment == Alignment.topLeft) {
              final newW = (_width - deltaX).clamp(80.0, _width + _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _height + _y) {
                _x += (_width - newW);
                _y += (_height - newH);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.topRight) {
              final newW = (_width + deltaX).clamp(80.0, 1100.0 - _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _height + _y) {
                _y += (_height - newH);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.bottomLeft) {
              final newW = (_width - deltaX).clamp(80.0, _width + _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= 825.0 - _y) {
                _x += (_width - newW);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.bottomRight) {
              final newW = (_width + deltaX).clamp(80.0, 1100.0 - _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= 825.0 - _y) {
                _width = newW;
                _height = newH;
              }
            }
          });
        },
        onPanEnd: (details) {
          widget.controller.isInteractingWithObject.value = false;
          _onInteractionEnd();
        },
        onPanCancel: () {
          widget.controller.isInteractingWithObject.value = false;
        },
        child: Container(
          width: 72,
          height: 72,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6B4EFF),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropHandle(Alignment alignment) {
    double hx;
    double hy;

    if (alignment.x == -1) {
      hx = _cropRect.left;
    } else if (alignment.x == 1) {
      hx = _cropRect.right;
    } else {
      hx = _cropRect.center.dx;
    }

    if (alignment.y == -1) {
      hy = _cropRect.top;
    } else if (alignment.y == 1) {
      hy = _cropRect.bottom;
    } else {
      hy = _cropRect.center.dy;
    }

    final isCorner = alignment.x != 0 && alignment.y != 0;
    final isHorizontalEdge = alignment.y != 0 && alignment.x == 0;

    return Positioned(
      left: hx - 22,
      top: hy - 22,
      width: 44,
      height: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          widget.controller.isInteractingWithObject.value = true;
        },
        onPanUpdate: (details) {
          setState(() {
            final dx = details.delta.dx;
            final dy = details.delta.dy;
            double left = _cropRect.left;
            double top = _cropRect.top;
            double right = _cropRect.right;
            double bottom = _cropRect.bottom;

            if (alignment.x == -1) {
              left = (left + dx).clamp(0.0, right - 30.0);
            } else if (alignment.x == 1) {
              right = (right + dx).clamp(left + 30.0, _width);
            }

            if (alignment.y == -1) {
              top = (top + dy).clamp(0.0, bottom - 30.0);
            } else if (alignment.y == 1) {
              bottom = (bottom + dy).clamp(top + 30.0, _height);
            }

            _cropRect = Rect.fromLTRB(left, top, right, bottom);
          });
        },
        onPanEnd: (_) {
          widget.controller.isInteractingWithObject.value = false;
        },
        onPanCancel: () {
          widget.controller.isInteractingWithObject.value = false;
        },
        child: Container(
          width: 44,
          height: 44,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: isCorner
              ? Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF6B4EFF),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                )
              : isHorizontalEdge
                  ? Container(
                      width: 24,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF6B4EFF),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: 7,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF6B4EFF),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildCropOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 4 Dimmed masks around crop rect
        // Top mask
        if (_cropRect.top > 0)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: _cropRect.top,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        // Bottom mask
        if (_cropRect.bottom < _height)
          Positioned(
            left: 0,
            top: _cropRect.bottom,
            right: 0,
            height: _height - _cropRect.bottom,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        // Left mask
        if (_cropRect.left > 0)
          Positioned(
            left: 0,
            top: _cropRect.top,
            width: _cropRect.left,
            height: _cropRect.height,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        // Right mask
        if (_cropRect.right < _width)
          Positioned(
            left: _cropRect.right,
            top: _cropRect.top,
            width: _width - _cropRect.right,
            height: _cropRect.height,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),

        // The active crop window (with border and rule-of-thirds grid)
        Positioned(
          left: _cropRect.left,
          top: _cropRect.top,
          width: _cropRect.width,
          height: _cropRect.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              widget.controller.isInteractingWithObject.value = true;
            },
            onPanUpdate: (details) {
              setState(() {
                final newLeft = (_cropRect.left + details.delta.dx)
                    .clamp(0.0, _width - _cropRect.width);
                final newTop = (_cropRect.top + details.delta.dy)
                    .clamp(0.0, _height - _cropRect.height);
                _cropRect = Rect.fromLTWH(
                  newLeft,
                  newTop,
                  _cropRect.width,
                  _cropRect.height,
                );
              });
            },
            onPanEnd: (_) {
              widget.controller.isInteractingWithObject.value = false;
            },
            onPanCancel: () {
              widget.controller.isInteractingWithObject.value = false;
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Stack(
                children: [
                  // Vertical 1/3 and 2/3 grid lines
                  Positioned(
                    left: _cropRect.width / 3,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: Container(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  Positioned(
                    left: _cropRect.width * 2 / 3,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: Container(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  // Horizontal 1/3 and 2/3 grid lines
                  Positioned(
                    top: _cropRect.height / 3,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: Container(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  Positioned(
                    top: _cropRect.height * 2 / 3,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: Container(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 8 Draggable Handles
        _buildCropHandle(Alignment.topLeft),
        _buildCropHandle(Alignment.topCenter),
        _buildCropHandle(Alignment.topRight),
        _buildCropHandle(Alignment.centerRight),
        _buildCropHandle(Alignment.bottomRight),
        _buildCropHandle(Alignment.bottomCenter),
        _buildCropHandle(Alignment.bottomLeft),
        _buildCropHandle(Alignment.centerLeft),
      ],
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(
              icon,
              size: 19,
              color: color ?? const Color(0xFF2D2A3E),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingToolbar() {
    if (_isCropping) {
      // Top crop control bar
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToolbarButton(
              icon: Icons.close_rounded,
              tooltip: 'إلغاء',
              color: Colors.redAccent,
              onTap: _cancelCrop,
            ),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'اقتصاص الصورة',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2A3E),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            _buildToolbarButton(
              icon: Icons.check_rounded,
              tooltip: 'تطبيق',
              color: const Color(0xFF10B981),
              onTap: _confirmCrop,
            ),
          ],
        ),
      );
    }

    // Normal floating toolbar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolbarButton(
            icon: Icons.copy_rounded,
            tooltip: 'نسخ',
            onTap: () {
              widget.controller.copyImage(widget.image);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ الصورة'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          if (SlideWorkspaceController.clipboardImage != null) ...[
            const SizedBox(width: 2),
            _buildToolbarButton(
              icon: Icons.content_paste_rounded,
              tooltip: 'لصق',
              onTap: () {
                widget.controller.pasteImage();
              },
            ),
          ],
          const SizedBox(width: 2),
          _buildToolbarButton(
            icon: Icons.crop_rounded,
            tooltip: 'اقتصاص',
            onTap: _startInPlaceCrop,
          ),
          if (widget.image.canDelete) ...[
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            _buildToolbarButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'حذف',
              color: Colors.redAccent,
              onTap: widget.onDelete,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final aspect = image.width / image.height;

    Widget imageChild = _WorkspaceImageDisplay(image: image);

    final bool toolbarAbove = _y >= 54.0;
    final double padTop = toolbarAbove ? 54.0 : 36.0;
    final double padBottom = toolbarAbove ? 36.0 : 54.0;
    const double padSide = 36.0;

    final containerLeft = _x - padSide;
    final containerTop = _y - padTop;
    final containerWidth = _width + padSide * 2;
    final containerHeight = _height + padTop + padBottom;

    return Positioned(
      left: containerLeft,
      top: containerTop,
      width: containerWidth,
      height: containerHeight,
      child: ValueListenableBuilder<SlideStroke?>(
        valueListenable: widget.controller.activeStroke,
        builder: (context, activeStroke, _) => IgnorePointer(
          ignoring: activeStroke != null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Image container
              Positioned(
                left: padSide,
                top: padTop,
                width: _width,
                height: _height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSelected,
                  onPanStart: (widget.isSelected && image.canMove && !_isCropping)
                      ? (_) {
                          widget.controller.isInteractingWithObject.value = true;
                        }
                      : null,
                  onPanUpdate: (widget.isSelected && image.canMove && !_isCropping)
                      ? (details) {
                          setState(() {
                            _x = (_x + details.delta.dx).clamp(0.0, 1100.0 - _width);
                            _y = (_y + details.delta.dy).clamp(0.0, 825.0 - _height);
                          });
                        }
                      : null,
                  onPanEnd: (widget.isSelected && image.canMove && !_isCropping)
                      ? (details) {
                          widget.controller.isInteractingWithObject.value = false;
                          _onInteractionEnd();
                        }
                      : null,
                  onPanCancel: () {
                    widget.controller.isInteractingWithObject.value = false;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.isSelected ? const Color(0xFF6B4EFF) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(child: imageChild),
                        if (_isCropping)
                          Positioned.fill(child: _buildCropOverlay()),
                        if (_isLoadingBytes)
                          Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        if (image.state == ImageState.uploading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B4EFF)),
                              ),
                            ),
                          ),
                        if (image.state == ImageState.uploadFailed)
                          Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      final tempId = image.localPath;
                                      if (tempId != null) {
                                        final isExam = !widget.controller.isStudyMode;
                                        const fileName = 'upload_retry.png';
                                        widget.controller.retryUpload(widget.controller.currentSlide.id, tempId, isExam, fileName);
                                      }
                                    },
                                    icon: const Icon(Icons.refresh_rounded, size: 14),
                                    label: const Text('Retry', style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
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

              // Normal 4 corner resize handles
              if (widget.isSelected && image.state != ImageState.uploading && !_isCropping) ...[
                if (image.canResize) ...[
                  _buildCornerHandle(Alignment.topLeft, aspect, padSide, padTop),
                  _buildCornerHandle(Alignment.topRight, aspect, padSide, padTop),
                  _buildCornerHandle(Alignment.bottomLeft, aspect, padSide, padTop),
                  _buildCornerHandle(Alignment.bottomRight, aspect, padSide, padTop),
                ],
              ],

              // Floating toolbar
              if (widget.isSelected && image.state != ImageState.uploading)
                Positioned(
                  top: toolbarAbove ? (padTop - 46) : (padTop + _height + 8),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildFloatingToolbar(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceImageDisplay extends StatefulWidget {
  final ImageObject image;
  const _WorkspaceImageDisplay({required this.image});

  @override
  State<_WorkspaceImageDisplay> createState() => _WorkspaceImageDisplayState();
}

class _WorkspaceImageDisplayState extends State<_WorkspaceImageDisplay> {
  String? _resolvedLocalPath;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(_WorkspaceImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.localPath != widget.image.localPath ||
        oldWidget.image.imageUrl != widget.image.imageUrl) {
      _checkCache();
    }
  }

  void _checkCache() {
    final img = widget.image;
    if (img.localPath != null && !kIsWeb && File(img.localPath!).existsSync()) {
      if (_resolvedLocalPath != img.localPath) {
        setState(() => _resolvedLocalPath = img.localPath);
      }
      return;
    }

    if (img.imageUrl != null && img.imageUrl!.isNotEmpty) {
      final cachedPath = ImageCacheService().getCachedPathSync(img.imageUrl!);
      if (cachedPath != null && !kIsWeb && File(cachedPath).existsSync()) {
        if (_resolvedLocalPath != cachedPath) {
          setState(() => _resolvedLocalPath = cachedPath);
        }
        return;
      }

      ImageCacheService().getOrDownload(img.imageUrl!).then((path) {
        if (path != null && mounted && _resolvedLocalPath != path) {
          setState(() => _resolvedLocalPath = path);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.image;

    if (_resolvedLocalPath != null && !kIsWeb && File(_resolvedLocalPath!).existsSync()) {
      return Image.file(
        File(_resolvedLocalPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    if (img.localPath != null) {
      final bytes = SlideWorkspaceController.localImageCache[img.localPath!];
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      }
    }

    if (img.imageUrl != null && img.imageUrl!.isNotEmpty) {
      return Image.network(
        img.imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return const Center(
      child: Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
