import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/models/question.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/audio_cache_service.dart';
import '../../../../core/services/image_cache_service.dart';
import '../../../../core/services/cache_service.dart';
import '../widgets/audio_explanation_player.dart';

class CachedQuestionImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget? loading;
  final Widget? error;

  const CachedQuestionImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.loading,
    this.error,
  });

  @override
  State<CachedQuestionImage> createState() => _CachedQuestionImageState();
}

class _CachedQuestionImageState extends State<CachedQuestionImage> {
  String? _path;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedQuestionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _path = null;
    });
    final path = await ImageCacheService().getOrDownload(widget.url);
    if (!mounted) return;
    setState(() {
      _path = path;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.loading ?? const SizedBox.expand();
    }
    final path = _path;
    if (path == null || path.isEmpty) {
      return widget.error ?? const Icon(Icons.broken_image_outlined);
    }
    if (path.startsWith('data:image')) {
      final commaIndex = path.indexOf(',');
      if (commaIndex > 0) {
        try {
          return Image.memory(
            base64Decode(path.substring(commaIndex + 1)),
            fit: widget.fit,
            errorBuilder: (_, __, ___) {
              return widget.error ?? const Icon(Icons.broken_image_outlined);
            },
          );
        } catch (_) {
          return widget.error ?? const Icon(Icons.broken_image_outlined);
        }
      }
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path, fit: widget.fit, errorBuilder: (_, __, ___) {
        return widget.error ?? const Icon(Icons.broken_image_outlined);
      });
    }
    return Image.file(File(path), fit: widget.fit, errorBuilder: (_, __, ___) {
      return widget.error ?? const Icon(Icons.broken_image_outlined);
    });
  }
}

class QuestionViewerScreen extends StatefulWidget {
  final int initialIndex;
  const QuestionViewerScreen({super.key, this.initialIndex = 0});

  @override
  _QuestionViewerScreenState createState() => _QuestionViewerScreenState();
}

class _QuestionViewerScreenState extends State<QuestionViewerScreen> {
  late int _currentIndex;
  final List<double> _fontSizes = [14.0, 16.0, 18.0, 22.0];
  int _fontSizeIdx = 1; // Default index matches 16.0px text size
  bool _isHighlightMode = false; // Highlight mode toggle
  bool _isEraserMode = false;
  // The current range comes directly from Flutter's SelectableText. We do
  // not derive it from pointer coordinates: RenderParagraph owns hit testing,
  // transforms, viewport changes, bidi layout, and text scaling.
  TextFormatRange? _nativeSelectionRange;
  bool _selectionCommitScheduled = false;

