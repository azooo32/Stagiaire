import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_protector/screen_protector.dart';

import 'package:record/record.dart';

import '../../../../core/providers/app_provider.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../data/slide_workspace_repository.dart';
import '../../domain/entities/slide_workspace_models.dart';
import '../../../../core/services/pdf_sound_parser.dart';
import '../../../../core/services/pdf_annotation_parser.dart';
import '../../../../core/services/image_cache_service.dart';
import '../controllers/slide_workspace_controller.dart';
import '../widgets/workspace_top_toolbar.dart';
import '../widgets/workspace_object_renderers.dart';
import '../widgets/stagiaire_slide_painters.dart';
import '../widgets/pdf_lecture_painters.dart';
import '../widgets/pdf_lecture_recording_bar.dart';

class PdfWorkspaceScreen extends StatefulWidget {
  final String stationName;
  final String? stationDbId;
  final WorkspaceSlide pdfSlide;
  final String localPdfPath;

  const PdfWorkspaceScreen({
    super.key,
    required this.stationName,
    this.stationDbId,
    required this.pdfSlide,
    required this.localPdfPath,
  });

  @override
  State<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends State<PdfWorkspaceScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final SlideWorkspaceController controller;
  late final _PdfSlideRepository _pdfRepository;
  final ScrollController _scrollController = ScrollController();
  final TransformationController _transformationController = TransformationController();

  late final AnimationController _flingAnimationController;
  final GlobalKey _contentKey = GlobalKey();
  double _lastViewportHeight = 0.0;
  double _lastViewportWidth = 0.0;
  double _lastPageWidth = 0.0;
  final Set<int> _activeStylusPointers = {};

  PdfDocument? _pdfDocument;
  List<PdfSoundAnnotation> _soundAnnotations = [];
  bool _isLoadingPdf = true;
  int _currentPageIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  String? _activeAudioPath;
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isDockedAudioVisible = false;

  // Lecture Recordings
  List<PdfLectureRecording> _lectureRecordings = [];
  PdfLectureRecording? _activeLectureRecording;
  bool _isLecturePillCollapsed = false;
  bool _isSoundPillCollapsed = false;
  bool _isSyncingRecordings = false;

  // Recording Engine (for Admin/Owner)
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingLecture = false;
  bool _isPausedLecture = false;
  Duration _lectureRecordDuration = Duration.zero;
  Stopwatch? _recordStopwatch;
  Timer? _recordTimer;
  int _recordingPageNumber = 1;
  double _recordingPosX = 0.0;
  double _recordingPosY = 0.0;
  final Map<int, List<SlideStroke>> _recordingStrokes = {};
  final List<PdfPointerEvent> _recordingPointerEvents = [];
  bool _isSavingLecture = false;
  String? _tempRecordingPath;

  // Live and Replay Laser pointers
  Offset? _liveLaserDot;
  int? _liveLaserPage;
  final List<ActiveLaserTrail> _activeLaserTrails = [];
  List<Offset> _currentDrawingTrail = [];
  int _trailStartTimeMs = 0;
  final Map<String, Offset> _draggedRecordingPositions = {};
  late final AnimationController _laserPulseController;

  // Interactive Stroke Tap to Seek Highlight
  String? _highlightedStrokeId;
  late final AnimationController _strokeHighlightController;

  // Persistent disk cache path
  String? _cacheDirPath;
  // Cache: pageNumber -> rendered Uint8List
  final Map<int, Uint8List> _pageCache = {};
  // Cache: pageNumber -> page dimensions (width, height in PDF points)
  final Map<int, Size> _pageSizes = {};
  final Set<int> _renderingPages = {};

  // GlobalKeys for each page widget — used to track which page is visible
  final Map<int, GlobalKey> _pageKeys = {};

  @override
  void initState() {
    super.initState();
    _preventScreenshot();
    WidgetsBinding.instance.addObserver(this);
    _flingAnimationController = AnimationController.unbounded(vsync: this);
    _flingAnimationController.addListener(_onFlingTick);
    _transformationController.addListener(_onTransformationChanged);

    _laserPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _laserPulseController.addListener(() {
      if (_activeLectureRecording == null && _activeLaserTrails.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _activeLaserTrails.removeWhere((t) => t.isExpired(now));
      }
      if (_liveLaserDot != null || _activeLaserTrails.isNotEmpty || _currentDrawingTrail.isNotEmpty) {
        if (mounted) setState(() {});
      }
    });

    _strokeHighlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _strokeHighlightController.addListener(() {
      if (mounted) setState(() {});
    });

    _initAudioListeners();
    _initWorkspace();
  }

  bool get _isDrawingTool =>
      controller.selectedTool == WorkspaceTool.pen ||
      controller.selectedTool == WorkspaceTool.highlighter ||
      controller.selectedTool == WorkspaceTool.eraser ||
      controller.selectedTool == WorkspaceTool.laserDot ||
      controller.selectedTool == WorkspaceTool.laserTrail;

  bool get _phoneDrawingMode =>
      MediaQuery.sizeOf(context).width < 600 && _isDrawingTool;

  bool _isStylus(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool get _customPanEnabled =>
      !_phoneDrawingMode &&
      !(_isDrawingTool && _activeStylusPointers.isNotEmpty);

  void _onFlingTick() {
    if (!_flingAnimationController.isAnimating) return;
    final currentMatrix = _transformationController.value;
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
        currentMatrix.getTranslation().x,
        newY,
        currentMatrix.getTranslation().z,
      );

    _transformationController.value = newMatrix;
  }

  void _onTransformationChanged() {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if ((controller.zoom - scale).abs() > 0.02) {
      controller.setZoom(scale.clamp(0.5, 5.0));
    }

    if (_lastViewportHeight > 0 && _lastViewportWidth > 0) {
      final contentHeight = _contentHeight(_lastPageWidth);
      final horizontalBounds = _translationBounds(
        _lastPageWidth,
        _lastViewportWidth,
        scale,
      );
      final verticalBounds = _translationBounds(
        contentHeight,
        _lastViewportHeight,
        scale,
      );
      final translation = matrix.getTranslation();
      final targetX = translation.x
          .clamp(horizontalBounds.min, horizontalBounds.max)
          .toDouble();
      final targetY = translation.y
          .clamp(verticalBounds.min, verticalBounds.max)
          .toDouble();

      if ((translation.x - targetX).abs() > 0.01 ||
          (translation.y - targetY).abs() > 0.01) {
        final constrained = Matrix4.copy(matrix)
          ..setTranslationRaw(targetX, targetY, translation.z);
        _transformationController.value = constrained;
        return;
      }

      _updateCurrentPageFromTranslation(translation.y, scale);
    }

    _updateDockedAudioState();
  }

