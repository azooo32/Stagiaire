import 'dart:ui';

enum WorkspaceTool { pan, pen, highlighter, eraser, lasso, shape, text, laserDot, laserTrail }

abstract class WorkspaceObject {
  final String id;
  final String type;

  const WorkspaceObject({required this.id, required this.type});

  Map<String, dynamic> toJson();

  factory WorkspaceObject.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'stroke':
        return SlideStroke.fromJson(json);
      case 'image':
        return ImageObject.fromJson(json);
      default:
        return UnknownWorkspaceObject.fromJson(json);
    }
  }

  // Stacking and Sorting
  int get zIndex;
  int get creationTime;

  // Capabilities
  bool get canMove;
  bool get canResize;
  bool get canRotate;
  bool get canDelete;
  bool get canEdit;
  bool get canDuplicate;
}

class StrokePoint {
  final double x;
  final double y;
  final double pressure;

  /// Monotonic pointer timestamp; used only for live, non-persisted prediction.
  final int timestampMicros;

  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1,
    this.timestampMicros = 0,
  });

  Offset get offset => Offset(x, y);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
        'time': timestampMicros,
      };

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: ((json['pressure'] ?? 1) as num).toDouble(),
        timestampMicros: ((json['time'] ?? 0) as num).toInt(),
      );
}

class SlideStroke extends WorkspaceObject {
  final List<StrokePoint> points;
  final int colorValue;
  final double width;
  final double opacity;
  final WorkspaceTool tool;
  final int createdAtMillis;
  final int? audioTimeMs;

  const SlideStroke({
    required super.id,
    required this.points,
    required this.colorValue,
    required this.width,
    required this.opacity,
    required this.tool,
    required this.createdAtMillis,
    this.audioTimeMs,
  }) : super(type: 'stroke');

  @override
  int get zIndex => 0;

  @override
  int get creationTime => createdAtMillis;

  @override
  bool get canMove => false;

  @override
  bool get canResize => false;

  @override
  bool get canRotate => false;

  @override
  bool get canDelete => true;

  @override
  bool get canEdit => false;

  @override
  bool get canDuplicate => false;

  Color get color => Color(colorValue).withValues(alpha: opacity);

  SlideStroke copyWith({
    String? id,
    List<StrokePoint>? points,
    int? colorValue,
    double? width,
    double? opacity,
    WorkspaceTool? tool,
    int? createdAtMillis,
    int? audioTimeMs,
  }) {
    return SlideStroke(
      id: id ?? this.id,
      points: points ?? this.points,
      colorValue: colorValue ?? this.colorValue,
      width: width ?? this.width,
      opacity: opacity ?? this.opacity,
      tool: tool ?? this.tool,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      audioTimeMs: audioTimeMs ?? this.audioTimeMs,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'stroke',
        'points': points.map((point) => point.toJson()).toList(),
        'color': colorValue,
        'width': width,
        'opacity': opacity,
        'tool': tool.name,
        'createdAt': createdAtMillis,
        if (audioTimeMs != null) 'audioTimeMs': audioTimeMs,
      };

  factory SlideStroke.fromJson(Map<String, dynamic> json) => SlideStroke(
        id: json['id'] as String,
        points: (json['points'] as List<dynamic>? ?? [])
            .map((point) => StrokePoint.fromJson(point as Map<String, dynamic>))
            .toList(),
        colorValue: json['color'] as int,
        width: ((json['width'] ?? 2) as num).toDouble(),
        opacity: ((json['opacity'] ?? 1) as num).toDouble(),
        tool: WorkspaceTool.values.firstWhere(
          (tool) => tool.name == json['tool'],
          orElse: () => WorkspaceTool.pen,
        ),
        createdAtMillis: ((json['createdAt'] ?? 0) as num).toInt(),
        audioTimeMs: json['audioTimeMs'] != null
            ? (json['audioTimeMs'] as num).toInt()
            : null,
      );
}

enum ImageState {
  local,
  uploading,
  uploaded,
  uploadFailed,
}

class ImageObject extends WorkspaceObject {
  final String? localPath;
  final String? imageUrl;
  final String? storagePath;
  final ImageState state;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double opacity;
  @override
  final int zIndex;
  final bool locked;
  final int createdAt;
  final int updatedAt;

  const ImageObject({
    required super.id,
    this.localPath,
    this.imageUrl,
    this.storagePath,
    this.state = ImageState.local,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.locked = false,
    required this.createdAt,
    required this.updatedAt,
  }) : super(type: 'image');

  @override
  int get creationTime => createdAt;

  @override
  bool get canMove => !locked;

  @override
  bool get canResize => !locked;

  @override
  bool get canRotate => !locked;

  @override
  bool get canDelete => true;

  @override
  bool get canEdit => !locked;

  @override
  bool get canDuplicate => true;

