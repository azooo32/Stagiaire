import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/slide_workspace_repository.dart';
import '../../domain/entities/slide_workspace_models.dart';

abstract class WorkspaceCommand {
  FutureOr<void> execute();
  FutureOr<void> undo();
}

class MoveObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final String objectId;
  final bool isExam;
  final double oldX;
  final double oldY;
  final double newX;
  final double newY;

  MoveObjectCommand({
    required this.controller,
    required this.slideId,
    required this.objectId,
    required this.isExam,
    required this.oldX,
    required this.oldY,
    required this.newX,
    required this.newY,
  });

  @override
  void execute() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(x: newX, y: newY, updatedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return obj;
    });
  }

  @override
  void undo() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(x: oldX, y: oldY, updatedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return obj;
    });
  }
}

class ResizeObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final String objectId;
  final bool isExam;
  final double oldX;
  final double oldY;
  final double oldW;
  final double oldH;
  final double newX;
  final double newY;
  final double newW;
  final double newH;

  ResizeObjectCommand({
    required this.controller,
    required this.slideId,
    required this.objectId,
    required this.isExam,
    required this.oldX,
    required this.oldY,
    required this.oldW,
    required this.oldH,
    required this.newX,
    required this.newY,
    required this.newW,
    required this.newH,
  });

  @override
  void execute() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(x: newX, y: newY, width: newW, height: newH, updatedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return obj;
    });
  }

  @override
  void undo() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(x: oldX, y: oldY, width: oldW, height: oldH, updatedAt: DateTime.now().millisecondsSinceEpoch);
      }
      return obj;
    });
  }
}

class DeleteObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final bool isExam;
  final WorkspaceObject object;
  final int index;

  DeleteObjectCommand({
    required this.controller,
    required this.slideId,
    required this.isExam,
    required this.object,
    required this.index,
  });

  @override
  void execute() {
    controller.removeObjectFromSlide(slideId, object.id, isExam);
  }

  @override
  void undo() {
    controller.insertObjectToSlide(slideId, object, index, isExam);
  }
}

class DeleteMultipleObjectsCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final bool isExam;
  final List<MapEntry<int, WorkspaceObject>> objectsWithIndices;

  DeleteMultipleObjectsCommand({
    required this.controller,
    required this.slideId,
    required this.isExam,
    required this.objectsWithIndices,
  });

  @override
  void execute() {
    for (final entry in objectsWithIndices) {
      controller.removeObjectFromSlide(slideId, entry.value.id, isExam);
    }
  }

  @override
  void undo() {
    for (final entry in objectsWithIndices) {
      controller.insertObjectToSlide(slideId, entry.value, entry.key, isExam);
    }
  }
}

class InsertObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final bool isExam;
  final WorkspaceObject object;

  InsertObjectCommand({
    required this.controller,
    required this.slideId,
    required this.isExam,
    required this.object,
  });

  @override
  void execute() {
    controller.insertObjectToSlide(slideId, object, null, isExam);
  }

  @override
  void undo() {
    controller.removeObjectFromSlide(slideId, object.id, isExam);
  }
}

class DuplicateObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final bool isExam;
  final WorkspaceObject original;
  late final WorkspaceObject duplicate;

  DuplicateObjectCommand({
    required this.controller,
    required this.slideId,
    required this.isExam,
    required this.original,
  }) {
    final id = 'picked_${DateTime.now().microsecondsSinceEpoch}';
    if (original is ImageObject) {
      final origPath = (original as ImageObject).localPath;
      String? dupPath;
      if (origPath != null) {
        if (!kIsWeb) {
          final file = File(origPath);
          final parent = file.parent.path;
          dupPath = '$parent/$id.png';
        } else {
          dupPath = id;
        }
      }
      duplicate = (original as ImageObject).copyWith(
        id: id,
        localPath: dupPath ?? id,
        x: ((original as ImageObject).x + 20).clamp(0.0, 1100.0 - (original as ImageObject).width),
        y: ((original as ImageObject).y + 20).clamp(0.0, 825.0 - (original as ImageObject).height),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      duplicate = original;
    }
  }

  @override
  Future<void> execute() async {
    if (original is ImageObject) {
      final origPath = (original as ImageObject).localPath;
      final dupPath = (duplicate as ImageObject).localPath;
      if (origPath != null && dupPath != null) {
        if (!kIsWeb) {
          final file = File(origPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            SlideWorkspaceController.localImageCache[dupPath] = bytes;
            await File(dupPath).writeAsBytes(bytes);
          } else {
            final bytes = SlideWorkspaceController.localImageCache[origPath];
            if (bytes != null) {
              SlideWorkspaceController.localImageCache[dupPath] = bytes;
              await File(dupPath).writeAsBytes(bytes);
            }
          }
        } else {
          final bytes = SlideWorkspaceController.localImageCache[origPath];
          if (bytes != null) {
            SlideWorkspaceController.localImageCache[dupPath] = bytes;
          }
        }
      }
    }
    controller.insertObjectToSlide(slideId, duplicate, null, isExam);
    if (duplicate is ImageObject && (duplicate as ImageObject).state == ImageState.local) {
      controller.triggerUploadForObject(slideId, duplicate as ImageObject, isExam);
    }
  }

  @override
  Future<void> undo() async {
    controller.removeObjectFromSlide(slideId, duplicate.id, isExam);
    if (duplicate is ImageObject) {
      final dupPath = (duplicate as ImageObject).localPath;
      if (dupPath != null) {
        SlideWorkspaceController.localImageCache.remove(dupPath);
        if (!kIsWeb) {
          final file = File(dupPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    }
  }
}

class ArrangeLayerCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final String objectId;
  final bool isExam;
  final int oldZIndex;
  final int newZIndex;

  ArrangeLayerCommand({
    required this.controller,
    required this.slideId,
    required this.objectId,
    required this.isExam,
    required this.oldZIndex,
    required this.newZIndex,
  });

  @override
  void execute() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(zIndex: newZIndex);
      }
      return obj;
    });
  }

  @override
  void undo() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(zIndex: oldZIndex);
      }
      return obj;
    });
  }
}

class LockObjectCommand extends WorkspaceCommand {
  final SlideWorkspaceController controller;
  final String slideId;
  final String objectId;
  final bool isExam;
  final bool oldLocked;
  final bool newLocked;

  LockObjectCommand({
    required this.controller,
    required this.slideId,
    required this.objectId,
    required this.isExam,
    required this.oldLocked,
    required this.newLocked,
  });

  @override
  void execute() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(locked: newLocked);
      }
      return obj;
    });
  }

  @override
  void undo() {
    controller.mutateObject(slideId, objectId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(locked: oldLocked);
      }
      return obj;
    });
  }
}

class SlideWorkspaceController extends ChangeNotifier {
  SlideWorkspaceController({
    required SlideWorkspaceRepository repository,
    required this.stationId,
  }) : _repository = repository;

  final SlideWorkspaceRepository _repository;
  final String? stationId;

  List<WorkspaceSlide> slides = const [];
  int currentIndex = 11;
  WorkspaceTool selectedTool = WorkspaceTool.pan;
  Color selectedColor = const Color(0xFF5B35F5);
  double strokeWidth = 2;
  // Landscape iPad fit: comfortable height with a small, even canvas margin.
  double zoom = .8;
  bool isLoading = true;
  // Session-only study view; intentionally never persisted.
  bool isStudyMode = true;

  String? selectedObjectId;

  void selectObject(String? id) {
    if (selectedObjectId != id) {
      selectedObjectId = id;
      notifyListeners();
    }
  }

  final List<WorkspaceCommand> _undoStack = [];
  final List<WorkspaceCommand> _redoStack = [];

  /// Live ink repaints independently from workspace UI.
  final ValueNotifier<SlideStroke?> activeStroke = ValueNotifier(null);

  bool get hasSlides => slides.isNotEmpty;
  WorkspaceSlide get currentSlide =>
      slides[currentIndex.clamp(0, slides.length - 1)];
  int get totalSlides => slides.length;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();

    final cachedSlides = await _repository.getCachedSlides(stationId);
    if (cachedSlides.isNotEmpty) {
      slides = cachedSlides;
      currentIndex = min(currentIndex, slides.length - 1);
      isLoading = false;
      notifyListeners();
      unawaited(_refreshSlidesInBackground());
      _processPendingUploadTasks();
      return;
    }

