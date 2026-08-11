import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/image_cache_service.dart';
import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';
import 'slide_pages_list.dart';

class _ReorderEntry {
  final String subtitle;
  final WorkspaceSlide? slide;

  _ReorderEntry({required this.subtitle, this.slide});

  bool get isHeader => slide == null;
}


class SlideReorderDialog extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool isDark;

  const SlideReorderDialog({
    super.key,
    required this.controller,
    required this.isDark,
  });

  static Future<bool?> show(
    BuildContext context, {
    required SlideWorkspaceController controller,
    required bool isDark,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SlideReorderDialog(
        controller: controller,
        isDark: isDark,
      ),
    );
  }

  @override
  State<SlideReorderDialog> createState() => _SlideReorderDialogState();
}

class _SlideReorderDialogState extends State<SlideReorderDialog> {
  late List<WorkspaceSlide> _slides;
  late List<_ReorderEntry> _entries;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _slides = List<WorkspaceSlide>.from(widget.controller.slides);
    _buildEntries();
  }

  void _buildEntries() {
    _entries = [];
    String? previousSubtitle;
    for (final slide in _slides) {
      final subtitle = slide.subtitle.trim().isEmpty ? 'Untitled' : slide.subtitle.trim();
      if (previousSubtitle == null || previousSubtitle.toLowerCase() != subtitle.toLowerCase()) {
        _entries.add(_ReorderEntry(subtitle: subtitle));
        previousSubtitle = subtitle;
      }
      _entries.add(_ReorderEntry(subtitle: subtitle, slide: slide));
    }
  }

  void _updateSlidesFromEntries() {
    final newSlides = <WorkspaceSlide>[];
    String currentSubtitle = '';
    
    for (final entry in _entries) {
      if (entry.isHeader) {
        currentSubtitle = entry.subtitle;
      } else {
        final slide = entry.slide!;
        newSlides.add(slide.copyWith(
          subtitle: currentSubtitle == 'Untitled' ? '' : currentSubtitle,
        ));
      }
    }
    
    _slides = newSlides;
    _buildEntries();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      await widget.controller.reorderSlides(_slides);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ أثناء حفظ ترتيب الشرائح: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final dialogBg = isDark ? const Color(0xFF1E1A2E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF28233D) : const Color(0xFFF7F5FE);
    final borderColor = isDark ? const Color(0xFF3B3356) : const Color(0xFFE2DCFA);
    final textColor = isDark ? Colors.white : workspaceInk;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 640,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: workspacePurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.swap_vert_rounded,
                    color: workspacePurple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ترتيب الشرائح',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'قم بسحب وإفلات الشرائح لترتيبها ثم اضغط حفظ',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : workspaceMuted,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إلغاء',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Reorderable List of Slide Thumbnails and Subtitle Headers
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: _entries.length,
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = _entries.removeAt(oldIndex);
                    _entries.insert(newIndex, item);
                    _updateSlidesFromEntries();
                  });
                },
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  if (entry.isHeader) {
                    return KeyedSubtree(
                      key: ValueKey('header_${entry.subtitle}_$index'),
                      child: Container(
                        margin: const EdgeInsets.only(top: 14, bottom: 8),
                        child: SubtitleHeader(
                          subtitle: entry.subtitle,
                          isDark: isDark,
                          compact: true,
                        ),
                      ),
                    );
                  }

                  final slide = entry.slide!;
                  return KeyedSubtree(
                    key: ValueKey(slide.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: isDark ? Colors.white54 : workspaceMuted,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Index Badge
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: workspacePurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_slides.indexOf(slide) + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Slide Thumbnail Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 68,
                              height: 44,
                              child: _SlideThumbnailView(
                                imageUrl: slide.imageAsset,
                                isDark: isDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Slide Details (Title & Subtitle)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slide.title.trim().isEmpty ? 'شريحة بدون عنوان' : slide.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                if (slide.subtitle.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    slide.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFFB4A6E8) : workspacePurple,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (slide.isHidden) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'مخفي',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),
            const SizedBox(height: 16),

            // Footer buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 15),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: workspacePurple,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _isSaving ? 'جاري الحفظ...' : 'حفظ الترتيب',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideThumbnailView extends StatefulWidget {
  final String imageUrl;
  final bool isDark;

  const _SlideThumbnailView({
    required this.imageUrl,
    required this.isDark,
  });

  @override
  State<_SlideThumbnailView> createState() => _SlideThumbnailViewState();
}

class _SlideThumbnailViewState extends State<_SlideThumbnailView> {
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  @override
  void didUpdateWidget(covariant _SlideThumbnailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolvePath();
    }
  }

  void _resolvePath() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty || kIsWeb) return;
    final path = ImageCacheService().getCachedPathSync(url);
    if (path != null && path.isNotEmpty) {
      _cachedPath = path;
    } else if (url.startsWith('http')) {
      ImageCacheService().getOrDownload(url).then((downloaded) {
        if (mounted && downloaded != null) {
          setState(() {
            _cachedPath = downloaded;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl.trim();
    final placeholder = Container(
      color: widget.isDark ? const Color(0xFF342D4B) : const Color(0xFFEBE7FA),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: widget.isDark ? Colors.white38 : workspaceMuted,
        size: 24,
      ),
    );

    if (url.isEmpty) return placeholder;

    if (_cachedPath != null && _cachedPath!.isNotEmpty && !kIsWeb) {
      return Image.file(
        File(_cachedPath!),
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    if (!kIsWeb) {
      return Image.file(
        File(url),
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    return placeholder;
  }
}
