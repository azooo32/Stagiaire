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
  final Future<void> Function(SlideEditorResult result)? onSave;

  const SlideEditorDialog({
    super.key,
    this.slide,
    required this.currentSlides,
    required this.isDark,
    this.onSave,
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
  bool _isSaving = false;

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

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'عنوان الشريحة مطلوب',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
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

    final result = SlideEditorResult(
      title: title,
      subtitle: _subtitleController.text.trim(),
      questions: questions,
      imagePath: _imagePath,
      imageBytes: _imageBytes,
      imageFileName: _imageFileName,
      imageContentType: _imageContentType,
      audioPath: _audioPath,
    );

    if (widget.onSave != null) {
      setState(() {
        _isSaving = true;
      });
      try {
        await widget.onSave!(result);
        if (mounted) {
          Navigator.pop(context, result);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'فشل حفظ الشريحة: $e',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.slide != null;
    final isDark = widget.isDark;
    final brandColor = isDark ? const Color(0xFF9E86FF) : const Color(0xFF5B35F5);

    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isEditing ? Icons.edit_note : Icons.add_photo_alternate_outlined,
              color: brandColor,
            ),
            const SizedBox(width: 8),
            Text(
              isEditing ? 'تعديل الشريحة' : 'إضافة شريحة جديدة',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSaving) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brandColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            backgroundColor: brandColor.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'جاري رفع الملفات وحفظ الشريحة... يرجى الانتظار',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الشريحة (Title)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 12),
                if (_subtitleOptions.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _selectedSubtitle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الموضوع الفرعي (Subtitle)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final subtitle in _subtitleOptions)
                        DropdownMenuItem(
                          value: subtitle,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      const DropdownMenuItem(
                        value: _newSubtitleChoice,
                        child: Text(
                          '+ موضوع فرعي جديد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
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
                if (_subtitleOptions.isEmpty || _selectedSubtitle == _newSubtitleChoice) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subtitleController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'اسم الموضوع الفرعي الجديد',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الأسئلة والأجوبة (Q&A)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _isSaving
                          ? null
                          : () => setState(() {
                                _promptControllers.add(TextEditingController());
                                _answerControllers.add(TextEditingController());
                              }),
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'إضافة سؤال',
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
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
                                'سؤال ${idx + 1}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
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
                                  onPressed: _isSaving
                                      ? null
                                      : () {
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
                            enabled: !_isSaving,
                            decoration: const InputDecoration(
                              labelText: 'السؤال',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            minLines: 1,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _answerControllers[idx],
                            enabled: !_isSaving,
                            decoration: const InputDecoration(
                              labelText: 'الإجابة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            minLines: 1,
                            maxLines: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Audio Section
                if ((_audioPath != null && _audioPath != 'clear_audio') ||
                    (_audioPath == null && widget.slide?.audioUrl.isNotEmpty == true)) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: brandColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.audiotrack,
                          size: 20,
                          color: brandColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _audioPath == null
                                ? 'ملف صوتي محفوظ'
                                : _audioPath!.split(RegExp(r'[\\/]+')).last,
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _isSaving
                              ? null
                              : () {
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
                // Image Section
                if (_imageFileName != null || (widget.slide?.imageAsset.isNotEmpty == true && _imagePath != 'clear_image')) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: brandColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.image,
                          size: 20,
                          color: brandColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _imageFileName ?? 'صورة الشريحة الحالية',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _imagePath = 'clear_image';
                                    _imageBytes = null;
                                    _imageFileName = null;
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(
                          _imageFileName ??
                              (widget.slide?.imageAsset.isNotEmpty == true && _imagePath != 'clear_image'
                                  ? 'تغيير الصورة'
                                  : 'إرفاق صورة'),
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _isSaving
                            ? null
                            : () async {
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
                    const SizedBox(width: 8),
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
                                    label: const Text('ملف صوت', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () async {
                                            final messenger = ScaffoldMessenger.of(context);
                                            final picked = await FilePicker.platform.pickFiles(
                                              type: FileType.audio,
                                              withData: true,
                                            );
                                            final file = picked?.files.single;
                                            if (file == null) return;
                                            if (kIsWeb) {
                                              if (mounted) {
                                                messenger.showSnackBar(
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
                                    label: const Text('تسجيل', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () async {
                                            final messenger = ScaffoldMessenger.of(context);
                                            final hasPermission = await _dialogRecorder.hasPermission();
                                            if (!hasPermission) {
                                              if (mounted) {
                                                messenger.showSnackBar(
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
            onPressed: _isSaving ? null : () => Navigator.pop(context, null),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: brandColor),
            child: Text(
              _isSaving ? 'جاري الحفظ...' : 'حفظ الشريحة',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
