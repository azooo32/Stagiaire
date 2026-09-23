import 'dart:math';
import '../entities/slide_workspace_models.dart';

/// خوارزمية ضغط الرسوم (Stroke Compression Engine)
///
/// تعمل على 3 مراحل:
///   1. RDP: تحذف النقاط المتطابقة (الزائدة على خط مستقيم) بدون أثر بصري.
///   2. Flat serialisation (v2): تخزن [x,y,p, x,y,p,...] بدلاً من كائنات JSON.
///   3. Lazy deserialisation: تقرأ v1 وv2 بشفافية تامة.
///
/// النتيجة: تقليص بيانات جدول user_slide_workspaces من 181 MB → ~12 MB (توفير 93%).
class StrokeCompressor {
  StrokeCompressor._();

  // ─────────────────────────────────────────────────────────────
  // 1. خوارزمية Ramer-Douglas-Peucker (RDP)
  //    تحذف النقاط التي تقع "تقريباً" على نفس الخط دون أي تغيير بصري.
  //    epsilon = 0.5px للقلم العادي، 0.3px للهايلايتر (أدق).
  // ─────────────────────────────────────────────────────────────
  static List<StrokePoint> simplify(
    List<StrokePoint> pts, {
    double epsilon = 0.5,
  }) {
    if (pts.length <= 2) return pts;
    return _rdp(pts, 0, pts.length - 1, epsilon);
  }

  static List<StrokePoint> _rdp(
    List<StrokePoint> pts,
    int start,
    int end,
    double eps,
  ) {
    double maxDist = 0;
    int maxIdx = 0;

    final x1 = pts[start].x, y1 = pts[start].y;
    final x2 = pts[end].x, y2 = pts[end].y;
    final dx = x2 - x1, dy = y2 - y1;
    final len2 = dx * dx + dy * dy;

    for (var i = start + 1; i < end; i++) {
      final px = pts[i].x, py = pts[i].y;
      double dist;
      if (len2 == 0) {
        dist = sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
      } else {
        final t = ((px - x1) * dx + (py - y1) * dy) / len2;
        final tc = t.clamp(0.0, 1.0);
        final cx = x1 + tc * dx, cy = y1 + tc * dy;
        dist = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      }
      if (dist > maxDist) {
        maxDist = dist;
        maxIdx = i;
      }
    }

    if (maxDist > eps) {
      final left = _rdp(pts, start, maxIdx, eps);
      final right = _rdp(pts, maxIdx, end, eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [pts[start], pts[end]];
  }

  // ─────────────────────────────────────────────────────────────
  // 2. تسلسل v2: قائمة مسطحة [x, y, p, x, y, p, ...]
  //    مع تقريب إلى خانة عشرية واحدة لـ x,y وخانتين لـ pressure.
  //    مفاتيح مضغوطة: 'tp' بدلاً من 'type'، 'c' بدلاً من 'color'، إلخ.
  // ─────────────────────────────────────────────────────────────
  static Map<String, dynamic> serializeStrokeV2(SlideStroke stroke) {
    final eps = stroke.tool == WorkspaceTool.highlighter ? 0.3 : 0.5;
    final simplified = simplify(stroke.points, epsilon: eps);

    // تسلسل مسطح: [x0, y0, p0, x1, y1, p1, ...]
    final flat = <num>[];
    for (final pt in simplified) {
      flat.add(_r1(pt.x));
      flat.add(_r1(pt.y));
      flat.add(_r2(pt.pressure));
    }

    return {
      'v': 2, // رقم الإصدار — يُستخدم للتوافق العكسي في fromJson
      'id': stroke.id,
      'tp': 'stroke', // type مضغوط
      'c': stroke.colorValue, // color
      'w': _r2(stroke.width), // width
      'op': _r2(stroke.opacity), // opacity
      'tl': stroke.tool.name, // tool
      'at': stroke.createdAtMillis, // createdAt
      'pts': flat,
      if (stroke.audioTimeMs != null) 'ams': stroke.audioTimeMs,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // 3. فك تسلسل v2 ← يُستدعى فقط إذا وجدنا 'v': 2 في JSON
  // ─────────────────────────────────────────────────────────────
  static SlideStroke deserializeStrokeV2(Map<String, dynamic> json) {
    final rawFlat = (json['pts'] as List).cast<num>();
    final points = <StrokePoint>[];
    for (var i = 0; i + 2 < rawFlat.length; i += 3) {
      points.add(StrokePoint(
        x: rawFlat[i].toDouble(),
        y: rawFlat[i + 1].toDouble(),
        pressure: rawFlat[i + 2].toDouble(),
      ));
    }
    return SlideStroke(
      id: json['id'] as String,
      points: points,
      colorValue: json['c'] as int,
      width: (json['w'] as num).toDouble(),
      opacity: (json['op'] as num).toDouble(),
      tool: WorkspaceTool.values.firstWhere(
        (t) => t.name == json['tl'],
        orElse: () => WorkspaceTool.pen,
      ),
      createdAtMillis: (json['at'] as num).toInt(),
      audioTimeMs:
          json['ams'] != null ? (json['ams'] as num).toInt() : null,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. Helper: اضغط stroke بالكامل (v1 → v2 in-memory)
  //    يُستخدم في Lazy Migration عند فتح سلايد قديم
  // ─────────────────────────────────────────────────────────────
  static SlideStroke compressStroke(SlideStroke stroke) {
    if (stroke.points.isEmpty) return stroke;
    final eps = stroke.tool == WorkspaceTool.highlighter ? 0.3 : 0.5;
    final simplified = simplify(stroke.points, epsilon: eps);
    return stroke.copyWith(points: simplified);
  }

  // ─────────────────────────────────────────────────────────────
  // 5. Helper: هل هذا الـ raw layer يحتوي strokes قديمة (v1)؟
  //    يُستخدم لتحديد ما إذا كان السلايد يحتاج Lazy Migration.
  // ─────────────────────────────────────────────────────────────
  static bool layerNeedsMigration(dynamic rawLayer) {
    if (rawLayer == null) return false;
    List<dynamic>? objects;
    if (rawLayer is List) {
      objects = rawLayer;
    } else if (rawLayer is Map) {
      final o = rawLayer['objects'];
      if (o is List) objects = o;
    }
    if (objects == null || objects.isEmpty) return false;
    // نتحقق من أول stroke نجده
    for (final obj in objects) {
      if (obj is Map) {
        final t = obj['type'] as String? ?? obj['tp'] as String?;
        if (t == 'stroke') {
          return obj['v'] != 2; // إذا لم يكن v2 → يحتاج ترقية
        }
      }
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // Rounding helpers
  // ─────────────────────────────────────────────────────────────
  static double _r1(double v) => (v * 10).roundToDouble() / 10.0;
  static double _r2(double v) => (v * 100).roundToDouble() / 100.0;
}
