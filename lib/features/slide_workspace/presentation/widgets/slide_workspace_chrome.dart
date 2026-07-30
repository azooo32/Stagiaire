import 'package:flutter/material.dart';

import '../../domain/entities/slide_workspace_models.dart';

const workspacePurple = Color(0xFF5B35F5);
const workspaceInk = Color(0xFF151044);
const workspaceMuted = Color(0xFF8A84AF);

class WorkspaceIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final String tooltip;
  final Color? foregroundColor;
  final double size;
  final double iconSize;
  final String? label;

  const WorkspaceIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.foregroundColor,
    this.size = 38,
    this.iconSize = 18,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? workspacePurple : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: label == null
              ? Icon(icon,
                  size: iconSize,
                  color: selected
                      ? Colors.white
                      : (foregroundColor ?? workspaceInk))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: iconSize,
                        color: selected
                            ? Colors.white
                            : (foregroundColor ?? workspaceInk)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        label!,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : (foregroundColor ?? workspaceInk),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
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

class ToolRailButton extends StatelessWidget {
  final WorkspaceTool tool;
  final WorkspaceTool selectedTool;
  final IconData icon;
  final String label;
  final ValueChanged<WorkspaceTool> onSelected;

  const ToolRailButton({
    super.key,
    required this.tool,
    required this.selectedTool,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = tool == selectedTool;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onSelected(tool),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? workspacePurple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 22, color: selected ? Colors.white : workspaceInk),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  color: selected ? Colors.white : workspacePurple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool rainbow;

  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.rainbow = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 23,
        height: 23,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: rainbow
              ? const SweepGradient(colors: [
                  Colors.red,
                  Colors.yellow,
                  Colors.green,
                  Colors.blue,
                  Colors.purple,
                  Colors.red
                ])
              : null,
          color: rainbow ? null : color,
          border: Border.all(
              color: selected ? workspaceInk : Colors.white,
              width: selected ? 2 : 1),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .18), blurRadius: 8)
          ],
        ),
      ),
    );
  }
}

class ToolbarCapsule extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;

  const ToolbarCapsule({
    super.key,
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEE191528) : const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF332C4A) : const Color(0xFFE6E1F3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