  ImageObject copyWith({
    String? id,
    String? localPath,
    String? imageUrl,
    String? storagePath,
    ImageState? state,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    int? zIndex,
    bool? locked,
    int? createdAt,
    int? updatedAt,
  }) {
    return ImageObject(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      imageUrl: imageUrl ?? this.imageUrl,
      storagePath: storagePath ?? this.storagePath,
      state: state ?? this.state,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      locked: locked ?? this.locked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'image',
        'localPath': localPath,
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'state': state.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'opacity': opacity,
        'zIndex': zIndex,
        'locked': locked,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory ImageObject.fromJson(Map<String, dynamic> json) => ImageObject(
        id: json['id'] as String,
        localPath: json['localPath'] as String?,
        imageUrl: json['imageUrl'] as String?,
        storagePath: json['storagePath'] as String?,
        state: ImageState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => ImageState.uploaded,
        ),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        rotation: ((json['rotation'] ?? 0.0) as num).toDouble(),
        opacity: ((json['opacity'] ?? 1.0) as num).toDouble(),
        zIndex: ((json['zIndex'] ?? 0) as num).toInt(),
        locked: json['locked'] == true,
        createdAt: ((json['createdAt'] ?? 0) as num).toInt(),
        updatedAt: ((json['updatedAt'] ?? 0) as num).toInt(),
      );
}

class UnknownWorkspaceObject extends WorkspaceObject {
  final Map<String, dynamic> rawJson;

  const UnknownWorkspaceObject({
    required super.id,
    required super.type,
    required this.rawJson,
  });

  @override
  int get zIndex => 0;

  @override
  int get creationTime => 0;

  @override
  bool get canMove => false;

  @override
  bool get canResize => false;

  @override
  bool get canRotate => false;

  @override
  bool get canDelete => true;

  @override
  bool get canEdit => false;

  @override
  bool get canDuplicate => false;

  @override
  Map<String, dynamic> toJson() => rawJson;

  factory UnknownWorkspaceObject.fromJson(Map<String, dynamic> json) =>
      UnknownWorkspaceObject(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'unknown').toString(),
        rawJson: json,
      );
}

class WorkspaceQuestion {
  final String prompt;
  final String answer;
  final int answerLines;

  const WorkspaceQuestion({
    required this.prompt,
    this.answer = '',
    this.answerLines = 4,
  });
}

class WorkspaceSlide {
  final String id;
  final int index;
  final int subtitleIndex;
  final int subtitleSlideIndex;
  final String title;
  final String subtitle;
  final String imageAsset;
  final String audioUrl;
  final String? pdfUrl;
  final bool isHidden;
  final List<WorkspaceQuestion> questions;
  final Map<String, dynamic> metadata;
  final List<WorkspaceObject> strokes;
  final List<WorkspaceObject> examStrokes;

  const WorkspaceSlide({
    required this.id,
    required this.index,
    this.subtitleIndex = 1,
    this.subtitleSlideIndex = 1,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    this.audioUrl = '',
    this.pdfUrl,
    this.isHidden = false,
    required this.questions,
    this.metadata = const {},
    this.strokes = const [],
    this.examStrokes = const [],
  });

  WorkspaceSlide copyWith({
    String? id,
    int? index,
    int? subtitleIndex,
    int? subtitleSlideIndex,
    String? title,
    String? subtitle,
    String? imageAsset,
    String? audioUrl,
    String? pdfUrl,
    bool? isHidden,
    List<WorkspaceQuestion>? questions,
    Map<String, dynamic>? metadata,
    List<WorkspaceObject>? strokes,
    List<WorkspaceObject>? examStrokes,
  }) {
    return WorkspaceSlide(
      id: id ?? this.id,
      index: index ?? this.index,
      subtitleIndex: subtitleIndex ?? this.subtitleIndex,
      subtitleSlideIndex: subtitleSlideIndex ?? this.subtitleSlideIndex,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageAsset: imageAsset ?? this.imageAsset,
      audioUrl: audioUrl ?? this.audioUrl,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      isHidden: isHidden ?? this.isHidden,
      questions: questions ?? this.questions,
      metadata: metadata ?? this.metadata,
      strokes: strokes ?? this.strokes,
      examStrokes: examStrokes ?? this.examStrokes,
    );
  }
}

enum PdfPointerType {
  dot,
  dotUp,
  trail,
}

class PdfPointerEvent {
  final int timestampMs;
  final int pageNumber;
  final PdfPointerType type;
  final double? x;
  final double? y;
  final List<Offset>? points;
  final int? durationMs;
  final int? drawDurationMs;

  const PdfPointerEvent({
    required this.timestampMs,
    required this.pageNumber,
    required this.type,
    this.x,
    this.y,
    this.points,
    this.durationMs,
    this.drawDurationMs,
  });

