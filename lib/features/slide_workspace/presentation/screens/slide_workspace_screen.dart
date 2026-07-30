import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../../core/providers/app_provider.dart';
import '../../data/slide_workspace_repository.dart';
import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import '../widgets/slide_workspace_chrome.dart';
import '../widgets/workspace_state_provider.dart';
import '../widgets/workspace_top_toolbar.dart';
import '../widgets/slide_editor_dialog.dart';
import '../widgets/desktop_workspace.dart';
import '../widgets/mobile_workspace.dart';

class SlideWorkspaceScreen extends StatefulWidget {
  final String stationName;
  final String? stationDbId;

  const SlideWorkspaceScreen({
    super.key,
    required this.stationName,
    this.stationDbId,
  });

  @override
  State<SlideWorkspaceScreen> createState() => _SlideWorkspaceScreenState();
}

class _SlideWorkspaceScreenState extends State<SlideWorkspaceScreen> with WidgetsBindingObserver {
  late final SlideWorkspaceController controller;

  // --- Outside Recording State ---
  String? _activeRecordingSlideId;
  AudioRecorder? _outsideRecorder;
  Timer? _outsideRecordTimer;
  final Stopwatch _outsideStopwatch = Stopwatch();
  Duration _outsideRecordDuration = Duration.zero;
  bool _isOutsideRecording = false;
  bool _isOutsidePaused = false;

  // --- In-place Editing State ---
  int? _editingSlideIndex;
  final List<TextEditingController> _inPlacePromptControllers = [];
  final List<TextEditingController> _inPlaceAnswerControllers = [];

  Future<void> _startOutsideRecording(WorkspaceSlide slide) async {
    if (_isOutsideRecording) {
      await _cancelOutsideRecording();
    }

    _outsideRecorder ??= AudioRecorder();
    final hasPermission = await _outsideRecorder!.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'يرجى السماح باستخدام الميكروفون للتسجيل',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
      return;
    }

