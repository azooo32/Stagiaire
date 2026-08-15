import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../features/slide_workspace/domain/entities/slide_workspace_models.dart';

/// Service to parse embedded PDF annotations (Ink, Shapes, Highlights)
/// and convert them into interactive WorkspaceObjects.
class PdfAnnotationParser {
  /// Parses a PDF file (or loads from disk cache `embedded_annotations.json`)
  static Future<Map<int, List<WorkspaceObject>>> parseEmbeddedAnnotationsWithCache(
    String pdfPath,
    String cacheDirPath,
  ) async {
    final cacheFile = File('$cacheDirPath/embedded_annotations.json');
    if (await cacheFile.exists()) {
      try {
        final jsonStr = await cacheFile.readAsString();
        final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final results = <int, List<WorkspaceObject>>{};
        for (final entry in jsonMap.entries) {
          final pageNum = int.tryParse(entry.key);
          if (pageNum != null && entry.value is List) {
            final objects = (entry.value as List)
                .map((item) => WorkspaceObject.fromJson(item as Map<String, dynamic>))
                .toList();
            results[pageNum] = objects;
          }
        }
        return results;
      } catch (e) {
        debugPrint('Error reading embedded annotations cache: $e');
      }
    }

    // Parse embedded annotations
    Map<int, List<WorkspaceObject>> parsed;
    try {
      parsed = await Isolate.run(() => parseEmbeddedAnnotations(pdfPath));
    } catch (_) {
      parsed = await parseEmbeddedAnnotations(pdfPath);
    }

    // Save to disk cache
    try {
      final jsonMap = <String, dynamic>{};
      for (final entry in parsed.entries) {
        jsonMap['${entry.key}'] = entry.value.map((o) => o.toJson()).toList();
      }
      await cacheFile.writeAsString(jsonEncode(jsonMap));
    } catch (e) {
      debugPrint('Error saving embedded annotations cache: $e');
    }

    return parsed;
  }