    slides = await _repository.getSlides(stationId);
    currentIndex = slides.isEmpty ? 0 : min(currentIndex, slides.length - 1);
    isLoading = false;
    notifyListeners();
    _processPendingUploadTasks();
  }

  Future<void> _refreshSlidesInBackground() async {
    try {
      final freshSlides = await _repository.refreshSlides(stationId);
      if (freshSlides.isEmpty) return;
      final activeSlideId = hasSlides ? currentSlide.id : null;
      
      final mergedSlides = freshSlides.map((fresh) {
        if (_dirtySlideIds.contains(fresh.id)) {
          final localIndex = slides.indexWhere((s) => s.id == fresh.id);
          if (localIndex != -1) {
            return fresh.copyWith(
              strokes: slides[localIndex].strokes,
              examStrokes: slides[localIndex].examStrokes,
            );
          }
        }
        return fresh;
      }).toList();

      slides = mergedSlides;
      if (activeSlideId != null) {
        final refreshedIndex =
            slides.indexWhere((slide) => slide.id == activeSlideId);
        currentIndex = refreshedIndex >= 0
            ? refreshedIndex
            : min(currentIndex, slides.length - 1);
      } else {
        currentIndex = min(currentIndex, slides.length - 1);
      }
      notifyListeners();
    } catch (_) {}
  }

  void selectTool(WorkspaceTool tool) {
    final nextTool = selectedTool == tool ? WorkspaceTool.pan : tool;
    selectedTool = nextTool;
    strokeWidth = switch (nextTool) {
      WorkspaceTool.highlighter => 12,
      WorkspaceTool.eraser => 18,
      _ => 2,
    };
    notifyListeners();
  }

  void setStrokeWidth(double value) {
    strokeWidth = value.clamp(1, 32).toDouble();
    notifyListeners();
  }

  void selectColor(Color color) {
    selectedColor = color;
    notifyListeners();
  }

  void toggleStudyMode() {
    isStudyMode = !isStudyMode;
    notifyListeners();
  }

  void setZoom(double value) {
    zoom = value.clamp(0.1, 5.0);
    notifyListeners();
  }

  void previousSlide() {
    if (slides.isEmpty || currentIndex == 0) return;
    _flushPendingSaves();
    selectedObjectId = null;
    currentIndex--;
    _clearHistory();
    notifyListeners();
  }

  void nextSlide() {
    if (slides.isEmpty || currentIndex >= slides.length - 1) return;
    _flushPendingSaves();
    selectedObjectId = null;
    currentIndex++;
    _clearHistory();
    notifyListeners();
  }

  void goToSlide(int index) {
    if (index < 0 || index >= slides.length) return;
    _flushPendingSaves();
    selectedObjectId = null;
    currentIndex = index;
    _clearHistory();
    notifyListeners();
  }

  Future<void> addSlide({
    required String title,
    required String subtitle,
    required List<WorkspaceQuestion> questions,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
    String? audioPath,
  }) async {
    final id = stationId;
    if (id == null || id.trim().isEmpty) return;
    final slide = await _repository.createSlide(
      stationId: id,
      title: title,
      subtitle: subtitle,
      questions: questions,
      imagePath: imagePath,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      imageContentType: imageContentType,
      audioPath: audioPath,
    );
    slides = [...slides, slide];
    currentIndex = slides.length - 1;
    notifyListeners();
  }

  Future<void> updateSlide({
    required String slideId,
    required String title,
    required String subtitle,
    required List<WorkspaceQuestion> questions,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
    String? audioPath,
  }) async {
    final index = slides.indexWhere((slide) => slide.id == slideId);
    if (index < 0) return;
    final previous = slides[index];
    final updated = await _repository.updateSlide(
      slideId: slideId,
      title: title,
      subtitle: subtitle,
      questions: questions,
      imagePath: imagePath,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      imageContentType: imageContentType,
      audioPath: audioPath,
    );
    final subtitleChanged =
        previous.subtitle.trim().toLowerCase() != subtitle.trim().toLowerCase();
    if (subtitleChanged) {
      final nextSlides = [...slides]..removeAt(index);
      final newKey = subtitle.trim().toLowerCase();
      final destination = nextSlides.lastIndexWhere(
        (slide) => slide.subtitle.trim().toLowerCase() == newKey,
      );
      nextSlides.insert(destination < 0 ? nextSlides.length : destination + 1,
          updated.copyWith(strokes: previous.strokes));
      slides = _renumber(nextSlides);
      currentIndex = slides.indexWhere((slide) => slide.id == slideId);
      await _persistOrder();
    } else {
      slides = [
        for (var i = 0; i < slides.length; i++)
          i == index ? updated.copyWith(strokes: slides[i].strokes) : slides[i],
      ];
    }
    notifyListeners();
  }

  Future<void> duplicateSlideAt(int index) async {
    if (index < 0 || index >= slides.length) return;
    final duplicated = await _repository.duplicateSlide(slides[index]);
    final nextSlides = [...slides]..insert(index + 1, duplicated);
    slides = _renumber(nextSlides);
    currentIndex = index + 1;
    await _persistOrder();
    notifyListeners();
  }

  Future<void> addBlankSlideAfter(int index) async {
    final id = stationId;
    if (id == null || id.trim().isEmpty) return;
    final blank = await _repository.createBlankSlide(stationId: id);
    final insertAt = slides.isEmpty ? 0 : (index + 1).clamp(0, slides.length);
    final nextSlides = [...slides]..insert(insertAt, blank);
    slides = _renumber(nextSlides);
    currentIndex = insertAt;
    await _persistOrder();
    notifyListeners();
  }

  Future<void> deleteSlideAt(int index) async {
    if (index < 0 || index >= slides.length) return;
    final slideId = slides[index].id;
    await _repository.deleteSlide(slideId);
    final nextSlides = [...slides]..removeAt(index);
    slides = _renumber(nextSlides);
    currentIndex = slides.isEmpty ? 0 : min(index, slides.length - 1);
    await _persistOrder();
    _clearHistory();
    notifyListeners();
  }

  Future<void> toggleSlideHidden(int index) async {
    if (index < 0 || index >= slides.length) return;
    final slide = slides[index];
    final updated = await _repository.setSlideHidden(slide.id, !slide.isHidden);
    slides = [
      for (var i = 0; i < slides.length; i++)
        i == index ? updated.copyWith(strokes: slide.strokes) : slides[i],
    ];
    notifyListeners();
  }

  Future<void> moveSlideUp(int index) async {
    if (index <= 0 || index >= slides.length) return;
    final nextSlides = [...slides];
    final slide = nextSlides.removeAt(index);
    nextSlides.insert(index - 1, slide);
    slides = _renumber(nextSlides);
    currentIndex = index - 1;
    await _persistOrder();
    notifyListeners();
  }

  Future<void> moveSlideDown(int index) async {
    if (index < 0 || index >= slides.length - 1) return;
    final nextSlides = [...slides];
    final slide = nextSlides.removeAt(index);
    nextSlides.insert(index + 1, slide);
    slides = _renumber(nextSlides);
    currentIndex = index + 1;
    await _persistOrder();
    notifyListeners();
  }

  void startStroke(Offset point, PointerDeviceKind kind,
      {double pressure = 1}) {
    if (!_isDrawingTool) return;
    activeStroke.value = SlideStroke(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      points: [
        StrokePoint(
            x: point.dx, y: point.dy, pressure: pressure <= 0 ? 1 : pressure)
      ],
      colorValue: _effectiveColor.toARGB32(),
      width: strokeWidth,
      opacity: selectedTool == WorkspaceTool.highlighter ? .25 : 1,
      tool: selectedTool,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void appendStrokePoint(Offset point, double pressure) {
    final stroke = activeStroke.value;
    if (stroke == null) return;
    final last = stroke.points.last;
    final dx = point.dx - last.x;
    final dy = point.dy - last.y;
    final minimumDistance = (stroke.width * .12).clamp(.45, 2.0);
    if (dx * dx + dy * dy < minimumDistance * minimumDistance) return;
    activeStroke.value = stroke.copyWith(
      points: [
        ...stroke.points,
        StrokePoint(
            x: point.dx, y: point.dy, pressure: pressure <= 0 ? 1 : pressure),
      ],
    );
  }

  Future<void> endStroke() async {
    final stroke = activeStroke.value;
    if (stroke == null) return;

    if (stroke.points.isEmpty) {
      activeStroke.value = null;
      return;
    }

    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;

    if (stroke.tool == WorkspaceTool.eraser) {
      activeStroke.value = null;
      final List<MapEntry<int, WorkspaceObject>> toDelete = [];
      for (int i = 0; i < currentStrokes.length; i++) {
        final existing = currentStrokes[i];
        if (existing is SlideStroke && _strokeTouchesEraser(existing, stroke)) {
          toDelete.add(MapEntry(i, existing));
        }
      }
      if (toDelete.isNotEmpty) {
        final command = DeleteMultipleObjectsCommand(
          controller: this,
          slideId: currentSlide.id,
          isExam: isExam,
          objectsWithIndices: toDelete,
        );
        executeCommand(command);
      }
      return;
    }

    final command = InsertObjectCommand(
      controller: this,
      slideId: currentSlide.id,
      isExam: isExam,
      object: stroke,
    );
    executeCommand(command);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeStroke.value?.id == stroke.id) {
        activeStroke.value = null;
      }
    });
  }

  bool _strokeTouchesEraser(SlideStroke stroke, SlideStroke eraser) {
    final radius = eraser.width / 2 + stroke.width / 2 + 4;
    final radiusSquared = radius * radius;
    for (final eraserPoint in eraser.points) {
      for (final point in stroke.points) {
        final dx = eraserPoint.x - point.x;
        final dy = eraserPoint.y - point.y;
        if (dx * dx + dy * dy <= radiusSquared) return true;
      }
    }
    return false;
  }

  void executeCommand(WorkspaceCommand command) {
    final res = command.execute();
    if (res is Future) {
      res.then((_) {
        _undoStack.add(command);
        _redoStack.clear();
        notifyListeners();
        scheduleSave(currentSlide.id);
      });
    } else {
      _undoStack.add(command);
      _redoStack.clear();
      notifyListeners();
      scheduleSave(currentSlide.id);
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final cmd = _undoStack.removeLast();
    cmd.undo();
    _redoStack.add(cmd);
    notifyListeners();
    scheduleSave(currentSlide.id);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final cmd = _redoStack.removeLast();
    cmd.execute();
    _undoStack.add(cmd);
    notifyListeners();
    scheduleSave(currentSlide.id);
  }

  static const double _slideCanvasWidth = 1100.0;
  static const double _slideCanvasHeight = 825.0;

  static final Map<String, Uint8List> localImageCache = {};

  Timer? _saveDebounceTimer;
  final Set<String> _dirtySlideIds = {};

  Future<String> _saveBytesToLocalFile(String tempId, Uint8List bytes) async {
    if (kIsWeb) return tempId;
    final docDir = await getApplicationDocumentsDirectory();
    final uploadsDir = Directory('${docDir.path}/workspace_uploads');
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    final file = File('${uploadsDir.path}/$tempId.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _addPendingUploadTask(String taskId, String slideId, String localPath, String fileName, bool isExam) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('pending_workspace_uploads') ?? [];
    rawList.add(jsonEncode({
      'taskId': taskId,
      'slideId': slideId,
      'localPath': localPath,
      'fileName': fileName,
      'isExam': isExam,
    }));
    await prefs.setStringList('pending_workspace_uploads', rawList);
  }

  Future<void> _removePendingUploadTask(String taskId) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('pending_workspace_uploads') ?? [];
    final updated = rawList.where((raw) {
      final task = jsonDecode(raw) as Map<String, dynamic>;
      return task['taskId'] != taskId;
    }).toList();
    await prefs.setStringList('pending_workspace_uploads', updated);
  }

  Future<void> _processPendingUploadTasks() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList('pending_workspace_uploads') ?? [];
      for (final raw in rawList) {
        try {
          final task = jsonDecode(raw) as Map<String, dynamic>;
          final String taskId = task['taskId'] as String;
          final String slideId = task['slideId'] as String;
          final String localPath = task['localPath'] as String;
          final String fileName = task['fileName'] as String;
          final bool isExam = task['isExam'] as bool;

          final file = File(localPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            localImageCache[localPath] = bytes;
            _uploadImageInBackground(slideId, taskId, localPath, bytes, fileName, isExam);
          } else {
            await _removePendingUploadTask(taskId);
          }
        } catch (e) {
          debugPrint('Error restoring pending upload task: $e');
        }
      }
    } catch (_) {}
  }

  Future<void> _uploadImageInBackground(String slideId, String objectId, String? localPath, Uint8List bytes, String fileName, bool isExam) async {
    try {
      final url = await _repository.uploadWorkspaceImage(bytes, fileName);
      if (url != null) {
        final slideIndex = slides.indexWhere((s) => s.id == slideId);
        if (slideIndex != -1) {
          final slide = slides[slideIndex];
          final objects = isExam ? slide.examStrokes : slide.strokes;
          final updatedObjects = objects.map((obj) {
            if (obj is ImageObject && obj.id == objectId) {
              return obj.copyWith(
                imageUrl: url,
                storagePath: 'student-workspace/$objectId',
                state: ImageState.uploaded,
              );
            }
            return obj;
          }).toList();

          slides[slideIndex] = isExam
              ? slide.copyWith(examStrokes: updatedObjects)
              : slide.copyWith(strokes: updatedObjects);

          if (localPath != null) {
            localImageCache.remove(localPath);
            if (!kIsWeb) {
              final file = File(localPath);
              if (await file.exists()) {
                await file.delete().catchError((_) => file);
              }
            }
          }
          await _removePendingUploadTask(objectId);
          notifyListeners();
          
          await _repository.saveSlideStrokes(
            slideId,
            isExam ? slides[slideIndex].examStrokes : slides[slideIndex].strokes,
            isExamMode: isExam,
          );
        }
      } else {
        _markUploadFailed(slideId, objectId, isExam);
      }
    } catch (e) {
      debugPrint('Background upload error: $e');
      _markUploadFailed(slideId, objectId, isExam);
    }
  }

  void _markUploadFailed(String slideId, String tempId, bool isExam) {
    mutateObject(slideId, tempId, isExam, (obj) {
      if (obj is ImageObject) {
        return obj.copyWith(state: ImageState.uploadFailed);
      }
      return obj;
    });
  }

  void mutateObject(String slideId, String objectId, bool isExam, WorkspaceObject Function(WorkspaceObject) mutator) {
    final slideIndex = slides.indexWhere((s) => s.id == slideId);
    if (slideIndex != -1) {
      final slide = slides[slideIndex];
      final objects = isExam ? slide.examStrokes : slide.strokes;
      final updated = objects.map((obj) => obj.id == objectId ? mutator(obj) : obj).toList();
      slides[slideIndex] = isExam
          ? slide.copyWith(examStrokes: updated)
          : slide.copyWith(strokes: updated);
      notifyListeners();
    }
  }

  void insertObjectToSlide(String slideId, WorkspaceObject object, int? index, bool isExam) {
    final slideIndex = slides.indexWhere((s) => s.id == slideId);
    if (slideIndex != -1) {
      final slide = slides[slideIndex];
      final objects = isExam ? slide.examStrokes : slide.strokes;
      final List<WorkspaceObject> updated;
      if (index != null && index >= 0 && index <= objects.length) {
        updated = List<WorkspaceObject>.from(objects)..insert(index, object);
      } else {
        updated = [...objects, object];
      }
      slides[slideIndex] = isExam
          ? slide.copyWith(examStrokes: updated)
          : slide.copyWith(strokes: updated);
      notifyListeners();
    }
  }

  void removeObjectFromSlide(String slideId, String objectId, bool isExam) {
    final slideIndex = slides.indexWhere((s) => s.id == slideId);
    if (slideIndex != -1) {
      final slide = slides[slideIndex];
      final objects = isExam ? slide.examStrokes : slide.strokes;
      final updated = objects.where((obj) => obj.id != objectId).toList();
      slides[slideIndex] = isExam
          ? slide.copyWith(examStrokes: updated)
          : slide.copyWith(strokes: updated);
      notifyListeners();
    }
  }

  void triggerUploadForObject(String slideId, ImageObject obj, bool isExam) async {
    final tempPath = obj.localPath;
    if (tempPath != null) {
      Uint8List? bytes = localImageCache[tempPath];
      if (bytes == null) {
        final file = File(tempPath);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
          localImageCache[tempPath] = bytes;
        }
      }
      if (bytes != null) {
        await _addPendingUploadTask(obj.id, slideId, tempPath, 'workspace_image_${DateTime.now().millisecondsSinceEpoch}.png', isExam);
        mutateObject(slideId, obj.id, isExam, (o) => (o as ImageObject).copyWith(state: ImageState.uploading));
        _uploadImageInBackground(slideId, obj.id, tempPath, bytes, 'workspace_image_${DateTime.now().millisecondsSinceEpoch}.png', isExam);
      }
    }
  }

  void retryUpload(String slideId, String tempId, bool isExam, String fileName) async {
    final slideIndex = slides.indexWhere((s) => s.id == slideId);
    if (slideIndex == -1) return;
    final slide = slides[slideIndex];
    final objects = isExam ? slide.examStrokes : slide.strokes;
    final objIdx = objects.indexWhere((o) => o.id == tempId);
    if (objIdx == -1) return;
    final obj = objects[objIdx] as ImageObject;
    final tempPath = obj.localPath;
    if (tempPath == null) return;

    Uint8List? bytes = localImageCache[tempPath];
    if (bytes == null) {
      final file = File(tempPath);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
        localImageCache[tempPath] = bytes;
      }
    }
    if (bytes == null) return;

    mutateObject(slideId, tempId, isExam, (o) => (o as ImageObject).copyWith(state: ImageState.uploading));
    _uploadImageInBackground(slideId, tempId, tempPath, bytes, fileName, isExam);
  }

  Future<String?> addImageObject(
    Uint8List bytes,
    String fileName, {
    required double originalWidth,
    required double originalHeight,
  }) async {
    if (bytes.lengthInBytes > 3 * 1024 * 1024) {
      return 'Please choose an image smaller than 3 MB.';
    }

    final isExam = !isStudyMode;
    final tempId = 'picked_${DateTime.now().microsecondsSinceEpoch}';
    final localPath = await _saveBytesToLocalFile(tempId, bytes);
    localImageCache[localPath] = bytes;

    const double maxW = _slideCanvasWidth * 0.35;
    const double maxH = _slideCanvasHeight * 0.35;
    double w = originalWidth > 0 ? originalWidth : 300.0;
    double h = originalHeight > 0 ? originalHeight : 300.0;
    final double aspectRatio = w / h;

    if (w > maxW) {
      w = maxW;
      h = w / aspectRatio;
    }
    if (h > maxH) {
      h = maxH;
      w = h * aspectRatio;
    }

    final double x = (_slideCanvasWidth - w) / 2;
    final double y = (_slideCanvasHeight - h) / 2;

    final imageObj = ImageObject(
      id: tempId,
      localPath: localPath,
      imageUrl: null,
      storagePath: null,
      state: ImageState.local,
      x: x,
      y: y,
      width: w,
      height: h,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final command = InsertObjectCommand(
      controller: this,
      slideId: currentSlide.id,
      isExam: isExam,
      object: imageObj,
    );
    executeCommand(command);

    triggerUploadForObject(currentSlide.id, imageObj, isExam);

    return null;
  }

  void updateWorkspaceObject(WorkspaceObject obj) {
    mutateObject(currentSlide.id, obj.id, !isStudyMode, (_) => obj);
    scheduleSave(currentSlide.id);
  }

  void onInteractionFinished(WorkspaceObject updated) {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final originalIdx = currentStrokes.indexWhere((o) => o.id == updated.id);
    if (originalIdx == -1) return;
    final original = currentStrokes[originalIdx];

    if (original is ImageObject && updated is ImageObject) {
      if (original.x != updated.x || original.y != updated.y || original.width != updated.width || original.height != updated.height) {
        if (original.width != updated.width || original.height != updated.height) {
          final command = ResizeObjectCommand(
            controller: this,
            slideId: currentSlide.id,
            objectId: updated.id,
            isExam: isExam,
            oldX: original.x,
            oldY: original.y,
            oldW: original.width,
            oldH: original.height,
            newX: updated.x,
            newY: updated.y,
            newW: updated.width,
            newH: updated.height,
          );
          executeCommand(command);
        } else {
          final command = MoveObjectCommand(
            controller: this,
            slideId: currentSlide.id,
            objectId: updated.id,
            isExam: isExam,
            oldX: original.x,
            oldY: original.y,
            newX: updated.x,
            newY: updated.y,
          );
          executeCommand(command);
        }
      }
    }
  }

  void bringToFront(String id) {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final objIdx = currentStrokes.indexWhere((o) => o.id == id);
    if (objIdx == -1) return;
    final obj = currentStrokes[objIdx];
    if (obj is! ImageObject) return;

    var maxZ = 0;
    for (final o in currentStrokes) {
      if (o is ImageObject && o.zIndex > maxZ) {
        maxZ = o.zIndex;
      }
    }

    final command = ArrangeLayerCommand(
      controller: this,
      slideId: currentSlide.id,
      objectId: id,
      isExam: isExam,
      oldZIndex: obj.zIndex,
      newZIndex: maxZ + 1,
    );
    executeCommand(command);
  }

  void sendToBack(String id) {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final objIdx = currentStrokes.indexWhere((o) => o.id == id);
    if (objIdx == -1) return;
    final obj = currentStrokes[objIdx];
    if (obj is! ImageObject) return;

    var minZ = 0;
    for (final o in currentStrokes) {
      if (o is ImageObject && o.zIndex < minZ) {
        minZ = o.zIndex;
      }
    }

    final command = ArrangeLayerCommand(
      controller: this,
      slideId: currentSlide.id,
      objectId: id,
      isExam: isExam,
      oldZIndex: obj.zIndex,
      newZIndex: minZ - 1,
    );
    executeCommand(command);
  }

  void lockWorkspaceObject(String id, bool locked) {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final objIdx = currentStrokes.indexWhere((o) => o.id == id);
    if (objIdx == -1) return;
    final obj = currentStrokes[objIdx];
    if (obj is! ImageObject) return;

    final command = LockObjectCommand(
      controller: this,
      slideId: currentSlide.id,
      objectId: id,
      isExam: isExam,
      oldLocked: obj.locked,
      newLocked: locked,
    );
    executeCommand(command);
  }

  void duplicateWorkspaceObject(String id) {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final objIdx = currentStrokes.indexWhere((o) => o.id == id);
    if (objIdx == -1) return;
    final obj = currentStrokes[objIdx];

    final command = DuplicateObjectCommand(
      controller: this,
      slideId: currentSlide.id,
      isExam: isExam,
      original: obj,
    );
    executeCommand(command);
  }

  void deleteWorkspaceObject(String id) async {
    final isExam = !isStudyMode;
    final currentStrokes = isExam ? currentSlide.examStrokes : currentSlide.strokes;
    final objIdx = currentStrokes.indexWhere((o) => o.id == id);
    if (objIdx == -1) return;
    final obj = currentStrokes[objIdx];

    final command = DeleteObjectCommand(
      controller: this,
      slideId: currentSlide.id,
      isExam: isExam,
      object: obj,
      index: objIdx,
    );
    executeCommand(command);

    if (obj is ImageObject) {
      final url = obj.imageUrl;
      if (url != null) {
        try {
          await _repository.deleteWorkspaceImage(url);
        } catch (e) {
          debugPrint('Error deleting workspace image from storage: $e');
        }
      }
      final tempId = obj.localPath;
      if (tempId != null) {
        localImageCache.remove(tempId);
      }
    }
  }

  void scheduleSave(String slideId) {
    _dirtySlideIds.add(slideId);
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), () {
      _flushPendingSaves();
    });
  }

  Future<void> flushPendingSaves() async {
    await _flushPendingSaves();
  }

  Future<void> _flushPendingSaves() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_dirtySlideIds.isEmpty) return;

    final idsToSave = Set<String>.from(_dirtySlideIds);
    _dirtySlideIds.clear();

    final isExam = !isStudyMode;
    for (final slideId in idsToSave) {
      final slideIdx = slides.indexWhere((s) => s.id == slideId);
      if (slideIdx != -1) {
        final slide = slides[slideIdx];
        await _repository.saveSlideStrokes(
          slide.id,
          isExam ? slide.examStrokes : slide.strokes,
          isExamMode: isExam,
        );
      }
    }
  }

  bool get _isDrawingTool =>
      selectedTool == WorkspaceTool.pen ||
      selectedTool == WorkspaceTool.highlighter ||
      selectedTool == WorkspaceTool.eraser;

  Color get _effectiveColor =>
      selectedTool == WorkspaceTool.eraser ? Colors.white : selectedColor;

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    activeStroke.value = null;
  }

  List<WorkspaceSlide> _renumber(List<WorkspaceSlide> value) => [
        for (var i = 0; i < value.length; i++) value[i].copyWith(index: i + 1),
      ];

  Future<void> _persistOrder() async {
    final id = stationId;
    if (id == null || id.trim().isEmpty || slides.isEmpty) return;
    await _repository.reorderSlides(id, slides);
  }

  @override
  void dispose() {
    _flushPendingSaves();
    activeStroke.dispose();
    super.dispose();
  }

}