    final outputPath = '${Directory.systemTemp.path}/slide_voice_outside_${slide.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _outsideRecorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
        autoGain: true,
      ),
      path: outputPath,
    );

    _outsideStopwatch.reset();
    _outsideStopwatch.start();
    setState(() {
      _activeRecordingSlideId = slide.id;
      _isOutsideRecording = true;
      _isOutsidePaused = false;
      _outsideRecordDuration = Duration.zero;
    });

    _outsideRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _outsideRecordDuration = _outsideStopwatch.elapsed;
      });
    });
  }

  Future<void> _pauseResumeOutsideRecording() async {
    if (_outsideRecorder == null || !_isOutsideRecording) return;
    if (_isOutsidePaused) {
      await _outsideRecorder!.resume();
      _outsideStopwatch.start();
    } else {
      await _outsideRecorder!.pause();
      _outsideStopwatch.stop();
    }
    setState(() {
      _isOutsidePaused = !_isOutsidePaused;
    });
  }

  Future<void> _stopOutsideRecording(WorkspaceSlide slide) async {
    if (_outsideRecorder == null || !_isOutsideRecording) return;
    final path = await _outsideRecorder!.stop();
    _outsideRecordTimer?.cancel();
    _outsideStopwatch.stop();

    setState(() {
      _isOutsideRecording = false;
      _isOutsidePaused = false;
      _activeRecordingSlideId = null;
    });

    if (path != null) {
      try {
        await controller.updateSlide(
          slideId: slide.id,
          title: slide.title,
          subtitle: slide.subtitle,
          questions: slide.questions,
          audioPath: path,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ التسجيل بنجاح', style: TextStyle(fontFamily: 'Cairo'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل حفظ التسجيل. يرجى المحاولة مرة أخرى.', style: TextStyle(fontFamily: 'Cairo'))),
          );
        }
      }
    }
  }

  Future<void> _cancelOutsideRecording() async {
    if (_outsideRecorder == null || !_isOutsideRecording) return;
    await _outsideRecorder!.stop();
    _outsideRecordTimer?.cancel();
    _outsideStopwatch.stop();
    setState(() {
      _isOutsideRecording = false;
      _isOutsidePaused = false;
      _activeRecordingSlideId = null;
    });
  }

  void _startInPlaceEdit(int index) {
    if (!mounted || index < 0 || index >= controller.slides.length) return;
    
    if (_editingSlideIndex != null) {
      if (_editingSlideIndex == index) return;
      _saveInPlaceEdit(_editingSlideIndex!);
    }

    final slide = controller.slides[index];
    
    for (var c in _inPlacePromptControllers) {
      c.dispose();
    }
    _inPlacePromptControllers.clear();
    for (var c in _inPlaceAnswerControllers) {
      c.dispose();
    }
    _inPlaceAnswerControllers.clear();

    for (final q in slide.questions) {
      _inPlacePromptControllers.add(TextEditingController(text: q.prompt));
      _inPlaceAnswerControllers.add(TextEditingController(text: q.answer));
    }

    setState(() {
      _editingSlideIndex = index;
    });
  }

  Future<void> _saveInPlaceEdit(int index) async {
    if (index < 0 || index >= controller.slides.length) return;
    final slide = controller.slides[index];

    final updatedQuestions = <WorkspaceQuestion>[];
    for (var i = 0; i < _inPlacePromptControllers.length; i++) {
      final prompt = _inPlacePromptControllers[i].text.trim();
      final answer = _inPlaceAnswerControllers[i].text.trim();
      if (prompt.isNotEmpty) {
        updatedQuestions.add(WorkspaceQuestion(prompt: prompt, answer: answer));
      }
    }

    bool hasChanged = updatedQuestions.length != slide.questions.length;
    if (!hasChanged) {
      for (var i = 0; i < updatedQuestions.length; i++) {
        if (updatedQuestions[i].prompt != slide.questions[i].prompt ||
            updatedQuestions[i].answer != slide.questions[i].answer) {
          hasChanged = true;
          break;
        }
      }
    }

    if (hasChanged) {
      try {
        await controller.updateSlide(
          slideId: slide.id,
          title: slide.title,
          subtitle: slide.subtitle,
          questions: updatedQuestions,
        );
      } catch (e) {
        debugPrint('Error saving in-place edit: $e');
      }
    }

    if (_editingSlideIndex == index) {
      for (var c in _inPlacePromptControllers) {
        c.dispose();
      }
      _inPlacePromptControllers.clear();
      for (var c in _inPlaceAnswerControllers) {
        c.dispose();
      }
      _inPlaceAnswerControllers.clear();

      setState(() {
        _editingSlideIndex = null;
      });
    }
  }

  Future<bool> _handleBack() async {
    if (_editingSlideIndex != null) {
      await _saveInPlaceEdit(_editingSlideIndex!);
    }
    if (_isOutsideRecording) {
      await _cancelOutsideRecording();
    }
    await _allowScreenshot();
    return true;
  }

  void _setZoom(double value) {
    controller.setZoom(value.clamp(0.5, 2.5));
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
  void initState() {
    super.initState();
    _preventScreenshot();
    WidgetsBinding.instance.addObserver(this);
    controller = SlideWorkspaceController(
      repository: SupabaseSlideWorkspaceRepository(),
      stationId: widget.stationDbId,
    );

    // Defer loading to prevent blocking the transition animation!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        if (route.animation!.isCompleted) {
          controller.load();
        } else {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              route.animation!.removeStatusListener(listener);
              controller.load();
            }
          }
          route.animation!.addStatusListener(listener);
        }
      } else {
        controller.load();
      }
    });
  }

  @override
  void dispose() {
    _allowScreenshot();
    WidgetsBinding.instance.removeObserver(this);
    if (_isOutsideRecording) {
      _outsideRecorder?.stop();
    }
    _outsideRecordTimer?.cancel();
    _outsideRecorder?.dispose();
    for (var c in _inPlacePromptControllers) {
      c.dispose();
    }
    for (var c in _inPlaceAnswerControllers) {
      c.dispose();
    }
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      controller.flushPendingSaves();
    }
  }

  Future<void> _showSlideEditorDialog({WorkspaceSlide? slide}) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;

    final result = await showDialog<SlideEditorResult>(
      context: context,
      builder: (dialogContext) => SlideEditorDialog(
        slide: slide,
        currentSlides: controller.slides,
        isDark: isDark,
      ),
    );

    if (result == null || !mounted) return;

    try {
      if (slide != null) {
        await controller.updateSlide(
          slideId: slide.id,
          title: result.title,
          subtitle: result.subtitle,
          questions: result.questions,
          imagePath: result.imagePath,
          imageBytes: result.imageBytes,
          imageFileName: result.imageFileName,
          imageContentType: result.imageContentType,
          audioPath: result.audioPath,
        );
      } else {
        await controller.addSlide(
          title: result.title,
          subtitle: result.subtitle,
          questions: result.questions,
          imagePath: result.imagePath,
          imageBytes: result.imageBytes,
          imageFileName: result.imageFileName,
          imageContentType: result.imageContentType,
          audioPath: result.audioPath,
        );
      }
    } catch (e, s) {
      debugPrint('Error updating/adding slide: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save the slide. Please try again.')),
        );
      }
    }
  }

  Future<void> _confirmDeleteSlide(int index) async {
    if (index < 0 || index >= controller.slides.length) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete slide?'),
        content: const Text('This slide will no longer be shown.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.deleteSlideAt(index);
    } catch (e, s) {
      debugPrint('Error deleting slide: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete the slide. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceOutsideStateProvider(
      activeRecordingSlideId: _activeRecordingSlideId,
      isOutsideRecording: _isOutsideRecording,
      isOutsidePaused: _isOutsidePaused,
      outsideRecordDuration: _outsideRecordDuration,
      editingSlideIndex: _editingSlideIndex,
      inPlacePromptControllers: _inPlacePromptControllers,
      inPlaceAnswerControllers: _inPlaceAnswerControllers,
      startRecording: _startOutsideRecording,
      pauseResumeRecording: _pauseResumeOutsideRecording,
      stopRecording: _stopOutsideRecording,
      cancelRecording: _cancelOutsideRecording,
      startInPlaceEdit: _startInPlaceEdit,
      saveInPlaceEdit: _saveInPlaceEdit,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await _handleBack();
          if (shouldPop && mounted) {
            Navigator.pop(context);
          }
        },
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.isLoading) {
                return const Scaffold(
                  backgroundColor: Color(0xFFF8F7FC),
                  body: Center(
                    child: CircularProgressIndicator(color: workspacePurple),
                  ),
                );
              }

              final provider = Provider.of<AppProvider>(context);
              final canManageSlides = provider.isAdminOrOwner;
              final isDark = provider.isDarkTheme;
              final width = MediaQuery.of(context).size.width;
              final compact = width < 760;
              final tablet = width >= 760 && width < 1100;

              return Scaffold(
                backgroundColor: isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
                body: SafeArea(
                  child: Column(
                    children: [
                      WorkspaceTopToolbar(
                        controller: controller,
                        stationName: widget.stationName,
                        compact: compact,
                        isDark: isDark,
                        showBrand: true,
                        showAddSlideButton: true,
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
                        onAddSlide: canManageSlides ? () => _showSlideEditorDialog() : null,
                      ),
                      if (!controller.hasSlides)
                        Expanded(
                          child: _EmptySlidesState(
                            canManageSlides: canManageSlides,
                            onAddSlide: () => _showSlideEditorDialog(),
                          ),
                        )
                      else
                        Expanded(
                          child: compact
                              ? MobileWorkspace(
                                  controller: controller,
                                  canManageSlides: canManageSlides,
                                  isDark: isDark,
                                  zoomScale: controller.zoom,
                                  onEditSlide: (index) => _showSlideEditorDialog(
                                    slide: controller.slides[index],
                                  ),
                                  onDeleteSlide: _confirmDeleteSlide,
                                )
                              : DesktopWorkspace(
                                  controller: controller,
                                  showSidebar: !tablet,
                                  canManageSlides: canManageSlides,
                                  isDark: isDark,
                                  zoomScale: controller.zoom,
                                  onZoomChanged: _setZoom,
                                  onBack: () async {
                                    if (await _handleBack()) {
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    }
                                  },
                                  onAddSlide: canManageSlides ? () => _showSlideEditorDialog() : null,
                                  onEditSlide: (index) => _showSlideEditorDialog(
                                    slide: controller.slides[index],
                                  ),
                                  onDeleteSlide: _confirmDeleteSlide,
                                ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptySlidesState extends StatelessWidget {
  final bool canManageSlides;
  final VoidCallback onAddSlide;

  const _EmptySlidesState({
    required this.canManageSlides,
    required this.onAddSlide,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.slideshow_outlined, color: workspacePurple, size: 56),
          const SizedBox(height: 14),
          const Text(
            'No real slides yet',
            style: TextStyle(
              color: workspaceInk,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canManageSlides
                ? 'Add the first slide for this station.'
                : 'Slides will appear here after an admin adds them.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: workspaceMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (canManageSlides) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAddSlide,
              icon: const Icon(Icons.add),
              label: const Text('Add Slide'),
            ),
          ],
        ],
      ),
    );
  }
}