  /// Parses a PDF file and returns a Map of `pageNumber (1-based)` -> `List<WorkspaceObject>`.
  static Future<Map<int, List<WorkspaceObject>>> parseEmbeddedAnnotations(String pdfPath) async {
    final result = <int, List<WorkspaceObject>>{};
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return result;

      final bytes = await file.readAsBytes();
      final latin1Str = latin1.decode(bytes, allowInvalid: true);

      // Default MediaBox from parent /Pages node if present
      double parentW = 595;
      double parentH = 842;
      final pagesNodeMatch = RegExp(r'/Type\s*/Pages\b[^>]*?/MediaBox\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]', dotAll: true).firstMatch(latin1Str);
      if (pagesNodeMatch != null) {
        parentW = double.tryParse(pagesNodeMatch.group(3)!) ?? 595;
        parentH = double.tryParse(pagesNodeMatch.group(4)!) ?? 842;
      }

      // 1. Resolve all Page objects and their MediaBoxes + /Annots
      final pageObjs = <int, _PdfPageInfo>{};
      final pageObjRegex = RegExp(r'(\d+)\s+0\s+obj\s*<<[^>]*?/Type\s*/Page\b(.*?)>>', dotAll: true);

      for (final m in pageObjRegex.allMatches(latin1Str)) {
        final objNum = int.parse(m.group(1)!);
        final body = m.group(0)!;
        if (body.contains('/Type /Pages') || body.contains('/Type/Pages')) continue;

        double pageH = parentH;
        double pageW = parentW;
        final mbMatch = RegExp(r'/MediaBox\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
        if (mbMatch != null) {
          pageW = double.tryParse(mbMatch.group(3)!) ?? parentW;
          pageH = double.tryParse(mbMatch.group(4)!) ?? parentH;
        }

        String annotsContent = '';
        final annotsMatch = RegExp(r'/Annots\s+(\d+\s+0\s+R|\[[^\]]*\])').firstMatch(body);
        if (annotsMatch != null) {
          annotsContent = annotsMatch.group(1)!;
          if (annotsContent.contains('R') && !annotsContent.startsWith('[')) {
            final refNum = int.parse(annotsContent.split(' ').first);
            final refMatch = RegExp('$refNum\\s+0\\s+obj\\s*(?:<<.*?>>\\s*)?(\\[.*?\\])\\s*endobj', dotAll: true).firstMatch(latin1Str);
            if (refMatch != null) {
              annotsContent = refMatch.group(1)!;
            }
          }
        }

        pageObjs[objNum] = _PdfPageInfo(
          objNum: objNum,
          width: pageW,
          height: pageH,
          annotsContent: annotsContent,
        );
      }

      // 2. Order pages as they appear in the PDF
      final orderedPageObjList = pageObjs.values.toList();

      for (var pageIdx = 0; pageIdx < orderedPageObjList.length; pageIdx++) {
        final pageNum = pageIdx + 1;
        final pageInfo = orderedPageObjList[pageIdx];
        final pageStrokes = <WorkspaceObject>[];

        final refRegex = RegExp(r'(\d+)\s+0\s+R');
        final annotRefs = refRegex.allMatches(pageInfo.annotsContent).map((m) => int.parse(m.group(1)!)).toList();

        for (final annotRef in annotRefs) {
          final annotMatch = RegExp('$annotRef\\s+0\\s+obj(.*?)endobj', dotAll: true).firstMatch(latin1Str);
          if (annotMatch == null) continue;
          final body = annotMatch.group(1)!;

          final subtypeMatch = RegExp(r'/Subtype\s*/([A-Za-z0-9_]+)').firstMatch(body);
          if (subtypeMatch == null) continue;
          final subtype = subtypeMatch.group(1);

          // Color
          int colorValue = const Color(0xFFE44234).toARGB32();
          final cMatch = RegExp(r'/C\s*\[\s*([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s*\]').firstMatch(body);
          if (cMatch != null) {
            final r = (double.parse(cMatch.group(1)!) * 255).round().clamp(0, 255);
            final g = (double.parse(cMatch.group(2)!) * 255).round().clamp(0, 255);
            final b = (double.parse(cMatch.group(3)!) * 255).round().clamp(0, 255);
            colorValue = Color.fromARGB(255, r, g, b).toARGB32();
          }

          // Opacity
          double opacity = 1.0;
          final caMatch = RegExp(r'/(?:ca|CA)\s+([\d\.]+)').firstMatch(body);
          if (caMatch != null) {
            opacity = double.tryParse(caMatch.group(1)!) ?? 1.0;
          }

          // Stroke Width
          double strokeWidth = 2.5;
          final bsMatch = RegExp(r'/BS\s*<<[^>]*?/W\s*([\d\.]+)[^>]*?>>').firstMatch(body);
          final borderMatch = RegExp(r'/Border\s*\[\s*[\d\.]+\s+[\d\.]+\s+([\d\.]+)\s*\]').firstMatch(body);
          if (bsMatch != null) {
            strokeWidth = double.tryParse(bsMatch.group(1)!) ?? 2.5;
          } else if (borderMatch != null) {
            strokeWidth = double.tryParse(borderMatch.group(1)!) ?? 2.5;
          }

          final now = DateTime.now().millisecondsSinceEpoch;

          if (subtype == 'Ink') {
            final inkListIdx = body.indexOf('/InkList');
            if (inkListIdx != -1) {
              final inkSub = body.substring(inkListIdx);
              final strokeRegex = RegExp(r'\[\s*([\d\.\s\-]+)\s*\]');
              final strokeMatches = strokeRegex.allMatches(inkSub).toList();

              for (var s = 0; s < strokeMatches.length; s++) {
                final nums = strokeMatches[s]
                    .group(1)!
                    .trim()
                    .split(RegExp(r'\s+'))
                    .map(double.tryParse)
                    .whereType<double>()
                    .toList();

                if (nums.length < 4) continue; // Need at least 2 points (4 coordinates)

                final points = <StrokePoint>[];
                for (var i = 0; i + 1 < nums.length; i += 2) {
                  final x = nums[i];
                  final y = pageInfo.height - nums[i + 1];
                  points.add(StrokePoint(x: x, y: y));
                }

                if (points.length >= 2) {
                  pageStrokes.add(
                    SlideStroke(
                      id: 'pdf_annot_${annotRef}_stroke_$s',
                      points: points,
                      colorValue: colorValue,
                      width: strokeWidth.clamp(1.0, 20.0),
                      opacity: opacity.clamp(0.1, 1.0),
                      tool: opacity < 0.6 ? WorkspaceTool.highlighter : WorkspaceTool.pen,
                      createdAtMillis: now,
                    ),
                  );
                }
              }
            }
          } else if (subtype == 'Square') {
            final rectMatch = RegExp(r'/Rect\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
            if (rectMatch != null) {
              final x1 = double.parse(rectMatch.group(1)!);
              final y1 = double.parse(rectMatch.group(2)!);
              final x2 = double.parse(rectMatch.group(3)!);
              final y2 = double.parse(rectMatch.group(4)!);

              final points = [
                StrokePoint(x: x1, y: pageInfo.height - y2),
                StrokePoint(x: x2, y: pageInfo.height - y2),
                StrokePoint(x: x2, y: pageInfo.height - y1),
                StrokePoint(x: x1, y: pageInfo.height - y1),
                StrokePoint(x: x1, y: pageInfo.height - y2),
              ];

              pageStrokes.add(
                SlideStroke(
                  id: 'pdf_annot_${annotRef}_square',
                  points: points,
                  colorValue: colorValue,
                  width: strokeWidth.clamp(1.0, 15.0),
                  opacity: opacity,
                  tool: WorkspaceTool.pen,
                  createdAtMillis: now,
                ),
              );
            }
          } else if (subtype == 'Circle') {
            final rectMatch = RegExp(r'/Rect\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
            if (rectMatch != null) {
              final x1 = double.parse(rectMatch.group(1)!);
              final y1 = double.parse(rectMatch.group(2)!);
              final x2 = double.parse(rectMatch.group(3)!);
              final y2 = double.parse(rectMatch.group(4)!);

              final cx = (x1 + x2) / 2;
              final cy = pageInfo.height - (y1 + y2) / 2;
              final rx = (x2 - x1).abs() / 2;
              final ry = (y2 - y1).abs() / 2;

              final points = <StrokePoint>[];
              for (var angle = 0; angle <= 360; angle += 15) {
                final rad = angle * (math.pi / 180);
                points.add(StrokePoint(x: cx + rx * math.cos(rad), y: cy + ry * math.sin(rad)));
              }

              pageStrokes.add(
                SlideStroke(
                  id: 'pdf_annot_${annotRef}_circle',
                  points: points,
                  colorValue: colorValue,
                  width: strokeWidth.clamp(1.0, 15.0),
                  opacity: opacity,
                  tool: WorkspaceTool.pen,
                  createdAtMillis: now,
                ),
              );
            }
          } else if (subtype == 'Line') {
            final lMatch = RegExp(r'/L\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
            if (lMatch != null) {
              final x1 = double.parse(lMatch.group(1)!);
              final y1 = double.parse(lMatch.group(2)!);
              final x2 = double.parse(lMatch.group(3)!);
              final y2 = double.parse(lMatch.group(4)!);

              pageStrokes.add(
                SlideStroke(
                  id: 'pdf_annot_${annotRef}_line',
                  points: [
                    StrokePoint(x: x1, y: pageInfo.height - y1),
                    StrokePoint(x: x2, y: pageInfo.height - y2),
                  ],
                  colorValue: colorValue,
                  width: strokeWidth.clamp(1.0, 15.0),
                  opacity: opacity,
                  tool: WorkspaceTool.pen,
                  createdAtMillis: now,
                ),
              );
            }
          } else if (subtype == 'Highlight') {
            final quadMatch = RegExp(r'/QuadPoints\s*\[\s*([\d\.\s\-]+)\s*\]').firstMatch(body);
            if (quadMatch != null) {
              final nums = quadMatch.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
              for (var q = 0; q + 7 < nums.length; q += 8) {
                final x1 = nums[q];
                final y1 = nums[q + 1];
                final x2 = nums[q + 2];
                final y2 = nums[q + 3];
                final y3 = nums[q + 5];
                final y4 = nums[q + 7];

                final midY1 = (y1 + y4) / 2;
                final midY2 = (y2 + y3) / 2;
                final h = ((y1 - y4).abs() + (y2 - y3).abs()) / 2;

                pageStrokes.add(
                  SlideStroke(
                    id: 'pdf_annot_${annotRef}_hl_$q',
                    points: [
                      StrokePoint(x: x1, y: pageInfo.height - midY1),
                      StrokePoint(x: x2, y: pageInfo.height - midY2),
                    ],
                    colorValue: colorValue != 0 ? colorValue : const Color(0xFFFFEB3B).toARGB32(),
                    width: h > 0 ? h : 16.0,
                    opacity: 0.35,
                    tool: WorkspaceTool.highlighter,
                    createdAtMillis: now,
                  ),
                );
              }
            }
          } else if (subtype == 'Text' || subtype == 'FreeText') {
            final rectMatch = RegExp(r'/Rect\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
            if (rectMatch != null) {
              final x1 = double.parse(rectMatch.group(1)!);
              final y1 = double.parse(rectMatch.group(2)!);
              final x2 = double.parse(rectMatch.group(3)!);
              final y2 = double.parse(rectMatch.group(4)!);

              final points = [
                StrokePoint(x: x1, y: pageInfo.height - y2),
                StrokePoint(x: x2, y: pageInfo.height - y2),
                StrokePoint(x: x2, y: pageInfo.height - y1),
                StrokePoint(x: x1, y: pageInfo.height - y1),
                StrokePoint(x: x1, y: pageInfo.height - y2),
              ];

              pageStrokes.add(
                SlideStroke(
                  id: 'pdf_annot_${annotRef}_text',
                  points: points,
                  colorValue: colorValue != 0 ? colorValue : const Color(0xFFFFD54F).toARGB32(),
                  width: strokeWidth.clamp(1.5, 8.0),
                  opacity: opacity,
                  tool: WorkspaceTool.pen,
                  createdAtMillis: now,
                ),
              );
            }
          } else if (subtype == 'PolyLine' || subtype == 'Polygon') {
            final vertMatch = RegExp(r'/Vertices\s*\[\s*([\d\.\s\-]+)\s*\]').firstMatch(body);
            if (vertMatch != null) {
              final nums = vertMatch.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
              final points = <StrokePoint>[];
              for (var i = 0; i + 1 < nums.length; i += 2) {
                final x = nums[i];
                final y = pageInfo.height - nums[i + 1];
                points.add(StrokePoint(x: x, y: y));
              }
              if (subtype == 'Polygon' && points.isNotEmpty) {
                points.add(points.first);
              }
              if (points.length >= 2) {
                pageStrokes.add(
                  SlideStroke(
                    id: 'pdf_annot_${annotRef}_poly',
                    points: points,
                    colorValue: colorValue,
                    width: strokeWidth.clamp(1.0, 15.0),
                    opacity: opacity,
                    tool: WorkspaceTool.pen,
                    createdAtMillis: now,
                  ),
                );
              }
            }
          } else if (subtype == 'Underline' || subtype == 'StrikeOut' || subtype == 'Squiggly') {
            final quadMatch = RegExp(r'/QuadPoints\s*\[\s*([\d\.\s\-]+)\s*\]').firstMatch(body);
            final rectMatch = RegExp(r'/Rect\s*\[\s*([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s+([\d\.\-]+)\s*\]').firstMatch(body);
            if (quadMatch != null) {
              final nums = quadMatch.group(1)!.trim().split(RegExp(r'\s+')).map(double.tryParse).whereType<double>().toList();
              for (var q = 0; q + 7 < nums.length; q += 8) {
                final x1 = nums[q];
                final y1 = nums[q + 1];
                final x2 = nums[q + 2];
                final y2 = nums[q + 3];
                final lineY = subtype == 'Underline' ? math.min(y1, y2) : (y1 + y2) / 2;
                pageStrokes.add(
                  SlideStroke(
                    id: 'pdf_annot_${annotRef}_markup_$q',
                    points: [
                      StrokePoint(x: x1, y: pageInfo.height - lineY),
                      StrokePoint(x: x2, y: pageInfo.height - lineY),
                    ],
                    colorValue: colorValue,
                    width: 2.0,
                    opacity: opacity,
                    tool: WorkspaceTool.pen,
                    createdAtMillis: now,
                  ),
                );
              }
            } else if (rectMatch != null) {
              final x1 = double.parse(rectMatch.group(1)!);
              final y1 = double.parse(rectMatch.group(2)!);
              final x2 = double.parse(rectMatch.group(3)!);
              final y2 = double.parse(rectMatch.group(4)!);
              final midY = (y1 + y2) / 2;
              pageStrokes.add(
                SlideStroke(
                  id: 'pdf_annot_${annotRef}_markup_rect',
                  points: [
                    StrokePoint(x: x1, y: pageInfo.height - midY),
                    StrokePoint(x: x2, y: pageInfo.height - midY),
                  ],
                  colorValue: colorValue,
                  width: 2.0,
                  opacity: opacity,
                  tool: WorkspaceTool.pen,
                  createdAtMillis: now,
                ),
              );
            }
          }
        }

        if (pageStrokes.isNotEmpty) {
          result[pageNum] = pageStrokes;
        }
      }
    } catch (e) {
      debugPrint('Error parsing PDF embedded annotations: $e');
    }
    return result;
  }

  /// Helper to decode PDF literal strings (hello) or UTF-16 hex strings <FEFF...>
  static String decodePdfString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
      final hex = trimmed.substring(1, trimmed.length - 1).replaceAll(RegExp(r'\s+'), '');
      if (hex.length % 4 == 0 && hex.toUpperCase().startsWith('FEFF')) {
        final bytes = <int>[];
        for (var i = 4; i + 3 < hex.length; i += 4) {
          final code = int.tryParse(hex.substring(i, i + 4), radix: 16);
          if (code != null) bytes.addAll(utf8.encode(String.fromCharCode(code)));
        }
        return utf8.decode(bytes, allowMalformed: true);
      }
      final bytes = <int>[];
      for (var i = 0; i + 1 < hex.length; i += 2) {
        final val = int.tryParse(hex.substring(i, i + 2), radix: 16);
        if (val != null) bytes.add(val);
      }
      return utf8.decode(bytes, allowMalformed: true);
    }

    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      final content = trimmed.substring(1, trimmed.length - 1);
      final sb = StringBuffer();
      for (var i = 0; i < content.length; i++) {
        if (content[i] == '\\' && i + 1 < content.length) {
          final next = content[i + 1];
          if (next == 'n') {
            sb.write('\n');
            i++;
          } else if (next == 'r') {
            sb.write('\r');
            i++;
          } else if (next == 't') {
            sb.write('\t');
            i++;
          } else if (next == '(' || next == ')' || next == '\\') {
            sb.write(next);
            i++;
          } else {
            sb.write(next);
            i++;
          }
        } else {
          sb.write(content[i]);
        }
      }
      return sb.toString();
    }
    return raw;
  }
}

class _PdfPageInfo {
  final int objNum;
  final double width;
  final double height;
  final String annotsContent;

  const _PdfPageInfo({
    required this.objNum,
    required this.width,
    required this.height,
    required this.annotsContent,
  });
}
