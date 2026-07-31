import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import 'slide_workspace_chrome.dart';

class WorkspaceLogo extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final Alignment alignment;

  const WorkspaceLogo({
    super.key,
    required this.color,
    required this.width,
    required this.height,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.modulate),
        child: Image.asset(
          'assets/Picsart_26-07-13_19-40-06-144.png',
          fit: BoxFit.contain,
          alignment: alignment,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: const Text(
              '.Stagiaire',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceTopToolbar extends StatelessWidget {
  final SlideWorkspaceController controller;
  final String stationName;
  final bool compact;
  final bool isDark;
  final bool showBrand;
  final bool showAddSlideButton;
  final int zoomPercent;
  final VoidCallback? onZoomTap;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback onBack;
  final VoidCallback? onAddSlide;
  final VoidCallback? onReorderSlides;

  const WorkspaceTopToolbar({
    super.key,
    required this.controller,
    required this.stationName,
    required this.compact,
    required this.isDark,
    this.showBrand = true,
    this.showAddSlideButton = true,
    this.zoomPercent = 100,
    this.onZoomTap,
    this.onZoomOut,
    this.onZoomIn,
    required this.onBack,
    this.onAddSlide,
    this.onReorderSlides,
  });

  static const _toolOrder = [
    WorkspaceTool.pen,
    WorkspaceTool.highlighter,
    WorkspaceTool.eraser,
  ];

  static const _toolIcons = {
    WorkspaceTool.pen: (Icons.edit_outlined, 'Pen'),
    WorkspaceTool.highlighter: (Icons.border_color_outlined, 'Highlighter'),
    WorkspaceTool.eraser: (Icons.crop_16_9_rounded, 'Eraser'),
    WorkspaceTool.shape: (Icons.category_outlined, 'Shapes'),
    WorkspaceTool.text: (Icons.text_fields_rounded, 'Text'),
  };

  static const _colors = [
    Colors.black,
    workspacePurple,
    Colors.red,
    Colors.blue,
    Colors.green,
  ];

  bool get _showDrawingOptions =>
      controller.selectedTool == WorkspaceTool.pen ||
      controller.selectedTool == WorkspaceTool.highlighter ||
      controller.selectedTool == WorkspaceTool.eraser ||
      controller.selectedTool == WorkspaceTool.shape;

  Color get _foreground => isDark ? Colors.white : workspaceInk;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLargeLandscape =
        media.orientation == Orientation.landscape && media.size.width >= 900;
    final isLargePortrait =
        media.orientation == Orientation.portrait && media.size.width >= 760;
    final isPhone = media.size.width < 600;
    final iconExtent = isPhone ? 28.0 : (isLargeLandscape ? 34.0 : 36.0);
    final iconSize = isPhone ? 16.0 : 18.0;

    if (isLargeLandscape) {
      return _buildLandscape(context, iconExtent: iconExtent, iconSize: iconSize);
    }

    return _buildPortrait(
      context,
      isPhone: isPhone,
      isLargePortrait: isLargePortrait,
      iconExtent: iconExtent,
      iconSize: iconSize,
    );
  }

  Widget _buildLandscape(
    BuildContext context, {
    required double iconExtent,
    required double iconSize,
  }) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        child: Row(
          children: [
            if (showBrand) _brand(width: 112, height: 34),
            if (showBrand) const SizedBox(width: 24),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toolGroup(
                        context,
                        iconExtent: iconExtent,
                        iconSize: iconSize,
                        includeColors: _showDrawingOptions,
                      ),
                      const SizedBox(width: 10),
                      if (_showDrawingOptions) ...[
                        _strokeWidthGroup(
                            iconExtent: iconExtent, iconSize: iconSize),
                        const SizedBox(width: 10),
                      ],
                      _zoomGroup(iconExtent: iconExtent, iconSize: iconSize),
                      const SizedBox(width: 10),
                      _historyButtons(
                          iconExtent: iconExtent, iconSize: iconSize),
                      const SizedBox(width: 12),
                      _zoomPercent(),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            _reorderButton(iconExtent: iconExtent, iconSize: iconSize),
            if (onReorderSlides != null) const SizedBox(width: 8),
            _backButton(iconExtent: iconExtent, iconSize: iconSize),
          ],
        ),
      ),
    );
  }

  Widget _buildPortrait(
    BuildContext context, {
    required bool isPhone,
    required bool isLargePortrait,
    required double iconExtent,
    required double iconSize,
  }) {
    final firstRowHeight = isPhone ? 44.0 : 56.0;
    final secondRowHeight = isPhone ? 44.0 : 52.0;

    if (isLargePortrait) {
      return SizedBox(
        height: firstRowHeight + (_showDrawingOptions ? secondRowHeight : 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SizedBox(
                height: firstRowHeight,
                child: Row(
                  children: [
                    if (showBrand) _brand(width: 112, height: 34),
                    if (showBrand) const SizedBox(width: 18),
                    _toolGroup(
                      context,
                      iconExtent: iconExtent,
                      iconSize: iconSize,
                      includeColors: false,
                    ),
                    const Spacer(),
                    _zoomGroup(
                      iconExtent: iconExtent,
                      iconSize: iconSize,
                      showPercentInside: true,
                    ),
                    const SizedBox(width: 10),
                    _historyButtons(iconExtent: iconExtent, iconSize: iconSize),
                    const SizedBox(width: 8),
                    _reorderButton(iconExtent: iconExtent, iconSize: iconSize),
                    if (onReorderSlides != null) const SizedBox(width: 8),
                    _backButton(iconExtent: iconExtent, iconSize: iconSize),
                  ],
                ),
              ),
              if (_showDrawingOptions)
                SizedBox(
                  height: secondRowHeight,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _colorGroup(isPhone: false),
                          const SizedBox(width: 10),
                          _strokeWidthGroup(
                              iconExtent: iconExtent, iconSize: iconSize),
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

    return SizedBox(
      height: firstRowHeight + (_showDrawingOptions ? secondRowHeight : 0),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isPhone ? 6 : 16),
        child: Column(
          children: [
            SizedBox(
              height: firstRowHeight,
              child: Row(
                children: [
                  if (showBrand)
                    _brand(
                      width: isPhone ? 64 : 104,
                      height: isPhone ? 29 : 32,
                    ),
                  if (showBrand) SizedBox(width: isPhone ? 8 : 22),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _toolGroup(
                          context,
                          iconExtent: iconExtent,
                          iconSize: iconSize,
                          includeColors: false,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isPhone ? 2 : 10),
                  _historyButtons(iconExtent: iconExtent, iconSize: iconSize),
                  SizedBox(width: isPhone ? 2 : 8),
                  _reorderButton(iconExtent: iconExtent, iconSize: iconSize),
                  if (onReorderSlides != null) SizedBox(width: isPhone ? 2 : 8),
                  _backButton(iconExtent: iconExtent, iconSize: iconSize),
                ],
              ),
            ),
            if (_showDrawingOptions)
              SizedBox(
                height: secondRowHeight,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _colorGroup(isPhone: isPhone),
                        SizedBox(width: isPhone ? 6 : 10),
                        _strokeWidthGroup(
                            iconExtent: iconExtent, iconSize: iconSize),
                        SizedBox(width: isPhone ? 6 : 10),
                        _zoomGroup(iconExtent: iconExtent, iconSize: iconSize),
                        SizedBox(width: isPhone ? 7 : 12),
                        _zoomPercent(),
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

  Widget _brand({required double width, required double height}) {
    return WorkspaceLogo(
      color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
      width: width,
      height: height,
    );
  }

  Widget _toolGroup(
    BuildContext context, {
    required double iconExtent,
    required double iconSize,
    required bool includeColors,
  }) {
    return ToolbarCapsule(
      isDark: isDark,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 7,
        vertical: compact ? 3 : 5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tool in _toolOrder)
            WorkspaceIconButton(
              icon: _toolIcons[tool]!.$1,
              tooltip: _toolIcons[tool]!.$2,
              selected: controller.selectedTool == tool,
              foregroundColor: _foreground,
              size: iconExtent,
              iconSize: iconSize,
              onTap: () => controller.selectTool(tool),
            ),
          if (onAddSlide != null && showAddSlideButton)
            WorkspaceIconButton(
              icon: Icons.add_box_outlined,
              tooltip: 'Add slide',
              foregroundColor: _foreground,
              size: iconExtent,
              iconSize: iconSize,
              onTap: onAddSlide,
            ),
          WorkspaceIconButton(
            icon: controller.isStudyMode
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            tooltip:
                controller.isStudyMode ? 'Study mode on' : 'Study mode off',
            selected: !controller.isStudyMode,
            foregroundColor: _foreground,
            size: iconExtent,
            iconSize: iconSize,
            onTap: controller.toggleStudyMode,
          ),
          WorkspaceIconButton(
            icon: Icons.image_search_outlined,
            tooltip: 'Add image to workspace',
            foregroundColor: _foreground,
            size: iconExtent,
            iconSize: iconSize,
            onTap: () async {
              final source = await showModalBottomSheet<ImageSource>(
                context: context,
                backgroundColor: isDark ? const Color(0xFF1E1B30) : Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (sheetCtx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.camera_alt_outlined, color: isDark ? Colors.white : Colors.black87),
                        title: Text('Take Photo', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                      ),
                      ListTile(
                        leading: Icon(Icons.photo_library_outlined, color: isDark ? Colors.white : Colors.black87),
                        title: Text('Choose from Gallery', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                      ),
                    ],
                  ),
                ),
              );

              if (source == null) return;

              final picker = ImagePicker();
              final pickedFile = await picker.pickImage(
                source: source,
                imageQuality: 85,
                maxWidth: 1920,
                maxHeight: 1920,
              );
              if (pickedFile == null) return;

              final bytes = await pickedFile.readAsBytes();
              if (bytes.lengthInBytes > 3 * 1024 * 1024) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please choose an image smaller than 3 MB.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
                return;
              }

              final decoded = await decodeImageFromList(bytes);

              if (context.mounted) {
                final error = await controller.addImageObject(
                  bytes,
                  pickedFile.name,
                  originalWidth: decoded.width.toDouble(),
                  originalHeight: decoded.height.toDouble(),
                );
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
          ),
          if (includeColors) ...[
            const SizedBox(width: 5),
            SizedBox(
              height: 26,
              child: VerticalDivider(
                width: 10,
                thickness: 1,
                color:
                    isDark ? const Color(0xFF4A4364) : const Color(0xFFE6E1F3),
              ),
            ),
            for (final color in _colors)
              ColorDot(
                color: color,
                selected:
                    controller.selectedColor.toARGB32() == color.toARGB32(),
                onTap: () => controller.selectColor(color),
              ),
            ColorDot(
              color: Colors.pink,
              rainbow: true,
              selected: false,
              onTap: () => controller.selectColor(Colors.pink),
            ),
          ],
        ],
      ),
    );
  }

  Widget _colorGroup({required bool isPhone}) {
    return ToolbarCapsule(
      isDark: isDark,
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 4 : 7,
        vertical: isPhone ? 5 : 7,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in _colors)
            ColorDot(
              color: color,
              selected: controller.selectedColor.toARGB32() == color.toARGB32(),
              onTap: () => controller.selectColor(color),
            ),
          ColorDot(
            color: Colors.pink,
            rainbow: true,
            selected: false,
            onTap: () => controller.selectColor(Colors.pink),
          ),
        ],
      ),
    );
  }

  Widget _strokeWidthGroup({
    required double iconExtent,
    required double iconSize,
  }) {
    return ToolbarCapsule(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'Smaller stroke',
            foregroundColor: _foreground,
            size: iconExtent,
            iconSize: iconSize,
            onTap: () => controller.setStrokeWidth(controller.strokeWidth - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '${controller.strokeWidth.round()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _foreground,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          WorkspaceIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Larger stroke',
            foregroundColor: _foreground,
            size: iconExtent,
            iconSize: iconSize,
            onTap: () => controller.setStrokeWidth(controller.strokeWidth + 1),
          ),
        ],
      ),
    );
  }

  Widget _zoomGroup({
    required double iconExtent,
    required double iconSize,
    bool showPercentInside = false,
  }) {
    return ToolbarCapsule(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceIconButton(
            icon: Icons.zoom_out_rounded,
            tooltip:
                showPercentInside ? 'Zoom out - $zoomPercent%' : 'Zoom out',
            foregroundColor: _foreground,
            size: showPercentInside ? iconExtent + 28 : iconExtent,
            iconSize: iconSize,
            label: showPercentInside ? '$zoomPercent%' : null,
            onTap: onZoomOut,
          ),
          WorkspaceIconButton(
            icon: Icons.zoom_in_rounded,
            tooltip: showPercentInside ? 'Zoom in - $zoomPercent%' : 'Zoom in',
            foregroundColor: _foreground,
            size: showPercentInside ? iconExtent + 28 : iconExtent,
            iconSize: iconSize,
            label: showPercentInside ? '$zoomPercent%' : null,
            onTap: onZoomIn,
          ),
        ],
      ),
    );
  }

  Widget _historyButtons({
    required double iconExtent,
    required double iconSize,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceIconButton(
          icon: Icons.undo_rounded,
          tooltip: 'Undo',
          foregroundColor: _foreground,
          size: iconExtent,
          iconSize: iconSize,
          onTap: controller.canUndo ? controller.undo : null,
        ),
        WorkspaceIconButton(
          icon: Icons.redo_rounded,
          tooltip: 'Redo',
          foregroundColor: _foreground,
          size: iconExtent,
          iconSize: iconSize,
          onTap: controller.canRedo ? controller.redo : null,
        ),
      ],
    );
  }

  Widget _zoomPercent() {
    return Tooltip(
      message: 'Reset zoom',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onZoomTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: Text(
            '$zoomPercent%',
            style: TextStyle(
              color: _foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _reorderButton({
    required double iconExtent,
    required double iconSize,
  }) {
    if (onReorderSlides == null) return const SizedBox.shrink();
    return WorkspaceIconButton(
      icon: Icons.swap_vert_rounded,
      tooltip: 'ترتيب الشرائح',
      foregroundColor: _foreground,
      size: iconExtent,
      iconSize: iconSize,
      onTap: onReorderSlides,
    );
  }

  Widget _backButton({
    required double iconExtent,
    required double iconSize,
  }) {
    return WorkspaceIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back',
      foregroundColor: _foreground,
      size: iconExtent,
      iconSize: iconSize,
      onTap: onBack,
    );
  }
}