  Map<String, dynamic> toJson() => {
        't': timestampMs,
        'p': pageNumber,
        'type': type.name,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (points != null)
          'pts': points!.map((pt) => {'x': pt.dx, 'y': pt.dy}).toList(),
        if (durationMs != null) 'dur': durationMs,
        if (drawDurationMs != null) 'drawDur': drawDurationMs,
      };

  factory PdfPointerEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'dot').toString();
    final type = PdfPointerType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => PdfPointerType.dot,
    );
    final rawPts = json['pts'] as List<dynamic>?;
    final points = rawPts
        ?.map((pt) => Offset(
              ((pt['x'] ?? 0) as num).toDouble(),
              ((pt['y'] ?? 0) as num).toDouble(),
            ))
        .toList();

    return PdfPointerEvent(
      timestampMs: ((json['t'] ?? 0) as num).toInt(),
      pageNumber: ((json['p'] ?? 1) as num).toInt(),
      type: type,
      x: json['x'] != null ? (json['x'] as num).toDouble() : null,
      y: json['y'] != null ? (json['y'] as num).toDouble() : null,
      points: points,
      durationMs: json['dur'] != null ? (json['dur'] as num).toInt() : null,
      drawDurationMs: json['drawDur'] != null ? (json['drawDur'] as num).toInt() : null,
    );
  }
}

class PdfLectureRecording {
  final String id;
  final String pdfId;
  final String stationId;
  final String audioUrl;
  final String? localAudioPath;
  final int durationMs;
  final int pageNumber;
  final double positionX;
  final double positionY;
  final Map<int, List<SlideStroke>> strokesData;
  final List<PdfPointerEvent> pointerEvents;
  final String? createdBy;
  final DateTime createdAt;

  const PdfLectureRecording({
    required this.id,
    required this.pdfId,
    required this.stationId,
    required this.audioUrl,
    this.localAudioPath,
    required this.durationMs,
    required this.pageNumber,
    required this.positionX,
    required this.positionY,
    required this.strokesData,
    required this.pointerEvents,
    this.createdBy,
    required this.createdAt,
  });

  PdfLectureRecording copyWith({
    String? id,
    String? pdfId,
    String? stationId,
    String? audioUrl,
    String? localAudioPath,
    int? durationMs,
    int? pageNumber,
    double? positionX,
    double? positionY,
    Map<int, List<SlideStroke>>? strokesData,
    List<PdfPointerEvent>? pointerEvents,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return PdfLectureRecording(
      id: id ?? this.id,
      pdfId: pdfId ?? this.pdfId,
      stationId: stationId ?? this.stationId,
      audioUrl: audioUrl ?? this.audioUrl,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      durationMs: durationMs ?? this.durationMs,
      pageNumber: pageNumber ?? this.pageNumber,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      strokesData: strokesData ?? this.strokesData,
      pointerEvents: pointerEvents ?? this.pointerEvents,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    final strokesMap = <String, dynamic>{};
    for (final entry in strokesData.entries) {
      strokesMap[entry.key.toString()] =
          entry.value.map((s) => s.toJson()).toList();
    }

    return {
      'id': id,
      'pdf_id': pdfId,
      'station_id': stationId,
      'audio_url': audioUrl,
      if (localAudioPath != null) 'local_audio_path': localAudioPath,
      'duration_ms': durationMs,
      'page_number': pageNumber,
      'position_x': positionX,
      'position_y': positionY,
      'strokes_data': strokesMap,
      'pointer_events': pointerEvents.map((e) => e.toJson()).toList(),
      if (createdBy != null) 'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PdfLectureRecording.fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes_data'] as Map<String, dynamic>? ?? {};
    final strokesData = <int, List<SlideStroke>>{};
    for (final entry in rawStrokes.entries) {
      final pageNum = int.tryParse(entry.key);
      if (pageNum != null && entry.value is List) {
        strokesData[pageNum] = (entry.value as List)
            .map((item) => SlideStroke.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }

    final rawPointers = json['pointer_events'] as List<dynamic>? ?? [];
    final pointerEvents = rawPointers
        .map((e) => PdfPointerEvent.fromJson(e as Map<String, dynamic>))
        .toList();

    return PdfLectureRecording(
      id: json['id']?.toString() ?? '',
      pdfId: json['pdf_id']?.toString() ?? '',
      stationId: json['station_id']?.toString() ?? '',
      audioUrl: json['audio_url']?.toString() ?? '',
      localAudioPath: json['local_audio_path']?.toString(),
      durationMs: ((json['duration_ms'] ?? 0) as num).toInt(),
      pageNumber: ((json['page_number'] ?? 1) as num).toInt(),
      positionX: ((json['position_x'] ?? 0.0) as num).toDouble(),
      positionY: ((json['position_y'] ?? 0.0) as num).toDouble(),
      strokesData: strokesData,
      pointerEvents: pointerEvents,
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

