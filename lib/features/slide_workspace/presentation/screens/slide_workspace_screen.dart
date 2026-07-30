import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'slide_image_crop_screen.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/image_cache_service.dart';
import '../../data/slide_workspace_repository.dart';
import '../../domain/entities/slide_workspace_models.dart';
import '../controllers/slide_workspace_controller.dart';
import '../widgets/slide_workspace_chrome.dart';
import '../widgets/stagiaire_slide_painters.dart';
import '../../../practice/presentation/widgets/audio_explanation_player.dart';

// Platform-native landscape canvas: retains the established width while
// permanently reducing page height to the comfortable former 80% view.
const _slideCanvasWidth = 1100.0;
const _slideCanvasHeight = 608.0;

class _WorkspaceOutsideStateProvider extends InheritedWidget {
  final String? activeRecordingSlideId;
  final bool isOutsideRecording;
  final bool isOutsidePaused;
  final Duration outsideRecordDuration;
  final int? editingSlideIndex;
  final List<TextEditingController> inPlacePromptControllers;
  final List<TextEditingController> inPlaceAnswerControllers;

  final Function(WorkspaceSlide slide) startRecording;
  final VoidCallback pauseResumeRecording;
  final Function(WorkspaceSlide slide) stopRecording;
  final VoidCallback cancelRecording;

  final Function(int index) startInPlaceEdit;
  final Function(int index) saveInPlaceEdit;

  const _WorkspaceOutsideStateProvider({
    required this.activeRecordingSlideId,
    required this.isOutsideRecording,
    required this.isOutsidePaused,
    required this.outsideRecordDuration,
    required this.editingSlideIndex,
    required this.inPlacePromptControllers,
    required this.inPlaceAnswerControllers,
    required this.startRecording,
    required this.pauseResumeRecording,
    required this.stopRecording,
    required this.cancelRecording,
    required this.startInPlaceEdit,
    required this.saveInPlaceEdit,
    required Widget child,
  }) : super(child: child);

  static _WorkspaceOutsideStateProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_WorkspaceOutsideStateProvider>();
  }

  @override
  bool updateShouldNotify(_WorkspaceOutsideStateProvider oldWidget) {
    return activeRecordingSlideId != oldWidget.activeRecordingSlideId ||
        isOutsideRecording != oldWidget.isOutsideRecording ||
        isOutsidePaused != oldWidget.isOutsidePaused ||
        outsideRecordDuration != oldWidget.outsideRecordDuration ||
        editingSlideIndex != oldWidget.editingSlideIndex ||
        inPlacePromptControllers != oldWidget.inPlacePromptControllers ||
        inPlaceAnswerControllers != oldWidget.inPlaceAnswerControllers;
  }
}

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
            content: Text('يرجى السماح باستخدام الميكروفون للتسجيل',
                style: TextStyle(fontFamily: 'Cairo')),
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
    final titleController = TextEditingController(text: slide?.title ?? '');
    final subtitleController =
        TextEditingController(text: slide?.subtitle ?? '');

    // قوائم الأسئلة المتعددة
    final List<TextEditingController> promptControllers = [];
    final List<TextEditingController> answerControllers = [];

    if (slide != null && slide.questions.isNotEmpty) {
      for (var q in slide.questions) {
        promptControllers.add(TextEditingController(text: q.prompt));
        answerControllers.add(TextEditingController(text: q.answer));
      }
    } else {
      // سؤال افتراضي واحد عند الإضافة
      promptControllers.add(TextEditingController());
      answerControllers.add(TextEditingController());
    }

    String? imagePath;
    Uint8List? imageBytes;
    String? imageFileName;
    String? imageContentType;
    String? audioPath;
    final isEditing = slide != null;
    final subtitleOptions = <String>[];
    final seenSubtitles = <String>{};
    for (final item in controller.slides) {
      final subtitle = item.subtitle.trim();
      final key = subtitle.toLowerCase();
      if (subtitle.isNotEmpty && seenSubtitles.add(key)) {
        subtitleOptions.add(subtitle);
      }
    }
    const newSubtitleChoice = '__new_subtitle__';
    final initialSubtitle = subtitleController.text.trim();
    var selectedSubtitle = subtitleOptions.firstWhere(
      (item) => item.toLowerCase() == initialSubtitle.toLowerCase(),
      orElse: () => newSubtitleChoice,
    );
    final dialogRecorder = AudioRecorder();
    Timer? recordTimer;
    Stopwatch stopwatch = Stopwatch();
    Duration recordDuration = Duration.zero;
    bool isRecording = false;
    bool isPaused = false;

    String formatDuration(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    try {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(isEditing ? 'Edit slide' : 'Add slide'),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Title')),
                  if (subtitleOptions.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: selectedSubtitle,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Subtitle'),
                      items: [
                        for (final subtitle in subtitleOptions)
                          DropdownMenuItem(
                            value: subtitle,
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const DropdownMenuItem(
                          value: newSubtitleChoice,
                          child: Text('New subtitle'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedSubtitle = value;
                          if (value == newSubtitleChoice) {
                            subtitleController.clear();
                          } else {
                            subtitleController.text = value;
                          }
                        });
                      },
                    ),
                  if (subtitleOptions.isEmpty ||
                      selectedSubtitle == newSubtitleChoice)
                    TextField(
                        controller: subtitleController,
                        decoration:
                            const InputDecoration(labelText: 'Subtitle')),

                  // قائمة الأسئلة الديناميكية
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Questions & Answers',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => setDialogState(() {
                          promptControllers.add(TextEditingController());
                          answerControllers.add(TextEditingController());
                        }),
                        icon: const Icon(Icons.add),
                        tooltip: 'Add Question',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: promptControllers.length,
                    itemBuilder: (ctx, idx) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text('Question ${idx + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const Spacer(),
                                if (promptControllers.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () {
                                      setDialogState(() {
                                        promptControllers.removeAt(idx);
                                        answerControllers.removeAt(idx);
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: promptControllers[idx],
                              decoration: const InputDecoration(
                                labelText: 'Question',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              minLines: 2,
                              maxLines: 4,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: answerControllers[idx],
                              decoration: const InputDecoration(
                                labelText: 'Answer',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              minLines: 2,
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() {
                      promptControllers.add(TextEditingController());
                      answerControllers.add(TextEditingController());
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Question'),
                  ),

                  if ((audioPath != null && audioPath != 'clear_audio') ||
                      (audioPath == null && slide?.audioUrl.isNotEmpty == true)) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.audiotrack, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              audioPath == null
                                  ? 'Existing audio file'
                                  : audioPath!.split(RegExp(r'[\\/]+')).last,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setDialogState(() {
                                audioPath = 'clear_audio';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.image_outlined),
                          label: Text(
                            imageFileName ??
                                (slide?.imageAsset.isNotEmpty == true
                                    ? 'Replace image'
                                    : 'Add image'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            final file = picked?.files.single;
                            if (file == null) return;
                            setDialogState(() {
                              imagePath = kIsWeb ? null : file.path;
                              imageBytes = file.bytes;
                              imageFileName = file.name;
                              imageContentType = file.extension == null
                                  ? null
                                  : 'image/${file.extension}';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isRecording) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.circle, color: Colors.red, size: 10),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Rec: ${formatDuration(recordDuration)}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(
                                        isPaused ? Icons.play_arrow : Icons.pause,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        if (isPaused) {
                                          await dialogRecorder.resume();
                                          stopwatch.start();
                                        } else {
                                          await dialogRecorder.pause();
                                          stopwatch.stop();
                                        }
                                        setDialogState(() {
                                          isPaused = !isPaused;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.stop,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        final path = await dialogRecorder.stop();
                                        recordTimer?.cancel();
                                        stopwatch.stop();
                                        setDialogState(() {
                                          isRecording = false;
                                          isPaused = false;
                                          if (path != null) {
                                            audioPath = path;
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.upload_file, size: 16),
                                      label: const Text('File', style: TextStyle(fontSize: 11)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                      onPressed: () async {
                                        final picked = await FilePicker.platform.pickFiles(
                                          type: FileType.audio,
                                          withData: true,
                                        );
                                        final file = picked?.files.single;
                                        if (file == null) return;
                                        if (kIsWeb) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    "Voice upload isn't available in the web preview — use the Android or desktop app."),
                                              ),
                                            );
                                          }
                                          return;
                                        }
                                        if (file.path == null) return;
                                        setDialogState(() => audioPath = file.path);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.mic, size: 16),
                                      label: const Text('Rec', style: TextStyle(fontSize: 11)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                      onPressed: () async {
                                        final hasPermission = await dialogRecorder.hasPermission();
                                        if (!hasPermission) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('يرجى السماح باستخدام الميكروفون للتسجيل',
                                                    style: TextStyle(fontFamily: 'Cairo')),
                                              ),
                                            );
                                          }
                                          return;
                                        }
                                        final outputPath = '${Directory.systemTemp.path}/slide_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
                                        await dialogRecorder.start(
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
                                        stopwatch.reset();
                                        stopwatch.start();
                                        setDialogState(() {
                                          isRecording = true;
                                          isPaused = false;
                                          recordDuration = Duration.zero;
                                        });
                                        recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                                          setDialogState(() {
                                            recordDuration = stopwatch.elapsed;
                                          });
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save')),
            ],
          ),
        ),
      );
      if (shouldSave != true || !mounted) return;
      final title = titleController.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Slide title is required.')));
        return;
      }

      // جمع الأسئلة من جميع المتحكمات
      final questions = <WorkspaceQuestion>[];
      for (var i = 0; i < promptControllers.length; i++) {
        final prompt = promptControllers[i].text.trim();
        final answer = answerControllers[i].text.trim();
        if (prompt.isNotEmpty) {
          questions.add(WorkspaceQuestion(prompt: prompt, answer: answer));
        }
      }

      if (isEditing) {
        await controller.updateSlide(
            slideId: slide.id,
            title: title,
            subtitle: subtitleController.text.trim(),
            questions: questions,
            imagePath: imagePath,
            imageBytes: imageBytes,
            imageFileName: imageFileName,
            imageContentType: imageContentType,
            audioPath: audioPath);
      } else {
        await controller.addSlide(
            title: title,
            subtitle: subtitleController.text.trim(),
            questions: questions,
            imagePath: imagePath,
            imageBytes: imageBytes,
            imageFileName: imageFileName,
            imageContentType: imageContentType,
            audioPath: audioPath);
      }
    } catch (e, s) {
      debugPrint('Error updating slide: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to save the slide. Please try again.')));
      }
    } finally {
      if (isRecording) {
        try {
          await dialogRecorder.stop();
        } catch (_) {}
      }
      recordTimer?.cancel();
      dialogRecorder.dispose();
      titleController.dispose();
      subtitleController.dispose();
      for (var c in promptControllers) {
        c.dispose();
      }
      for (var c in answerControllers) {
        c.dispose();
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
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.deleteSlideAt(index);
    } catch (e, s) {
      debugPrint('Error deleting slide: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to delete the slide. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WorkspaceOutsideStateProvider(
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
      child: WillPopScope(
        onWillPop: _handleBack,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.isLoading) {
                return const Scaffold(
                  backgroundColor: Color(0xFFF8F7FC),
                  body: Center(
                      child: CircularProgressIndicator(color: workspacePurple)),
                );
              }

              final provider = Provider.of<AppProvider>(context);
              final canManageSlides = provider.isAdminOrOwner;
              final isDark = provider.isDarkTheme;
              final width = MediaQuery.of(context).size.width;
              final compact = width < 760;
              final tablet = width >= 760 && width < 1100;

              return Scaffold(
                backgroundColor:
                    isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
                body: SafeArea(
                  child: Column(
                    children: [
                      _TopToolbar(
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
                        onAddSlide:
                            canManageSlides ? () => _showSlideEditorDialog() : null,
                      ),
                      if (!controller.hasSlides)
                        Expanded(
                            child: _EmptySlidesState(
                                canManageSlides: canManageSlides,
                                onAddSlide: () => _showSlideEditorDialog()))
                      else
                        Expanded(
                          child: compact
                              ? _MobileWorkspace(
                                  controller: controller,
                                  canManageSlides: canManageSlides,
                                  isDark: isDark,
                                  zoomScale: controller.zoom,
                                  onEditSlide: (index) => _showSlideEditorDialog(
                                      slide: controller.slides[index]),
                                  onDeleteSlide: _confirmDeleteSlide)
                              : _DesktopWorkspace(
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
                                  onAddSlide: canManageSlides
                                      ? () => _showSlideEditorDialog()
                                      : null,
                                  onEditSlide: (index) => _showSlideEditorDialog(
                                      slide: controller.slides[index]),
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

  const _EmptySlidesState(
      {required this.canManageSlides, required this.onAddSlide});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.slideshow_outlined,
              color: workspacePurple, size: 56),
          const SizedBox(height: 14),
          const Text('No real slides yet',
              style: TextStyle(
                  color: workspaceInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            canManageSlides
                ? 'Add the first slide for this station.'
                : 'Slides will appear here after an admin adds them.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: workspaceMuted, fontWeight: FontWeight.w600),
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

void _animateToSlide({
  required TransformationController transformationController,
  required int index,
  required bool compact,
  required bool fillWidth,
  required bool canManageSlides,
  required List<WorkspaceSlide> slides,
  required BuildContext context,
  bool sidebarOpen = false,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final viewportHeight = renderBox.size.height;
    
    final totalWidth = renderBox.size.width;
    final pageWidth = ((sidebarOpen ? (totalWidth - 216.0) : totalWidth) - 20.0).clamp(280.0, double.infinity);
    final pageHeight = pageWidth * _slideCanvasHeight / _slideCanvasWidth;
    final controlsHeight = canManageSlides ? 33.0 : 0.0;
    final pageExtent = pageHeight + controlsHeight;
    final spacing = compact ? 2.0 : 3.0;
    const topPadding = 10.0;
    final headersBefore = [
      for (var i = 0; i <= index && i < slides.length; i++)
        if (i == 0 ||
            _subtitleKey(slides[i].subtitle) !=
                _subtitleKey(slides[i - 1].subtitle))
          i,
    ].length;
    final headerExtent = headersBefore * (compact ? 50.0 : 64.0);
    final top = topPadding + headerExtent + index * (pageExtent + spacing);
    
    final currentScale = transformationController.value.getMaxScaleOnAxis();
    final targetY = -(top * currentScale) + (viewportHeight - (pageExtent * currentScale)) / 2;
    
    // We can't easily animate Matrix4 without an AnimationController passed in,
    // so we just jump for now to avoid boilerplate, or we can use a Tween locally.
    // For simplicity, we just jump to the new translation.
    final matrix = transformationController.value.clone();
    
    // Center horizontally: when zoomed in the scaled content is wider than
    // the viewport, so we compute the correct offset.  We must NOT clamp to
    // negative-only values – that would prevent reaching the left side of the
    // canvas when the content is centred and overflows to the left.
    matrix.setTranslationRaw(0.0, targetY.clamp(-double.infinity, 0.0), 0);
    transformationController.value = matrix;
  });
}

class _DesktopWorkspace extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool showSidebar;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onBack;
  final VoidCallback? onAddSlide;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;

  const _DesktopWorkspace({
    required this.controller,
    required this.showSidebar,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onZoomChanged,
    required this.onBack,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onAddSlide,
  });

  @override
  State<_DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<_DesktopWorkspace> {
  bool _sidebarOpen = true;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.value = Matrix4.identity()
      ..scale(widget.zoomScale, widget.zoomScale, 1.0);
  }

  @override
  void didUpdateWidget(covariant _DesktopWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomScale != widget.zoomScale) {
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      if ((currentScale - widget.zoomScale).abs() > 0.01) {
        if (widget.zoomScale <= 1.0) {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY.clamp(-double.infinity, 0.0));
        } else {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY)
            ..scale(widget.zoomScale, widget.zoomScale, 1.0);
        }
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _goToSlide(int index) {
    final stateProvider = _WorkspaceOutsideStateProvider.of(context);
    if (stateProvider != null && stateProvider.editingSlideIndex != null && stateProvider.editingSlideIndex != index) {
      stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
    }
    widget.controller.goToSlide(index);
    _animateToSlide(
      transformationController: _transformationController,
      index: index,
      compact: false,
      fillWidth: true,
      canManageSlides: widget.canManageSlides,
      slides: widget.controller.slides,
      context: context,
      sidebarOpen: _sidebarOpen,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showSidebar) {
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _sidebarOpen ? 216 : 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 216,
                maxWidth: 216,
                child: _ThumbnailSidebar(
                  controller: widget.controller,
                  onAddSlide: widget.onAddSlide,
                  onBrandTap: widget.onBack,
                  onSlideTap: _goToSlide,
                  isDark: widget.isDark,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _SlidePagesList(
                  controller: widget.controller,
                  compact: false,
                  canManageSlides: widget.canManageSlides,
                  isDark: widget.isDark,
                  transformationController: _transformationController,
                  fillWidth: true,
                  onEditSlide: widget.onEditSlide,
                  onDeleteSlide: widget.onDeleteSlide,
                  onSlideTap: _goToSlide,
                ),
                Positioned(
                  left: 0,
                  top: 16,
                  child: _SidebarHandle(
                    isOpen: _sidebarOpen,
                    isDark: widget.isDark,
                    onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _CollapsibleSlideWorkspace(
      controller: widget.controller,
      compact: false,
      canManageSlides: widget.canManageSlides,
      isDark: widget.isDark,
      zoomScale: widget.zoomScale,
      onEditSlide: widget.onEditSlide,
      onDeleteSlide: widget.onDeleteSlide,
    );
  }
}

class _SidebarHandle extends StatelessWidget {
  final bool isOpen;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarHandle({
    required this.isOpen,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF2A2540) : Colors.white,
      elevation: 6,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 54,
          child: Icon(
            isOpen ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: isDark ? Colors.white : workspacePurple,
          ),
        ),
      ),
    );
  }
}

class _ToolbarCapsule extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;

  const _ToolbarCapsule({
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

class _SlidePagesList extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final TransformationController transformationController;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;
  final ValueChanged<int>? onSlideTap;
  final bool fillWidth;

  const _SlidePagesList({
    required this.controller,
    required this.compact,
    required this.canManageSlides,
    this.isDark = false,
    required this.transformationController,
    this.fillWidth = false,
    required this.onEditSlide,
    required this.onDeleteSlide,
    this.onSlideTap,
  });

  @override
  State<_SlidePagesList> createState() => _SlidePagesListState();
}

class _SlidePagesListState extends State<_SlidePagesList> with SingleTickerProviderStateMixin {
  final Map<int, GlobalKey> _slideKeys = {};
  final Set<int> _activeStylusPointers = {};

  late final AnimationController _flingAnimationController;
  bool _wasZoomed = false;
  double _lastViewportHeight = 0.0;
  double _lastPageWidth = 0.0;

  bool get _isDrawingTool =>
      widget.controller.selectedTool == WorkspaceTool.pen ||
      widget.controller.selectedTool == WorkspaceTool.highlighter ||
      widget.controller.selectedTool == WorkspaceTool.eraser;

  bool get _phoneDrawingMode =>
      MediaQuery.sizeOf(context).width < 600 && _isDrawingTool;

  bool _isStylus(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool get _customPanEnabled =>
      !_wasZoomed &&
      !_phoneDrawingMode &&
      !(_isDrawingTool && _activeStylusPointers.isNotEmpty);

  GlobalKey _slideKeyFor(int index) =>
      _slideKeys.putIfAbsent(index, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
    _flingAnimationController = AnimationController.unbounded(vsync: this);
    _flingAnimationController.addListener(_onFlingTick);
  }

  @override
  void didUpdateWidget(covariant _SlidePagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController.removeListener(_onTransformChanged);
      widget.transformationController.addListener(_onTransformChanged);
    }
  }

  void _onTransformChanged() {
    final matrix = widget.transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();

    if ((widget.controller.zoom - scale).abs() > 0.01) {
      widget.controller.setZoom(scale);
    }

    final isZoomedNow = scale > 1.01;
    if (isZoomedNow != _wasZoomed) {
      setState(() {
        _wasZoomed = isZoomedNow;
      });
    }

    // Automatically update the active slide index to the one closest to the vertical center of the screen
    if (_lastViewportHeight > 0 && _lastPageWidth > 0 && widget.controller.hasSlides) {
      final translation = matrix.getTranslation();
      final centerY = (-translation.y + _lastViewportHeight / 2) / scale;

      const topPad = 10.0;
      double currentY = topPad;
      double bestDistance = double.infinity;
      int bestIndex = widget.controller.currentIndex;
      final entries = _workspaceEntries(widget.controller.slides);

      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        final entry = entries[entryIndex];
        double entryHeight = 0.0;
        if (entry.isHeader) {
          entryHeight = widget.compact ? 50.0 : 64.0;
        } else {
          entryHeight = _lastPageWidth * _slideCanvasHeight / _slideCanvasWidth +
              (widget.canManageSlides ? 33.0 : 0.0) +
              (widget.compact ? 2.0 : 3.0);
        }

        if (!entry.isHeader) {
          final slideIndex = entry.slideIndex!;
          final slideCenterY = currentY + entryHeight / 2;
          final distance = (slideCenterY - centerY).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = slideIndex;
          }
        }
        currentY += entryHeight;
      }

      if (bestIndex != widget.controller.currentIndex) {
        final stateProvider = _WorkspaceOutsideStateProvider.of(context);
        if (stateProvider != null && stateProvider.editingSlideIndex != null && stateProvider.editingSlideIndex != bestIndex) {
          stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
        }
        widget.controller.goToSlide(bestIndex);
      }
    }
  }

  void _onFlingTick() {
    if (!_flingAnimationController.isAnimating) return;
    final currentMatrix = widget.transformationController.value;
    final scale = currentMatrix.getMaxScaleOnAxis();

    double totalContentHeight = 10.0 + 10.0;
    final entries = _workspaceEntries(widget.controller.slides);
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final entry = entries[entryIndex];
      if (entry.isHeader) {
        totalContentHeight += widget.compact ? 50.0 : 64.0;
      } else {
        totalContentHeight += _lastPageWidth * _slideCanvasHeight / _slideCanvasWidth +
            (widget.canManageSlides ? 33.0 : 0.0) +
            (widget.compact ? 2.0 : 3.0);
      }
    }

    final double maxScrollY = (totalContentHeight * scale - _lastViewportHeight).clamp(0.0, double.infinity);
    final double newY = _flingAnimationController.value.clamp(-maxScrollY, 0.0);

    final newMatrix = Matrix4.copy(currentMatrix)
      ..setTranslationRaw(0.0, newY, currentMatrix.getTranslation().z);

    widget.transformationController.value = newMatrix;
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    _flingAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _workspaceEntries(widget.controller.slides);
    
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const sidePad = 10.0;
          const topPad = 10.0;
          const bottomPad = 10.0;
          
          final pageWidth = (constraints.maxWidth - (sidePad * 2)).clamp(280.0, double.infinity);

          _lastViewportHeight = constraints.maxHeight;
          _lastPageWidth = pageWidth;

          final gestures = <Type, GestureRecognizerFactory>{};
          if (_customPanEnabled) {
            gestures[WorkspaceScrollGestureRecognizer] = GestureRecognizerFactoryWithHandlers<WorkspaceScrollGestureRecognizer>(
              () => WorkspaceScrollGestureRecognizer(),
              (WorkspaceScrollGestureRecognizer instance) {
                instance
                  ..onStart = () {
                    _flingAnimationController.stop();
                  }
                  ..onUpdate = (deltaY) {
                    final currentMatrix = widget.transformationController.value;
                    final translation = currentMatrix.getTranslation();
                    final scale = currentMatrix.getMaxScaleOnAxis();

                    double totalContentHeight = topPad + bottomPad;
                    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
                      final entry = entries[entryIndex];
                      if (entry.isHeader) {
                        totalContentHeight += widget.compact ? 50.0 : 64.0;
                      } else {
                        totalContentHeight += pageWidth * _slideCanvasHeight / _slideCanvasWidth +
                            (widget.canManageSlides ? 33.0 : 0.0) +
                            (widget.compact ? 2.0 : 3.0);
                      }
                    }

                    final double maxScrollY = (totalContentHeight * scale - constraints.maxHeight).clamp(0.0, double.infinity);
                    final double newY = (translation.y + deltaY).clamp(-maxScrollY, 0.0);

                    final newMatrix = Matrix4.copy(currentMatrix)
                      ..setTranslationRaw(0.0, newY, translation.z);

                    widget.transformationController.value = newMatrix;
                  }
                  ..onEnd = (velocity) {
                    final double velocityY = velocity.pixelsPerSecond.dy;
                    if (velocityY.abs() > 100) {
                      final currentMatrix = widget.transformationController.value;
                      final translation = currentMatrix.getTranslation();
                      final simulation = ClampingScrollSimulation(
                        position: translation.y,
                        velocity: velocityY,
                        tolerance: Tolerance.defaultTolerance,
                      );
                      _flingAnimationController.animateWith(simulation);
                    }
                  }
                  ..onStylusDetected = () {
                    // Stylus is tracked separately, no additional action needed here
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
                if (_activeStylusPointers.contains(event.pointer)) {
                  setState(() {
                    _activeStylusPointers.remove(event.pointer);
                  });
                }
              },
              onPointerCancel: (event) {
                if (_activeStylusPointers.contains(event.pointer)) {
                  setState(() {
                    _activeStylusPointers.remove(event.pointer);
                  });
                }
              },
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(pointerSignal, (event) {
                    if (event is PointerScrollEvent) {
                      final double scrollDeltaY = event.scrollDelta.dy;
                      final double scrollDeltaX = event.scrollDelta.dx;
                      if (scrollDeltaY != 0 || scrollDeltaX != 0) {
                        final currentMatrix = widget.transformationController.value;
                        final translation = currentMatrix.getTranslation();
                        final scale = currentMatrix.getMaxScaleOnAxis();

                        final double viewportWidth = constraints.maxWidth;
                        final double viewportHeight = constraints.maxHeight;

                        // Calculate content dimensions
                        final double totalContentWidth = pageWidth + sidePad * 2;
                        double totalContentHeight = topPad + bottomPad;
                        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
                          final entry = entries[entryIndex];
                          if (entry.isHeader) {
                            totalContentHeight += widget.compact ? 50.0 : 64.0;
                          } else {
                            totalContentHeight += pageWidth * _slideCanvasHeight / _slideCanvasWidth +
                                (widget.canManageSlides ? 33.0 : 0.0) +
                                (widget.compact ? 2.0 : 3.0);
                          }
                        }

                        final double maxScrollY = (totalContentHeight * scale - viewportHeight).clamp(0.0, double.infinity);
                        final double maxScrollX = (totalContentWidth * scale - viewportWidth).clamp(0.0, double.infinity);

                        final double newY = (translation.y - scrollDeltaY).clamp(-maxScrollY, 0.0);
                        final double newX = (translation.x - scrollDeltaX).clamp(-maxScrollX, 0.0);

                        final newMatrix = Matrix4.copy(currentMatrix)
                          ..setTranslationRaw(newX, newY, translation.z);

                        widget.transformationController.value = newMatrix;
                      }
                    }
                  });
                }
              },
              child: InteractiveViewer(
                transformationController: widget.transformationController,
                panEnabled: _wasZoomed && !_phoneDrawingMode && !(_isDrawingTool && _activeStylusPointers.isNotEmpty),
                scaleEnabled: !_phoneDrawingMode && !(_isDrawingTool && _activeStylusPointers.isNotEmpty),
                // Boundary margin stops panning exactly at the subtle 10px (~3mm) outer edge.
                boundaryMargin: EdgeInsets.zero,
                minScale: 1.0,
                maxScale: 5.0,
                alignment: Alignment.topLeft,
                constrained: false, 
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(sidePad, topPad, sidePad, bottomPad),
                  child: SizedBox(
                    width: pageWidth, 
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++)
                          _buildEntry(entries[entryIndex], entryIndex, entries.length, pageWidth),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntry(_WorkspaceListEntry entry, int entryIndex, int totalEntries, double pageWidth) {
    final isLast = entryIndex == totalEntries - 1;
    if (entry.isHeader) {
      final isFirst = entryIndex == 0;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          isFirst ? 0 : (widget.compact ? 10 : 14),
          0,
          widget.compact ? 6 : 8,
        ),
        child: _SubtitleHeader(
          subtitle: entry.subtitle,
          isDark: widget.isDark,
          compact: widget.compact,
        ),
      );
    }
    
    final index = entry.slideIndex!;
    final baseHeight = pageWidth * _slideCanvasHeight / _slideCanvasWidth +
        (widget.canManageSlides ? 33 : 0);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : (widget.compact ? 2 : 3)),
      child: SizedBox(
        height: baseHeight,
        child: _MobileSlidePage(
          key: _slideKeyFor(index),
          controller: widget.controller,
          index: index,
          compact: widget.compact,
          canManageSlides: widget.canManageSlides,
          isDark: widget.isDark,
          zoomScale: 1.0, 
          onEdit: () => widget.onEditSlide(index),
          onDelete: () => widget.onDeleteSlide(index),
          onSlideTap: widget.onSlideTap,
        ),
      ),
    );
  }
}

class _WorkspaceListEntry {
  final String subtitle;
  final int? slideIndex;

  const _WorkspaceListEntry.header(this.subtitle) : slideIndex = null;
  const _WorkspaceListEntry.slide(this.subtitle, int index)
      : slideIndex = index;

  bool get isHeader => slideIndex == null;
}

String _subtitleLabel(String subtitle) =>
    subtitle.trim().isEmpty ? 'Untitled' : subtitle.trim();

String _subtitleKey(String subtitle) => _subtitleLabel(subtitle).toLowerCase();

List<_WorkspaceListEntry> _workspaceEntries(List<WorkspaceSlide> slides) {
  final entries = <_WorkspaceListEntry>[];
  String? previousKey;
  for (var index = 0; index < slides.length; index++) {
    final subtitle = _subtitleLabel(slides[index].subtitle);
    final key = _subtitleKey(subtitle);
    if (key != previousKey) {
      entries.add(_WorkspaceListEntry.header(subtitle));
      previousKey = key;
    }
    entries.add(_WorkspaceListEntry.slide(subtitle, index));
  }
  return entries;
}

List<List<int>> _subtitleGroups(List<WorkspaceSlide> slides) {
  final groups = <List<int>>[];
  String? previousKey;
  for (var index = 0; index < slides.length; index++) {
    final key = _subtitleKey(slides[index].subtitle);
    if (key != previousKey) {
      groups.add(<int>[]);
      previousKey = key;
    }
    groups.last.add(index);
  }
  return groups;
}

class _SubtitleHeader extends StatelessWidget {
  final String subtitle;
  final bool isDark;
  final bool compact;

  const _SubtitleHeader({
    required this.subtitle,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF252039) : workspacePurple;
    final textColor = isDark ? const Color(0xFF9F8AFF) : Colors.white;
    final borderColor = isDark ? const Color(0xFF383153) : workspacePurple;

    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: workspacePurple.withValues(alpha: 0.20),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Text(
        subtitle,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 18 : 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CollapsibleSlideWorkspace extends StatefulWidget {
  final SlideWorkspaceController controller;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;

  const _CollapsibleSlideWorkspace({
    required this.controller,
    required this.compact,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEditSlide,
    required this.onDeleteSlide,
  });

  @override
  State<_CollapsibleSlideWorkspace> createState() =>
      _CollapsibleSlideWorkspaceState();
}

class _CollapsibleSlideWorkspaceState
    extends State<_CollapsibleSlideWorkspace> {
  bool _showThumbnails = false;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.value = Matrix4.identity()
      ..scale(widget.zoomScale, widget.zoomScale, 1.0);
  }

  @override
  void didUpdateWidget(covariant _CollapsibleSlideWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomScale != widget.zoomScale) {
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      if ((currentScale - widget.zoomScale).abs() > 0.01) {
        if (widget.zoomScale <= 1.0) {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY.clamp(-double.infinity, 0.0));
        } else {
          final currentY = _transformationController.value.getTranslation().y;
          _transformationController.value = Matrix4.identity()
            ..translate(0.0, currentY)
            ..scale(widget.zoomScale, widget.zoomScale, 1.0);
        }
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _goToSlide(int index) {
    final stateProvider = _WorkspaceOutsideStateProvider.of(context);
    if (stateProvider != null && stateProvider.editingSlideIndex != null && stateProvider.editingSlideIndex != index) {
      stateProvider.saveInPlaceEdit(stateProvider.editingSlideIndex!);
    }
    widget.controller.goToSlide(index);
    _animateToSlide(
      transformationController: _transformationController,
      index: index,
      compact: widget.compact,
      fillWidth: false,
      canManageSlides: widget.canManageSlides,
      slides: widget.controller.slides,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _SlidePagesList(
          controller: widget.controller,
          compact: widget.compact,
          canManageSlides: widget.canManageSlides,
          isDark: widget.isDark,
          transformationController: _transformationController,
          onEditSlide: widget.onEditSlide,
          onDeleteSlide: widget.onDeleteSlide,
          onSlideTap: _goToSlide,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: _ToolbarCapsule(
                    isDark: widget.isDark,
                    child: WorkspaceIconButton(
                      icon: _showThumbnails
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      tooltip: 'Slides',
                      onTap: () =>
                          setState(() => _showThumbnails = !_showThumbnails),
                    ),
                  ),
                ),
              ),
              if (_showThumbnails)
                SizedBox(
                  height: widget.compact ? 148 : 160,
                  child: _HorizontalThumbnails(
                    controller: widget.controller,
                    isDark: widget.isDark,
                    onSlideTap: _goToSlide,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileWorkspace extends StatelessWidget {
  final SlideWorkspaceController controller;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final ValueChanged<int> onEditSlide;
  final ValueChanged<int> onDeleteSlide;

  const _MobileWorkspace({
    required this.controller,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEditSlide,
    required this.onDeleteSlide,
  });

  @override
  Widget build(BuildContext context) {
    return _CollapsibleSlideWorkspace(
      controller: controller,
      compact: true,
      canManageSlides: canManageSlides,
      isDark: isDark,
      zoomScale: zoomScale,
      onEditSlide: onEditSlide,
      onDeleteSlide: onDeleteSlide,
    );
  }
}

abstract class WorkspaceObjectRenderer<T extends WorkspaceObject> {
  Widget buildRenderer({
    required BuildContext context,
    required T object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  });
}

class WorkspaceRendererRegistry {
  static final Map<String, WorkspaceObjectRenderer> _renderers = {};

  static void register(String type, WorkspaceObjectRenderer renderer) {
    _renderers[type] = renderer;
  }

  static void _ensureInitialized() {
    if (_renderers.isEmpty) {
      register('stroke', SlideStrokeRenderer());
      register('image', ImageObjectRenderer());
    }
  }

  static Widget render({
    required BuildContext context,
    required WorkspaceObject object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    _ensureInitialized();
    final renderer = _renderers[object.type];
    if (renderer == null) return const SizedBox.shrink();
    return renderer.buildRenderer(
      context: context,
      object: object,
      controller: controller,
      isSelected: isSelected,
      onSelected: onSelected,
      onUpdate: onUpdate,
      onDelete: onDelete,
    );
  }
}

class SlideStrokeRenderer extends WorkspaceObjectRenderer<SlideStroke> {
  @override
  Widget buildRenderer({
    required BuildContext context,
    required SlideStroke object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: DrawingLayerPainter(
              strokes: [object],
              activeStroke: null,
            ),
          ),
        ),
      ),
    );
  }
}

class ImageObjectRenderer extends WorkspaceObjectRenderer<ImageObject> {
  @override
  Widget buildRenderer({
    required BuildContext context,
    required ImageObject object,
    required SlideWorkspaceController controller,
    required bool isSelected,
    required VoidCallback onSelected,
    required ValueChanged<WorkspaceObject> onUpdate,
    required VoidCallback onDelete,
  }) {
    return _InteractiveImageWidget(
      image: object,
      isSelected: isSelected,
      onSelected: onSelected,
      onUpdate: (val) => onUpdate(val),
      onDelete: onDelete,
      controller: controller,
    );
  }
}

class _MobileSlidePage extends StatefulWidget {
  final SlideWorkspaceController controller;
  final int index;
  final bool compact;
  final bool canManageSlides;
  final bool isDark;
  final double zoomScale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int>? onSlideTap;

  const _MobileSlidePage({
    super.key,
    required this.controller,
    required this.index,
    required this.compact,
    required this.canManageSlides,
    required this.isDark,
    required this.zoomScale,
    required this.onEdit,
    required this.onDelete,
    this.onSlideTap,
  });

  @override
  State<_MobileSlidePage> createState() => _MobileSlidePageState();
}

class _MobileSlidePageState extends State<_MobileSlidePage> {
  final GlobalKey _canvasKey = GlobalKey();
  int? _activePointer;
  PointerDeviceKind? _activeKind;

  SlideWorkspaceController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final slide = controller.slides[widget.index];
    final isCurrent = widget.index == controller.currentIndex;
    final page = AspectRatio(
      aspectRatio: _slideCanvasWidth / _slideCanvasHeight,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Listener(
          onPointerDown: (event) => _handlePointerDown(event),
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerUp,
          child: SizedBox(
            key: _canvasKey,
            width: _slideCanvasWidth,
            height: _slideCanvasHeight,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onSlideTap?.call(widget.index);
                    controller.selectObject(null);
                  },
                  onDoubleTap: () {
                    final stateProvider = _WorkspaceOutsideStateProvider.of(context);
                    if (stateProvider != null && widget.canManageSlides) {
                      stateProvider.startInPlaceEdit(widget.index);
                    }
                  },
                  child: _SlidePaper(
                      slide: slide,
                      compact: widget.compact,
                      isDark: widget.isDark,
                      studyMode: controller.isStudyMode,
                      isCurrent: isCurrent,
                      controller: controller,
                      slideIndex: widget.index),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final obj in ((controller.isStudyMode ? slide.strokes : slide.examStrokes)
                            .toList()
                          ..sort((a, b) {
                            final cmp = a.zIndex.compareTo(b.zIndex);
                            if (cmp != 0) return cmp;
                            return a.creationTime.compareTo(b.creationTime);
                          })))
                          WorkspaceRendererRegistry.render(
                            context: context,
                            object: obj,
                            controller: controller,
                            isSelected: isCurrent && controller.selectedObjectId == obj.id,
                            onSelected: () {
                              widget.onSlideTap?.call(widget.index);
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
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.canManageSlides && controller.isStudyMode)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 3),
            child: _ObjectControls(
              index: widget.index,
              total: controller.slides.length,
              onEdit: widget.onEdit,
              onDuplicate: () => controller.duplicateSlideAt(widget.index),
              onDelete: widget.onDelete,
              onMoveUp: () => controller.moveSlideUp(widget.index),
              onMoveDown: () => controller.moveSlideDown(widget.index),
              isHidden: slide.isHidden,
              isDark: widget.isDark,
              onHide: () => controller.toggleSlideHidden(widget.index),
              controller: controller,
            ),
          ),
        page,
      ],
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
      controller.goToSlide(widget.index);
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
    controller.startStroke(
      _toSlidePoint(event.position),
      event.kind,
      pressure: event.pressure,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    controller.appendStrokePoint(_toSlidePoint(event.position), event.pressure);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _activeKind = null;
    controller.endStroke();
  }

  bool get _canDraw =>
      controller.selectedTool == WorkspaceTool.pen ||
      controller.selectedTool == WorkspaceTool.highlighter ||
      controller.selectedTool == WorkspaceTool.eraser;

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

class _WorkspaceLogo extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final Alignment alignment;

  const _WorkspaceLogo({
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

class _TopToolbar extends StatelessWidget {
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

  const _TopToolbar({
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
    return _WorkspaceLogo(
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
    return _ToolbarCapsule(
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
    return _ToolbarCapsule(
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
    return _ToolbarCapsule(
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
    return _ToolbarCapsule(
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

class _SlidePaper extends StatelessWidget {
  final WorkspaceSlide slide;
  final bool compact;
  final bool isDark;
  final bool studyMode;
  final bool isCurrent;
  final bool isThumbnail;
  final SlideWorkspaceController? controller;
  final bool? loadRealImage;
  final int? slideIndex;

  const _SlidePaper({
    required this.slide,
    required this.compact,
    required this.isDark,
    required this.studyMode,
    required this.isCurrent,
    this.isThumbnail = false,
    this.controller,
    this.loadRealImage,
    this.slideIndex,
  });

  bool get _shouldLoadImage {
    if (loadRealImage != null) return loadRealImage!;
    if (isThumbnail) return true;
    if (controller == null) return true;
    final currentIndex = controller!.currentIndex;
    final position = slideIndex ?? slide.index;
    return (position - currentIndex).abs() <= 5;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242039) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3258) : const Color(0xFFE2E0EF),
          width: 1.5,
        ),
        boxShadow: [
          if (isCurrent) ...
            [
              BoxShadow(
                color: workspacePurple.withValues(alpha: 0.45),
                blurRadius: 28,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: workspacePurple.withValues(alpha: 0.18),
                blurRadius: 56,
                spreadRadius: 10,
              ),
            ]
          else
            BoxShadow(
              color: workspacePurple.withValues(alpha: .05),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Opacity(
              opacity: .035,
              child: Text(
                '.Stagiaire',
                style: TextStyle(
                  fontSize: 118,
                  color: isDark ? const Color(0xFF6F55FF) : workspacePurple,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _BrandTab(isDark: isDark)),
          ),
          if (slide.isHidden)
            Positioned(
              top: 12,
              right: 16,
              child: _HiddenSlideBadge(isDark: isDark),
            ),
          Positioned.fill(
            top: 44,
            child: _AdaptiveSlideContent(
              slide: slide,
              compact: compact,
              isDark: isDark,
              studyMode: studyMode,
              isThumbnail: isThumbnail,
              loadRealImage: _shouldLoadImage,
              slideIndex: slideIndex,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveSlideContent extends StatefulWidget {
  final WorkspaceSlide slide;
  final bool compact;
  final bool isDark;
  final bool studyMode;
  final bool isThumbnail;
  final bool loadRealImage;
  final int? slideIndex;

  const _AdaptiveSlideContent({
    required this.slide,
    required this.compact,
    required this.isDark,
    required this.studyMode,
    this.isThumbnail = false,
    this.loadRealImage = true,
    this.slideIndex,
  });

  @override
  State<_AdaptiveSlideContent> createState() => _AdaptiveSlideContentState();
}

class _AdaptiveSlideContentState extends State<_AdaptiveSlideContent> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double? _imageAspectRatio;
  bool _hasLoadedRealImage = false;

  static final Map<String, double> _aspectRatioCache = {};

  @override
  void initState() {
    super.initState();
    if (widget.loadRealImage) {
      _hasLoadedRealImage = true;
    }
    final url = widget.slide.imageAsset.trim();
    if (_aspectRatioCache.containsKey(url)) {
      _imageAspectRatio = _aspectRatioCache[url];
    }
    _resolveImageAspect();
  }

  @override
  void didUpdateWidget(covariant _AdaptiveSlideContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadRealImage) {
      _hasLoadedRealImage = true;
    }
    if (oldWidget.slide.imageAsset != widget.slide.imageAsset ||
        oldWidget.loadRealImage != widget.loadRealImage) {
      final url = widget.slide.imageAsset.trim();
      _imageAspectRatio = _aspectRatioCache[url];
      _resolveImageAspect();
    }
  }

  void _resolveImageAspect() {
    final loadReal = widget.loadRealImage || _hasLoadedRealImage;
    if (!loadReal) return;
    if (widget.isThumbnail) return;
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    final url = widget.slide.imageAsset.trim();
    if (url.isEmpty || !url.startsWith('http')) return;

    if (_aspectRatioCache.containsKey(url)) {
      final cachedAspect = _aspectRatioCache[url];
      if (cachedAspect != null && cachedAspect > 0) {
        if (_imageAspectRatio != cachedAspect) {
          setState(() => _imageAspectRatio = cachedAspect);
        }
        return;
      }
    }

    _imageStream = NetworkImage(url).resolve(const ImageConfiguration());
    _imageListener = ImageStreamListener(
      (image, _) {
        final aspect = image.image.width / image.image.height;
        if (aspect > 0) {
          _aspectRatioCache[url] = aspect;
          if (mounted && aspect != _imageAspectRatio) {
            setState(() => _imageAspectRatio = aspect);
          }
        }
      },
      onError: (exception, stackTrace) {
        debugPrint('Error resolving image aspect: $exception');
      },
    );
    _imageStream!.addListener(_imageListener!);
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stateProvider = _WorkspaceOutsideStateProvider.of(context);
    final isEditingInPlace = stateProvider != null &&
        widget.slideIndex != null &&
        stateProvider.editingSlideIndex == widget.slideIndex;

    const totalFlex = 10;
    final loadReal = widget.loadRealImage || _hasLoadedRealImage;
    final imageFlex = (_imageAspectRatio ?? 0) > 1.12 ? 5 : 4;
    final questionFlex = totalFlex - imageFlex;
    final slide = widget.slide;
    final compact = widget.compact;
    final isDark = widget.isDark;

    return Row(
      children: [
        Expanded(
          flex: imageFlex,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 44 : 56,
              30,
              compact ? 20 : 34,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: loadReal
                        ? _SlideImagePanel(imageUrl: slide.imageAsset)
                        : Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1F1C33) : const Color(0xFFF7F5FE),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isDark ? const Color(0xFF383154) : const Color(0xFFE6E3F4)),
                            ),
                            child: const Icon(Icons.image_outlined, color: workspaceMuted, size: 54),
                          ),
                  ),
                ),
                if (widget.studyMode &&
                    (slide.title.trim().isNotEmpty ||
                        slide.audioUrl.trim().isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  if (slide.title.trim().isNotEmpty)
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : workspaceInk,
                        fontSize: compact ? 22 : 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  if (slide.audioUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    AudioExplanationPlayer(
                      audioUrl: slide.audioUrl,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 32),
          color: isDark ? const Color(0xFF3C3654) : const Color(0xFFE0DEF1),
        ),
        Expanded(
          flex: questionFlex,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 18,
              12,
              compact ? 32 : 48,
              12,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < slide.questions.length; i++)
                      _QuestionBlock(
                        number: i + 1,
                        question: slide.questions[i],
                        isDark: isDark,
                        showAnswer: widget.studyMode,
                        isEditingInPlace: isEditingInPlace,
                        promptController: isEditingInPlace && i < stateProvider.inPlacePromptControllers.length
                            ? stateProvider.inPlacePromptControllers[i]
                            : null,
                        answerController: isEditingInPlace && i < stateProvider.inPlaceAnswerControllers.length
                            ? stateProvider.inPlaceAnswerControllers[i]
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}



class _SlideImagePanel extends StatefulWidget {
  final String imageUrl;

  const _SlideImagePanel({required this.imageUrl});

  @override
  State<_SlideImagePanel> createState() => _SlideImagePanelState();
}

class _SlideImagePanelState extends State<_SlideImagePanel> {
  late Future<String?> _imagePath;
  String? _syncPath;

  @override
  void initState() {
    super.initState();
    _syncPath = ImageCacheService().getCachedPathSync(widget.imageUrl);
    _imagePath = _loadImage();
  }

  @override
  void didUpdateWidget(covariant _SlideImagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _syncPath = ImageCacheService().getCachedPathSync(widget.imageUrl);
      _imagePath = _loadImage();
    }
  }

  Future<String?> _loadImage() async {
    final url = widget.imageUrl.trim();
    if (url.isEmpty || kIsWeb || !url.startsWith('http')) {
      return url;
    }
    final path = await ImageCacheService().getOrDownload(url);
    if (mounted && path != _syncPath) {
      setState(() {
        _syncPath = path;
      });
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.imageUrl.trim();
    if (imageUrl.isEmpty) return _placeholder();

    if (_syncPath != null && _syncPath!.isNotEmpty && _syncPath != imageUrl && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(_syncPath!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _brokenImage(),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _imagePath,
      builder: (context, snapshot) {
        final path = snapshot.data?.trim() ?? _syncPath ?? '';
        final image = path.isNotEmpty && path != imageUrl && !kIsWeb
            ? Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _brokenImage(),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _brokenImage(),
              );
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: image,
        );
      },
    );
  }

  Widget _placeholder() => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5FE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E3F4)),
        ),
        child:
            const Icon(Icons.image_outlined, color: workspaceMuted, size: 54),
      );

  Widget _brokenImage() => const Center(
        child:
            Icon(Icons.broken_image_outlined, color: workspaceMuted, size: 48),
      );
}

class _SlideMiniature extends StatelessWidget {
  final WorkspaceSlide slide;
  final bool isDark;
  final bool loadRealImage;
  final int? slideIndex;

  const _SlideMiniature({
    required this.slide,
    required this.isDark,
    this.loadRealImage = true,
    this.slideIndex,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _slideCanvasWidth,
            height: _slideCanvasHeight,
            child: _SlidePaper(
              slide: slide,
              compact: false,
              isDark: isDark,
              studyMode: true,
              isCurrent: false,
              isThumbnail: true,
              controller: null,
              loadRealImage: loadRealImage,
              slideIndex: slideIndex,
            ),
          ),
        ),
      );
}

class _QuestionBlock extends StatelessWidget {
  final int number;
  final WorkspaceQuestion question;
  final bool isDark;
  final bool showAnswer;
  final bool isEditingInPlace;
  final TextEditingController? promptController;
  final TextEditingController? answerController;

  const _QuestionBlock({
    required this.number,
    required this.question,
    required this.isDark,
    required this.showAnswer,
    this.isEditingInPlace = false,
    this.promptController,
    this.answerController,
  });

  @override
  Widget build(BuildContext context) {
    final softLightPurple = isDark
        ? const Color(0xFFC7B8EA).withValues(alpha: 0.55)
        : const Color(0xFFB39DDB).withValues(alpha: 0.65);

    if (isEditingInPlace && promptController != null && answerController != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number.  ',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: promptController,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Question prompt...',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 28.0),
              child: TextField(
                controller: answerController,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  color: isDark ? Colors.white : workspaceInk,
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Answer explanation...',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$number.  ${question.prompt}',
              style: TextStyle(
                  color: isDark ? const Color(0xFF8B75FF) : workspacePurple,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          const SizedBox(height: 12),
          if (showAnswer && question.answer.trim().isNotEmpty)
            Text(question.answer,
                style: TextStyle(
                    color: isDark ? Colors.white : workspaceInk,
                    fontSize: 20,
                    fontWeight: FontWeight.normal,
                    height: 1.5))
          else
            for (var i = 0; i < question.answerLines; i++)
              Container(
                  height: 2.0,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: softLightPurple,
                    borderRadius: BorderRadius.circular(1),
                  )),
        ],
      ),
    );
  }
}

class _ObjectControls extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool isHidden;
  final bool isDark;
  final VoidCallback onHide;
  final SlideWorkspaceController? controller;

  const _ObjectControls({
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.isHidden,
    required this.isDark,
    required this.onHide,
    this.controller,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final stateProvider = _WorkspaceOutsideStateProvider.of(context);
    final slide = controller != null && index >= 0 && index < controller!.slides.length
        ? controller!.slides[index]
        : null;

    final isRecordingThisSlide = stateProvider != null &&
        slide != null &&
        stateProvider.activeRecordingSlideId == slide.id;

    if (isRecordingThisSlide && stateProvider != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, color: Colors.red, size: 10),
            const SizedBox(width: 8),
            Text(
              'Rec: ${_formatDuration(stateProvider.outsideRecordDuration)}',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                stateProvider.isOutsidePaused ? Icons.play_arrow : Icons.pause,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: stateProvider.pauseResumeRecording,
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(
                Icons.stop,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => stateProvider.stopRecording(slide),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(
                Icons.close,
                size: 18,
                color: Colors.red,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: stateProvider.cancelRecording,
            ),
          ],
        ),
      );
    }

    final items = [
      (Icons.keyboard_arrow_up_rounded, 'Move up', onMoveUp, index > 0),
      (
        Icons.keyboard_arrow_down_rounded,
        'Move down',
        onMoveDown,
        index < total - 1
      ),
      (
        isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        isHidden ? 'Show' : 'Hide',
        onHide,
        true,
      ),
      if (slide != null && stateProvider != null) ...[
        if (slide.audioUrl.isNotEmpty)
          (
            Icons.music_off_outlined,
            'Clear voice',
            () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Delete audio?'),
                  content: const Text('Are you sure you want to delete the audio explanation for this slide?'),
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
              if (confirmed == true && controller != null) {
                await controller!.updateSlide(
                  slideId: slide.id,
                  title: slide.title,
                  subtitle: slide.subtitle,
                  questions: slide.questions,
                  audioPath: 'clear_audio',
                );
              }
            },
            !stateProvider.isOutsideRecording,
          ),
        (
          Icons.mic_none_outlined,
          'Record voice',
          () => stateProvider.startRecording(slide),
          !stateProvider.isOutsideRecording,
        ),
      ],
      (Icons.edit_outlined, 'Edit', onEdit, true),
      (Icons.control_point_duplicate_rounded, 'Duplicate', onDuplicate, true),
      (Icons.delete_outline_rounded, 'Delete', onDelete, true),
    ];

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in items)
          _SlideActionIcon(
            icon: item.$1,
            tooltip: item.$2,
            isDark: isDark,
            onTap: item.$4 ? item.$3 : null,
          ),
      ],
    );
  }
}

class _SlideActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback? onTap;

  const _SlideActionIcon({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = isDark ? Colors.white : workspaceInk;
    final muted = isDark ? Colors.white : workspaceMuted;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 21,
            color: enabled
                ? base.withValues(alpha: .84)
                : muted.withValues(alpha: .35),
          ),
        ),
      ),
    );
  }
}

class _HiddenSlideBadge extends StatelessWidget {
  final bool isDark;

  const _HiddenSlideBadge({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF332C55) : const Color(0xFFF3EFFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF4B4171) : const Color(0xFFE0D8FA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined,
              color: isDark ? Colors.white : workspacePurple, size: 16),
          const SizedBox(width: 6),
          Text(
            'Hidden',
            style: TextStyle(
              color: isDark ? Colors.white : workspacePurple,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandTab extends StatelessWidget {
  final bool isDark;

  const _BrandTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6F55FF) : workspacePurple,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: const _WorkspaceLogo(
        color: Colors.white,
        width: 106,
        height: 27,
      ),
    );
  }
}

class _ThumbnailSidebar extends StatelessWidget {
  final SlideWorkspaceController controller;
  final VoidCallback? onAddSlide;
  final VoidCallback? onBrandTap;
  final ValueChanged<int>? onSlideTap;
  final bool isDark;

  const _ThumbnailSidebar({
    required this.controller,
    this.onAddSlide,
    this.onBrandTap,
    this.onSlideTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1930) : const Color(0xFFFBFAFF),
        border: Border(
            right: BorderSide(
                color: isDark
                    ? const Color(0xFF312B49)
                    : const Color(0xFFECE9F7))),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: ListView(
                children: [
                  for (var index = 0;
                      index < controller.slides.length;
                      index++) ...[
                    if (index == 0 ||
                        _subtitleKey(controller.slides[index].subtitle) !=
                            _subtitleKey(controller.slides[index - 1].subtitle))
                      Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : 18,
                          bottom: 10,
                        ),
                        child: Transform.scale(
                          scale: 0.7,
                          alignment: Alignment.topCenter,
                          child: _SubtitleHeader(
                            subtitle: _subtitleLabel(
                                controller.slides[index].subtitle),
                            isDark: isDark,
                            compact: true,
                          ),
                        ),
                      ),
                    _ThumbCard(
                      controller: controller,
                      index: index,
                      isDark: isDark,
                      onTap:
                          onSlideTap == null ? null : () => onSlideTap!(index),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onAddSlide != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 38,
                child: PopupMenuButton<int>(
                  tooltip: 'Choose slide subtitle',
                  onSelected: (index) {
                    controller.goToSlide(index);
                    onSlideTap?.call(index);
                  },
                  itemBuilder: (context) {
                    final groups = _subtitleGroups(controller.slides);
                    return [
                      for (final group in groups)
                        PopupMenuItem<int>(
                          value: group.first,
                          child: Text(
                            _subtitleLabel(
                                controller.slides[group.first].subtitle),
                          ),
                        ),
                    ];
                  },
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0ECFF),
                      foregroundColor: workspacePurple,
                      elevation: 0,
                    ),
                    onPressed: null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            controller.currentSlide.subtitle.trim().isEmpty
                                ? 'Untitled'
                                : controller.currentSlide.subtitle.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HorizontalThumbnails extends StatelessWidget {
  final SlideWorkspaceController controller;
  final bool isDark;
  final ValueChanged<int>? onSlideTap;

  const _HorizontalThumbnails({
    required this.controller,
    required this.isDark,
    this.onSlideTap,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _subtitleGroups(controller.slides);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final group in groups)
          SizedBox(
            width: group.length * 136,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.scale(
                    scale: 0.65,
                    alignment: Alignment.topCenter,
                    child: _SubtitleHeader(
                      subtitle: _subtitleLabel(
                          controller.slides[group.first].subtitle),
                      isDark: isDark,
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Expanded(
                    child: Row(
                      children: [
                        for (final index in group)
                          Expanded(
                            child: _ThumbCard(
                              controller: controller,
                              index: index,
                              isDark: isDark,
                              horizontal: true,
                              onTap: onSlideTap == null
                                  ? null
                                  : () => onSlideTap!(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ThumbCard extends StatelessWidget {
  final SlideWorkspaceController controller;
  final int index;
  final bool isDark;
  final bool horizontal;
  final VoidCallback? onTap;

  const _ThumbCard({
    required this.controller,
    required this.index,
    this.isDark = false,
    this.horizontal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final slide = controller.slides[index];
    final selected = index == controller.currentIndex;
    final muted = isDark ? const Color(0xFFCBC4EA) : workspaceMuted;
    const loadRealImage = true;

    return GestureDetector(
      onTap: onTap ?? () => controller.goToSlide(index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: horizontal ? 78 : 108,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252039) : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6B4EFF)
                      : (isDark
                          ? const Color(0xFF312B49)
                          : const Color(0xFFE6E3F4)),
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? const Color(0xFF6B4EFF).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: selected ? 12 : 5,
                    spreadRadius: selected ? 1.5 : 0,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _SlideMiniature(
                slide: slide,
                isDark: isDark,
                loadRealImage: loadRealImage,
                slideIndex: index,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${index + 1}',
              style: TextStyle(
                color:
                    selected ? workspacePurple : muted.withValues(alpha: .72),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkspaceScrollGestureRecognizer extends OneSequenceGestureRecognizer {
  WorkspaceScrollGestureRecognizer({
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onStylusDetected,
  });

  VoidCallback? onStart;
  ValueChanged<double>? onUpdate; // vertical delta Y
  ValueChanged<Velocity>? onEnd;
  VoidCallback? onStylusDetected;

  final Map<int, VelocityTracker> _velocityTrackers = {};
  final Set<int> _touchPointers = {};
  bool _hasStarted = false;
  bool _isRejected = false;
  double? _lastY;

  @override
  void addPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      onStylusDetected?.call();
      _isRejected = true;
      resolve(GestureDisposition.rejected);
      return;
    }

    startTrackingPointer(event.pointer, event.transform);
    _velocityTrackers[event.pointer] = VelocityTracker.withKind(event.kind);
    _touchPointers.add(event.pointer);

    if (_touchPointers.length > 1) {
      // Immediately reject self so that child InteractiveViewer's ScaleGestureRecognizer wins!
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
      final double currentY = event.position.dy;
      if (_lastY != null) {
        final double deltaY = currentY - _lastY!;
        if (!_hasStarted) {
          _hasStarted = true;
          onStart?.call();
        }
        onUpdate?.call(deltaY);
      }
      _lastY = currentY;
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
    _lastY = null;
    _touchPointers.clear();
    _velocityTrackers.clear();
  }

  @override
  String get debugDescription => 'WorkspaceScrollGestureRecognizer';
}

class _InteractiveImageWidget extends StatefulWidget {
  final ImageObject image;
  final bool isSelected;
  final VoidCallback onSelected;
  final ValueChanged<ImageObject> onUpdate;
  final VoidCallback onDelete;
  final SlideWorkspaceController controller;

  const _InteractiveImageWidget({
    required this.image,
    required this.isSelected,
    required this.onSelected,
    required this.onUpdate,
    required this.onDelete,
    required this.controller,
  });

  @override
  State<_InteractiveImageWidget> createState() => _InteractiveImageWidgetState();
}

class _InteractiveImageWidgetState extends State<_InteractiveImageWidget> {
  late double _x;
  late double _y;
  late double _width;
  late double _height;
  bool _isLoadingBytes = false;

  Future<void> _cropImage() async {
    final image = widget.image;
    setState(() {
      _isLoadingBytes = true;
    });
    try {
      Uint8List? bytes;
      if (image.localPath != null) {
        bytes = SlideWorkspaceController.localImageCache[image.localPath!];
        if (bytes == null) {
          final file = File(image.localPath!);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }
      }
      if (bytes == null && image.imageUrl != null) {
        final cachedPath = await ImageCacheService().getOrDownload(image.imageUrl!);
        if (cachedPath != null) {
          bytes = await File(cachedPath).readAsBytes();
        }
      }

      if (bytes != null && mounted) {
        setState(() {
          _isLoadingBytes = false;
        });
        final croppedBytes = await SlideImageCropScreen.show(context, bytes);
        if (croppedBytes != null && mounted) {
          final isExam = !widget.controller.isStudyMode;
          final tempId = 'picked_${DateTime.now().microsecondsSinceEpoch}';

          final docDir = await getApplicationDocumentsDirectory();
          final uploadsDir = Directory('${docDir.path}/workspace_uploads');
          if (!await uploadsDir.exists()) {
            await uploadsDir.create(recursive: true);
          }
          final file = File('${uploadsDir.path}/$tempId.png');
          await file.writeAsBytes(croppedBytes);
          final newLocalPath = file.path;

          SlideWorkspaceController.localImageCache[newLocalPath] = croppedBytes;

          final decodedImage = await decodeImageFromList(croppedBytes);
          final double originalWidth = decodedImage.width.toDouble();
          final double originalHeight = decodedImage.height.toDouble();
          final double newAspectRatio = originalWidth / originalHeight;
          final double newHeight = _width / newAspectRatio;

          setState(() {
            _height = newHeight;
          });

          final updatedImage = image.copyWith(
            localPath: newLocalPath,
            imageUrl: null,
            storagePath: null,
            state: ImageState.local,
            height: newHeight,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );

          widget.controller.mutateObject(widget.controller.currentSlide.id, image.id, isExam, (_) => updatedImage);
          widget.controller.triggerUploadForObject(widget.controller.currentSlide.id, updatedImage, isExam);
          widget.controller.scheduleSave(widget.controller.currentSlide.id);
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingBytes = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load image bytes for cropping')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBytes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _x = widget.image.x;
    _y = widget.image.y;
    _width = widget.image.width;
    _height = widget.image.height;
  }

  @override
  void didUpdateWidget(_InteractiveImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.x != widget.image.x ||
        oldWidget.image.y != widget.image.y ||
        oldWidget.image.width != widget.image.width ||
        oldWidget.image.height != widget.image.height) {
      _x = widget.image.x;
      _y = widget.image.y;
      _width = widget.image.width;
      _height = widget.image.height;
    }
  }

  void _onInteractionEnd() {
    widget.onUpdate(widget.image.copyWith(
      x: _x,
      y: _y,
      width: _width,
      height: _height,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Widget _buildCornerHandle(Alignment alignment, double aspect) {
    return Positioned(
      left: alignment.x == -1 ? 0 : null,
      right: alignment.x == 1 ? 0 : null,
      top: alignment.y == -1 ? 0 : null,
      bottom: alignment.y == 1 ? 0 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          // No-op, just to intercept gesture
        },
        onPanUpdate: (details) {
          setState(() {
            final deltaX = details.delta.dx;

            if (alignment == Alignment.topLeft) {
              final newW = (_width - deltaX).clamp(80.0, _width + _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _height + _y) {
                _x += (_width - newW);
                _y += (_height - newH);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.topRight) {
              final newW = (_width + deltaX).clamp(80.0, _slideCanvasWidth - _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _height + _y) {
                _y += (_height - newH);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.bottomLeft) {
              final newW = (_width - deltaX).clamp(80.0, _width + _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _slideCanvasHeight - _y) {
                _x += (_width - newW);
                _width = newW;
                _height = newH;
              }
            } else if (alignment == Alignment.bottomRight) {
              final newW = (_width + deltaX).clamp(80.0, _slideCanvasWidth - _x);
              final newH = newW / aspect;
              if (newH >= 80.0 && newH <= _slideCanvasHeight - _y) {
                _width = newW;
                _height = newH;
              }
            }
          });
        },
        onPanEnd: (details) => _onInteractionEnd(),
        child: Container(
          width: 72,
          height: 72,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6B4EFF),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final aspect = image.width / image.height;

    Widget imageChild;
    if (image.state == ImageState.local ||
        image.state == ImageState.uploading ||
        image.state == ImageState.uploadFailed) {
      if (!kIsWeb && image.localPath != null && File(image.localPath!).existsSync()) {
        imageChild = Image.file(
          File(image.localPath!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      } else {
        final bytes = image.localPath != null
            ? SlideWorkspaceController.localImageCache[image.localPath!]
            : null;
        if (bytes != null) {
          imageChild = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          );
        } else if (image.imageUrl != null) {
          imageChild = Image.network(
            image.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          );
        } else {
          imageChild = const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          );
        }
      }
    } else {
      imageChild = Image.network(
        image.imageUrl ?? '',
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    // The outer Positioned is padded by 36px on all sides to make sure the
    // 72x72 corner handles are completely within the bounds of this parent
    // Positioned widget. This guarantees Flutter hit-testing registers the taps.
    return Positioned(
      left: _x - 36,
      top: _y - 36,
      width: _width + 72,
      height: _height + 72,
      child: ValueListenableBuilder<SlideStroke?>(
        valueListenable: widget.controller.activeStroke,
        builder: (context, activeStroke, _) => IgnorePointer(
          // Block pointer events only while a stroke is actively being drawn.
          // This lets images be tapped/selected at all other times.
          ignoring: activeStroke != null,
          child: Stack(
            children: [
              // Inner Image Container positioned at offset 36
              Positioned(
                left: 36,
                top: 36,
                width: _width,
                height: _height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSelected,
                  onPanUpdate: (widget.isSelected && image.canMove)
                      ? (details) {
                          setState(() {
                            _x = (_x + details.delta.dx).clamp(0.0, _slideCanvasWidth - _width);
                            _y = (_y + details.delta.dy).clamp(0.0, _slideCanvasHeight - _height);
                          });
                        }
                      : null,
                  onPanEnd: (widget.isSelected && image.canMove)
                      ? (details) {
                          _onInteractionEnd();
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.isSelected ? const Color(0xFF6B4EFF) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(child: imageChild),
                        if (_isLoadingBytes)
                          Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        if (image.state == ImageState.uploading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B4EFF)),
                              ),
                            ),
                          ),
                        if (image.state == ImageState.uploadFailed)
                          Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      final tempId = image.localPath;
                                      if (tempId != null) {
                                        final isExam = !widget.controller.isStudyMode;
                                        const fileName = 'upload_retry.png';
                                        widget.controller.retryUpload(widget.controller.currentSlide.id, tempId, isExam, fileName);
                                      }
                                    },
                                    icon: const Icon(Icons.refresh_rounded, size: 14),
                                    label: const Text('Retry', style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Corner resize handles
              if (widget.isSelected && image.state != ImageState.uploading) ...[
                if (image.canResize) ...[
                  _buildCornerHandle(Alignment.topLeft, aspect),
                  _buildCornerHandle(Alignment.topRight, aspect),
                  _buildCornerHandle(Alignment.bottomLeft, aspect),
                  _buildCornerHandle(Alignment.bottomRight, aspect),
                ],
                // Delete & Crop Pill overlay positioned at offset 36 + margin
                Positioned(
                  left: 44,
                  top: 44,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (image.canDelete) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onDelete,
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.delete_forever_rounded,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _cropImage,
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.crop_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
