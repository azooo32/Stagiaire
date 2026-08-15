import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import '../screens/slide_image_crop_screen.dart';
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

  Future<void> _cropImage() async {
    final image = widget.image;
    setState(() {
      _isLoadingBytes = true;
    });
    try {
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

      if (bytes != null && mounted) {
        setState(() {
          _isLoadingBytes = false;
        });
        final croppedBytes = await SlideImageCropScreen.show(context, bytes);
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

          final decodedImage = await decodeImageFromList(croppedBytes);
          final double originalWidth = decodedImage.width.toDouble();
          final double originalHeight = decodedImage.height.toDouble();
          final double newAspectRatio = originalWidth / originalHeight;
          final double newHeight = _width / newAspectRatio;

          setState(() {
            _height = newHeight;
          });

          final updatedImage = image.copyWith(
            localPath: newLocalPath,
            imageUrl: null,
            storagePath: null,
            state: ImageState.local,
            height: newHeight,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );

          widget.controller.mutateObject(widget.controller.currentSlide.id, image.id, isExam, (_) => updatedImage);
          widget.controller.triggerUploadForObject(widget.controller.currentSlide.id, updatedImage, isExam);
          widget.controller.scheduleSave(widget.controller.currentSlide.id);
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingBytes = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load image bytes for cropping')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBytes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

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

  void _onInteractionEnd() {
    // We should compute delta or just execute command
    // Let's create the command using controller.executeCommand
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

  Widget _buildCornerHandle(Alignment alignment, double aspect) {
    return Positioned(
      left: alignment.x == -1 ? 0 : null,
      right: alignment.x == 1 ? 0 : null,
      top: alignment.y == -1 ? 0 : null,
      bottom: alignment.y == 1 ? 0 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          // Intercept gesture
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
        onPanEnd: (details) => _onInteractionEnd(),
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
                  color: Colors.black.withValues(alpha: 0.2),
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

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final aspect = image.width / image.height;

    Widget imageChild = _WorkspaceImageDisplay(image: image);

    return Positioned(
      left: _x - 36,
      top: _y - 36,
      width: _width + 72,
      height: _height + 72,
      child: ValueListenableBuilder<SlideStroke?>(
        valueListenable: widget.controller.activeStroke,
        builder: (context, activeStroke, _) => IgnorePointer(
          ignoring: activeStroke != null,
          child: Stack(
            children: [
              Positioned(
                left: 36,
                top: 36,
                width: _width,
                height: _height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSelected,
                  onPanUpdate: (widget.isSelected && image.canMove)
                      ? (details) {
                          setState(() {
                            _x = (_x + details.delta.dx).clamp(0.0, 1100.0 - _width);
                            _y = (_y + details.delta.dy).clamp(0.0, 825.0 - _height);
                          });
                        }
                      : null,
                  onPanEnd: (widget.isSelected && image.canMove)
                      ? (details) {
                          _onInteractionEnd();
                        }
                      : null,
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
              if (widget.isSelected && image.state != ImageState.uploading) ...[
                if (image.canResize) ...[
                  _buildCornerHandle(Alignment.topLeft, aspect),
                  _buildCornerHandle(Alignment.topRight, aspect),
                  _buildCornerHandle(Alignment.bottomLeft, aspect),
                  _buildCornerHandle(Alignment.bottomRight, aspect),
                ],
                Positioned(
                  left: 44,
                  top: 44,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (image.canDelete) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onDelete,
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.delete_forever_rounded,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _cropImage,
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.crop_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