  List<Map<String, dynamic>> _images = [];
  final Map<int, List<Map<String, dynamic>>> _questionImagesCache = {};
  final AudioRecorder _headerAudioRecorder = AudioRecorder();
  Timer? _headerRecordTimer;
  final Stopwatch _headerRecordingStopwatch = Stopwatch();
  bool _isHeaderRecordingAudio = false;
  bool _isHeaderRecordingPaused = false;
  Duration _headerRecordDuration = Duration.zero;
  int? _recordingQuestionId;
  final List<AudioHighlight> _recordingAudioHighlights = <AudioHighlight>[];
  String? _selectedExplanationText;
  int? _activeAudioQuestionId;
  final Set<int> _revealedAudioHighlightIndices = <int>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadImagesForCurrentQuestion());
      _prefetchNearbyQuestionAudiosDeferred();
    });
  }

  void _prefetchNearbyQuestionAudiosDeferred() {
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      final questions = provider.practiceQuestions;
      if (questions.isEmpty || _currentIndex >= questions.length) return;

      final urls = <String?>[
        _audioUrlForQuestion(questions[_currentIndex]),
        if (_currentIndex + 1 < questions.length)
          _audioUrlForQuestion(questions[_currentIndex + 1]),
      ];

      await AudioCacheService().prefetchQuestionAudios(urls, limit: 1);
    });
  }

  void _goToQuestionIndex(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _images = [];
      _activeAudioQuestionId = null;
      _revealedAudioHighlightIndices.clear();
      _nativeSelectionRange = null;
      _selectionCommitScheduled = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadImagesForCurrentQuestion());
      _prefetchNearbyQuestionAudiosDeferred();
    });
  }

  void _updateAudioHighlight(Question question, Duration position) {
    final seconds = position.inMilliseconds / 1000.0;
    final items = question.audioHighlights;
    final revealed = <int>{
      for (var i = 0; i < items.length; i++)
        if (seconds >= items[i].audioTime) i,
    };

    final unchanged = _activeAudioQuestionId == question.id &&
        _revealedAudioHighlightIndices.length == revealed.length &&
        _revealedAudioHighlightIndices.containsAll(revealed);
    if (unchanged) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _activeAudioQuestionId = question.id;
      _revealedAudioHighlightIndices
        ..clear()
        ..addAll(revealed);
    });
  }

  List<AudioHighlight> _revealedAudioHighlightsFor(Question question) {
    if (_activeAudioQuestionId != question.id) return const [];
    return [
      for (var i = 0; i < question.audioHighlights.length; i++)
        if (_revealedAudioHighlightIndices.contains(i))
          question.audioHighlights[i],
    ];
  }

  @override
  void dispose() {
    _headerRecordTimer?.cancel();
    _headerAudioRecorder.dispose();
    super.dispose();
  }

  void _startHeaderRecordTimer() {
    _headerRecordTimer?.cancel();
    _headerRecordTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_isHeaderRecordingAudio || _isHeaderRecordingPaused)
        return;
      setState(() => _headerRecordDuration = _headerRecordingStopwatch.elapsed);
    });
  }

  String _formatHeaderRecordDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Question _recordingTargetQuestion(Question fallback, AppProvider provider) {
    final targetId = _recordingQuestionId;
    if (targetId == null) return fallback;
    for (final question in provider.practiceQuestions) {
      if (question.id == targetId) return question;
    }
    return fallback;
  }

  List<Map<String, dynamic>> _rangesToJson(List<TextFormatRange> ranges) {
    return ranges.map((range) => range.toJson()).toList();
  }

  bool _rangesOverlap(TextFormatRange a, TextFormatRange b) {
    return a.start < b.end && b.start < a.end;
  }

  List<TextFormatRange> _toggleExplanationRange(
    String text,
    List<TextFormatRange> ranges,
    String selectedText,
  ) {
    if (selectedText.trim().isEmpty) return ranges;
    final start = text.indexOf(selectedText);
    if (start < 0) return ranges;
    final end = start + selectedText.length;

    final selectedRange =
        TextFormatRange(start: start, end: end, text: selectedText);
    final alreadyExists = ranges.any((range) =>
        range.start == selectedRange.start &&
        range.end == selectedRange.end &&
        range.text == selectedRange.text);

    final nextRanges = ranges
        .where((range) => alreadyExists
            ? !(range.start == selectedRange.start &&
                range.end == selectedRange.end)
            : !_rangesOverlap(range, selectedRange))
        .toList();

    if (!alreadyExists) {
      nextRanges.add(selectedRange);
      nextRanges.sort((a, b) => a.start.compareTo(b.start));
    }
    return nextRanges;
  }

  Future<void> _applyExplanationFormat(
    Question q,
    AppProvider provider,
    String fieldName,
  ) async {
    final text =
        q.explanation.isNotEmpty ? q.explanation : 'لا يوجد شرح متوفر.';
    final selectedText = _selectedExplanationText;
    if (selectedText == null ||
        selectedText.trim().isEmpty ||
        !text.contains(selectedText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('حدد جزءا من الشرح أولا',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    final currentRanges = fieldName == 'explanation_bold_ranges'
        ? q.explanationBoldRanges
        : q.explanationUnderlineRanges;
    final nextRanges =
        _toggleExplanationRange(text, currentRanges, selectedText);
    final rangesJson = _rangesToJson(nextRanges);
    debugPrint('[ExplanationFormat] saving explanation format');
    final success = await provider.updateQuestionExplanationFormat(
        q.id, fieldName, rangesJson);

    if (!mounted) return;
    if (success) {
      debugPrint('[ExplanationFormat] saved to Supabase');
      setState(() => _selectedExplanationText = null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل حفظ تنسيق الشرح: ${provider.lastSupabaseError ?? 'خطأ غير معروف'}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    }
  }

  Widget _buildExplanationAdminTools(
      Question q, AppProvider provider, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: 'Bold',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 19,
              color: isDark ? AppColors.text : const Color(0xFF1F2937),
              onPressed: () => _applyExplanationFormat(
                  q, provider, 'explanation_bold_ranges'),
              icon: const Icon(Icons.format_bold_rounded),
            ),
          ),
          Tooltip(
            message: 'Red underline',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 19,
              color: const Color(0xFFEF4444),
              onPressed: () => _applyExplanationFormat(
                  q, provider, 'explanation_underline_ranges'),
              icon: const Icon(Icons.format_underlined_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleHeaderRecording(Question q, AppProvider provider) async {
    if (_isHeaderRecordingAudio) {
      await _stopAndUploadHeaderRecording(q, provider);
      return;
    }

    try {
      final hasPermission = await _headerAudioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى السماح باستخدام الميكروفون للتسجيل',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        );
        return;
      }

      final outputPath =
          '${Directory.systemTemp.path}/question_${q.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _headerAudioRecorder.start(
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

      if (!mounted) return;
      setState(() {
        _isHeaderRecordingAudio = true;
        _isHeaderRecordingPaused = false;
        _headerRecordingStopwatch
          ..reset()
          ..start();
        _headerRecordDuration = Duration.zero;
        _recordingQuestionId = q.id;
        _recordingAudioHighlights.clear();
      });
      _startHeaderRecordTimer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر بدء التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _toggleHeaderRecordPause() async {
    if (!_isHeaderRecordingAudio) return;
    try {
      if (_isHeaderRecordingPaused) {
        await _headerAudioRecorder.resume();
        _headerRecordingStopwatch.start();
      } else {
        await _headerAudioRecorder.pause();
        _headerRecordingStopwatch.stop();
      }
      if (!mounted) return;
      setState(() {
        _isHeaderRecordingPaused = !_isHeaderRecordingPaused;
        _headerRecordDuration = _headerRecordingStopwatch.elapsed;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر تغيير حالة التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _stopAndUploadHeaderRecording(
      Question q, AppProvider provider) async {
    try {
      final recordedPath = await _headerAudioRecorder.stop();
      _headerRecordTimer?.cancel();
      _headerRecordingStopwatch.stop();

      if (mounted) {
        setState(() {
          _isHeaderRecordingAudio = false;
          _isHeaderRecordingPaused = false;
          _headerRecordDuration = _headerRecordingStopwatch.elapsed;
        });
      }

      if (recordedPath == null || recordedPath.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لم يتم حفظ التسجيل',
                  style: TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }

      final targetQuestion = _recordingTargetQuestion(q, provider);
      final uploadedUrl = await SupabaseService().uploadFile(
        'question-audios',
        recordedPath,
        folder: 'questions',
      );

      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('فشل رفع التسجيل',
                  style: TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }

      final previousAudioUrl = targetQuestion.audioUrl?.trim();
      if (previousAudioUrl != null && previousAudioUrl.isNotEmpty) {
        await SupabaseService()
            .deleteStorageFile('question-audios', previousAudioUrl);
      }

      final success = await provider.updateQuestion(targetQuestion.id, {
        'audio_url': uploadedUrl,
        'audio_duration_seconds': _headerRecordDuration.inSeconds > 0
            ? _headerRecordDuration.inSeconds
            : null,
        'audio_highlights': _recordingAudioHighlights
            .map((highlight) => highlight.toJson())
            .toList(),
      });

      if (!mounted) return;
      setState(() {
        _recordingQuestionId = null;
        _headerRecordDuration = Duration.zero;
        _headerRecordingStopwatch.reset();
        _recordingAudioHighlights.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم رفع التسجيل وربطه بالسؤال'
                : 'تم رفع التسجيل لكن فشل تحديث السؤال',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    } catch (e) {
      _headerRecordTimer?.cancel();
      _headerRecordingStopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isHeaderRecordingAudio = false;
        _isHeaderRecordingPaused = false;
        _recordingQuestionId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر حفظ التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  String _questionImagesCacheKey(int questionId) =>
      'question_images_$questionId';

  List<Map<String, dynamic>> _cachedQuestionImages(int questionId) {
    final cached =
        CacheService().getCache(_questionImagesCacheKey(questionId)) ??
            CacheService()
                .getCacheAllowExpired(_questionImagesCacheKey(questionId));
    if (cached is List) {
      return cached
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _saveQuestionImagesCache(
    int questionId,
    List<Map<String, dynamic>> images,
  ) async {
    await CacheService().setCache(
      _questionImagesCacheKey(questionId),
      images,
      const Duration(days: 36500),
    );
  }

  void _prefetchQuestionImages(List<Map<String, dynamic>> images) {
    for (final image in images) {
      final url = _extractQuestionImageUrl(image);
      if (url.startsWith('http://') || url.startsWith('https://')) {
        unawaited(ImageCacheService().getOrDownload(url));
      }
    }
  }

  Future<void> _loadImagesForCurrentQuestion() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final questions = provider.practiceQuestions;
    if (questions.isEmpty || _currentIndex >= questions.length) return;

    final q = questions[_currentIndex];
    final memoryCachedImages = _questionImagesCache[q.id];
    final persistentCachedImages =
        memoryCachedImages ?? _cachedQuestionImages(q.id);

    if (persistentCachedImages.isNotEmpty) {
      _questionImagesCache[q.id] = persistentCachedImages;
      setState(() {
        _images = persistentCachedImages;
      });
    } else {
      setState(() {
        _images = [];
      });
    }

    try {
      final supabase = SupabaseService();
      final List<Map<String, dynamic>> imagesData =
          await supabase.getQuestionImages(q.id);
      _questionImagesCache[q.id] = imagesData;
      await _saveQuestionImagesCache(q.id, imagesData);
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _prefetchQuestionImages(imagesData);
      });
      if (mounted &&
          _currentIndex < questions.length &&
          questions[_currentIndex].id == q.id) {
        setState(() {
          _images = imagesData;
        });
      }
    } catch (e) {
      print('Error loading explanation images: $e');
      if (mounted &&
          _currentIndex < questions.length &&
          questions[_currentIndex].id == q.id) {
        setState(() {});
      }
    }
  }

  String _audioUrlForQuestion(Question q) {
    final rawUrl = q.audioUrl?.trim() ?? '';
    if (rawUrl.isEmpty) return '';
    final version = q.updatedAt?.trim();
    if (version == null || version.isEmpty) return rawUrl;
    final separator = rawUrl.contains('?') ? '&' : '?';
    return '$rawUrl${separator}v=${Uri.encodeComponent(version)}';
  }

  String _extractQuestionImageUrl(Map<String, dynamic> imageRecord) {
    const keys = [
      'url',
      'image_url',
      'public_url',
      'file_url',
      'signed_url',
      'src',
      'path',
      'file_path',
      'storage_path',
      'image_path',
      'file_name',
      'filename',
    ];

    String normalizeImageValue(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return '';
      if (value.startsWith('http://') ||
          value.startsWith('https://') ||
          value.startsWith('data:image') ||
          value.startsWith('blob:')) {
        return value;
      }

      var storagePath = value.replaceFirst(RegExp(r'^/+'), '');
      const bucketPrefix = 'question-images/';
      final bucketIndex = storagePath.indexOf(bucketPrefix);
      if (bucketIndex >= 0) {
        storagePath = storagePath.substring(bucketIndex + bucketPrefix.length);
      }

      if (storagePath.isEmpty) return '';
      return SupabaseService()
          .client
          .storage
          .from('question-images')
          .getPublicUrl(storagePath);
    }

    String findUrl(Map<String, dynamic> record) {
      for (final key in keys) {
        final value = record[key]?.toString();
        if (value == null) continue;
        final normalized = normalizeImageValue(value);
        if (normalized.isNotEmpty) return normalized;
      }
      return '';
    }

    final details = imageRecord['question_images'];
    if (details is Map<String, dynamic>) {
      final nestedUrl = findUrl(details);
      if (nestedUrl.isNotEmpty) return nestedUrl;
    }

    return findUrl(imageRecord);
  }

  Future<void> _downloadImage(String url) async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري تنزيل الصورة...',
              style: TextStyle(fontFamily: 'Cairo')),
          duration: Duration(seconds: 1),
        ),
      );

      final localPath = await ImageCacheService().getOrDownload(url);
      if (localPath == null || localPath.isEmpty) {
        throw Exception('تعذر تحميل ملف الصورة');
      }

      List<int> bytes;
      if (localPath.startsWith('data:image')) {
        final commaIndex = localPath.indexOf(',');
        bytes = base64Decode(localPath.substring(commaIndex + 1));
      } else {
        final file = File(localPath);
        if (!await file.exists()) {
          throw Exception('ملف الصورة غير موجود');
        }
        bytes = await file.readAsBytes();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = url.toLowerCase().contains('.png') ? 'png' : 'jpg';
      final filename = 'question_image_$timestamp.$extension';

      String? savedPath;

      try {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ الصورة في الجهاز',
          fileName: filename,
          bytes: Uint8List.fromList(bytes),
        );
      } catch (_) {}

      if (savedPath == null && !kIsWeb) {
        Directory? dir;
        if (defaultTargetPlatform == TargetPlatform.android) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            dir = Directory('/storage/emulated/0/Pictures');
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows) {
          dir = await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
        }

        if (dir != null && await dir.exists()) {
          final destFile = File('${dir.path}/$filename');
          await destFile.writeAsBytes(bytes);
          savedPath = destFile.path;
        }
      }

      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الصورة بنجاح في الاستوديو / التنزيلات 📥',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء حفظ الصورة',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الصورة: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showEnlargedImageDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CachedQuestionImage(
                        url: url,
                        fit: BoxFit.contain,
                        loading: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        error: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        tooltip: 'تنزيل الصورة في الاستوديو',
                        onPressed: () => _downloadImage(url),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onAnswerSelected(Question q, int index, AppProvider provider) {
    if (q.isSolved || provider.isAnswersRevealed) return;

    provider.answerQuestion(q, index);
  }

  void _showQuestionsBottomSheet(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final questions = provider.practiceQuestions;
    final isDark = provider.isDarkTheme;
    final sheetColor = isDark ? AppColors.surface : Colors.white;
    final itemColor = isDark ? AppColors.surface2 : Colors.white;
    final selectedColor = isDark ? AppColors.surface3 : const Color(0xFFF3F4FF);
    final borderColor = isDark ? AppColors.border : const Color(0xFFF1F5F9);
    final textColor = isDark ? AppColors.text : const Color(0xFF191C1D);
    final mutedColor = isDark ? AppColors.textDim : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
                return Container(
                  decoration: BoxDecoration(
                    color: sheetColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.borderBright
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 40),
                            Expanded(
                              child: Text(
                                'جميع الأسئلة (${questions.length})',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: mutedColor),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: questions.length,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final question = questions[index];
                            final isCurrent = index == _currentIndex;
                            final isFavorite =
                                provider.favorites.contains(question.id);

                            final isSolvedVisually =
                                question.isSolved || provider.isAnswersRevealed;
                            final ansVisually = question.userAnswer ??
                                (provider.isAnswersRevealed
                                    ? question.correct
                                    : null);
                            final isCorrect = isSolvedVisually &&
                                ansVisually != null &&
                                ansVisually == question.correct;
                            final isIncorrect = isSolvedVisually &&
                                ansVisually != null &&
                                ansVisually != question.correct;

                            final Color circleColor = isCorrect
                                ? const Color(0xFF10B981)
                                : isIncorrect
                                    ? const Color(0xFFEF4444)
                                    : isCurrent
                                        ? const Color(0xFF4F46E5)
                                        : itemColor;
                            final Color circleTextColor =
                                (isCorrect || isIncorrect || isCurrent)
                                    ? Colors.white
                                    : mutedColor;

                            return InkWell(
                              onTap: () {
                                _goToQuestionIndex(index);
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? selectedColor
                                      : Colors.transparent,
                                  border: Border(
                                      bottom: BorderSide(
                                          color: borderColor, width: 1)),
                                ),
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: circleColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: (isCorrect ||
                                                    isIncorrect ||
                                                    isCurrent)
                                                ? Colors.transparent
                                                : (isDark
                                                    ? AppColors.borderBright
                                                    : const Color(0xFFCBD5E1)),
                                            width: 1.5,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            color: circleTextColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              backgroundColor: sheetColor,
                                              title: Text(
                                                'السؤال ${index + 1}',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontWeight: FontWeight.bold,
                                                  color: textColor,
                                                ),
                                                textAlign: TextAlign.right,
                                              ),
                                              content: SingleChildScrollView(
                                                child: Text(
                                                  question.text,
                                                  style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 15,
                                                    height: 1.5,
                                                    fontFamily: 'Inter',
                                                  ),
                                                  textAlign: TextAlign.left,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('إغلاق',
                                                      style: TextStyle(
                                                          fontFamily: 'Cairo')),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        child: Icon(Icons.chevron_right,
                                            color: mutedColor, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          question.text,
                                          style: TextStyle(
                                            color: isCurrent
                                                ? textColor
                                                : mutedColor,
                                            fontWeight: isCurrent
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            fontSize: 13,
                                            fontFamily: 'Inter',
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.left,
                                          textDirection: TextDirection.ltr,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(
                                          isFavorite
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          color: isFavorite
                                              ? const Color(0xFF4F46E5)
                                              : mutedColor,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          setSheetState(() {});
                                          await provider
                                              .toggleFavorite(question.id);
                                          setSheetState(() {});
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final questions = provider.practiceQuestions;
    final isDark = provider.isDarkTheme;
    final pageBg = isDark ? AppColors.bg : const Color(0xFFF8F9FE);
    final surfaceColor = isDark ? AppColors.surface : Colors.white;
    final surfaceAltColor =
        isDark ? AppColors.surface2 : const Color(0xFFF8FAFC);
    final borderColor = isDark ? AppColors.border : const Color(0xFFE2E8F0);
    final textColor = isDark ? AppColors.text : const Color(0xFF191C1D);
    final mutedColor = isDark ? AppColors.textDim : const Color(0xFF64748B);

    if (questions.isEmpty) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: Text(
            'لا توجد أسئلة متوفرة حالياً.',
            style:
                TextStyle(fontFamily: 'Cairo', fontSize: 16, color: textColor),
          ),
        ),
      );
    }

    final q = questions[_currentIndex];
    final bool isSolved = q.isSolved || provider.isAnswersRevealed;
    final int? userAnswer =
        q.userAnswer ?? (provider.isAnswersRevealed ? q.correct : null);
    final double fontSize = _fontSizes[_fontSizeIdx];
    // Single source of truth for the question body's text alignment. The
    // highlight brush's hit-testing painter and the actually-displayed
    // text widget both read from this ONE variable (passed through below),
    // so they can never drift apart no matter what alignment is used
    // (right, left, center, or justify) — previously each spot hardcoded
    // its own literal, and if they ever disagreed, taps would land on the
    // wrong word.
    const TextAlign questionTextAlign = TextAlign.justify;
    // Question content is authored primarily in LTR form. Keep its base
    // direction LTR so the question is not forced to start on the right;
    // Flutter still lays out embedded Arabic runs correctly via bidi text.
    const TextDirection questionTextDirection = TextDirection.ltr;
    final int totalOptions = q.options.length;
    final List<String> highlights = provider.getQuestionHighlights(q.id);
    final revealedAudioHighlights = _revealedAudioHighlightsFor(q);
    final recordingAudioHighlights =
        _isHeaderRecordingAudio && _recordingQuestionId == q.id
            ? _recordingAudioHighlights
            : const <AudioHighlight>[];
    final questionHighlights = <String>[
      ...highlights,
      for (final highlight in revealedAudioHighlights)
        if (highlight.elementType == 'question')
          _audioHighlightRangeToken(highlight, q.text),
      for (final highlight in recordingAudioHighlights)
        _audioHighlightRangeToken(highlight, q.text),
    ];

    // Real distribution percentages from Supabase/provider
    final List<int> optionPcts = List.generate(totalOptions, (index) {
      final stat = q.answersDistribution[index];
      return stat?.percent.round() ?? 0;
    });

    return Scaffold(
      backgroundColor: isDark ? AppColors.indigo : const Color(0xFF5B3EEF),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // ─── Premium Two-Row Header ───
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                      : const [Color(0xFF7B5EFF), Color(0xFF5B3EEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16.0,
                MediaQuery.of(context).padding.top + 8.0,
                16.0,
                12.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Back Button & Title
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          provider.viewMode == 'chapter'
                              ? (q.topic ?? '')
                              : (q.subTopic ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(
                          width: 24), // Spacer to balance back button
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Tools Actions (LTR) & Source Chip
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Tools Icons
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _fontSizeIdx > 0
                                  ? () => setState(() => _fontSizeIdx--)
                                  : null,
                              child: Opacity(
                                opacity: _fontSizeIdx > 0 ? 1.0 : 0.4,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.zoom_out,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _fontSizeIdx < _fontSizes.length - 1
                                  ? () => setState(() => _fontSizeIdx++)
                                  : null,
                              child: Opacity(
                                opacity: _fontSizeIdx < _fontSizes.length - 1
                                    ? 1.0
                                    : 0.4,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.zoom_in,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isHighlightMode = !_isHighlightMode;
                                  if (_isHighlightMode) {
                                    _isEraserMode = false;
                                  }
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _isHighlightMode
                                          ? 'تم تفعيل وضع التظليل'
                                          : 'تم إلغاء وضع التظليل',
                                      style:
                                          const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    duration: const Duration(milliseconds: 800),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 12.0),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _isHighlightMode
                                      ? const Color(0xFFF59E0B)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isHighlightMode
                                        ? const Color(0xFFF59E0B)
                                        : Colors.white.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.border_color,
                                  color: _isHighlightMode
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.9),
                                  size: 16,
                                ),
                              ),
                            ),
                            // Touch eraser: removes only the highlight under the finger.
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isEraserMode = !_isEraserMode;
                                  if (_isEraserMode) {
                                    _isHighlightMode = false;
                                  }
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _isEraserMode
                                          ? 'الممحاة مفعلة: المس التظليل لحذفه'
                                          : 'تم إلغاء وضع الممحاة',
                                      style:
                                          const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    duration: const Duration(milliseconds: 800),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 12.0),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _isEraserMode
                                      ? const Color(0xFFEF4444)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isEraserMode
                                        ? const Color(0xFFEF4444)
                                        : Colors.white.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: FaIcon(
                                    FontAwesomeIcons.eraser,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                            // Bookmark Button (Save icon instead of Heart, placed after Eraser)
                            GestureDetector(
                              onTap: () {
                                provider.toggleFavorite(q.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: Icon(
                                  provider.favorites.contains(q.id)
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: provider.favorites.contains(q.id)
                                      ? const Color(0xFFF59E0B)
                                      : Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            if (provider.isAdminOrOwner) ...[
                              if (_isHeaderRecordingAudio) ...[
                                Container(
                                  margin: const EdgeInsets.only(right: 10.0),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.36),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.24)),
                                  ),
                                  child: Text(
                                    _formatHeaderRecordDuration(
                                        _headerRecordDuration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _toggleHeaderRecordPause,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12.0),
                                    child: Icon(
                                      _isHeaderRecordingPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      color: Colors.white,
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ],
                              GestureDetector(
                                onTap: () =>
                                    _toggleHeaderRecording(q, provider),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Icon(
                                    _isHeaderRecordingAudio
                                        ? Icons.stop_circle_rounded
                                        : Icons.mic_rounded,
                                    color: _isHeaderRecordingAudio
                                        ? const Color(0xFFFFD6D6)
                                        : Colors.white,
                                    size: 21,
                                  ),
                                ),
                              ),
                              // Edit Button
                              GestureDetector(
                                onTap: () =>
                                    _showEditQuestionDialog(q, provider),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.edit,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                              // Delete Button
                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('حذف السؤال',
                                          style:
                                              TextStyle(fontFamily: 'Cairo')),
                                      content: const Text(
                                          'هل أنت متأكد من حذف هذا السؤال؟\nهذا الإجراء لا يمكن التراجع عنه.',
                                          style:
                                              TextStyle(fontFamily: 'Cairo')),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('إلغاء',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo')),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            final success = await provider
                                                .deleteQuestion(q.id);
                                            if (success) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        '🗑 تم حذف السؤال بنجاح',
                                                        style: TextStyle(
                                                            fontFamily:
                                                                'Cairo'))),
                                              );
                                              if (provider
                                                  .practiceQuestions.isEmpty) {
                                                Navigator.pop(context);
                                              } else {
                                                setState(() {
                                                  if (_currentIndex >=
                                                      provider.practiceQuestions
                                                          .length) {
                                                    _currentIndex = provider
                                                            .practiceQuestions
                                                            .length -
                                                        1;
                                                  }
                                                });
                                                _loadImagesForCurrentQuestion();
                                              }
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'فشل حذف السؤال',
                                                        style: TextStyle(
                                                            fontFamily:
                                                                'Cairo'))),
                                              );
                                            }
                                          },
                                          child: const Text('حذف',
                                              style: TextStyle(
                                                  color: Colors.red,
                                                  fontFamily: 'Cairo')),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Icon(Icons.delete,
                                    color: Colors.white, size: 20),
                              ),
                            ],
                          ],
                        ),
                        // Source Chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 110),
                                child: Text(
                                  q.ref?.toUpperCase() ?? 'UWORLD',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ─── Inner White Card Content (Sheet Metaphor - Edge-to-Edge) ───
            Expanded(
              child: Container(
                margin: EdgeInsets.zero, // Edge-to-Edge matching request
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: TextSelectionThemeData(
                        selectionColor: _isHighlightMode
                            ? const Color(0xFFFEF08A).withValues(alpha: 0.8)
                            : _isEraserMode
                                ? const Color(0xFFFCA5A5).withValues(alpha: 0.7)
                                : Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(
                          left: 12, right: 12, top: 10, bottom: 20),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomPaint(
                                painter: _QuestionGlowPainter(
                                  color: const Color(0xFF6B4EFF).withValues(
                                    alpha: isDark ? 0.42 : 0.36,
                                  ),
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1A1828)
                                        : const Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF8B7CFF)
                                              .withValues(alpha: 0.42)
                                          : const Color(0xFF6B4EFF)
                                              .withValues(alpha: 0.36),
                                      width: 1,
                                    ),
                                  ),
                                  child: _isHighlightMode || _isEraserMode
                                      ? Listener(
                                          // SelectableText performs the only
                                          // hit test. This listener only
                                          // commits its native selection when
                                          // the gesture ends; it never maps a
                                          // pointer position into text.
                                          onPointerDown: (_) =>
                                              _nativeSelectionRange = null,
                                          onPointerUp: (_) =>
                                              _scheduleNativeSelectionCommit(
                                            questionId: q.id,
                                            text: q.text,
                                            highlights: highlights,
                                          ),
                                          onPointerCancel: (_) =>
                                              _nativeSelectionRange = null,
                                          child: _buildRichTextWithHighlights(
                                            q.text,
                                            questionHighlights,
                                            fontSize,
                                            textColor: textColor,
                                            textAlign: questionTextAlign,
                                            textDirection:
                                                questionTextDirection,
                                            onSelectionChanged:
                                                _recordNativeSelection,
                                          ),
                                        )
                                      : SelectionArea(
                                          child: _buildRichTextWithHighlights(
                                            q.text,
                                            questionHighlights,
                                            fontSize,
                                            textColor: textColor,
                                            textAlign: questionTextAlign,
                                            textDirection:
                                                questionTextDirection,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Options List
                              Column(
                                children: List.generate(totalOptions, (index) {
                                  final String optText = q.options[index];
                                  final String letter =
                                      String.fromCharCode(65 + index);
                                  final int pctVal = optionPcts[index];

                                  // Answer status colors
                                  bool isCorrect = false;
                                  bool isIncorrect = false;

                                  if (isSolved) {
                                    if (index == q.correct) {
                                      isCorrect = true;
                                    } else if (index == userAnswer) {
                                      isIncorrect = true;
                                    }
                                  }

                                  Color optionBg =
                                      surfaceAltColor; // Default slightly darker background
                                  Color optionBorder = borderColor;
                                  Color optionTextColor = textColor;
                                  Color barColor = isDark
                                      ? AppColors.textDim
                                      : const Color(0xFF94A3B8);

                                  if (isCorrect) {
                                    optionBg = isDark
                                        ? const Color(0xFF123526)
                                        : const Color(0xFFECFDF5);
                                    optionBorder = isDark
                                        ? const Color(0xFF5EE9A8)
                                        : const Color(0xFF10B981);
                                    optionTextColor = isDark
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFF047857);
                                    barColor = isDark
                                        ? const Color(0xFF5EE9A8)
                                        : const Color(0xFF10B981);
                                  } else if (isIncorrect) {
                                    optionBg = isDark
                                        ? const Color(0xFF3A161A)
                                        : const Color(0xFFFEF2F2);
                                    optionBorder = isDark
                                        ? const Color(0xFFFF8A8A)
                                        : const Color(0xFFEF4444);
                                    optionTextColor = isDark
                                        ? const Color(0xFFFFE4E6)
                                        : const Color(0xFFB91C1C);
                                    barColor = isDark
                                        ? const Color(0xFFFF8A8A)
                                        : const Color(0xFFEF4444);
                                  } else if (isSolved) {
                                    optionBg =
                                        surfaceAltColor; // Keep slightly darker for solved but other options
                                    optionBorder = borderColor;
                                  }

                                  return GestureDetector(
                                    onTap: () =>
                                        _onAnswerSelected(q, index, provider),
                                    behavior: HitTestBehavior.opaque,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: optionBg,
                                            border: Border.all(
                                              color: optionBorder,
                                              width: isCorrect ? 2.0 : 1.0,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            boxShadow: isCorrect
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(
                                                              0xFF10B981)
                                                          .withValues(
                                                              alpha: 0.06),
                                                      blurRadius: 4,
                                                      offset:
                                                          const Offset(0, 2),
                                                    )
                                                  ]
                                                : null,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Stack(
                                            children: [
                                              // Full-width background progress overlay (behind text)
                                              if (isSolved)
                                                Positioned(
                                                  left: 0,
                                                  top: 0,
                                                  bottom: 0,
                                                  width: constraints.maxWidth *
                                                      (pctVal / 100.0),
                                                  child: Container(
                                                    color: barColor.withValues(
                                                        alpha: 0.018),
                                                  ),
                                                ),

                                              // Content Row (LTR)
                                              Directionality(
                                                textDirection:
                                                    TextDirection.ltr,
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16.0,
                                                      vertical: 12.0),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center, // Center vertically
                                                    children: [
                                                      // Left side: Letter + Option Text
                                                      Expanded(
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center, // Center vertically
                                                          children: [
                                                            // Circular Container for Option Letter
                                                            Container(
                                                              width: 26,
                                                              height: 26,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: isCorrect
                                                                    ? const Color(
                                                                        0xFF10B981)
                                                                    : (isIncorrect
                                                                        ? const Color(
                                                                            0xFFEF4444)
                                                                        : (isSolved
                                                                            ? const Color(0xFF94A3B8) // Muted slate grey
                                                                            : const Color(0xFF4F46E5))), // Purple/Indigo
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              child: Text(
                                                                letter,
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .white, // White letter text
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                  fontFamily:
                                                                      'Inter',
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 12),
                                                            Expanded(
                                                              child:
                                                                  _buildRichTextWithHighlights(
                                                                optText,
                                                                <String>[
                                                                  ...provider
                                                                      .getQuestionHighlights(
                                                                    q.id,
                                                                    elementType:
                                                                        'option',
                                                                    optionIndex:
                                                                        index,
                                                                  ),
                                                                  for (final highlight
                                                                      in revealedAudioHighlights)
                                                                    if (highlight.elementType ==
                                                                            'option' &&
                                                                        highlight.optionIndex ==
                                                                            index)
                                                                      _audioHighlightRangeToken(
                                                                        highlight,
                                                                        optText,
                                                                      ),
                                                                ],
                                                                fontSize - 1,
                                                                textColor:
                                                                    optionTextColor,
                                                                isSelectable:
                                                                    false,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Right side: Percentage + Icon
                                                      if (isSolved) ...[
                                                        const SizedBox(
                                                            width: 12),
                                                        Text(
                                                          '$pctVal%',
                                                          style: TextStyle(
                                                            color: barColor
                                                                .withValues(
                                                                    alpha:
                                                                        0.32),
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }),
                              ),

                              // Explanation Section
                              if (isSolved) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.surface2
                                        : const Color(0xFFECFDF5)
                                            .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: isDark
                                            ? AppColors.borderBright
                                            : const Color(0xFF10B981)
                                                .withValues(alpha: 0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_audioUrlForQuestion(q)
                                          .isNotEmpty) ...[
                                        AudioExplanationPlayer(
                                          audioUrl: _audioUrlForQuestion(q),
                                          questionId: q.id,
                                          initialDurationSeconds:
                                              q.audioDurationSeconds,
                                          onDurationDiscovered: (seconds) =>
                                              provider.updateQuestion(q.id, {
                                            'audio_duration_seconds': seconds
                                          }),
                                          onPositionChanged: (position) =>
                                              _updateAudioHighlight(
                                                  q, position),
                                        ),
                                        const SizedBox(height: 8),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: isDark
                                              ? AppColors.borderBright
                                              : const Color(
                                                  0xFFD1FAE5), // Soft green separator line
                                        ),
                                        const SizedBox(height: 12),
                                      ],

                                      if (provider.isAdminOrOwner)
                                        _buildExplanationAdminTools(
                                            q, provider, isDark),

                                      // LTR Explanation text
                                      _buildFormattedExplanation(
                                        q.explanation.isNotEmpty
                                            ? q.explanation
                                            : 'لا يوجد شرح متوفر.',
                                        fontSize,
                                        textColor: textColor,
                                        mutedColor: mutedColor,
                                        boldRanges: q.explanationBoldRanges,
                                        underlineRanges:
                                            q.explanationUnderlineRanges,
                                      ),
                                      if (_images.any((img) =>
                                          _extractQuestionImageUrl(img)
                                              .isNotEmpty)) ...[
                                        const SizedBox(height: 16),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final visibleImages = _images
                                                .where((img) =>
                                                    _extractQuestionImageUrl(img)
                                                        .isNotEmpty)
                                                .toList();

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                ...visibleImages.map((img) {
                                                  final url =
                                                      _extractQuestionImageUrl(
                                                          img);
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 12.0),
                                                    child: GestureDetector(
                                                      onTap: () =>
                                                          _showEnlargedImageDialog(
                                                              context, url),
                                                      child: Container(
                                                        width: double.infinity,
                                                        constraints:
                                                            BoxConstraints(
                                                          maxHeight:
                                                              MediaQuery.of(
                                                                      context)
                                                                  .size
                                                                  .height *
                                                              0.65,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isDark
                                                              ? AppColors
                                                                  .surface2
                                                              : const Color(
                                                                  0xFFF8FAFC),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          border: Border.all(
                                                              color:
                                                                  borderColor),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.black
                                                                  .withValues(
                                                                      alpha: isDark
                                                                          ? 0.2
                                                                          : 0.04),
                                                              blurRadius: 6,
                                                              offset:
                                                                  const Offset(
                                                                      0, 2),
                                                            ),
                                                          ],
                                                        ),
                                                        clipBehavior:
                                                            Clip.antiAlias,
                                                        child:
                                                            CachedQuestionImage(
                                                          url: url,
                                                          fit: BoxFit.contain,
                                                          loading:
                                                              const SizedBox(
                                                            height: 180,
                                                            child: Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2),
                                                            ),
                                                          ),
                                                          error: Icon(
                                                            Icons
                                                                .broken_image_outlined,
                                                            color: mutedColor,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.touch_app,
                                                        size: 14,
                                                        color: mutedColor),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'اضغط لتكبير الصورة وتنزيلها',
                                                      style: TextStyle(
                                                        color: mutedColor,
                                                        fontSize: 12,
                                                        fontFamily: 'Cairo',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ─── Question Navigation Bottom Bar (Slimmer Footer) ───
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(
                  top: BorderSide(
                    color: borderColor,
                    width: 1,
                  ),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                14,
                4,
                14,
                4 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Next button (renders on the right in RTL)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _currentIndex < questions.length - 1
                          ? LinearGradient(
                              colors: isDark
                                  ? const [Color(0xFF6047D6), Color(0xFF4930B6)]
                                  : const [
                                      Color(0xFF7B5EFF),
                                      Color(0xFF5B3EEF)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [
                                Colors.grey.shade200,
                                Colors.grey.shade200
                              ],
                            ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _currentIndex < questions.length - 1
                          ? [
                              BoxShadow(
                                color: (isDark
                                        ? const Color(0xFF4930B6)
                                        : const Color(0xFF5B3EEF))
                                    .withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: ElevatedButton(
                      onPressed: _currentIndex < questions.length - 1
                          ? () {
                              _goToQuestionIndex(_currentIndex + 1);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        disabledForegroundColor: Colors.grey.shade400,
                        disabledBackgroundColor: Colors.transparent,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size(90, 30), // Shorter and slimmer
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.ltr,
                        children: [
                          Text(
                            'التالي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_left, size: 15),
                        ],
                      ),
                    ),
                  ),

                  // Clickable Progress Pill
                  InkWell(
                    onTap: () => _showQuestionsBottomSheet(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: surfaceAltColor,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: borderColor), // Slate 200 border
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.format_list_bulleted,
                            color: Color(0xFF3525CD),
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_currentIndex + 1} من ${questions.length}',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Previous button (renders on the left in RTL)
                  ElevatedButton(
                    onPressed: _currentIndex > 0
                        ? () {
                            _goToQuestionIndex(_currentIndex - 1);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      foregroundColor:
                          isDark ? AppColors.text : const Color(0xFF3525CD),
                      backgroundColor:
                          isDark ? AppColors.surface2 : const Color(0xFFE2DFFF),
                      disabledForegroundColor: Colors.grey.shade400,
                      disabledBackgroundColor: Colors.grey.shade200,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(90, 30), // Shorter and slimmer
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      textDirection: TextDirection.ltr,
                      children: [
                        Icon(Icons.chevron_right, size: 15),
                        SizedBox(width: 4),
                        Text(
                          'السابق',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableExplanationText(
    TextSpan span, {
    TextAlign textAlign = TextAlign.left,
  }) {
    return SelectableText.rich(
      span,
      textAlign: textAlign,
      onSelectionChanged: (selection, cause) {
        if (selection.isCollapsed) return;
        final plainText = span.toPlainText();
        final selectedText = selection.textInside(plainText).trim();
        if (selectedText.isNotEmpty) {
          _selectedExplanationText = selectedText;
        }
      },
    );
  }

  Widget _buildFormattedExplanation(String text, double baseFontSize,
      {Color textColor = const Color(0xFF191C1D),
      Color mutedColor = const Color(0xFF64748B),
      List<TextFormatRange> boldRanges = const [],
      List<TextFormatRange> underlineRanges = const []}) {
    if (text.isEmpty) return const SizedBox.shrink();

    // Standardize newlines
    String cleanText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final List<String> lines = cleanText.split('\n');
    final boldPhrases = boldRanges
        .map((range) => range.text)
        .where((phrase) => phrase.trim().isNotEmpty)
        .toList();
    final underlinePhrases = underlineRanges
        .map((range) => range.text)
        .where((phrase) => phrase.trim().isNotEmpty)
        .toList();
    final List<Widget> children = [];

    bool inKeyPoints = false;
    bool inOtherOptions = false;
    List<String> keyPointLines = [];

    // Helper to flush accumulated key points inside the styled container
    void flushKeyPoints() {
      if (keyPointLines.isNotEmpty) {
        children.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: keyPointLines.map((line) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: _buildSelectableExplanationText(
                    _parseInlineStyles(
                        line, AppColors.indigo, baseFontSize - 1.5,
                        boldPhrases: boldPhrases,
                        underlinePhrases: underlinePhrases),
                    textAlign: TextAlign.left,
                  ),
                );
              }).toList(),
            ),
          ),
        );
        keyPointLines.clear();
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final String rawLine = lines[i];
      final String trimmedLine = rawLine.trim();

      if (trimmedLine.isEmpty) continue;

      // Section Headings
      if (trimmedLine.startsWith('Explanation / Key Points:') ||
          trimmedLine.contains('Explanation / Key Points')) {
        flushKeyPoints();
        inKeyPoints = true;
        inOtherOptions = false;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              'Explanation / Key Points:',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                fontFamily: 'Inter',
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmedLine.startsWith('Other options (why incorrect):') ||
          trimmedLine.startsWith('Other options:')) {
        flushKeyPoints();
        inKeyPoints = false;
        inOtherOptions = true;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              'Other options (why incorrect):',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                fontFamily: 'Inter',
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmedLine.startsWith('Answer:')) {
        flushKeyPoints();
        inKeyPoints = false;
        inOtherOptions = false;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Answer:',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                fontFamily: 'Inter',
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmedLine.startsWith('Ref:')) {
        flushKeyPoints();
        inKeyPoints = false;
        inOtherOptions = false;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _buildSelectableExplanationText(
              _parseInlineStyles(trimmedLine, mutedColor, baseFontSize - 2.5,
                  isItalic: true,
                  boldPhrases: boldPhrases,
                  underlinePhrases: underlinePhrases),
              textAlign: TextAlign.left,
            ),
          ),
        );
        continue;
      }

      // Inside Section Content Rendering
      if (inKeyPoints) {
        keyPointLines.add(trimmedLine);
      } else if (inOtherOptions) {
        if (trimmedLine.contains('→')) {
          final parts = trimmedLine.split('→');
          final String prefix = parts[0];
          final String suffix = parts.sublist(1).join('→');

          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: _buildSelectableExplanationText(
                TextSpan(
                  children: [
                    _parseInlineStyles(
                        prefix, const Color(0xFFEF4444), baseFontSize - 1.5,
                        isIncorrectPrefix: true,
                        boldPhrases: boldPhrases,
                        underlinePhrases: underlinePhrases),
                    const TextSpan(
                      text: ' → ',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _parseInlineStyles(suffix, textColor, baseFontSize - 1.5,
                        boldPhrases: boldPhrases,
                        underlinePhrases: underlinePhrases),
                  ],
                ),
                textAlign: TextAlign.left,
              ),
            ),
          );
        } else {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: _buildSelectableExplanationText(
                _parseInlineStyles(trimmedLine, textColor, baseFontSize - 1.5,
                    boldPhrases: boldPhrases,
                    underlinePhrases: underlinePhrases),
                textAlign: TextAlign.left,
              ),
            ),
          );
        }
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: _buildSelectableExplanationText(
              _parseInlineStyles(trimmedLine, textColor, baseFontSize - 1.5,
                  boldPhrases: boldPhrases, underlinePhrases: underlinePhrases),
              textAlign: TextAlign.left,
            ),
          ),
        );
      }
    }

    flushKeyPoints();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  TextSpan _parseInlineStyles(String line, Color defaultColor, double fontSize,
      {bool isIncorrectPrefix = false,
      bool isItalic = false,
      List<String> boldPhrases = const [],
      List<String> underlinePhrases = const []}) {
    String cleanLine = line.trim();
    bool hasBullet = false;
    if (cleanLine.startsWith('•') ||
        cleanLine.startsWith('-') ||
        cleanLine.startsWith('*')) {
      hasBullet = true;
      cleanLine = cleanLine.substring(1).trim();
    }

    final StringBuffer displayBuffer = StringBuffer();
    final List<TextFormatRange> markdownBoldRanges = [];
    int sourceIndex = 0;
    while (sourceIndex < cleanLine.length) {
      if (cleanLine.startsWith('**', sourceIndex)) {
        final end = cleanLine.indexOf('**', sourceIndex + 2);
        if (end != -1) {
          final boldText = cleanLine.substring(sourceIndex + 2, end);
          final start = displayBuffer.length;
          displayBuffer.write(boldText);
          markdownBoldRanges.add(TextFormatRange(
            start: start,
            end: start + boldText.length,
            text: boldText,
          ));
          sourceIndex = end + 2;
          continue;
        }
      }
      displayBuffer.write(cleanLine[sourceIndex]);
      sourceIndex++;
    }

    final displayText = displayBuffer.toString();
    final List<TextFormatRange> adminBoldRanges =
        _findPhraseRanges(displayText, boldPhrases);
    final List<TextFormatRange> adminUnderlineRanges =
        _findPhraseRanges(displayText, underlinePhrases);

    Color textColor = defaultColor;
    FontWeight baseWeight = FontWeight.normal;
    if (isIncorrectPrefix) {
      textColor = const Color(0xFFEF4444);
      baseWeight = FontWeight.w600;
    }

    bool inRanges(int index, List<TextFormatRange> ranges) {
      return ranges.any((range) => index >= range.start && index < range.end);
    }

    final List<TextSpan> spans = [];
    int pos = 0;
    while (pos < displayText.length) {
      final isMarkdownBold = inRanges(pos, markdownBoldRanges);
      final isAdminBold = inRanges(pos, adminBoldRanges);
      final isBold = isMarkdownBold || isAdminBold;
      final isUnderlined = inRanges(pos, adminUnderlineRanges);
      int next = pos + 1;
      while (next < displayText.length &&
          inRanges(next, markdownBoldRanges) == isMarkdownBold &&
          inRanges(next, adminBoldRanges) == isAdminBold &&
          inRanges(next, adminUnderlineRanges) == isUnderlined) {
        next++;
      }

      spans.add(TextSpan(
        text: displayText.substring(pos, next),
        style: TextStyle(
          color: textColor,
          fontWeight: isBold ? FontWeight.bold : baseWeight,
          fontSize: isAdminBold ? fontSize + 1.4 : fontSize,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          fontFamily: 'Inter',
          decoration:
              isUnderlined ? TextDecoration.underline : TextDecoration.none,
          decorationColor: const Color(0xFFEF4444),
          decorationThickness: isUnderlined ? 2.0 : null,
        ),
      ));
      pos = next;
    }

    return TextSpan(
      children: [
        if (hasBullet)
          TextSpan(
            text: '• ',
            style: TextStyle(
              color: isIncorrectPrefix ? const Color(0xFFEF4444) : defaultColor,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              fontFamily: 'Inter',
            ),
          ),
        ...spans,
      ],
    );
  }

  List<TextFormatRange> _findPhraseRanges(String text, List<String> phrases) {
    final List<TextFormatRange> ranges = [];
    final sortedPhrases = phrases
        .where((phrase) => phrase.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final phrase in sortedPhrases) {
      int start = 0;
      while (start < text.length) {
        final index = text.indexOf(phrase, start);
        if (index == -1) break;
        final end = index + phrase.length;
        final overlaps =
            ranges.any((range) => index < range.end && range.start < end);
        if (!overlaps) {
          ranges.add(TextFormatRange(start: index, end: end, text: phrase));
        }
        start = end;
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  static const String _touchRangePrefix = '__range__:';

  String _encodeTouchRange(int start, int end) =>
      '$_touchRangePrefix$start:$end';

  TextFormatRange? _decodeTouchRange(String value, String text) {
    if (!value.startsWith(_touchRangePrefix)) return null;
    final parts = value.substring(_touchRangePrefix.length).split(':');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null ||
        end == null ||
        start < 0 ||
        end <= start ||
        start >= text.length) {
      return null;
    }
    final safeEnd = end.clamp(start + 1, text.length).toInt();
    return TextFormatRange(
        start: start, end: safeEnd, text: text.substring(start, safeEnd));
  }

  String _audioHighlightRangeToken(AudioHighlight highlight, String text) {
    final start = highlight.start.clamp(0, text.length).toInt();
    final end =
        (highlight.start + highlight.length).clamp(start, text.length).toInt();
    if (start >= end) return '';
    return _encodeTouchRange(start, end);
  }

  // ignore: unused_element
  bool _isWordChar(String char) =>
      char.trim().isNotEmpty &&
      !RegExp(r'''[\s.,;:!?"'()\[\]{}،؛؟]''').hasMatch(char);

  // Erase exactly the word under the touch point, not the whole saved
  // range it happens to belong to. A single brush stroke can cover
  // several words as ONE saved range, so deleting that entire range
  // whenever any word inside it is touched would wipe out all of them
  // at once. Instead, "punch a hole" the size of the touched word out
  // of whichever saved range(s) it overlaps, and keep the remaining
  // left/right portions as their own ranges.
  void _recordNativeSelection(
      TextSelection selection, SelectionChangedCause? cause) {
    if (selection.isCollapsed) {
      _nativeSelectionRange = null;
      return;
    }

    _nativeSelectionRange = TextFormatRange(
      start: selection.start,
      end: selection.end,
      text: '',
    );
  }

  void _scheduleNativeSelectionCommit({
    required int questionId,
    required String text,
    required List<String> highlights,
  }) {
    if (_selectionCommitScheduled) return;
    _selectionCommitScheduled = true;

    // The selectable render object completes its final selection update in
    // this input frame. This is coordinate-free for touch, pencil, mouse,
    // and trackpad input alike.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionCommitScheduled = false;
      if (!mounted) return;
      final selected = _nativeSelectionRange;
      _nativeSelectionRange = null;
      if (selected == null || selected.start >= selected.end) return;

      if (_isHighlightMode) {
        _saveNativeHighlightRange(
          questionId: questionId,
          text: text,
          highlights: highlights,
          selected: selected,
        );
      } else if (_isEraserMode) {
        _eraseNativeHighlightRange(
          questionId: questionId,
          text: text,
          highlights: highlights,
          selected: selected,
        );
      }
    });
  }

  void _saveNativeHighlightRange({
    required int questionId,
    required String text,
    required List<String> highlights,
    required TextFormatRange selected,
  }) {
    if (_isHeaderRecordingAudio && _recordingQuestionId == questionId) {
      _addRecordingAudioHighlight(text: text, selected: selected);
      return;
    }

    var mergedStart = selected.start.clamp(0, text.length).toInt();
    var mergedEnd = selected.end.clamp(mergedStart + 1, text.length).toInt();
    final toRemove = <String>[];

    for (final item in highlights) {
      final existing = _decodeTouchRange(item, text);
      if (existing == null) continue;
      if (mergedStart > existing.end || existing.start > mergedEnd) continue;
      toRemove.add(item);
      mergedStart = mergedStart < existing.start ? mergedStart : existing.start;
      mergedEnd = mergedEnd > existing.end ? mergedEnd : existing.end;
    }

    final encoded = _encodeTouchRange(mergedStart, mergedEnd);
    if (toRemove.isEmpty && highlights.contains(encoded)) return;

    final provider = context.read<AppProvider>();
    for (final item in toRemove) {
      provider.removeHighlight(questionId, item);
    }
    provider.addHighlight(questionId, encoded);
  }

  void _addRecordingAudioHighlight({
    required String text,
    required TextFormatRange selected,
  }) {
    final start = selected.start.clamp(0, text.length).toInt();
    final end = selected.end.clamp(start + 1, text.length).toInt();
    if (start >= end) return;

    final timestamp = _headerRecordingStopwatch.elapsed.inMilliseconds / 1000.0;
    final duplicate = _recordingAudioHighlights.any((highlight) =>
        highlight.start == start &&
        highlight.length == end - start &&
        (highlight.audioTime - timestamp).abs() < 0.05);
    if (duplicate || !mounted) return;

    setState(() {
      _recordingAudioHighlights.add(AudioHighlight(
        text: text.substring(start, end),
        start: start,
        length: end - start,
        audioTime: timestamp,
        elementType: 'question',
        color: '#ffeb3b',
      ));
    });
  }

  void _eraseNativeHighlightRange({
    required int questionId,
    required String text,
    required List<String> highlights,
    required TextFormatRange selected,
  }) {
    final eraseStart = selected.start.clamp(0, text.length).toInt();
    final eraseEnd = selected.end.clamp(eraseStart + 1, text.length).toInt();
    final provider = context.read<AppProvider>();

    for (final item in highlights) {
      final existing = _decodeTouchRange(item, text);
      if (existing != null) {
        final overlapStart =
            eraseStart > existing.start ? eraseStart : existing.start;
        final overlapEnd = eraseEnd < existing.end ? eraseEnd : existing.end;
        if (overlapStart >= overlapEnd) continue;

        provider.removeHighlight(questionId, item);
        if (existing.start < overlapStart) {
          provider.addHighlight(
              questionId, _encodeTouchRange(existing.start, overlapStart));
        }
        if (overlapEnd < existing.end) {
          provider.addHighlight(
              questionId, _encodeTouchRange(overlapEnd, existing.end));
        }
        continue;
      }

      if (item.isEmpty || item.startsWith(_touchRangePrefix)) continue;
      if (_findPhraseRanges(text, [item]).any(
        (range) => eraseStart < range.end && range.start < eraseEnd,
      )) {
        provider.removeHighlight(questionId, item);
      }
    }
  }

  Widget _buildRichTextWithHighlights(
      String text, List<String> highlights, double fontSize,
      {Color textColor = const Color(0xFF191C1D),
      TextAlign textAlign = TextAlign.left,
      TextDirection textDirection = TextDirection.ltr,
      bool isSelectable = true,
      void Function(TextSelection, SelectionChangedCause?)?
          onSelectionChanged}) {
    TextStyle baseStyle([Color? color]) => TextStyle(
          color: color ?? textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.5,
          fontFamily: 'Cairo',
        );

    final highlightStyle = baseStyle(const Color(0xFF111827)).copyWith(
      backgroundColor: const Color(0xFFFEF08A).withValues(alpha: 0.88),
    );

    if (highlights.isEmpty) {
      if (isSelectable) {
        return SelectableText(
          text,
          style: baseStyle(),
          textAlign: textAlign,
          textDirection: textDirection,
          onSelectionChanged: onSelectionChanged,
        );
      } else {
        return Text(
          text,
          style: baseStyle(),
          textAlign: textAlign,
          textDirection: textDirection,
        );
      }
    }

    final List<TextFormatRange> rawRanges = [];
    final legacyHighlights = <String>[];
    for (final item in highlights) {
      final range = _decodeTouchRange(item, text);
      if (range != null) {
        rawRanges.add(range);
      } else if (item.trim().isNotEmpty) {
        legacyHighlights.add(item);
      }
    }
    rawRanges.addAll(_findPhraseRanges(text, legacyHighlights));

    // IMPORTANT: previously, any range that overlapped an already-accepted
    // range was silently skipped and never painted, even though it stayed
    // in the saved highlight data. That's why some highlighted words never
    // showed any color. Instead of dropping overlapping ranges, merge them
    // into a single continuous span so every saved highlight is guaranteed
    // to be visible.
    rawRanges.sort((a, b) => a.start.compareTo(b.start));
    final List<TextFormatRange> highlightRanges = [];
    for (final range in rawRanges) {
      final safeStart = range.start.clamp(0, text.length).toInt();
      if (safeStart >= text.length) continue;
      final safeEnd = range.end.clamp(safeStart + 1, text.length).toInt();
      if (highlightRanges.isNotEmpty && safeStart <= highlightRanges.last.end) {
        final last = highlightRanges.last;
        final mergedEnd = safeEnd > last.end ? safeEnd : last.end;
        highlightRanges[highlightRanges.length - 1] = TextFormatRange(
          start: last.start,
          end: mergedEnd,
          text: text.substring(last.start, mergedEnd),
        );
      } else {
        highlightRanges.add(TextFormatRange(
          start: safeStart,
          end: safeEnd,
          text: text.substring(safeStart, safeEnd),
        ));
      }
    }

    final List<TextSpan> spans = [];
    int currentPos = 0;
    for (final range in highlightRanges) {
      if (range.start >= text.length) continue;
      final safeEnd = range.end.clamp(range.start + 1, text.length).toInt();
      if (range.start > currentPos) {
        spans.add(TextSpan(
          text: text.substring(currentPos, range.start),
          style: baseStyle(),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(range.start, safeEnd),
        style: highlightStyle,
      ));
      currentPos = safeEnd;
    }

    if (currentPos < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentPos),
        style: baseStyle(),
      ));
    }
    if (!isSelectable) {
      return Text.rich(
        TextSpan(style: baseStyle(), children: spans),
        textAlign: textAlign,
        textDirection: textDirection,
      );
    }
    if (isSelectable) {
      return SelectableText.rich(
        TextSpan(style: baseStyle(), children: spans),
        textAlign: textAlign,
        textDirection: textDirection,
        onSelectionChanged: onSelectionChanged,
      );
    } else {
      return Text.rich(
        TextSpan(style: baseStyle(), children: spans),
        textAlign: textAlign,
        textDirection: textDirection,
      );
    }
  }

  void _showEditQuestionDialog(Question q, AppProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _EditQuestionDialog(question: q, provider: provider),
    );
  }
}

class _EditQuestionDialog extends StatefulWidget {
  final Question question;
  final AppProvider provider;

  const _EditQuestionDialog({
    required this.question,
    required this.provider,
  });

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _questionController;
  late TextEditingController _explanationController;
  late List<TextEditingController> _optionControllers;
  late String _selectedCorrectAnswer;
  late String _selectedTitle;
  late String _selectedSubTitle;

  // AI related
  String _selectedAIModel = 'gemini-2.5-flash';
  bool _isGeneratingAI = false;
  bool _isSaving = false;

  String? _currentAudioUrl;
  String? _selectedAudioPath;
  String? _selectedAudioName;
  bool _audioDeleted = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordTimer;
  bool _isRecordingAudio = false;
  bool _isRecordingPaused = false;
  Duration _recordDuration = Duration.zero;

  // Question Images list
  List<Map<String, dynamic>> _imagesList = [];
  bool _isLoadingImages = true;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.question.text);
    _explanationController =
        TextEditingController(text: widget.question.explanation);
    _optionControllers = List.generate(
      widget.question.options.length,
      (index) => TextEditingController(text: widget.question.options[index]),
    );
    _selectedCorrectAnswer = String.fromCharCode(65 + widget.question.correct);
    _currentAudioUrl = widget.question.audioUrl;

    // Set initial values
    final List<String> existingTitles = widget.provider.questions
        .map((q) => q.topic ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    existingTitles.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final String initialTitle = widget.question.topic ?? '';
    _selectedTitle = existingTitles.contains(initialTitle)
        ? initialTitle
        : (existingTitles.isNotEmpty ? existingTitles.first : '');

    final List<String> filteredSubTitles = widget.provider.questions
        .where((q) => q.topic == _selectedTitle)
        .map((q) => q.subTopic ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    filteredSubTitles
        .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final String initialSubTitle = widget.question.subTopic ?? '';
    _selectedSubTitle = filteredSubTitles.contains(initialSubTitle)
        ? initialSubTitle
        : (filteredSubTitles.isNotEmpty ? filteredSubTitles.first : '');

    _loadQuestionImages();
  }

  Future<void> _loadQuestionImages() async {
    try {
      final imgs = await widget.provider.questions.isEmpty
          ? <Map<String, dynamic>>[]
          : await SupabaseService().getQuestionImages(widget.question.id);
      if (mounted) {
        setState(() {
          _imagesList = imgs;
          _isLoadingImages = false;
        });
      }
    } catch (e) {
      print('Error loading images: $e');
      if (mounted) {
        setState(() {
          _isLoadingImages = false;
        });
      }
    }
  }

  Map<String, dynamic> _imageDetails(Map<String, dynamic> imageRecord) {
    final details = imageRecord['question_images'];
    if (details is Map) return Map<String, dynamic>.from(details);
    return Map<String, dynamic>.from(imageRecord);
  }

  String _editorImageUrl(Map<String, dynamic> imageRecord) {
    final details = _imageDetails(imageRecord);
    return details['file_url']?.toString() ??
        details['url']?.toString() ??
        details['image_url']?.toString() ??
        details['public_url']?.toString() ??
        '';
  }

  String _storagePathFromQuestionImageUrl(String url) {
    final marker = '/storage/v1/object/public/question-images/';
    final index = url.indexOf(marker);
    if (index == -1) return url;
    return Uri.decodeFull(url.substring(index + marker.length));
  }

  int? _editorImageId(Map<String, dynamic> imageRecord) {
    final details = _imageDetails(imageRecord);
    final rawId = details['id'] ?? imageRecord['image_id'];
    if (rawId is int) return rawId;
    return int.tryParse(rawId?.toString() ?? '');
  }

  bool _hasEditorImage(String url, {int? imageId}) {
    return _imagesList.any((img) {
      if (imageId != null && _editorImageId(img) == imageId) return true;
      return _editorImageUrl(img) == url;
    });
  }

  Future<void> _pickQuestionImageFromDevice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        final path = file.path;
        final bytes = file.bytes;
        final imageKey = path?.isNotEmpty == true
            ? path!
            : '${file.name}_${file.size}_${_imagesList.length}';
        if (_hasEditorImage(imageKey)) continue;
        _imagesList.add({
          'position': _imagesList.length,
          'question_images': {
            'url': imageKey,
            'file_name': file.name,
            'file_size': file.size,
            'mime_type':
                file.extension == null ? null : 'image/' + file.extension!,
            '_local_path': path,
            '_bytes': bytes,
          },
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر اختيار الصورة: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  Future<void> _browseSubjectImages() async {
    setState(() => _isLoadingImages = true);
    try {
      final questionIds =
          widget.provider.questions.map((q) => q.id).toSet().toList();
      final List<Map<String, dynamic>> rows = questionIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await SupabaseService()
              .client
              .from('question_image_relations')
              .select('question_id, position, question_images(*)')
              .inFilter('question_id', questionIds));

      final seen = <String>{};
      final images = <Map<String, dynamic>>[];
      for (final row in rows) {
        final details = _imageDetails(row);
        final url = _editorImageUrl(row);
        final id = details['id']?.toString() ?? url;
        if (url.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        images.add(row);
      }
      images.sort((a, b) => _editorImageUrl(a).compareTo(_editorImageUrl(b)));

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'تصفح صور هذه المادة',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: images.isEmpty
                            ? const Center(
                                child: Text('لا توجد صور محفوظة في هذه المادة',
                                    style: TextStyle(fontFamily: 'Cairo')))
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: images.length,
                                itemBuilder: (context, index) {
                                  final img = images[index];
                                  final url = _editorImageUrl(img);
                                  return InkWell(
                                    onTap: () {
                                      final id = _editorImageId(img);
                                      if (!_hasEditorImage(url, imageId: id)) {
                                        setState(() {
                                          _imagesList.add({
                                            'position': _imagesList.length,
                                            'question_images':
                                                _imageDetails(img),
                                          });
                                        });
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedQuestionImage(
                                        url: url,
                                        fit: BoxFit.contain,
                                        loading: const SizedBox.expand(),
                                        error: const Icon(
                                            Icons.broken_image_outlined),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تصفح الصور: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _syncQuestionImages() async {
    final supabase = SupabaseService();
    await supabase.client
        .from('question_image_relations')
        .delete()
        .eq('question_id', widget.question.id);

    for (var i = 0; i < _imagesList.length; i++) {
      final details = _imageDetails(_imagesList[i]);
      var imageId = _editorImageId(_imagesList[i]);
      var url = _editorImageUrl(_imagesList[i]);
      final localPath = details['_local_path']?.toString();
      final localBytes = details['_bytes'];
      final fileNameForError = details['file_name']?.toString() ?? 'بدون اسم';
      final fileSizeForError = details['file_size']?.toString() ?? 'غير معروف';

      if (imageId == null) {
        if (localPath != null && localPath.isNotEmpty) {
          final uploadedUrl = await supabase.uploadFile(
            'question-images',
            localPath,
            folder: 'questions',
          );
          if (uploadedUrl == null || uploadedUrl.isEmpty) {
            throw Exception(
                'فشل رفع صورة الشرح من المسار المحلي. الملف: $fileNameForError، الحجم: $fileSizeForError، السبب: ${supabase.lastError ?? 'لم يرجع Supabase سبباً'}');
          }
          url = uploadedUrl;
        } else if (localBytes is Uint8List) {
          final uploadedUrl = await supabase.uploadFileBytes(
            'question-images',
            localBytes,
            details['file_name']?.toString() ?? 'question-image.png',
            folder: 'questions',
            contentType: details['mime_type']?.toString(),
          );
          if (uploadedUrl == null || uploadedUrl.isEmpty) {
            throw Exception(
                'فشل رفع صورة الشرح من بيانات المتصفح. الملف: $fileNameForError، الحجم: $fileSizeForError، السبب: ${supabase.lastError ?? 'لم يرجع Supabase سبباً'}');
          }
          url = uploadedUrl;
        }
        if (url.isEmpty) continue;
        final originalFilename =
            details['file_name']?.toString() ?? url.split('/').last;
        final inserted = await supabase.client
            .from('question_images')
            .insert({
              'name': originalFilename,
              'original_filename': originalFilename,
              'file_path': _storagePathFromQuestionImageUrl(url),
              'file_url': url,
              'file_size': details['file_size'],
              'mime_type': details['mime_type'],
              'subject': widget.question.subject,
              'title': widget.question.topic,
              'subtitle': widget.question.subTopic,
              'is_active': true,
            })
            .select('id, file_url')
            .single();
        imageId = inserted['id'] as int;
        _imagesList[i] = {
          'position': i,
          'question_images': Map<String, dynamic>.from(inserted),
        };
      }

      await supabase.client.from('question_image_relations').insert({
        'question_id': widget.question.id,
        'image_id': imageId,
        'position': i,
      });
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _explanationController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecordingAudio || _isRecordingPaused) return;
      setState(() {
        _recordDuration += const Duration(seconds: 1);
      });
    });
  }

  String _formatRecordDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startAudioRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى السماح باستخدام المايكروفون',
                  style: TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }

      final path =
          '${Directory.systemTemp.path}/question_${widget.question.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
          autoGain: true,
        ),
        path: path,
      );

      setState(() {
        _isRecordingAudio = true;
        _isRecordingPaused = false;
        _recordDuration = Duration.zero;
        _selectedAudioPath = null;
        _selectedAudioName = null;
        _audioDeleted = false;
      });
      _startRecordTimer();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل بدء التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _togglePauseRecording() async {
    if (!_isRecordingAudio) return;
    try {
      if (_isRecordingPaused) {
        await _audioRecorder.resume();
      } else {
        await _audioRecorder.pause();
      }
      setState(() {
        _isRecordingPaused = !_isRecordingPaused;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر إيقاف/استئناف التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _stopAudioRecording() async {
    if (!_isRecordingAudio) return;
    try {
      final path = await _audioRecorder.stop();
      _recordTimer?.cancel();
      setState(() {
        _isRecordingAudio = false;
        _isRecordingPaused = false;
        if (path != null && path.isNotEmpty) {
          _selectedAudioPath = path;
          _selectedAudioName = path.split('/').last.split('\\').last;
          _audioDeleted = false;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل حفظ التسجيل: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final file = result?.files.single;
      if (file == null || file.path == null) return;

      setState(() {
        _selectedAudioPath = file.path;
        _selectedAudioName = file.name;
        _audioDeleted = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل اختيار الملف الصوتي: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  Future<void> _deleteAudioSelection() async {
    if (_isRecordingAudio) {
      await _stopAudioRecording();
    }
    setState(() {
      _selectedAudioPath = null;
      _selectedAudioName = null;
      _currentAudioUrl = null;
      _audioDeleted = true;
      _recordDuration = Duration.zero;
    });
  }

  Future<void> _generateAIExplanation() async {
    final String model = _selectedAIModel;
    final String questionText = _questionController.text.trim();

    // Convert selected answer letter to index
    final int correctIdx = _selectedCorrectAnswer.codeUnitAt(0) - 65;
    final String correctText = correctIdx < _optionControllers.length
        ? _optionControllers[correctIdx].text.trim()
        : '';

    if (questionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى كتابة نص السؤال أولاً لتوليد الشرح',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() {
      _isGeneratingAI = true;
    });

    final client = HttpClient();
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=AIzaSyCJ6BJaZT0cJXI7GhcfESUD2ynotMoHh0Q');
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final optsText = _optionControllers.asMap().entries.map((e) {
        final letter = String.fromCharCode(65 + e.key);
        return '- $letter: ${e.value.text}';
      }).join('\n');

      final prompt = """
You are a medical education assistant. Based on medical facts, explain the following medical question.
CRITICAL RULES:
- Explain why the correct option is correct.
- Explain why the other options are incorrect.
- Format the output with clear bullet points (•) and clean formatting.
- Keep the language medical, scientific, and direct.

Question: "$questionText"
Options:
$optsText
Suggested Correct Answer: "$correctText"
""";

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      });

      request.write(body);
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody);
        final String text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        setState(() {
          _explanationController.text = text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ تم توليد الشرح بنجاح!',
                  style: TextStyle(fontFamily: 'Cairo'))),
        );
      } else {
        throw Exception('API error code: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل توليد الشرح بالذكاء الاصطناعي: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    } finally {
      client.close();
      setState(() {
        _isGeneratingAI = false;
      });
    }
  }

  Widget _buildLeftColumn(bool isDark, Color cardColor, Color borderColor,
      Color textColor, Color labelColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Question text field
        Text(
          'نص السؤال:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _questionController,
          maxLines: 5,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'أدخل نص السؤال...',
            hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.grey),
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
          validator: (val) =>
              val == null || val.trim().isEmpty ? 'نص السؤال مطلوب' : null,
        ),
        const SizedBox(height: 16),

        // Options fields
        Text(
          'الخيارات:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        ...List.generate(_optionControllers.length, (index) {
          final letter = String.fromCharCode(65 + index);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '$letter. ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4F46E5),
                              fontSize: 14),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _optionControllers[index],
                            style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                                fontFamily: 'Cairo'),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                              isDense: true,
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                    ? 'هذا الخيار مطلوب'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_optionControllers.length > 2) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFEF4444), size: 22),
                    onPressed: () {
                      setState(() {
                        final removed = _optionControllers.removeAt(index);
                        removed.dispose();

                        // Recalculate correct answer selection if it exceeds options length
                        final maxLetter = String.fromCharCode(
                            65 + _optionControllers.length - 1);
                        if (_selectedCorrectAnswer.codeUnitAt(0) >
                            maxLetter.codeUnitAt(0)) {
                          _selectedCorrectAnswer = 'A';
                        }
                      });
                    },
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 8),

        // Add Option Button
        OutlinedButton.icon(
          onPressed: () {
            if (_optionControllers.length < 11) {
              setState(() {
                _optionControllers.add(TextEditingController());
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('الحد الأقصى هو 11 خياراً',
                        style: TextStyle(fontFamily: 'Cairo'))),
              );
            }
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('إضافة خيار',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF4F46E5),
            side: BorderSide(color: borderColor),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildRightColumn(bool isDark, Color cardColor, Color borderColor,
      Color textColor, Color labelColor) {
    final List<String> existingTitles = widget.provider.questions
        .map((q) => q.topic ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    existingTitles.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Filter subtopics based on selected chapter (_selectedTitle)
    final List<String> filteredSubTitles = widget.provider.questions
        .where((q) => q.topic == _selectedTitle)
        .map((q) => q.subTopic ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    filteredSubTitles
        .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Correct Answer dropdown
        Text(
          'الإجابة الصحيحة:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedCorrectAnswer,
          dropdownColor: Colors.white,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          items: List.generate(_optionControllers.length, (index) {
            final letter = String.fromCharCode(65 + index);
            return DropdownMenuItem(
              value: letter,
              child: Text('الخيار $letter',
                  style: TextStyle(fontFamily: 'Cairo', color: textColor)),
            );
          }),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedCorrectAnswer = val;
              });
            }
          },
        ),
        const SizedBox(height: 14),

        // AI Model select
        Text(
          'نموذج الذكاء الاصطناعي:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedAIModel,
          dropdownColor: Colors.white,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          items: [
            DropdownMenuItem(
                value: 'gemini-2.5-flash',
                child: Text('Gemini 2.5 Flash ⭐',
                    style: TextStyle(fontFamily: 'Cairo', color: textColor))),
            DropdownMenuItem(
                value: 'gemini-2.5-flash-lite',
                child: Text('Gemini 2.5 Flash Lite',
                    style: TextStyle(fontFamily: 'Cairo', color: textColor))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedAIModel = val;
              });
            }
          },
        ),
        const SizedBox(height: 12),

        // AI Generate Explanation Button
        Text(
          'الشرح بالذكاء الاصطناعي:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: _isGeneratingAI ? null : _generateAIExplanation,
          icon: _isGeneratingAI
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 1.5))
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(
            _isGeneratingAI ? 'جاري التوليد...' : 'Generate AI Explanation',
            style: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 14),

        _buildAudioToolsSection(
            isDark, cardColor, borderColor, textColor, labelColor),
        const SizedBox(height: 14),

        // Explanation text field
        Text(
          'الشرح:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _explanationController,
          maxLines: 4,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'أدخل شرح السؤال...',
            hintStyle: const TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            contentPadding: const EdgeInsets.all(12),
          ),
          onChanged: (val) {
            setState(() {}); // For character count update
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '${_explanationController.text.length}/2000',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Topic (Chapter) select
        Text(
          'اختر الجابتر:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          alignment: AlignmentDirectional.centerStart,
          value: existingTitles.contains(_selectedTitle)
              ? _selectedTitle
              : (existingTitles.isNotEmpty ? existingTitles.first : null),
          dropdownColor: Colors.white,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            hintText: 'اختر العنوان الرئيسي',
            hintStyle: const TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
          ),
          items: existingTitles
              .map((t) => DropdownMenuItem(
                  value: t,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(t,
                        textAlign: TextAlign.left,
                        style:
                            TextStyle(fontFamily: 'Cairo', color: textColor)),
                  )))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedTitle = val;

                // Recalculate subtopics for this chapter
                final List<String> newSubTitles = widget.provider.questions
                    .where((q) => q.topic == val)
                    .map((q) => q.subTopic ?? '')
                    .where((s) => s.isNotEmpty)
                    .toSet()
                    .toList();
                newSubTitles
                    .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                if (newSubTitles.isNotEmpty) {
                  _selectedSubTitle = newSubTitles.first;
                } else {
                  _selectedSubTitle = '';
                }
              });
            }
          },
        ),
        const SizedBox(height: 14),

        // Subtopic select
        Text(
          'اختر الموضوع الفرعي:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          alignment: AlignmentDirectional.centerStart,
          value: filteredSubTitles.contains(_selectedSubTitle)
              ? _selectedSubTitle
              : (filteredSubTitles.isNotEmpty ? filteredSubTitles.first : null),
          dropdownColor: Colors.white,
          style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            hintText: 'اختر العنوان الفرعي',
            hintStyle: const TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
          ),
          items: filteredSubTitles
              .map((s) => DropdownMenuItem(
                  value: s,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(s,
                        textAlign: TextAlign.left,
                        style:
                            TextStyle(fontFamily: 'Cairo', color: textColor)),
                  )))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedSubTitle = val;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildAudioToolsSection(bool isDark, Color cardColor,
      Color borderColor, Color textColor, Color labelColor) {
    final hasCurrentAudio =
        _currentAudioUrl != null && _currentAudioUrl!.trim().isNotEmpty;
    final hasSelectedAudio =
        _selectedAudioPath != null && _selectedAudioPath!.trim().isNotEmpty;
    final statusText = _isRecordingAudio
        ? 'تسجيل جارٍ ${_formatRecordDuration(_recordDuration)}'
        : hasSelectedAudio
            ? (_selectedAudioName ?? 'تسجيل جديد')
            : (hasCurrentAudio ? 'يوجد شرح صوتي محفوظ' : 'لا يوجد شرح صوتي');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الصوت:',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: labelColor,
          ),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (_isRecordingAudio
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF6B4EFF))
                          .withValues(alpha: isDark ? 0.22 : 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isRecordingAudio
                          ? Icons.fiber_manual_record_rounded
                          : Icons.graphic_eq_rounded,
                      color: _isRecordingAudio
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6B4EFF),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
              if (hasCurrentAudio &&
                  !hasSelectedAudio &&
                  !_isRecordingAudio) ...[
                const SizedBox(height: 8),
                AudioExplanationPlayer(
                  audioUrl: _currentAudioUrl!,
                  questionId: widget.question.id,
                  initialDurationSeconds: widget.question.audioDurationSeconds,
                  onDurationDiscovered: (seconds) => widget.provider
                      .updateQuestion(widget.question.id,
                          {'audio_duration_seconds': seconds}),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : (_isRecordingAudio
                              ? _stopAudioRecording
                              : _startAudioRecording),
                      icon: Icon(
                          _isRecordingAudio
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          size: 16),
                      label: Text(
                        _isRecordingAudio ? 'إيقاف وحفظ' : 'تسجيل نقي',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecordingAudio
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF6B4EFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _isRecordingPaused ? 'استئناف' : 'Pause',
                    onPressed: _isRecordingAudio && !_isSaving
                        ? _togglePauseRecording
                        : null,
                    icon: Icon(_isRecordingPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded),
                    color: const Color(0xFFF59E0B),
                    style: IconButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFF59E0B).withValues(alpha: 0.12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving || _isRecordingAudio
                          ? null
                          : _pickAudioFile,
                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                      label: const Text('رفع ملف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B4EFF),
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'حذف الصوت',
                    onPressed: (hasCurrentAudio ||
                                hasSelectedAudio ||
                                _isRecordingAudio) &&
                            !_isSaving
                        ? _deleteAudioSelection
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: const Color(0xFFEF4444),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFEF4444).withValues(alpha: 0.10),
                      disabledBackgroundColor:
                          isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagesUploadSection(bool isDark, Color cardColor,
      Color borderColor, Color textColor, Color labelColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'صور الشرح:',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: labelColor),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _pickQuestionImageFromDevice,
              icon: const Icon(Icons.upload, size: 14),
              label: const Text('رفع صورة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? const Color(0xFF2C2C3D) : const Color(0xFFF1F5F9),
                foregroundColor:
                    isDark ? Colors.white : const Color(0xFF1E293B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _browseSubjectImages,
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('تصفح المرفوعات',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? const Color(0xFF2C2C3D) : const Color(0xFFF1F5F9),
                foregroundColor:
                    isDark ? Colors.white : const Color(0xFF1E293B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Horizontal list of images
        _isLoadingImages
            ? const SizedBox(
                height: 60, child: Center(child: CircularProgressIndicator()))
            : _imagesList.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    alignment: Alignment.center,
                    child: Text('لا توجد صور مضافة حالياً',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white38 : Colors.grey,
                            fontSize: 12)),
                  )
                : SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _imagesList.length + 1,
                      itemBuilder: (context, idx) {
                        if (idx == _imagesList.length) {
                          // Plus card to add more
                          return InkWell(
                            onTap:
                                _isSaving ? null : _pickQuestionImageFromDevice,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF4A4A62)
                                        : const Color(0xFFCBD5E1),
                                    style: BorderStyle.values[1]),
                              ),
                              child: const Icon(Icons.add, color: Colors.grey),
                            ),
                          );
                        }

                        final img = _imagesList[idx];
                        final url = _editorImageUrl(img);

                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: url.isEmpty
                                  ? const Icon(Icons.broken_image_outlined)
                                  : CachedQuestionImage(
                                      url: url,
                                      fit: BoxFit.contain,
                                      loading: const SizedBox.expand(),
                                      error: const Icon(
                                          Icons.broken_image_outlined),
                                    ),
                            ),
                            Positioned(
                              top: 2,
                              right: 10,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _imagesList.removeAt(idx);
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 10),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const bool isDark =
        false; // Force clean light styling for this dialog as requested
    const Color bgColor = Colors.white;
    const Color cardColor = Color(0xFFF8FAFC); // Soft light blue-gray
    const Color borderColor = Color(0xFFD0D7DE); // Clean borders
    const Color textColor = Colors.black87;
    const Color labelColor = Color(0xFF4F46E5); // Indigo blue labels

    return Dialog(
      backgroundColor: bgColor,
      elevation: 12,
      shadowColor: const Color(0x2B4F46E5), // Indigo blue shadow
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width * 0.95,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تعديل السؤال',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: labelColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isWide = constraints.maxWidth > 650;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Swapped columns: Metadata/Actions on the right (first RTL), Question/Options on the left (second RTL)
                                Expanded(
                                    flex: 5,
                                    child: _buildRightColumn(isDark, cardColor,
                                        borderColor, textColor, labelColor)),
                                const SizedBox(width: 20),
                                Expanded(
                                    flex: 5,
                                    child: _buildLeftColumn(isDark, cardColor,
                                        borderColor, textColor, labelColor)),
                              ],
                            )
                          else ...[
                            _buildLeftColumn(isDark, cardColor, borderColor,
                                textColor, labelColor),
                            const SizedBox(height: 20),
                            _buildRightColumn(isDark, cardColor, borderColor,
                                textColor, labelColor),
                          ],
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 10),
                          _buildImagesUploadSection(isDark, cardColor,
                              borderColor, textColor, labelColor),
                          const SizedBox(height: 20),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4F46E5),
                      side: const BorderSide(color: Color(0xFF4F46E5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(100, 42),
                    ),
                    child: const Text('إلغاء',
                        style: TextStyle(fontFamily: 'Cairo')),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                          0xFF4F46E5), // Purple Save button matching mockup
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(130, 42),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('حفظ التغييرات',
                            style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    final String finalTitle = _selectedTitle.trim();
    final String finalSubTitle = _selectedSubTitle.trim();

    if (finalTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('العنوان الرئيسي مطلوب',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }
    if (finalSubTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('العنوان الفرعي مطلوب',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final Map<String, dynamic> updateData = {
      'question': _questionController.text.trim(),
      'correct_answer': _selectedCorrectAnswer.codeUnitAt(0) - 65 + 1,
      'explanation': _explanationController.text.trim(),
      'title': finalTitle,
      'sub_title': finalSubTitle,
    };

    for (int i = 0; i < _optionControllers.length; i++) {
      updateData['answer_${i + 1}'] = _optionControllers[i].text.trim();
    }

    for (int i = _optionControllers.length; i < 11; i++) {
      updateData['answer_${i + 1}'] = '';
    }

    if (_isRecordingAudio) {
      await _stopAudioRecording();
    }

    if (_selectedAudioPath != null && _selectedAudioPath!.isNotEmpty) {
      final uploadedUrl = await SupabaseService().uploadFile(
        'question-audios',
        _selectedAudioPath!,
        folder: 'questions',
      );
      if (uploadedUrl == null) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('فشل رفع الصوت', style: TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }

      if (widget.question.audioUrl != null &&
          widget.question.audioUrl!.isNotEmpty) {
        await SupabaseService()
            .deleteStorageFile('question-audios', widget.question.audioUrl!);
      }

      updateData['audio_url'] = uploadedUrl;
      updateData['audio_duration_seconds'] =
          _recordDuration.inSeconds > 0 ? _recordDuration.inSeconds : null;
      updateData['audio_highlights'] = null;
    } else if (_audioDeleted) {
      if (widget.question.audioUrl != null &&
          widget.question.audioUrl!.isNotEmpty) {
        await SupabaseService()
            .deleteStorageFile('question-audios', widget.question.audioUrl!);
      }
      updateData['audio_url'] = null;
      updateData['audio_duration_seconds'] = null;
      updateData['audio_highlights'] = null;
    }

    try {
      await _syncQuestionImages();
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل حفظ صور السؤال: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    final success =
        await widget.provider.updateQuestion(widget.question.id, updateData);

    setState(() {
      _isSaving = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ تم تحديث السؤال بنجاح',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "فشل تحديث السؤال: ${widget.provider.lastSupabaseError ?? 'خطأ غير معروف'}",
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    }
  }
}

class _QuestionGlowPainter extends CustomPainter {
  const _QuestionGlowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 11);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(12),
      ),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QuestionGlowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