  void _updateCurrentPageFromTranslation(double translationY, double scale) {
    if (controller.slides.isEmpty || _lastPageWidth <= 0) return;
    final centerY = (-translationY + _lastViewportHeight / 2) / scale;

    const topPad = 8.0;
    const spacing = 12.0;
    double currentY = topPad;
    double bestDistance = double.infinity;
    int bestIndex = _currentPageIndex;

    for (var i = 0; i < controller.slides.length; i++) {
      final pageNum = i + 1;
      final size = _pageSizes[pageNum];
      final pdfW = size?.width ?? 595.0;
      final pdfH = size?.height ?? 842.0;
      final pageHeight = _lastPageWidth * pdfH / pdfW;

      final pageCenterY = currentY + pageHeight / 2;
      final distance = (pageCenterY - centerY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
      currentY += pageHeight + spacing;
    }

    if (bestIndex != _currentPageIndex) {
      setState(() => _currentPageIndex = bestIndex);
      controller.goToSlide(bestIndex, clearHistory: false);
    }
  }

  void _initAudioListeners() {
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _currentPosition = pos);
        if (_activeLectureRecording != null) {
          _updateLectureReplayAt(pos.inMilliseconds);
        }
      }
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _totalDuration = dur);
    });
    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.stopped;
          _currentPosition = Duration.zero;
          _isDockedAudioVisible = false;
          _isLecturePillCollapsed = false;
          _isSoundPillCollapsed = false;
          _liveLaserDot = null;
          _activeLaserTrails.clear();
        });
      }
    });
  }

  void _updateLectureReplayAt(int posMs) {
    final rec = _activeLectureRecording;
    if (rec == null) return;

    // 1. Replay Laser Dot
    PdfPointerEvent? latestDot;
    for (final e in rec.pointerEvents) {
      if (e.timestampMs <= posMs && e.timestampMs >= posMs - 450) {
        if (e.type == PdfPointerType.dot || e.type == PdfPointerType.dotUp) {
          latestDot = e;
        }
      }
    }

    if (latestDot != null &&
        latestDot.type == PdfPointerType.dot &&
        latestDot.x != null &&
        latestDot.y != null) {
      _liveLaserDot = Offset(latestDot.x!, latestDot.y!);
      _liveLaserPage = latestDot.pageNumber;
    } else {
      _liveLaserDot = null;
    }

    // 2. Replay Laser Trails
    final trails = <ActiveLaserTrail>[];
    Offset? replayLaserTip;
    int? replayLaserTipPage;

    for (final e in rec.pointerEvents) {
      if (e.type == PdfPointerType.trail &&
          e.points != null &&
          e.points!.length >= 2) {
        final startMs = e.timestampMs;
        final drawDur = (e.drawDurationMs != null && e.drawDurationMs! > 0) ? e.drawDurationMs! : 400;
        final fadeDur = e.durationMs ?? 2000;
        final totalEventDur = drawDur + fadeDur;

        if (posMs >= startMs && posMs <= startMs + totalEventDur) {
          if (posMs < startMs + drawDur) {
            // Actively being drawn live: show progressive points matching drawing speed
            final drawProgress = ((posMs - startMs) / drawDur).clamp(0.0, 1.0);
            final count = (e.points!.length * drawProgress).round().clamp(2, e.points!.length);
            final visiblePts = e.points!.sublist(0, count);

            trails.add(ActiveLaserTrail(
              points: visiblePts,
              startTimeMs: posMs,
              totalDurationMs: fadeDur + 1000,
              pageNumber: e.pageNumber,
            ));

            replayLaserTip = visiblePts.last;
            replayLaserTipPage = e.pageNumber;
          } else {
            // Finished drawing, full trail smoothly fades out over 2000ms
            final finishTimeMs = startMs + drawDur;
            trails.add(ActiveLaserTrail(
              points: e.points!,
              startTimeMs: finishTimeMs,
              totalDurationMs: fadeDur,
              pageNumber: e.pageNumber,
            ));
          }
        }
      }
    }
    _activeLaserTrails
      ..clear()
      ..addAll(trails);

    if (replayLaserTip != null) {
      _liveLaserDot = replayLaserTip;
      _liveLaserPage = replayLaserTipPage;
    }
  }

  Future<void> _initWorkspace() async {
    try {
      // 1. Open the PDF Document
      _pdfDocument = await PdfDocument.openFile(widget.localPdfPath);
      final pageCount = _pdfDocument!.pagesCount;

      // 2. Setup Persistent Disk Cache Directory
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/pdf_pages_cache/${widget.pdfSlide.id}');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _cacheDirPath = cacheDir.path;

      // Fast-load cached page dimensions if available
      final pageSizesFile = File('$_cacheDirPath/page_sizes.json');
      if (await pageSizesFile.exists()) {
        try {
          final jsonStr = await pageSizesFile.readAsString();
          final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
          for (final entry in jsonMap.entries) {
            final pageNum = int.tryParse(entry.key);
            if (pageNum != null && entry.value is Map) {
              final w = ((entry.value['w'] ?? 595) as num).toDouble();
              final h = ((entry.value['h'] ?? 842) as num).toDouble();
              _pageSizes[pageNum] = Size(w, h);
            }
          }
        } catch (_) {}
      }

      // If page 1 size isn't cached yet, fetch page 1 size synchronously to preserve aspect ratio
      if (!_pageSizes.containsKey(1) && pageCount > 0) {
        final p1 = await _pdfDocument!.getPage(1);
        _pageSizes[1] = Size(p1.width, p1.height);
        await p1.close();
      }

      // Fast-load cached sound annotations if available
      final soundCacheFile = File('$_cacheDirPath/sound_annotations.json');
      if (await soundCacheFile.exists()) {
        try {
          final jsonStr = await soundCacheFile.readAsString();
          final list = jsonDecode(jsonStr) as List;
          _soundAnnotations = list
              .map((item) => PdfSoundAnnotation.fromJson(item as Map<String, dynamic>))
              .where((annot) => File(annot.tempAudioPath).existsSync())
              .toList();
        } catch (_) {}
      }

      // Fast-load cached synchronized lecture recordings if available
      final lectureCacheFile = File('$_cacheDirPath/lecture_recordings.json');
      if (await lectureCacheFile.exists()) {
        try {
          final jsonStr = await lectureCacheFile.readAsString();
          final list = jsonDecode(jsonStr) as List;
          _lectureRecordings = list
              .map((item) => PdfLectureRecording.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      // Fast-load local drawing annotations from disk cache
      final localSavedAnnotations = await _readLocalSavedAnnotations();

      // Create initial slides with cached strokes instantly
      final dummySlides = <WorkspaceSlide>[];
      for (var i = 1; i <= pageCount; i++) {
        final cachedStrokes = localSavedAnnotations[i] ?? const [];
        dummySlides.add(
          WorkspaceSlide(
            id: '${widget.pdfSlide.id}_page_$i',
            index: i - 1,
            title: 'الصفحة $i',
            subtitle: '',
            imageAsset: '',
            strokes: cachedStrokes,
            questions: const [],
          ),
        );
      }

      // Setup proxy repository for PDF saving
      final mainRepository = SupabaseSlideWorkspaceRepository();
      _pdfRepository = _PdfSlideRepository(
        pdfId: widget.pdfSlide.id,
        stationId: widget.stationDbId ?? '',
        mainRepository: mainRepository,
        onLocalStrokesUpdated: (pageNum, strokes) {
          _updatePageStrokesCache(pageNum, strokes);
        },
      );

      // Initialize Controller with dummy slides and default to PAN/HAND tool
      controller = SlideWorkspaceController(
        repository: _pdfRepository,
        stationId: widget.pdfSlide.id,
      );
      controller.slides = dummySlides;
      controller.selectedTool = WorkspaceTool.pan; // Default tool is PAN (Hand Mode)
      controller.isLoading = false;

      // Create a GlobalKey for each page
      for (var i = 1; i <= pageCount; i++) {
        _pageKeys[i] = GlobalKey(debugLabel: 'pdf_page_$i');
      }

      // Load already rendered pages from disk cache asynchronously
      for (var i = 1; i <= pageCount; i++) {
        final diskFile = File('$_cacheDirPath/page_$i.jpg');
        if (await diskFile.exists()) {
          final bytes = await diskFile.readAsBytes();
          if (bytes.isNotEmpty) {
            _pageCache[i] = bytes;
          }
        }
      }

      // Always start from Page 1 (index 0) for instant 0ms launch
      _currentPageIndex = 0;
      controller.currentIndex = 0;

      // Render Page 1 if not cached
      if (!_pageCache.containsKey(1) && pageCount > 0) {
        await _renderAndCacheSinglePage(1);
      }

      // Dismiss loading screen IMMEDIATELY so PDF displays Page 1 instantly in 0ms
      if (mounted) {
        setState(() {
          _isLoadingPdf = false;
        });
      }

      // Run background parsing for remaining page sizes, remote annotations & sound AFTER frame renders smoothly
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _runBackgroundWorkspaceInit(pageCount, mainRepository);
        }
      });

    } catch (e) {
      debugPrint('Error initializing PDF workspace: $e');
      if (mounted) {
        setState(() {
          _isLoadingPdf = false;
        });
      }
    }
  }

  Future<Map<int, List<WorkspaceObject>>> _readLocalSavedAnnotations() async {
    if (_cacheDirPath == null) return {};
    final file = File('$_cacheDirPath/saved_annotations.json');
    if (!await file.exists()) return {};
    try {
      final jsonStr = await file.readAsString();
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final results = <int, List<WorkspaceObject>>{};
      for (final entry in jsonMap.entries) {
        final pageNum = int.tryParse(entry.key);
        if (pageNum != null && entry.value is List) {
          final objects = (entry.value as List)
              .map((item) => WorkspaceObject.fromJson(item as Map<String, dynamic>))
              .where((item) => !(item is SlideStroke && item.audioTimeMs != null))
              .toList();
          results[pageNum] = objects;
        }
      }
      return results;
    } catch (e) {
      return {};
    }
  }

  void _writeLocalSavedAnnotations(Map<int, List<WorkspaceObject>> annotations) {
    if (_cacheDirPath == null) return;
    try {
      final jsonMap = <String, dynamic>{};
      for (final entry in annotations.entries) {
        final cleanList = entry.value
            .where((item) => !(item is SlideStroke && item.audioTimeMs != null))
            .map((o) => o.toJson())
            .toList();
        jsonMap['${entry.key}'] = cleanList;
      }
      File('$_cacheDirPath/saved_annotations.json')
          .writeAsString(jsonEncode(jsonMap))
          .ignore();
    } catch (_) {}
  }

  void _updatePageStrokesCache(int pageNum, List<WorkspaceObject> strokes) async {
    final currentMap = await _readLocalSavedAnnotations();
    currentMap[pageNum] = strokes
        .where((s) => !(s is SlideStroke && s.audioTimeMs != null))
        .toList();
    _writeLocalSavedAnnotations(currentMap);
  }

  Future<void> _runBackgroundWorkspaceInit(int pageCount, SupabaseSlideWorkspaceRepository mainRepository) async {
    try {
      // 1. Fetch remaining page sizes in background & cache them
      bool sizesUpdated = false;
      for (var i = 1; i <= pageCount; i++) {
        if (!_pageSizes.containsKey(i)) {
          final page = await _pdfDocument!.getPage(i);
          _pageSizes[i] = Size(page.width, page.height);
          await page.close();
          sizesUpdated = true;
          await Future.delayed(Duration.zero);
        }
      }
      if (sizesUpdated && _cacheDirPath != null) {
        final sizesMap = {
          for (final entry in _pageSizes.entries)
            '${entry.key}': {'w': entry.value.width, 'h': entry.value.height}
        };
        File('$_cacheDirPath/page_sizes.json').writeAsString(jsonEncode(sizesMap)).ignore();
      }

      // 2. Parse sound annotations & embedded PDF drawings if not cached
      if (_soundAnnotations.isEmpty && _cacheDirPath != null) {
        _soundAnnotations = await PdfSoundParser.parseAndExtract(
          widget.localPdfPath,
          _cacheDirPath!,
        );
        if (_soundAnnotations.isNotEmpty) {
          final jsonList = _soundAnnotations.map((a) => a.toJson()).toList();
          File('$_cacheDirPath/sound_annotations.json')
              .writeAsString(jsonEncode(jsonList))
              .ignore();
        }
      }

      final embeddedAnnotations = _cacheDirPath != null
          ? await PdfAnnotationParser.parseEmbeddedAnnotationsWithCache(
              widget.localPdfPath,
              _cacheDirPath!,
            )
          : await PdfAnnotationParser.parseEmbeddedAnnotations(
              widget.localPdfPath,
            );

      // 3. Get user annotations from database & merge with local disk cache
      final remoteSavedAnnotations = await mainRepository.getPdfAnnotations(widget.pdfSlide.id);
      final localSavedAnnotations = await _readLocalSavedAnnotations();

      final mergedSavedAnnotations = <int, List<WorkspaceObject>>{};
      final allPageNums = <int>{...localSavedAnnotations.keys, ...remoteSavedAnnotations.keys};
      for (final p in allPageNums) {
        final localList = localSavedAnnotations[p] ?? const [];
        final remoteList = remoteSavedAnnotations[p] ?? const [];

        final strokeMap = <String, WorkspaceObject>{};
        for (final s in remoteList) {
          if (s is SlideStroke && s.audioTimeMs != null) continue;
          strokeMap[s.id] = s;
        }
        for (final s in localList) {
          if (s is SlideStroke && s.audioTimeMs != null) continue;
          strokeMap[s.id] = s;
        }
        mergedSavedAnnotations[p] = strokeMap.values.toList();
      }

      _writeLocalSavedAnnotations(mergedSavedAnnotations);
      unawaited(mainRepository.purgeLectureStrokesFromUserAnnotations(widget.pdfSlide.id));

      // 4. Merge annotations into controller slides
      final updatedSlides = <WorkspaceSlide>[];
      for (var i = 1; i <= pageCount; i++) {
        final pageEmbedded = embeddedAnnotations[i] ?? const [];
        final pageSaved = mergedSavedAnnotations[i] ?? const [];

        final strokeMap = <String, WorkspaceObject>{};
        for (final s in pageEmbedded) {
          strokeMap[s.id] = s;
        }
        for (final s in pageSaved) {
          strokeMap[s.id] = s;
        }

        updatedSlides.add(
          WorkspaceSlide(
            id: '${widget.pdfSlide.id}_page_$i',
            index: i - 1,
            title: 'الصفحة $i',
            subtitle: '',
            imageAsset: '',
            strokes: strokeMap.values.toList(),
            questions: const [],
          ),
        );
      }

      // Preload user image URLs in background
      final imageUrls = <String>[];
      for (final slide in updatedSlides) {
        for (final obj in slide.strokes) {
          if (obj is ImageObject && obj.imageUrl != null && obj.imageUrl!.isNotEmpty) {
            imageUrls.add(obj.imageUrl!);
          }
        }
        for (final obj in slide.examStrokes) {
          if (obj is ImageObject && obj.imageUrl != null && obj.imageUrl!.isNotEmpty) {
            imageUrls.add(obj.imageUrl!);
          }
        }
      }
      if (imageUrls.isNotEmpty) {
        unawaited(ImageCacheService().preloadUrls(imageUrls));
      }

      if (mounted) {
        setState(() {
          controller.slides = updatedSlides;
        });
      }

      // Pre-render remaining pages in background
      _preRenderRemainingPages(pageCount);

      // 5. Background sync for lecture recordings (fetch additions/deletions from Supabase)
      await _syncLectureRecordingsInBackground(mainRepository);

    } catch (e) {
      debugPrint('Error in background PDF workspace init: $e');
    }
  }

  Future<void> _syncLectureRecordingsInBackground(
      SupabaseSlideWorkspaceRepository mainRepository) async {
    if (_cacheDirPath == null || _isSyncingRecordings) return;
    _isSyncingRecordings = true;
    try {
      final remoteRecordings =
          await mainRepository.getPdfLectureRecordings(widget.pdfSlide.id);

      final remoteIds = remoteRecordings.map((r) => r.id).toSet();
      final cacheDir = Directory(_cacheDirPath!);

      // Case 1: All lecture recordings deleted remotely by admin
      if (remoteRecordings.isEmpty) {
        bool needsUpdate = _lectureRecordings.isNotEmpty;

        // Cancel active audio if it was a lecture recording
        if (_activeLectureRecording != null) {
          await _cancelAudio();
          needsUpdate = true;
        }

        // Clean up all local cached lecture audio files
        if (await cacheDir.exists()) {
          try {
            final files = cacheDir.listSync();
            for (final f in files) {
              if (f is File &&
                  f.path.contains('lecture_') &&
                  f.path.endsWith('.m4a')) {
                try {
                  await f.delete();
                } catch (_) {}
              }
            }
          } catch (_) {}
        }

        // Overwrite cache file with empty list
        final cacheFile = File('$_cacheDirPath/lecture_recordings.json');
        if (await cacheFile.exists() || needsUpdate) {
          try {
            await cacheFile.writeAsString(jsonEncode([]));
          } catch (_) {}
        }

        if (needsUpdate && mounted) {
          setState(() {
            _lectureRecordings = [];
            _activeLectureRecording = null;
          });
        }
        return;
      }

      // Case 2: Remote recordings exist - reconcile with local cache
      if (_activeLectureRecording != null &&
          !remoteIds.contains(_activeLectureRecording!.id)) {
        await _cancelAudio();
      }

      // Delete orphaned local audio files for recordings no longer on server
      if (await cacheDir.exists()) {
        try {
          final files = cacheDir.listSync();
          for (final f in files) {
            if (f is File &&
                f.path.contains('lecture_') &&
                f.path.endsWith('.m4a')) {
              final filename = f.uri.pathSegments.last;
              final recId =
                  filename.replaceFirst('lecture_', '').replaceAll('.m4a', '');
              if (!remoteIds.contains(recId)) {
                try {
                  await f.delete();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      // Download missing audio files for active recordings
      final updatedRecordings = <PdfLectureRecording>[];
      final audioClient = HttpClient();
      for (final rec in remoteRecordings) {
        final localAudioFile = File('$_cacheDirPath/lecture_${rec.id}.m4a');
        if (!await localAudioFile.exists() && rec.audioUrl.isNotEmpty) {
          try {
            final req = await audioClient.getUrl(Uri.parse(rec.audioUrl));
            final res = await req.close();
            if (res.statusCode == 200) {
              final sink = localAudioFile.openWrite();
              await res.pipe(sink);
            }
          } catch (err) {
            debugPrint('Error downloading lecture audio ${rec.id}: $err');
          }
        }
        updatedRecordings.add(
          localAudioFile.existsSync()
              ? rec.copyWith(localAudioPath: localAudioFile.path)
              : rec,
        );
      }
      audioClient.close();

      try {
        final jsonList = updatedRecordings.map((r) => r.toJson()).toList();
        await File('$_cacheDirPath/lecture_recordings.json')
            .writeAsString(jsonEncode(jsonList));
      } catch (_) {}

      if (mounted) {
        final hasChanged =
            _hasLectureRecordingsChanged(_lectureRecordings, updatedRecordings);
        if (hasChanged) {
          setState(() {
            _lectureRecordings = updatedRecordings;
            if (_activeLectureRecording != null) {
              final idx = updatedRecordings
                  .indexWhere((r) => r.id == _activeLectureRecording!.id);
              if (idx != -1) {
                _activeLectureRecording = updatedRecordings[idx];
              } else {
                _activeLectureRecording = null;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error syncing lecture recordings in background: $e');
    } finally {
      _isSyncingRecordings = false;
    }
  }

  bool _hasLectureRecordingsChanged(
      List<PdfLectureRecording> current, List<PdfLectureRecording> updated) {
    if (current.length != updated.length) return true;
    final currentMap = {for (final r in current) r.id: r};
    for (final u in updated) {
      final c = currentMap[u.id];
      if (c == null) return true;
      if (c.positionX != u.positionX ||
          c.positionY != u.positionY ||
          c.pageNumber != u.pageNumber ||
          c.localAudioPath != u.localAudioPath ||
          c.audioUrl != u.audioUrl) {
        return true;
      }
    }
    return false;
  }

  double _contentHeight(double pageWidth) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize == true
        ? box!.size.height
        : _calculateFallbackPdfHeight(pageWidth);
  }

  double _calculateFallbackPdfHeight(double pageWidth) {
    double total = 8.0 + 100.0;
    for (var i = 1; i <= controller.slides.length; i++) {
      final s = _pageSizes[i];
      final h = s != null ? (pageWidth * s.height / s.width) : (pageWidth * 842 / 595);
      total += h + 12.0;
    }
    return total;
  }

  void _scrollToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= controller.slides.length || _lastPageWidth <= 0) return;
    const topPad = 8.0;
    const spacing = 12.0;
    double top = topPad;

    for (var i = 0; i < pageIndex; i++) {
      final pageNum = i + 1;
      final size = _pageSizes[pageNum];
      final pdfW = size?.width ?? 595.0;
      final pdfH = size?.height ?? 842.0;
      final pageHeight = _lastPageWidth * pdfH / pdfW;
      top += pageHeight + spacing;
    }

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetPageSize = _pageSizes[pageIndex + 1];
    final pdfW = targetPageSize?.width ?? 595.0;
    final pdfH = targetPageSize?.height ?? 842.0;
    final targetPageHeight = _lastPageWidth * pdfH / pdfW;

    final targetY = -(top * currentScale) +
        (_lastViewportHeight - (targetPageHeight * currentScale)) / 2;

    final contentHeight = _contentHeight(_lastPageWidth);
    final verticalBounds = _translationBounds(contentHeight, _lastViewportHeight, currentScale);
    final horizontalBounds = _translationBounds(_lastPageWidth, _lastViewportWidth, currentScale);

    final matrix = _transformationController.value.clone();
    matrix.setTranslationRaw(
      horizontalBounds.center,
      targetY.clamp(verticalBounds.min, verticalBounds.max).toDouble(),
      0,
    );
    _transformationController.value = matrix;
    setState(() {
      _currentPageIndex = pageIndex;
    });
  }

  Future<Uint8List?> _renderAndCacheSinglePage(int pageNum) async {
    if (_pdfDocument == null || _cacheDirPath == null) return null;
    if (_pageCache.containsKey(pageNum)) return _pageCache[pageNum];
    if (_renderingPages.contains(pageNum)) return null;

    _renderingPages.add(pageNum);
    try {
      final diskFile = File('$_cacheDirPath/page_$pageNum.jpg');
      if (await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          if (!_pageSizes.containsKey(pageNum)) {
            final page = await _pdfDocument!.getPage(pageNum);
            _pageSizes[pageNum] = Size(page.width, page.height);
            await page.close();
          }
          _pageCache[pageNum] = bytes;
          return bytes;
        }
      }

      final page = await _pdfDocument!.getPage(pageNum);
      _pageSizes[pageNum] = Size(page.width, page.height);
      final img = await page.render(
        width: page.width * 2.2,
        height: page.height * 2.2,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 92,
      );
      await page.close();

      if (img != null && img.bytes.isNotEmpty) {
        _pageCache[pageNum] = img.bytes;
        diskFile.writeAsBytes(img.bytes, flush: true).ignore();
        return img.bytes;
      }
    } catch (e) {
      debugPrint('Error rendering page $pageNum: $e');
    } finally {
      _renderingPages.remove(pageNum);
    }
    return null;
  }

  Future<void> _preRenderRemainingPages(int pageCount) async {
    for (var i = 1; i <= pageCount; i++) {
      if (!mounted) return;
      if (!_pageCache.containsKey(i)) {
        await _renderAndCacheSinglePage(i);
        if (mounted) setState(() {});
        await Future.delayed(const Duration(milliseconds: 40));
      }
    }
  }

  void _ensurePageLoaded(int pageNum) {
    if (!_pageCache.containsKey(pageNum) && !_renderingPages.contains(pageNum)) {
      _renderAndCacheSinglePage(pageNum).then((bytes) {
        if (bytes != null && mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _preventScreenshot() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await ScreenProtector.preventScreenshotOn();
      }
    } catch (e) {
      debugPrint('Error enabling screenshot protection: $e');
    }
  }

  Future<void> _allowScreenshot() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await ScreenProtector.preventScreenshotOff();
      }
    } catch (e) {
      debugPrint('Error disabling screenshot protection: $e');
    }
  }

  @override
  void dispose() {
    _allowScreenshot();
    WidgetsBinding.instance.removeObserver(this);
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _flingAnimationController.dispose();
    _recordTimer?.cancel();
    _recordStopwatch?.stop();
    _audioRecorder.dispose();
    _laserPulseController.dispose();
    _strokeHighlightController.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();
    _pdfDocument?.close();
    _scrollController.dispose();
    if (!_isLoadingPdf) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLoadingPdf &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      controller.flushPendingSaves();
    }
    if (state == AppLifecycleState.resumed &&
        !_isLoadingPdf &&
        !_isRecordingLecture &&
        !_isSavingLecture) {
      _syncLectureRecordingsInBackground(_pdfRepository.mainRepository);
    }
  }

  Future<bool> _handleBack() async {
    if (!_isLoadingPdf) {
      controller.flushPendingSaves();
    }
    if (_isRecordingLecture) {
      await _cancelLectureRecording();
    }
    await _audioPlayer.stop();
    await _allowScreenshot();
    return true;
  }

  void _setZoom(double value) {
    final clamped = value.clamp(0.5, 5.0);
    controller.setZoom(clamped);
    _transformationController.value = Matrix4.diagonal3Values(clamped, clamped, 1.0);
  }

  PdfSoundAnnotation? get _activeSound {
    if (_activeAudioPath == null) return null;
    try {
      return _soundAnnotations
          .where((s) => s.tempAudioPath == _activeAudioPath)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  double? _getSoundScreenY(PdfSoundAnnotation sound) {
    if (_lastPageWidth <= 0 || _lastViewportHeight <= 0) return null;

    final matrix = _transformationController.value;
    final translationY = matrix.getTranslation().y;
    final scale = matrix.getMaxScaleOnAxis();

    const initialTopPad = 8.0;
    const pageVerticalPadding = 6.0;
    double currentY = initialTopPad;

    for (var i = 0; i < controller.slides.length; i++) {
      final pageNum = i + 1;
      final size = _pageSizes[pageNum];
      final pdfW = size?.width ?? 595.0;
      final pdfH = size?.height ?? 842.0;
      final pageHeight = _lastPageWidth * pdfH / pdfW;

      if (pageNum == sound.pageNumber) {
        final double rectTop = sound.rect.length >= 4 ? sound.rect[3] : 0.0;
        final double soundTopInPdf = (pdfH - rectTop).clamp(0.0, pdfH);
        final double soundTopInPage = soundTopInPdf * (_lastPageWidth / pdfW);
        final double soundYInContent = currentY + pageVerticalPadding + soundTopInPage;
        final double screenY = translationY + soundYInContent * scale;
        return screenY;
      }

      currentY += pageHeight + (pageVerticalPadding * 2);
    }
    return null;
  }

  bool _isSoundScrolledOff(PdfSoundAnnotation sound) {
    final screenY = _getSoundScreenY(sound);
    if (screenY == null) return false;
    return screenY < 24.0;
  }

  double? _getLectureScreenY(PdfLectureRecording rec) {
    if (_lastPageWidth <= 0 || _lastViewportHeight <= 0) return null;

    final matrix = _transformationController.value;
    final translationY = matrix.getTranslation().y;
    final scale = matrix.getMaxScaleOnAxis();

    const initialTopPad = 8.0;
    const pageVerticalPadding = 6.0;
    double currentY = initialTopPad;

    for (var i = 0; i < controller.slides.length; i++) {
      final pageNum = i + 1;
      final size = _pageSizes[pageNum];
      final pdfW = size?.width ?? 595.0;
      final pdfH = size?.height ?? 842.0;
      final pageHeight = _lastPageWidth * pdfH / pdfW;

      if (pageNum == rec.pageNumber) {
        final double soundTopInPage = rec.positionY * (_lastPageWidth / pdfW);
        final double soundYInContent = currentY + pageVerticalPadding + soundTopInPage;
        final double screenY = translationY + soundYInContent * scale;
        return screenY;
      }

      currentY += pageHeight + (pageVerticalPadding * 2);
    }
    return null;
  }

  bool _isLectureScrolledOff(PdfLectureRecording rec) {
    final screenY = _getLectureScreenY(rec);
    if (screenY == null) return false;
    return screenY < 24.0;
  }

  void _updateDockedAudioState() {
    if (_activeLectureRecording != null) {
      final shouldDock = _isLectureScrolledOff(_activeLectureRecording!);
      if (shouldDock != _isDockedAudioVisible) {
        setState(() => _isDockedAudioVisible = shouldDock);
      }
      return;
    }

    final sound = _activeSound;
    if (sound == null) {
      if (_isDockedAudioVisible) {
        setState(() => _isDockedAudioVisible = false);
      }
      return;
    }

    final shouldDock = _isSoundScrolledOff(sound);
    if (shouldDock != _isDockedAudioVisible) {
      setState(() => _isDockedAudioVisible = shouldDock);
    }
  }

  Future<void> _cancelAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
    if (mounted) {
      setState(() {
        _activeAudioPath = null;
        _activeLectureRecording = null;
        _isDockedAudioVisible = false;
        _isLecturePillCollapsed = false;
        _isSoundPillCollapsed = false;
        _playerState = PlayerState.stopped;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
        _liveLaserDot = null;
        _activeLaserTrails.clear();
      });
    }
  }

  Future<void> _togglePlayPause(String audioPath) async {
    try {
      if (_activeAudioPath != audioPath) {
        _activeAudioPath = audioPath;
        _isSoundPillCollapsed = false;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
        await _audioPlayer.stop();
        await _audioPlayer.setPlaybackRate(_playbackSpeed);
        await _audioPlayer.play(DeviceFileSource(audioPath));
        if (mounted) {
          final sound = _activeSound;
          _isDockedAudioVisible = sound != null && _isSoundScrolledOff(sound);
          setState(() {});
        }
        return;
      }

      if (_playerState == PlayerState.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error toggling audio play/pause: $e');
    }
  }

  void _togglePlaybackSpeed() {
    final speeds = [1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    _playbackSpeed = speeds[nextIndex];
    _audioPlayer.setPlaybackRate(_playbackSpeed);
    if (mounted) setState(() {});
  }

  String _formatRemainingTime(Duration current, Duration total) {
    if (total <= Duration.zero) return '-00:00';
    final remaining = total - current;
    final displayDur = remaining.isNegative ? Duration.zero : remaining;
    final seconds = (displayDur.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (displayDur.inMinutes % 60).toString().padLeft(2, '0');
    return '-$minutes:$seconds';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _playLectureRecording(PdfLectureRecording rec, {int initialPositionMs = 0}) async {
    try {
      final audioSourcePath = rec.localAudioPath ??
          (_cacheDirPath != null && File('$_cacheDirPath/lecture_${rec.id}.m4a').existsSync()
              ? '$_cacheDirPath/lecture_${rec.id}.m4a'
              : rec.audioUrl);

      if (audioSourcePath.isEmpty) return;

      _activeAudioPath = null;
      _activeLectureRecording = rec;
      _isLecturePillCollapsed = false;
      _currentPosition = Duration(milliseconds: initialPositionMs);
      _totalDuration = Duration(milliseconds: rec.durationMs);

      await _audioPlayer.stop();
      await _audioPlayer.setPlaybackRate(_playbackSpeed);

      if (audioSourcePath.startsWith('http://') || audioSourcePath.startsWith('https://')) {
        await _audioPlayer.play(UrlSource(audioSourcePath), position: Duration(milliseconds: initialPositionMs));
      } else {
        await _audioPlayer.play(DeviceFileSource(audioSourcePath), position: Duration(milliseconds: initialPositionMs));
      }

      if (mounted) {
        _isDockedAudioVisible = _isLectureScrolledOff(rec);
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error playing lecture recording: $e');
    }
  }

  Future<void> _toggleLecturePlayPause(PdfLectureRecording rec) async {
    if (_activeLectureRecording?.id != rec.id) {
      await _playLectureRecording(rec);
      return;
    }

    if (_playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.resume();
    }
    if (mounted) setState(() {});
  }

  void _seekToLectureStroke(PdfLectureRecording rec, SlideStroke stroke) {
    if (stroke.audioTimeMs == null) return;
    final seekPos = Duration(milliseconds: stroke.audioTimeMs!);

    if (_activeLectureRecording?.id != rec.id) {
      _playLectureRecording(rec, initialPositionMs: stroke.audioTimeMs!);
    } else {
      _audioPlayer.seek(seekPos);
      if (_playerState != PlayerState.playing) {
        _audioPlayer.resume();
      }
    }

    _highlightedStrokeId = stroke.id;
    _strokeHighlightController.forward(from: 0.0);
    setState(() {});
  }

  Future<void> _startLectureRecording(int pageNum, double x, double y) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isAdminOrOwner) return;
    if (_isRecordingLecture) return;

    try {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer.stop();
      }

      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final recId = 'lec_${DateTime.now().millisecondsSinceEpoch}';
        final filePath = '${tempDir.path}/$recId.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        _tempRecordingPath = filePath;
        _isRecordingLecture = true;
        _isPausedLecture = false;
        _lectureRecordDuration = Duration.zero;
        _recordingPageNumber = pageNum;
        _recordingPosX = x;
        _recordingPosY = y;
        _recordingStrokes.clear();
        _recordingPointerEvents.clear();

        _recordStopwatch = Stopwatch()..start();
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
          if (mounted && _recordStopwatch != null) {
            setState(() {
              _lectureRecordDuration = _recordStopwatch!.elapsed;
            });
          }
        });

        setState(() {});
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الرجاء منح إذن الميكروفون لبدء التسجيل', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting lecture recording: $e');
    }
  }

  Future<void> _pauseResumeLectureRecording() async {
    if (!_isRecordingLecture) return;
    try {
      if (_isPausedLecture) {
        await _audioRecorder.resume();
        _recordStopwatch?.start();
        _isPausedLecture = false;
      } else {
        await _audioRecorder.pause();
        _recordStopwatch?.stop();
        _isPausedLecture = true;
      }
      setState(() {});
    } catch (e) {
      debugPrint('Error pausing/resuming recording: $e');
    }
  }

  Future<void> _finishAndSaveLectureRecording() async {
    if (!_isRecordingLecture || _isSavingLecture) return;

    setState(() {
      _isSavingLecture = true;
    });

    try {
      _recordTimer?.cancel();
      _recordStopwatch?.stop();

      final recordedPath = await _audioRecorder.stop() ?? _tempRecordingPath;
      if (recordedPath == null || !File(recordedPath).existsSync()) {
        throw Exception('ملف الصوت المسجل غير موجود');
      }

      final recordedFile = File(recordedPath);
      final finalDurationMs = _lectureRecordDuration.inMilliseconds;

      final savedRec = await _pdfRepository.mainRepository.savePdfLectureRecording(
        pdfId: widget.pdfSlide.id,
        stationId: widget.stationDbId ?? '',
        audioFile: recordedFile,
        durationMs: finalDurationMs > 0 ? finalDurationMs : 1000,
        pageNumber: _recordingPageNumber,
        positionX: _recordingPosX,
        positionY: _recordingPosY,
        strokesData: Map.from(_recordingStrokes),
        pointerEvents: List.from(_recordingPointerEvents),
      );

      if (_cacheDirPath != null) {
        final cacheFile = File('$_cacheDirPath/lecture_${savedRec.id}.m4a');
        await recordedFile.copy(cacheFile.path);
        final cachedRec = savedRec.copyWith(localAudioPath: cacheFile.path);
        _lectureRecordings.add(cachedRec);

        final jsonList = _lectureRecordings.map((r) => r.toJson()).toList();
        await File('$_cacheDirPath/lecture_recordings.json')
            .writeAsString(jsonEncode(jsonList));
      } else {
        _lectureRecordings.add(savedRec);
      }

      for (final slide in controller.slides) {
        slide.strokes.removeWhere((s) => s is SlideStroke && s.audioTimeMs != null);
      }

      _isRecordingLecture = false;
      _isPausedLecture = false;
      _isSavingLecture = false;
      _tempRecordingPath = null;
      _recordingStrokes.clear();
      _recordingPointerEvents.clear();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ شرح المحاضرة المتزامن بنجاح', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Color(0xFF5B35F5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving lecture recording: $e');
      _isSavingLecture = false;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ التسجيل: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _cancelLectureRecording() async {
    try {
      _recordTimer?.cancel();
      _recordStopwatch?.stop();
      await _audioRecorder.stop();
      if (_tempRecordingPath != null) {
        final f = File(_tempRecordingPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}

    if (mounted) {
      for (final slide in controller.slides) {
        slide.strokes.removeWhere((s) => s is SlideStroke && s.audioTimeMs != null);
      }
      setState(() {
        _isRecordingLecture = false;
        _isPausedLecture = false;
        _isSavingLecture = false;
        _tempRecordingPath = null;
        _recordingStrokes.clear();
        _recordingPointerEvents.clear();
      });
    }
  }

  void _promptStartLectureRecording(int pageNum, double x, double y) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242038),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.mic_rounded, color: Color(0xFF7C5CFC)),
            SizedBox(width: 8),
            Text(
              'تسجيل شرح صوتي',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'هل ترغب في بدء تسجيل شرح صوتي متزامن مع الكتابة في الصفحة $pageNum؟',
          style: const TextStyle(
            fontFamily: 'Cairo',
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CFC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 18),
            label: const Text('بدء التسجيل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _startLectureRecording(pageNum, x, y);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteLectureRecording(PdfLectureRecording rec) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242038),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              'حذف التسجيل',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'هل تريد حذف هذا الشرح الصوتي مع جميع الملاحظات والكتابات الخاصة به نهائياً؟',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteLectureRecording(rec);
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLectureRecording(PdfLectureRecording rec) async {
    try {
      if (_activeLectureRecording?.id == rec.id) {
        await _cancelAudio();
      }
      await _pdfRepository.mainRepository.deletePdfLectureRecording(rec.id, rec.audioUrl);

      if (rec.localAudioPath != null) {
        final f = File(rec.localAudioPath!);
        if (await f.exists()) await f.delete();
      }
      if (_cacheDirPath != null) {
        final f = File('$_cacheDirPath/lecture_${rec.id}.m4a');
        if (await f.exists()) await f.delete();
      }

      _lectureRecordings.removeWhere((r) => r.id == rec.id);
      if (_cacheDirPath != null) {
        final jsonList = _lectureRecordings.map((r) => r.toJson()).toList();
        await File('$_cacheDirPath/lecture_recordings.json')
            .writeAsString(jsonEncode(jsonList));
      }

      // Collect all stroke IDs belonging to this recording
      final deletedStrokeIds = <String>{};
      for (final list in rec.strokesData.values) {
        for (final s in list) {
          deletedStrokeIds.add(s.id);
        }
      }

      // 1. Purge strokes from in-memory controller slides
      for (final slide in controller.slides) {
        slide.strokes.removeWhere((s) =>
            deletedStrokeIds.contains(s.id) ||
            (s is SlideStroke && s.audioTimeMs != null));
      }

      // 2. Clean local disk cache of saved_annotations.json
      if (_cacheDirPath != null) {
        final currentMap = await _readLocalSavedAnnotations();
        bool anyCleaned = false;
        for (final p in currentMap.keys) {
          final beforeLen = currentMap[p]?.length ?? 0;
          currentMap[p]?.removeWhere((s) =>
              deletedStrokeIds.contains(s.id) ||
              (s is SlideStroke && s.audioTimeMs != null));
          if ((currentMap[p]?.length ?? 0) != beforeLen) {
            anyCleaned = true;
          }
        }
        if (anyCleaned) {
          _writeLocalSavedAnnotations(currentMap);
        }
      }

      // 3. Purge strokes from user_pdf_workspaces in Supabase database
      unawaited(_pdfRepository.mainRepository.purgeLectureStrokesFromUserAnnotations(
        widget.pdfSlide.id,
        strokeIds: deletedStrokeIds,
      ));

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف التسجيل وجميع الملاحظات المرتبطة به بنجاح ✓', style: TextStyle(fontFamily: 'Cairo')),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting lecture recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف التسجيل: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _onLaserDotMoved(int pageNum, Offset localPos) {
    setState(() {
      _liveLaserDot = localPos;
      _liveLaserPage = pageNum;
    });
    if (_isRecordingLecture) {
      _recordingPointerEvents.add(
        PdfPointerEvent(
          pageNumber: pageNum,
          timestampMs: _recordStopwatch?.elapsedMilliseconds ?? 0,
          type: PdfPointerType.dot,
          x: localPos.dx,
          y: localPos.dy,
        ),
      );
    }
  }

  void _onLaserDotEnded(int pageNum) {
    setState(() {
      _liveLaserDot = null;
    });
    if (_isRecordingLecture) {
      _recordingPointerEvents.add(
        PdfPointerEvent(
          pageNumber: pageNum,
          timestampMs: _recordStopwatch?.elapsedMilliseconds ?? 0,
          type: PdfPointerType.dotUp,
        ),
      );
    }
  }

  void _onLaserTrailStarted(int pageNum, Offset startPos) {
    _trailStartTimeMs = _recordStopwatch?.elapsedMilliseconds ?? 0;
    _currentDrawingTrail = [startPos];
    _liveLaserDot = startPos;
    _liveLaserPage = pageNum;
    setState(() {});
  }

  void _onLaserTrailMoved(int pageNum, Offset pos) {
    _currentDrawingTrail.add(pos);
    _liveLaserDot = pos;
    _liveLaserPage = pageNum;
    setState(() {});
  }

  void _onLaserTrailEnded(int pageNum) {
    _liveLaserDot = null;
    if (_currentDrawingTrail.length >= 2) {
      final trailPoints = List<Offset>.from(_currentDrawingTrail);
      final now = DateTime.now().millisecondsSinceEpoch;
      final drawEndMs = _recordStopwatch?.elapsedMilliseconds ?? 0;
      final drawDur = (drawEndMs - _trailStartTimeMs).clamp(30, 10000);

      setState(() {
        _activeLaserTrails.add(
          ActiveLaserTrail(
            points: trailPoints,
            startTimeMs: now,
            totalDurationMs: 2000,
            pageNumber: pageNum,
          ),
        );
        _currentDrawingTrail = [];
      });

      if (_isRecordingLecture) {
        _recordingPointerEvents.add(
          PdfPointerEvent(
            pageNumber: pageNum,
            timestampMs: _trailStartTimeMs,
            type: PdfPointerType.trail,
            points: trailPoints,
            durationMs: 2000,
            drawDurationMs: drawDur,
          ),
        );
      }
    } else {
      setState(() {
        _currentDrawingTrail = [];
      });
    }
  }

  Future<void> _saveRecordingPosition(PdfLectureRecording rec) async {
    try {
      if (_cacheDirPath != null) {
        final jsonList = _lectureRecordings.map((r) => r.toJson()).toList();
        await File('$_cacheDirPath/lecture_recordings.json')
            .writeAsString(jsonEncode(jsonList));
      }
      await _pdfRepository.mainRepository.updatePdfLectureRecordingPosition(
        rec.id,
        rec.positionX,
        rec.positionY,
      );
    } catch (e) {
      debugPrint('Error saving lecture recording position: $e');
    }
  }

  Widget _buildLectureRecordingOverlay(
    PdfLectureRecording rec,
    double pdfWidth,
    double pdfHeight,
    bool isAdminOrOwner,
  ) {
    final isActive = _activeLectureRecording?.id == rec.id;
    final dragPos = _draggedRecordingPositions[rec.id];
    final left = (dragPos?.dx ?? rec.positionX).clamp(8.0, pdfWidth - 36.0);
    final top = (dragPos?.dy ?? rec.positionY).clamp(8.0, pdfHeight - 36.0);

    if (isActive) {
      if (_isDockedAudioVisible) {
        return Positioned(
          left: left,
          top: top,
          width: 34,
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleLecturePlayPause(rec),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF5B35F5),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x555B35F5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 1.5),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 1.8),
              ),
              child: Icon(
                _playerState == PlayerState.playing
                    ? Icons.graphic_eq_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        );
      }

      // If folded/collapsed while playing on the slide:
      if (_isLecturePillCollapsed) {
        final isPlaying = _playerState == PlayerState.playing;
        return Positioned(
          left: left.clamp(8.0, pdfWidth - 66.0),
          top: top.clamp(8.0, pdfHeight - 38.0),
          child: Material(
            color: Colors.transparent,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedBuilder(
                animation: _laserPulseController,
                builder: (context, _) {
                  final t = (math.sin(_laserPulseController.value * 2 * math.pi) + 1.0) / 2.0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Circular sound icon (Tap to Play/Pause, Drag to move if Admin)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggleLecturePlayPause(rec),
                        onLongPress: isAdminOrOwner ? () => _confirmDeleteLectureRecording(rec) : null,
                        onPanUpdate: isAdminOrOwner ? (details) {
                          setState(() {
                            final current = _draggedRecordingPositions[rec.id] ?? Offset(rec.positionX, rec.positionY);
                            _draggedRecordingPositions[rec.id] = Offset(
                              (current.dx + details.delta.dx).clamp(8.0, pdfWidth - 36.0),
                              (current.dy + details.delta.dy).clamp(8.0, pdfHeight - 36.0),
                            );
                          });
                        } : null,
                        onPanEnd: isAdminOrOwner ? (details) {
                          final newPos = _draggedRecordingPositions.remove(rec.id);
                          if (newPos != null) {
                            final idx = _lectureRecordings.indexWhere((r) => r.id == rec.id);
                            if (idx != -1) {
                              final updated = _lectureRecordings[idx].copyWith(
                                positionX: newPos.dx,
                                positionY: newPos.dy,
                              );
                              setState(() {
                                _lectureRecordings[idx] = updated;
                              });
                              _saveRecordingPosition(updated);
                            }
                          }
                        } : null,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B35F5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF5B35F5).withValues(alpha: 0.35 + 0.25 * t),
                                blurRadius: 6.0 + 4.0 * t,
                                spreadRadius: 1.0 + 1.5 * t,
                              ),
                              const BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),

                      // Pop-out Arrow Button (سهم منبثق لليمين لإعادة فتح المشغل)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _isLecturePillCollapsed = false);
                        },
                        child: Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF26223D),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(13),
                              bottomRight: Radius.circular(13),
                            ),
                            border: Border.all(color: const Color(0xFF7C5CFC), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 4,
                                offset: Offset(1.5, 1.5),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }

      const double pillWidth = 285.0;
      final double adjustedLeft = (left + pillWidth > pdfWidth)
          ? (pdfWidth - pillWidth - 8).clamp(8.0, pdfWidth)
          : left.clamp(8.0, pdfWidth - pillWidth);
      final double adjustedTop = (top - 8).clamp(8.0, pdfHeight - 48);

      return Positioned(
        left: adjustedLeft,
        top: adjustedTop,
        child: _buildLecturePillPlayer(rec, pdfWidth, pdfHeight, isAdminOrOwner),
      );
    }

    // Unplayed / Idle state:
    // Slightly smaller circular sound icon with refined, subtle glow & draggable for Admin
    final isDraggingThis = _draggedRecordingPositions.containsKey(rec.id);
    return Positioned(
      left: left,
      top: top,
      child: Tooltip(
        message: 'تسجيل صوتي للمحاضر (${_formatDuration(Duration(milliseconds: rec.durationMs))})',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _playLectureRecording(rec),
          onLongPress: isAdminOrOwner ? () => _confirmDeleteLectureRecording(rec) : null,
          onPanUpdate: isAdminOrOwner ? (details) {
            setState(() {
              final current = _draggedRecordingPositions[rec.id] ?? Offset(rec.positionX, rec.positionY);
              _draggedRecordingPositions[rec.id] = Offset(
                (current.dx + details.delta.dx).clamp(8.0, pdfWidth - 36.0),
                (current.dy + details.delta.dy).clamp(8.0, pdfHeight - 36.0),
              );
            });
          } : null,
          onPanEnd: isAdminOrOwner ? (details) {
            final newPos = _draggedRecordingPositions.remove(rec.id);
            if (newPos != null) {
              final idx = _lectureRecordings.indexWhere((r) => r.id == rec.id);
              if (idx != -1) {
                final updated = _lectureRecordings[idx].copyWith(
                  positionX: newPos.dx,
                  positionY: newPos.dy,
                );
                setState(() {
                  _lectureRecordings[idx] = updated;
                });
                _saveRecordingPosition(updated);
              }
            }
          } : null,
          child: AnimatedBuilder(
            animation: _laserPulseController,
            builder: (context, _) {
              final t = (math.sin(_laserPulseController.value * 2 * math.pi) + 1.0) / 2.0;
              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B35F5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.8),
                  boxShadow: [
                    // Subtle, gentle pulsating glow (الأيقونة متوهجة قليلاً)
                    BoxShadow(
                      color: const Color(0xFF5B35F5).withValues(alpha: isDraggingThis ? 0.6 : (0.35 + 0.25 * t)),
                      blurRadius: isDraggingThis ? 10.0 : (6.0 + 4.0 * t),
                      spreadRadius: isDraggingThis ? 2.5 : (1.0 + 1.5 * t),
                    ),
                    const BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1.5),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLecturePillPlayer(
    PdfLectureRecording rec,
    double pdfWidth,
    double pdfHeight,
    bool isAdminOrOwner,
  ) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : (rec.durationMs > 0 ? rec.durationMs.toDouble() : 1.0);
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Material(
      color: Colors.transparent,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF26223D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF7C5CFC), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Play / Pause Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleLecturePlayPause(rec),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // 2. Audio Slider / Progress Track
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: const Color(0xFF7C5CFC),
                    inactiveTrackColor: const Color(0xFF8E8E93),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 3. Playback Speed Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 4. Remaining Countdown Time
              Text(
                _formatRemainingTime(_currentPosition, _totalDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 4),

              // 5. Delete Button if Admin / Owner
              if (isAdminOrOwner) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDeleteLectureRecording(rec),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],

              // 6. Fold / Collapse Button (سهم لطي المشغل وإظهار المحتوى مع استمرار تشغيل الصوت)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _isLecturePillCollapsed = true);
                },
                child: Tooltip(
                  message: 'طي المشغل',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 2),

              // 7. Close / Cancel Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelAudio,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockedLecturePlayer(
    PdfLectureRecording rec,
    bool isDark,
    bool compact,
    bool isAdminOrOwner,
  ) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : (rec.durationMs > 0 ? rec.durationMs.toDouble() : 1.0);
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26223D) : const Color(0xFF322F46),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFF7C5CFC),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Page Indicator & Jump-to Page
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _scrollToPage(rec.pageNumber - 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ص ${rec.pageNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 2. Play / Pause Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleLecturePlayPause(rec),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 3. Audio Slider / Progress Track
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? 110 : 180,
                  minWidth: 70,
                ),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: const Color(0xFF7C5CFC),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 4. Playback Speed Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 5. Remaining Countdown Time
              Text(
                _formatRemainingTime(_currentPosition, _totalDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 6),

              // 6. Delete Button if Admin / Owner
              if (isAdminOrOwner) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDeleteLectureRecording(rec),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],

              // 7. Cancel / Close Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelAudio,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoundAnnotationOverlay(
    PdfSoundAnnotation sound,
    double pdfWidth,
    double pdfHeight,
  ) {
    final isActive = _activeAudioPath == sound.tempAudioPath;
    final left = sound.rect[0];
    final double rectTop = sound.rect.length >= 4 ? sound.rect[3] : 0.0;
    final top = (pdfHeight - rectTop).clamp(0.0, pdfHeight);

    if (isActive) {
      // When docked under toolbar, show active compact glowing icon on the page
      if (_isDockedAudioVisible) {
        return Positioned(
          left: left,
          top: top,
          width: 44,
          height: 44,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _togglePlayPause(sound.tempAudioPath),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF5B35F5),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x775B35F5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                _playerState == PlayerState.playing
                    ? Icons.volume_up_rounded
                    : Icons.pause_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        );
      }

      if (_isSoundPillCollapsed) {
        final isPlaying = _playerState == PlayerState.playing;
        return Positioned(
          left: left.clamp(8.0, pdfWidth - 78.0),
          top: top.clamp(8.0, pdfHeight - 48.0),
          child: Material(
            color: Colors.transparent,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _togglePlayPause(sound.tempAudioPath),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B35F5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x885B35F5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlaying ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _isSoundPillCollapsed = false);
                    },
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4A494E),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 6,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      const double pillWidth = 260.0;
      final double adjustedLeft = (left + pillWidth > pdfWidth)
          ? (pdfWidth - pillWidth - 8).clamp(8.0, pdfWidth)
          : left.clamp(8.0, pdfWidth - pillWidth);
      final double adjustedTop = (top - 8).clamp(8.0, pdfHeight - 48);

      return Positioned(
        left: adjustedLeft,
        top: adjustedTop,
        child: _buildAudioPillPlayer(sound, pdfWidth, pdfHeight),
      );
    }

    final width = (sound.rect[2] - sound.rect[0]).abs();
    final height = ((sound.rect.length >= 4 ? sound.rect[3] : 0.0) - sound.rect[1]).abs();

    final clickWidth = width.clamp(36.0, 56.0);
    final clickHeight = height.clamp(36.0, 56.0);

    return Positioned(
      left: left,
      top: top,
      width: clickWidth,
      height: clickHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _togglePlayPause(sound.tempAudioPath),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF5B35F5),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(
            Icons.volume_up_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioPillPlayer(
    PdfSoundAnnotation sound,
    double pdfWidth,
    double pdfHeight,
  ) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0;
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Material(
      color: Colors.transparent,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF4A494E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Play / Pause Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _togglePlayPause(sound.tempAudioPath),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // 2. Audio Slider / Progress Track
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF8E8E93),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 3. Playback Speed Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 4. Remaining Countdown Time (e.g. -00:05)
              Text(
                _formatRemainingTime(_currentPosition, _totalDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 2),

              // 5. Fold / Collapse Button (سهم لطي المشغل مع استمرار تشغيل الصوت)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _isSoundPillCollapsed = true);
                },
                child: Tooltip(
                  message: 'طي المشغل',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 2),

              // 6. Close / Cancel Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelAudio,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockedAudioPlayer(
    PdfSoundAnnotation sound,
    bool isDark,
    bool compact,
  ) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs =
        _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26223D) : const Color(0xFF322F46),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.white24,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Page Indicator & Jump-to Page
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _scrollToPage(sound.pageNumber - 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B35F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ص ${sound.pageNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 2. Play / Pause Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _togglePlayPause(sound.tempAudioPath),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 3. Audio Slider / Progress Track
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? 110 : 180,
                  minWidth: 70,
                ),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: const Color(0xFF7C5CFC),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 4. Playback Speed Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 5. Remaining Countdown Time
              Text(
                _formatRemainingTime(_currentPosition, _totalDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 6),

              // 6. Cancel / Close Button
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelAudio,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;

    if (_isLoadingPdf) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
        body: const Center(
          child: LogoSpinner(size: 78, logoSize: 42),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleBack();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final width = MediaQuery.of(context).size.width;
            final compact = width < 760;
            final isSmallPhone = MediaQuery.of(context).size.shortestSide < 600;

            final currentPageNum = _currentPageIndex + 1;
            final totalPages = controller.slides.length;

            // Lock scroll on small phones when any draw tool is active
            final isPenActive =
                controller.selectedTool == WorkspaceTool.pen ||
                controller.selectedTool == WorkspaceTool.highlighter ||
                controller.selectedTool == WorkspaceTool.eraser ||
                controller.selectedTool == WorkspaceTool.laserDot ||
                controller.selectedTool == WorkspaceTool.laserTrail;
            final lockScroll = isPenActive && isSmallPhone;

            return Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
              body: SafeArea(
                maintainBottomViewPadding: true,
                child: Column(
                  children: [
                    WorkspaceTopToolbar(
                      controller: controller,
                      stationName: widget.stationName,
                      compact: compact,
                      isDark: isDark,
                      showBrand: true,
                      showAddSlideButton: false,
                      showLaserTool: true,
                      isRecordingLecture: _isRecordingLecture,
                      onRecordLecture: provider.isAdminOrOwner
                          ? () {
                              if (_isRecordingLecture) {
                                _pauseResumeLectureRecording();
                              } else {
                                final pageNum = _currentPageIndex + 1;
                                final size = _pageSizes[pageNum] ?? const Size(595, 842);
                                _startLectureRecording(pageNum, size.width / 2, 40.0);
                              }
                            }
                          : null,
                      zoomPercent: (controller.zoom * 100).round(),
                      onZoomTap: () => _setZoom(1),
                      onZoomOut: () => _setZoom(controller.zoom - .1),
                      onZoomIn: () => _setZoom(controller.zoom + .1),
                      onBack: () async {
                        if (await _handleBack()) {
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      },
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          // Interactive Zoom & Vertical scrollable PDF pages (Same gesture engine as Slide Workspace)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final viewportHeight = constraints.maxHeight;
                              final viewportWidth = constraints.maxWidth;
                              final pageWidth = (viewportWidth - 16.0)
                                  .clamp(280.0, double.infinity)
                                  .toDouble();

                              _lastViewportHeight = viewportHeight;
                              _lastViewportWidth = viewportWidth;
                              _lastPageWidth = pageWidth;

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
                                        final currentMatrix =
                                            _transformationController.value;
                                        final translation =
                                            currentMatrix.getTranslation();
                                        final scale =
                                            currentMatrix.getMaxScaleOnAxis();

                                        final contentHeight =
                                            _contentHeight(pageWidth);
                                        final verticalBounds = _translationBounds(
                                            contentHeight, viewportHeight, scale);
                                        final horizontalBounds =
                                            _translationBounds(
                                                pageWidth, viewportWidth, scale);

                                        final double newY = (translation.y + delta.dy)
                                            .clamp(verticalBounds.min, verticalBounds.max)
                                            .toDouble();
                                        final double newX = (translation.x + delta.dx)
                                            .clamp(horizontalBounds.min, horizontalBounds.max)
                                            .toDouble();

                                        final newMatrix =
                                            Matrix4.copy(currentMatrix)
                                              ..setTranslationRaw(
                                                  newX, newY, translation.z);
                                        _transformationController.value =
                                            newMatrix;
                                      }
                                      ..onEnd = (velocity) {
                                        final double velocityY =
                                            velocity.pixelsPerSecond.dy;
                                        if (velocityY.abs() > 100) {
                                          final currentMatrix =
                                              _transformationController.value;
                                          final translation =
                                              currentMatrix.getTranslation();
                                          final simulation =
                                              ClampingScrollSimulation(
                                            position: translation.y,
                                            velocity: velocityY,
                                            tolerance: Tolerance.defaultTolerance,
                                          );
                                          _flingAnimationController
                                              .animateWith(simulation);
                                        }
                                      };
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
                                    if (_activeStylusPointers
                                        .contains(event.pointer)) {
                                      setState(() {
                                        _activeStylusPointers
                                            .remove(event.pointer);
                                      });
                                    }
                                  },
                                  onPointerCancel: (event) {
                                    if (_activeStylusPointers
                                        .contains(event.pointer)) {
                                      setState(() {
                                        _activeStylusPointers
                                            .remove(event.pointer);
                                      });
                                    }
                                  },
                                  onPointerSignal: (pointerSignal) {
                                    if (pointerSignal is PointerScrollEvent) {
                                      GestureBinding.instance.pointerSignalResolver
                                          .register(pointerSignal, (event) {
                                        if (event is PointerScrollEvent) {
                                          final double scrollDeltaY =
                                              event.scrollDelta.dy;
                                          final double scrollDeltaX =
                                              event.scrollDelta.dx;
                                          if (scrollDeltaY != 0 ||
                                              scrollDeltaX != 0) {
                                            final currentMatrix =
                                                _transformationController.value;
                                            final translation =
                                                currentMatrix.getTranslation();
                                            final scale = currentMatrix
                                                .getMaxScaleOnAxis();

                                            final contentHeight =
                                                _contentHeight(pageWidth);
                                            final verticalBounds =
                                                _translationBounds(contentHeight,
                                                    viewportHeight, scale);
                                            final horizontalBounds =
                                                _translationBounds(
                                                    pageWidth, viewportWidth, scale);

                                            final double newY = (translation.y -
                                                    scrollDeltaY)
                                                .clamp(verticalBounds.min,
                                                    verticalBounds.max)
                                                .toDouble();
                                            final double newX = (translation.x -
                                                    scrollDeltaX)
                                                .clamp(horizontalBounds.min,
                                                    horizontalBounds.max)
                                                .toDouble();

                                            final newMatrix =
                                                Matrix4.copy(currentMatrix)
                                                  ..setTranslationRaw(
                                                      newX, newY, translation.z);
                                            _transformationController.value =
                                                newMatrix;
                                          }
                                        }
                                      });
                                    }
                                  },
                                  child: InteractiveViewer(
                                    transformationController:
                                        _transformationController,
                                    panEnabled: false,
                                    scaleEnabled: !_phoneDrawingMode &&
                                        !(_isDrawingTool &&
                                            _activeStylusPointers.isNotEmpty),
                                    boundaryMargin: EdgeInsets.zero,
                                    minScale: 0.5,
                                    maxScale: 5.0,
                                    alignment: Alignment.topLeft,
                                    constrained: false,
                                    child: Padding(
                                      key: _contentKey,
                                      padding: const EdgeInsets.fromLTRB(
                                          8, 8, 8, 100),
                                      child: SizedBox(
                                        width: pageWidth,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (var index = 0;
                                                index < totalPages;
                                                index++) ...[
                                              Builder(builder: (context) {
                                                final pageNum = index + 1;
                                                final pageSounds =
                                                    _soundAnnotations
                                                        .where((s) =>
                                                            s.pageNumber == pageNum)
                                                        .toList();
                                                return Padding(
                                                  key: _pageKeys[pageNum],
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 6),
                                                  child: _buildPdfPageCanvas(
                                                      index,
                                                      isDark,
                                                      pageSounds,
                                                      isSmallPhone),
                                                );
                                              }),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Sticky Docked Audio Bar (when active lecture recording or active sound is scrolled out of view under toolbar)
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: AnimatedSlide(
                              offset: (_isDockedAudioVisible && (_activeLectureRecording != null || _activeSound != null))
                                  ? Offset.zero
                                  : const Offset(0, -0.4),
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: (_isDockedAudioVisible && (_activeLectureRecording != null || _activeSound != null))
                                    ? 1.0
                                    : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: IgnorePointer(
                                  ignoring: !(_isDockedAudioVisible && (_activeLectureRecording != null || _activeSound != null)),
                                  child: _activeLectureRecording != null
                                      ? Center(
                                          child: _buildDockedLecturePlayer(
                                            _activeLectureRecording!,
                                            isDark,
                                            compact,
                                            provider.isAdminOrOwner,
                                          ),
                                        )
                                      : (_activeSound != null
                                          ? Center(
                                              child: _buildDockedAudioPlayer(
                                                _activeSound!,
                                                isDark,
                                                compact,
                                              ),
                                            )
                                          : const SizedBox.shrink()),
                                ),
                              ),
                            ),
                          ),
                          // Floating Lecture Recording Bar for Admin/Owner
                          if (_isRecordingLecture)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: PdfLectureRecordingBar(
                                  elapsed: _lectureRecordDuration,
                                  isPaused: _isPausedLecture,
                                  pageNumber: _recordingPageNumber,
                                  isSaving: _isSavingLecture,
                                  onPauseResume: _pauseResumeLectureRecording,
                                  onFinish: _finishAndSaveLectureRecording,
                                  onCancel: _cancelLectureRecording,
                                ),
                              ),
                            ),
                          // Bottom Page Indicator / Controller
                          if (!_isRecordingLecture)
                            Positioned(
                              bottom: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF242038) : Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black26, blurRadius: 10)
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                                      onPressed: _currentPageIndex > 0
                                          ? () => _scrollToPage(_currentPageIndex - 1)
                                          : null,
                                    ),
                                    Text(
                                      '$currentPageNum / $totalPages',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                      onPressed: _currentPageIndex < totalPages - 1
                                          ? () => _scrollToPage(_currentPageIndex + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Pen mode active indicator on small phones
                          if (lockScroll)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5B35F5),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'وضع الرسم',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPdfPageCanvas(int index, bool isDark, List<PdfSoundAnnotation> pageSounds, bool isSmallPhone) {
    final pageNum = index + 1;
    final cachedBytes = _pageCache[pageNum];
    final pageSize = _pageSizes[pageNum];

    if (cachedBytes == null) {
      _ensurePageLoaded(pageNum);
      final double placeholderAspect = pageSize != null ? (pageSize.width / pageSize.height) : (595 / 842);
      return AspectRatio(
        aspectRatio: placeholderAspect,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF242038) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final double pdfW = pageSize?.width ?? 595;
    final double pdfH = pageSize?.height ?? 842;
    final double aspect = pdfW / pdfH;

    // Collect lecturer strokes for this page (for Notability dimming effect & tap-seeking)
    final List<SlideStroke> pageLecturerStrokes;
    if (_activeLectureRecording != null) {
      pageLecturerStrokes = _activeLectureRecording!.strokesData[pageNum] ?? const [];
    } else {
      final strokes = <SlideStroke>[];
      for (final rec in _lectureRecordings) {
        final s = rec.strokesData[pageNum];
        if (s != null) strokes.addAll(s);
      }
      pageLecturerStrokes = strokes;
    }

    final provider = Provider.of<AppProvider>(context, listen: false);

    return AspectRatio(
      aspectRatio: aspect,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: pdfW,
          height: pdfH,
          child: Stack(
            children: [
              // 1. The rendered PDF page image (fills the exact PDF dimensions)
              Positioned.fill(
                child: Image.memory(
                  cachedBytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),

              // 2. Synchronized Lecturer Notes (Notability Effect: Dimmed when in future, vivid on reach, pulse highlight on seek)
              // Hidden during active recording to avoid old strokes showing during new session
              if (pageLecturerStrokes.isNotEmpty && !_isRecordingLecture)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PdfLecturerNotesPainter(
                        strokes: pageLecturerStrokes,
                        currentAudioMs: _activeLectureRecording != null
                            ? _currentPosition.inMilliseconds
                            : null,
                        highlightedStrokeId: _highlightedStrokeId,
                        highlightProgress: _strokeHighlightController.value,
                      ),
                    ),
                  ),
                ),

              // 2b. Live Lecturer Notes drawn during active recording session
              if (_isRecordingLecture && (_recordingStrokes[pageNum]?.isNotEmpty ?? false))
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PdfLecturerNotesPainter(
                        strokes: _recordingStrokes[pageNum]!,
                        currentAudioMs: null, // Full opacity
                      ),
                    ),
                  ),
                ),

              // 3. User Drawing layer & interactive gestures
              Positioned.fill(
                child: _PdfDrawingOverlay(
                  controller: controller,
                  index: index,
                  isDark: isDark,
                  isSmallPhone: isSmallPhone,
                  isRecordingLecture: _isRecordingLecture,
                  getAudioTimeMs: () => _recordStopwatch?.elapsedMilliseconds ?? 0,
                  onStrokeCompleted: (stroke) {
                    if (_isRecordingLecture) {
                      setState(() {
                        _recordingStrokes.putIfAbsent(pageNum, () => []).add(stroke);
                      });
                    }
                  },
                  onLaserDotMoved: (pos) => _onLaserDotMoved(pageNum, pos),
                  onLaserDotEnded: () => _onLaserDotEnded(pageNum),
                  onLaserTrailStarted: (pos) => _onLaserTrailStarted(pageNum, pos),
                  onLaserTrailMoved: (pos) => _onLaserTrailMoved(pageNum, pos),
                  onLaserTrailEnded: () => _onLaserTrailEnded(pageNum),
                  onTapCanvas: (localPos) {
                    if (pageLecturerStrokes.isNotEmpty) {
                      final tapped = PdfLecturerNotesPainter.findTappedStroke(
                        pageLecturerStrokes,
                        localPos,
                      );
                      if (tapped != null && tapped.audioTimeMs != null) {
                        PdfLectureRecording? targetRec = _activeLectureRecording;
                        if (targetRec == null ||
                            !(targetRec.strokesData[pageNum]?.any((s) => s.id == tapped.id) ?? false)) {
                          targetRec = _lectureRecordings.where((r) =>
                              r.strokesData[pageNum]?.any((s) => s.id == tapped.id) ?? false).firstOrNull;
                        }
                        if (targetRec != null) {
                          _seekToLectureStroke(targetRec, tapped);
                        }
                      }
                    }
                  },
                  onLongPressCanvas: (localPos) {
                    if (provider.isAdminOrOwner && !_isRecordingLecture) {
                      _promptStartLectureRecording(pageNum, localPos.dx, localPos.dy);
                    }
                  },
                ),
              ),

              // 4. Laser Pointer Layer (Pulsing Laser Dot & Vanishing Laser Trail)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PdfLaserPainter(
                      activeLaserDot: (_liveLaserPage == pageNum) ? _liveLaserDot : null,
                      pulsePhase: _laserPulseController.value,
                      activeTrails: _activeLaserTrails.where((t) => t.pageNumber == pageNum).toList(),
                      currentTimestampMs: _activeLectureRecording != null
                          ? _currentPosition.inMilliseconds
                          : DateTime.now().millisecondsSinceEpoch,
                      currentDrawingTrail: (_liveLaserPage == pageNum) ? _currentDrawingTrail : null,
                    ),
                  ),
                ),
              ),

              // 5. Lecture Recording Overlays & Badges
              for (final rec in _lectureRecordings.where((r) => r.pageNumber == pageNum))
                _buildLectureRecordingOverlay(rec, pdfW, pdfH, provider.isAdminOrOwner),

              // 6. Sound annotation overlays
              for (final sound in pageSounds)
                _buildSoundAnnotationOverlay(sound, pdfW, pdfH),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfDrawingOverlay extends StatefulWidget {
  final SlideWorkspaceController controller;
  final int index;
  final bool isDark;
  final bool isSmallPhone;
  final bool isRecordingLecture;
  final int Function()? getAudioTimeMs;
  final ValueChanged<SlideStroke>? onStrokeCompleted;
  final ValueChanged<Offset>? onLaserDotMoved;
  final VoidCallback? onLaserDotEnded;
  final ValueChanged<Offset>? onLaserTrailStarted;
  final ValueChanged<Offset>? onLaserTrailMoved;
  final VoidCallback? onLaserTrailEnded;
  final ValueChanged<Offset>? onTapCanvas;
  final ValueChanged<Offset>? onLongPressCanvas;

  const _PdfDrawingOverlay({
    required this.controller,
    required this.index,
    required this.isDark,
    required this.isSmallPhone,
    this.isRecordingLecture = false,
    this.getAudioTimeMs,
    this.onStrokeCompleted,
    this.onLaserDotMoved,
    this.onLaserDotEnded,
    this.onLaserTrailStarted,
    this.onLaserTrailMoved,
    this.onLaserTrailEnded,
    this.onTapCanvas,
    this.onLongPressCanvas,
  });

  @override
  State<_PdfDrawingOverlay> createState() => _PdfDrawingOverlayState();
}

class _PdfDrawingOverlayState extends State<_PdfDrawingOverlay> {
  final GlobalKey _canvasKey = GlobalKey();
  int? _activePointer;
  PointerDeviceKind? _activeKind;

  SlideWorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(_PdfDrawingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.index < 0 || widget.index >= controller.slides.length) {
      return const SizedBox.shrink();
    }
    final slide = controller.slides[widget.index];
    final isCurrent = widget.index == controller.currentIndex;

    final canDraw = _canDraw;
    return GestureDetector(
      behavior: canDraw ? HitTestBehavior.deferToChild : HitTestBehavior.translucent,
      onTapUp: (details) {
        if (!canDraw) {
          widget.onTapCanvas?.call(details.localPosition);
        }
      },
      onLongPressStart: (details) {
        if (!canDraw) {
          widget.onLongPressCanvas?.call(details.localPosition);
        }
      },
      child: Listener(
        behavior: canDraw ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onPointerDown: canDraw
            ? (event) {
                unawaited(_handlePointerDown(event));
              }
            : null,
        onPointerMove: canDraw ? _handlePointerMove : null,
        onPointerUp: canDraw ? _handlePointerUp : null,
        onPointerCancel: canDraw ? _handlePointerUp : null,
        child: Stack(
          key: _canvasKey,
          fit: StackFit.expand,
          children: [
            // Transparent layer to guarantee full pointer hit testing across whole canvas when drawing tool is active
            if (canDraw)
              const Positioned.fill(
                child: ColoredBox(color: Colors.transparent),
              ),
            // Render existing user strokes (keep visible during lecture recording, only skip during passive replay)
            for (final obj in (slide.strokes.toList()
              ..sort((a, b) {
                final cmp = a.zIndex.compareTo(b.zIndex);
                if (cmp != 0) return cmp;
                return a.creationTime.compareTo(b.creationTime);
              })))
              if (obj is SlideStroke && obj.audioTimeMs != null)
                const SizedBox.shrink()
              else
                WorkspaceRendererRegistry.render(
                  context: context,
                  object: obj,
                  controller: controller,
                  isSelected: isCurrent && controller.selectedObjectId == obj.id,
                  onSelected: () {
                    if (widget.index != controller.currentIndex) {
                      controller.goToSlide(widget.index, clearHistory: false);
                    }
                    controller.selectObject(obj.id);
                  },
                  onUpdate: (updated) {
                    controller.onInteractionFinished(updated);
                  },
                  onDelete: () {
                    controller.deleteWorkspaceObject(obj.id);
                    controller.selectObject(null);
                  },
                ),
            // Render active live strokes drawing
            if (isCurrent)
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: DrawingLayerPainter(
                      strokes: const [],
                      activeStroke: controller.activeStroke,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePointerDown(PointerDownEvent event) async {
    if (!_canDraw || !_isPrimaryMouseButton(event)) return;

    final fingerDrawing = MediaQuery.sizeOf(context).width < 600 &&
        event.kind == PointerDeviceKind.touch;
    if (!_isStylus(event.kind) &&
        event.kind != PointerDeviceKind.mouse &&
        !fingerDrawing) {
      return;
    }

    if (widget.index != controller.currentIndex) {
      controller.goToSlide(widget.index, clearHistory: false);
      final repo = controller.repository as _PdfSlideRepository;
      repo.mainRepository.savePdfLastOpenedPage(repo.pdfId, repo.stationId, widget.index + 1);
    }

    // Laser pointer tools bypass normal stroke drawing
    if (controller.selectedTool == WorkspaceTool.laserDot) {
      final pt = _toSlidePoint(event.position);
      _activePointer = event.pointer;
      widget.onLaserDotMoved?.call(pt);
      return;
    }
    if (controller.selectedTool == WorkspaceTool.laserTrail) {
      final pt = _toSlidePoint(event.position);
      _activePointer = event.pointer;
      widget.onLaserTrailStarted?.call(pt);
      return;
    }

    final incomingIsStylus = _isStylus(event.kind);
    final activeIsStylus = _isStylus(_activeKind);
    if (_activePointer != null) {
      if (incomingIsStylus && !activeIsStylus) {
        await controller.endStroke();
      } else {
        return;
      }
    }

    _activePointer = event.pointer;
    _activeKind = event.kind;
    final audioTime = widget.isRecordingLecture ? widget.getAudioTimeMs?.call() : null;
    controller.startStroke(
      _toSlidePoint(event.position),
      event.kind,
      pressure: event.pressure,
      audioTimeMs: audioTime,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    if (controller.selectedTool == WorkspaceTool.laserDot) {
      widget.onLaserDotMoved?.call(_toSlidePoint(event.position));
      return;
    }
    if (controller.selectedTool == WorkspaceTool.laserTrail) {
      widget.onLaserTrailMoved?.call(_toSlidePoint(event.position));
      return;
    }
    controller.appendStrokePoint(_toSlidePoint(event.position), event.pressure);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _activeKind = null;

    if (controller.selectedTool == WorkspaceTool.laserDot) {
      widget.onLaserDotEnded?.call();
      return;
    }
    if (controller.selectedTool == WorkspaceTool.laserTrail) {
      widget.onLaserTrailEnded?.call();
      return;
    }

    final currentStroke = controller.activeStroke.value;
    if (currentStroke != null && widget.onStrokeCompleted != null) {
      widget.onStrokeCompleted!(currentStroke);
    }
    unawaited(controller.endStroke());
  }

  bool get _canDraw =>
      controller.selectedTool == WorkspaceTool.pen ||
      controller.selectedTool == WorkspaceTool.highlighter ||
      controller.selectedTool == WorkspaceTool.eraser ||
      controller.selectedTool == WorkspaceTool.laserDot ||
      controller.selectedTool == WorkspaceTool.laserTrail;

  bool _isPrimaryMouseButton(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.mouse ||
      event.buttons == kPrimaryMouseButton;

  bool _isStylus(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  Offset _toSlidePoint(Offset globalPosition) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(globalPosition) ?? Offset.zero;
  }
}

class _PdfSlideRepository extends SupabaseSlideWorkspaceRepository {
  final String pdfId;
  final String stationId;
  final SupabaseSlideWorkspaceRepository mainRepository;
  final Function(int pageNum, List<WorkspaceObject> strokes)? onLocalStrokesUpdated;

  _PdfSlideRepository({
    required this.pdfId,
    required this.stationId,
    required this.mainRepository,
    this.onLocalStrokesUpdated,
  });

  @override
  Future<void> saveSlideStrokes(String slideId, List<WorkspaceObject> strokes, {bool isExamMode = false}) async {
    final parts = slideId.split('_page_');
    if (parts.length >= 2) {
      final pageNum = int.tryParse(parts[1]);
      if (pageNum != null) {
        final cleanStrokes = strokes
            .where((s) => !(s is SlideStroke && s.audioTimeMs != null))
            .toList();
        onLocalStrokesUpdated?.call(pageNum, cleanStrokes);
        try {
          await mainRepository.savePdfAnnotations(pdfId, stationId, pageNum, cleanStrokes);
        } catch (e) {
          debugPrint('Offline/Network saving PDF annotations error: $e');
        }
      }
    }
  }
}

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

