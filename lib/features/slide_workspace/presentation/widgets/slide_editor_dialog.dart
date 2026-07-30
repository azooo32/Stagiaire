import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';

import '../../domain/entities/slide_workspace_models.dart';

class SlideEditorResult {
  final String title;
  final String subtitle;
  final List<WorkspaceQuestion> questions;
  final String? imagePath;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String? imageContentType;
  final String? audioPath;

  SlideEditorResult({
    required this.title,
    required this.subtitle,
    required this.questions,
    this.imagePath,
    this.imageBytes,
    this.imageFileName,
    this.imageContentType,
    this.audioPath,
  });
}

class SlideEditorDialog extends StatefulWidget {
  final WorkspaceSlide? slide;
  final List<WorkspaceSlide> currentSlides;
  final bool isDark;

  const SlideEditorDialog({
    super.key,
    this.slide,
    required this.currentSlides,
    required this.isDark,
  });

  @override
  State<SlideEditorDialog> createState() => _SlideEditorDialogState();
}

class _SlideEditorDialogState extends State<SlideEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;

  final List<TextEditingController> _promptControllers = [];
  final List<TextEditingController> _answerControllers = [];

  String? _imagePath;
  Uint8List? _imageBytes;
  String? _imageFileName;
  String? _imageContentType;
  String? _audioPath;

  final List<String> _subtitleOptions = [];
  static const _newSubtitleChoice = '__new_subtitle__';
  late String _selectedSubtitle;

  final _dialogRecorder = AudioRecorder();
  Timer? _recordTimer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _recordDuration = Duration.zero;
  bool _isRecording = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.slide?.title ?? '');
    _subtitleController = TextEditingController(text: widget.slide?.subtitle ?? '');

    if (widget.slide != null && widget.slide!.questions.isNotEmpty) {
      for (var q in widget.slide!.questions) {
        _promptControllers.add(TextEditingController(text: q.prompt));
        _answerControllers.add(TextEditingController(text: q.answer));
      }
    } else {
      _promptControllers.add(TextEditingController());
      _answerControllers.add(TextEditingController());
    }

    // Populate subtitle options
    final seenSubtitles = <String>{};
    for (final item in widget.currentSlides) {
      final subtitle = item.subtitle.trim();
      final key = subtitle.toLowerCase();
      if (subtitle.isNotEmpty && seenSubtitles.add(key)) {
        _subtitleOptions.add(subtitle);
      }
    }

    final initialSubtitle = _subtitleController.text.trim();
    _selectedSubtitle = _subtitleOptions.firstWhere(
      (item) => item.toLowerCase() == initialSubtitle.toLowerCase(),
      orElse: () => _newSubtitleChoice,
    );
  }

  @override
  void dispose() {
    if (_isRecording) {
      try {
        _dialogRecorder.stop();
      } catch (_) {}
    }
    _recordTimer?.cancel();
    _dialogRecorder.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    for (var c in _promptControllers) {
      c.dispose();
    }
    for (var c in _answerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slide title is required.')),
      );
      return;
    }

    final questions = <WorkspaceQuestion>[];
    for (var i = 0; i < _promptControllers.length; i++) {
      final prompt = _promptControllers[i].text.trim();
      final answer = _answerControllers[i].text.trim();
      if (prompt.isNotEmpty) {
        questions.add(WorkspaceQuestion(prompt: prompt, answer: answer));
      }
    }

    Navigator.pop(
      context,
      SlideEditorResult(
        title: title,
        subtitle: _subtitleController.text.trim(),
        questions: questions,
        imagePath: _imagePath,
        imageBytes: _imageBytes,
        imageFileName: _imageFileName,
        imageContentType: _imageContentType,
        audioPath: _audioPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.slide != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit slide' : 'Add slide'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              if (_subtitleOptions.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedSubtitle,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Subtitle'),
                  items: [
                    for (final subtitle in _subtitleOptions)
                      DropdownMenuItem(
                        value: subtitle,
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const DropdownMenuItem(
                      value: _newSubtitleChoice,
                      child: Text('New subtitle'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedSubtitle = value;
                      if (value == _newSubtitleChoice) {
                        _subtitleController.clear();
                      } else {
                        _subtitleController.text = value;
                      }
                    });
                  },
                ),
              if (_subtitleOptions.isEmpty || _selectedSubtitle == _newSubtitleChoice)
                TextField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(labelText: 'Subtitle'),
                ),
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
                    onPressed: () => setState(() {
                      _promptControllers.add(TextEditingController());
                      _answerControllers.add(TextEditingController());
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
                itemCount: _promptControllers.length,
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
                            Text(
                              'Question ${idx + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (_promptControllers.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _promptControllers.removeAt(idx);
                                    _answerControllers.removeAt(idx);
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _promptControllers[idx],
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
                          controller: _answerControllers[idx],
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
                onPressed: () => setState(() {
                  _promptControllers.add(TextEditingController());
                  _answerControllers.add(TextEditingController());
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add Question'),
              ),
              if ((_audioPath != null && _audioPath != 'clear_audio') ||
                  (_audioPath == null && widget.slide?.audioUrl.isNotEmpty == true)) ...[
                const SizedBox(height: 12),
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
                      Icon(
                        Icons.audiotrack,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _audioPath == null
                              ? 'Existing audio file'
                              : _audioPath!.split(RegExp(r'[\\/]+')).last,
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
                          setState(() {
                            _audioPath = 'clear_audio';
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
                        _imageFileName ??
                            (widget.slide?.imageAsset.isNotEmpty == true
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
                        setState(() {
                          _imagePath = kIsWeb ? null : file.path;
                          _imageBytes = file.bytes;
                          _imageFileName = file.name;
                          _imageContentType = file.extension == null
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
                        if (_isRecording) ...[
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
                                  'Rec: ${_formatDuration(_recordDuration)}',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(
                                    _isPaused ? Icons.play_arrow : Icons.pause,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () async {
                                    if (_isPaused) {
                                      await _dialogRecorder.resume();
                                      _stopwatch.start();
                                    } else {
                                      await _dialogRecorder.pause();
                                      _stopwatch.stop();
                                    }
                                    setState(() {
                                      _isPaused = !_isPaused;
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
                                    final path = await _dialogRecorder.stop();
                                    _recordTimer?.cancel();
                                    _stopwatch.stop();
                                    setState(() {
                                      _isRecording = false;
                                      _isPaused = false;
                                      if (path != null) {
                                        _audioPath = path;
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
                                              "Voice upload isn't available in the web preview — use the Android or desktop app.",
                                            ),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    if (file.path == null) return;
                                    setState(() => _audioPath = file.path);
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
                                    final hasPermission = await _dialogRecorder.hasPermission();
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
                                    final outputPath = '${Directory.systemTemp.path}/slide_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
                                    await _dialogRecorder.start(
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
                                    _stopwatch.reset();
                                    _stopwatch.start();
                                    setState(() {
                                      _isRecording = true;
                                      _isPaused = false;
                                      _recordDuration = Duration.zero;
                                    });
                                    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                                      setState(() {
                                        _recordDuration = _stopwatch.elapsed;
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
