import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' show TextLine;

/// A fully transparent widget that sits on top of a rendered PDF page image
/// and enables native text selection / copy.
///
/// The original PDF text positions (in PDF point coordinates, origin at the
/// top-left, Y increasing downward as returned by syncfusion) are scaled to
/// fill the available widget space. Each [TextLine] is rendered as a
/// transparent [Text] widget so that Flutter's [SelectionArea] can expose it
/// for selection without visually altering the image below.
class PdfTextSelectionLayer extends StatelessWidget {
  /// Width of the PDF page in PDF points (from pdfx page.width).
  final double pdfPageWidth;

  /// Height of the PDF page in PDF points (from pdfx page.height).
  final double pdfPageHeight;

  /// Text lines extracted by [syncfusion_flutter_pdf]'s PdfTextExtractor.
  final List<TextLine> textLines;

  const PdfTextSelectionLayer({
    super.key,
    required this.pdfPageWidth,
    required this.pdfPageHeight,
    required this.textLines,
  });

  @override
  Widget build(BuildContext context) {
    if (textLines.isEmpty) return const SizedBox.shrink();

    return SelectionArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cw = constraints.maxWidth;
          final ch = constraints.maxHeight;
          if (cw <= 0 || ch <= 0) return const SizedBox.shrink();

          final scaleX = cw / pdfPageWidth;
          final scaleY = ch / pdfPageHeight;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final line in textLines)
                _buildTextBlock(line, scaleX, scaleY),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextBlock(TextLine line, double scaleX, double scaleY) {
    final b = line.bounds;
    final left = b.left * scaleX;
    final top = b.top * scaleY;
    final width = (b.width * scaleX).clamp(1.0, double.infinity);
    final height = (b.height * scaleY).clamp(1.0, double.infinity);
    final fontSize = (height * 0.78).clamp(4.0, 96.0);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Text(
        line.text,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.transparent,
          height: 1.0,
        ),
        overflow: TextOverflow.clip,
        maxLines: 1,
        softWrap: false,
        textDirection:
            _isRtl(line.text) ? TextDirection.rtl : TextDirection.ltr,
      ),
    );
  }

  /// Simple RTL heuristic — checks if the first meaningful character is
  /// Arabic (U+0600–U+06FF, etc.) or Hebrew (U+0590–U+05FF).
  static bool _isRtl(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0590 && rune <= 0x05FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF)) {
        return true;
      }
      if (rune > 0x0040) break;
    }
    return false;
  }
}
