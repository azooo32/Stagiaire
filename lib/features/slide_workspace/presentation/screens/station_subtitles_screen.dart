import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/app_provider.dart';
import '../../../../core/services/pdf_sound_parser.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../data/slide_workspace_repository.dart';
import '../../domain/entities/slide_workspace_models.dart';
import 'slide_workspace_screen.dart';
import 'pdf_workspace_screen.dart';
import '../widgets/slide_editor_dialog.dart';

class StationSubtitlesScreen extends StatefulWidget {
  final String stationName;
  final String? stationDbId;
  final String stationType; // 'slides' or 'pdf'

  const StationSubtitlesScreen({
    super.key,
    required this.stationName,
    this.stationDbId,
    required this.stationType,
  });

  @override
  State<StationSubtitlesScreen> createState() => _StationSubtitlesScreenState();
}

class _StationSubtitlesScreenState extends State<StationSubtitlesScreen> {
  final SupabaseSlideWorkspaceRepository _repository =
      SupabaseSlideWorkspaceRepository();

  bool _isLoading = true;
  List<WorkspaceSlide> _slides = [];
  Map<String, List<WorkspaceSlide>> _slidesBySubtitle = {};
  final Map<String, double> _downloadProgress = {}; // pdfId -> progress (0.0 to 1.0)
  final Map<String, bool> _isDownloading = {};
  final Map<String, String> _localPdfPaths = {}; // pdfId -> localPath
  final Map<String, HttpClient> _activeClients = {};

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    for (final client in _activeClients.values) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
    _cleanupInterruptedDownloads();
    super.dispose();
  }

  Future<void> _cleanupInterruptedDownloads() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      for (final entry in _isDownloading.entries) {
        if (entry.value) {
          final slideId = entry.key;
          final tmpFile = File('${appDir.path}/cached_pdfs/$slideId.pdf.tmp');
          if (await tmpFile.exists()) {
            await tmpFile.delete();
          }
        }
      }
    } catch (_) {}
  }

  Future<bool> _isPdfValid(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 100) return false;

      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(4);
      await raf.close();
      if (headerBytes.length < 4) return false;
      final headerStr = String.fromCharCodes(headerBytes);
      if (!headerStr.startsWith('%PDF')) return false;

      final pdfDoc = await PdfDocument.openFile(localPath);
      final count = pdfDoc.pagesCount;
      await pdfDoc.close();
      return count > 0;
    } catch (e) {
      debugPrint('PDF validation failed for $localPath: $e');
      return false;
    }
  }

  Future<void> _cleanupCorruptedPdf(String pdfId, String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final tmpFile = File('$localPath.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      final tempDir = await getTemporaryDirectory();
      final pdfCacheDir = Directory('${tempDir.path}/pdf_pages_cache/$pdfId');
      if (await pdfCacheDir.exists()) {
        await pdfCacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error cleaning up corrupted PDF ($pdfId): $e');
    }
  }

  Future<void> _loadContent() async {
    // 1. Check synchronous cache first for instant 0ms offline display
    final cachedSync = _repository.getCachedSlidesSync(widget.stationDbId);
    if (cachedSync.isNotEmpty) {
      final bypassed = await _processSlides(cachedSync);
      if (bypassed) return;
      unawaited(_refreshInBackground());
      return;
    }

    // 2. Check async cache if sync cache was empty
    final cachedAsync = await _repository.getCachedSlides(widget.stationDbId);
    if (cachedAsync.isNotEmpty) {
      final bypassed = await _processSlides(cachedAsync);
      if (bypassed) return;
      unawaited(_refreshInBackground());
      return;
    }

    // 3. No cache available at all, set loading state and attempt network fetch
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final fetched = await _repository.getSlides(widget.stationDbId);
      await _processSlides(fetched);
    } catch (e) {
      debugPrint('Error loading subtitles/PDFs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await _repository
          .refreshSlides(widget.stationDbId)
          .timeout(const Duration(seconds: 4));
      if (fresh.isNotEmpty && mounted) {
        await _processSlides(fresh);
      }
    } catch (e) {
      debugPrint('Background refresh in StationSubtitlesScreen skipped/failed: $e');
    }
  }

  Future<bool> _processSlides(List<WorkspaceSlide> rawSlides) async {
    _slides = rawSlides.where((s) => !s.isHidden).toList();

    if (_slides.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return false;
    }

    // Check cached status for PDFs without bypassing the station screen
    if (widget.stationType == 'pdf') {
      final appDir = await getApplicationDocumentsDirectory();
      for (final slide in _slides) {
        final localPath = '${appDir.path}/cached_pdfs/${slide.id}.pdf';
        final tmpPath = '$localPath.tmp';

        // Clean up leftover temporary file if previous download was interrupted
        final tmpFile = File(tmpPath);
        if (await tmpFile.exists()) {
          try { await tmpFile.delete(); } catch (_) {}
        }

        final file = File(localPath);
        if (await file.exists()) {
          final isValid = await _isPdfValid(localPath);
          if (isValid) {
            _localPdfPaths[slide.id] = localPath;
          } else {
            await _cleanupCorruptedPdf(slide.id, localPath);
            _localPdfPaths.remove(slide.id);
          }
        } else {
          _localPdfPaths.remove(slide.id);
        }
      }
    } else {
      // Group by subtitle
      _slidesBySubtitle = {};
      for (final s in _slides) {
        final sub = s.subtitle.trim().isEmpty ? 'General' : s.subtitle.trim();
        _slidesBySubtitle.putIfAbsent(sub, () => []).add(s);
      }

      if (_slidesBySubtitle.keys.length == 1) {
        // Bypass: open workspace screen directly for the only subtitle
        _openSlideWorkspace(_slidesBySubtitle.keys.first);
        return true;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    return false;
  }

  void _openSlideWorkspace(String subtitle) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SlideWorkspaceScreen(
          stationName: '${widget.stationName} - $subtitle',
          stationDbId: widget.stationDbId,
          filterSubtitle: subtitle == 'General' ? '' : subtitle,
        ),
      ),
    );
  }

  Future<void> _openPdfWorkspace(WorkspaceSlide pdfSlide, String path) async {
    if (!mounted) return;

    // Verify file validity before opening
    final isValid = await _isPdfValid(path);
    if (!isValid) {
      await _cleanupCorruptedPdf(pdfSlide.id, path);
      if (mounted) {
        setState(() {
          _localPdfPaths.remove(pdfSlide.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الملف غير صالح أو غير مكتمل. جاري إعادة التنزيل...'),
            duration: Duration(seconds: 2),
          ),
        );
        _downloadPdf(pdfSlide);
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfWorkspaceScreen(
          stationName: pdfSlide.title,
          stationDbId: widget.stationDbId,
          pdfSlide: pdfSlide,
          localPdfPath: path,
        ),
      ),
    );
  }

  Future<void> _downloadPdf(WorkspaceSlide slide) async {
    if (_isDownloading[slide.id] == true) return;

    final url = slide.pdfUrl;
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('روابط الملف غير متوفر')),
      );
      return;
    }

    setState(() {
      _isDownloading[slide.id] = true;
      _downloadProgress[slide.id] = 0.0;
    });

    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/cached_pdfs');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final localPath = '${cacheDir.path}/${slide.id}.pdf';
    final tmpPath = '$localPath.tmp';
    final tmpFile = File(tmpPath);

    if (await tmpFile.exists()) {
      try { await tmpFile.delete(); } catch (_) {}
    }

    final client = HttpClient();
    _activeClients[slide.id] = client;

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final total = response.contentLength;

      if (response.statusCode != 200) {
        throw Exception('HTTP response code ${response.statusCode}');
      }

      final sink = tmpFile.openWrite();

      var received = 0;
      await response.forEach((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && mounted) {
          setState(() {
            _downloadProgress[slide.id] = received / total;
          });
        }
      });

      await sink.close();
      _activeClients.remove(slide.id);
      client.close();

      // Check PDF validity on tmp file before finalizing
      final isValid = await _isPdfValid(tmpPath);
      if (!isValid) {
        throw Exception('Downloaded file validation failed');
      }

      // Pre-process sound annotations as part of download completion step
      if (mounted) {
        setState(() {
          _downloadProgress[slide.id] = 0.95;
        });
      }

      try {
        final tempDir = await getTemporaryDirectory();
        final pdfCacheDir = Directory('${tempDir.path}/pdf_pages_cache/${slide.id}');
        if (!await pdfCacheDir.exists()) {
          await pdfCacheDir.create(recursive: true);
        }

        final soundCacheFile = File('${pdfCacheDir.path}/sound_annotations.json');
        if (!soundCacheFile.existsSync()) {
          final soundAnnotations = await PdfSoundParser.parseAndExtract(
            tmpPath,
            pdfCacheDir.path,
          );
          if (soundAnnotations.isNotEmpty) {
            final jsonList = soundAnnotations.map((a) => a.toJson()).toList();
            await File('${pdfCacheDir.path}/sound_annotations.json')
                .writeAsString(jsonEncode(jsonList));
          }
        }

        // Pre-render Page 1 & page sizes if not cached yet for 0ms workspace launch
        final page1File = File('${pdfCacheDir.path}/page_1.jpg');
        if (!page1File.existsSync()) {
          final pdfDoc = await PdfDocument.openFile(tmpPath);
          final count = pdfDoc.pagesCount;
          if (count > 0) {
            final pageSizes = <String, dynamic>{};
            final p1 = await pdfDoc.getPage(1);
            pageSizes['1'] = {'w': p1.width, 'h': p1.height};
            final img = await p1.render(
              width: p1.width * 2.2,
              height: p1.height * 2.2,
              format: PdfPageImageFormat.jpeg,
              backgroundColor: '#FFFFFF',
              quality: 92,
            );
            await p1.close();
            if (img != null && img.bytes.isNotEmpty) {
              await page1File.writeAsBytes(img.bytes, flush: true);
            }
            await File('${pdfCacheDir.path}/page_sizes.json')
                .writeAsString(jsonEncode(pageSizes));
          }
          await pdfDoc.close();
        }
      } catch (e) {
        debugPrint('Error pre-processing PDF assets during download: $e');
      }

      // Rename tmp file to final file ONLY on complete success
      final targetFile = File(localPath);
      if (await targetFile.exists()) {
        try { await targetFile.delete(); } catch (_) {}
      }
      await tmpFile.rename(localPath);

      if (mounted) {
        setState(() {
          _downloadProgress[slide.id] = 1.0;
          _isDownloading[slide.id] = false;
          _localPdfPaths[slide.id] = localPath;
        });
      }

      _openPdfWorkspace(slide, localPath);
    } catch (e) {
      debugPrint('Error downloading PDF: $e');
      _activeClients.remove(slide.id);
      try { client.close(force: true); } catch (_) {}
      await _cleanupCorruptedPdf(slide.id, localPath);

      if (mounted) {
        setState(() {
          _isDownloading[slide.id] = false;
          _localPdfPaths.remove(slide.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تنزيل ملف الـ PDF. يرجى المحاولة مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _addNewPdfDialog() async {
    final titleController = TextEditingController();
    String? selectedFilePath;
    String? selectedFileName;
    int? selectedFileSize;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final brandColor = isDark ? const Color(0xFF9E86FF) : const Color(0xFF5B35F5);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                isUploading ? 'جاري رفع الملف...' : 'إضافة ملف PDF جديد',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUploading) ...[
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان المستند',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'PDF'],
                            withData: true,
                          );
                          if (result != null && result.files.isNotEmpty) {
                            final file = result.files.single;
                            String? filePath = file.path;

                            // iOS fallback: if path is null, write bytes to temporary directory
                            if ((filePath == null || filePath.isEmpty) && file.bytes != null) {
                              final tempDir = await getTemporaryDirectory();
                              final tempFile = File('${tempDir.path}/${file.name}');
                              await tempFile.writeAsBytes(file.bytes!, flush: true);
                              filePath = tempFile.path;
                            }

                            if (filePath != null && filePath.isNotEmpty) {
                              setModalState(() {
                                selectedFilePath = filePath;
                                selectedFileName = file.name;
                                selectedFileSize = file.size;
                              });
                            }
                          }
                        } catch (e) {
                          debugPrint('Error picking PDF file: $e');
                        }
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        selectedFilePath == null ? 'اختيار ملف PDF' : 'تم اختيار الملف ✓',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    if (selectedFileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        selectedFileName!,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (selectedFileSize != null)
                        Text(
                          '${(selectedFileSize! / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: brandColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ] else ...[
                    Text(
                      titleController.text.trim(),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: null,
                        minHeight: 10,
                        backgroundColor: brandColor.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'يرجى الانتظار...',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!isUploading) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty || selectedFilePath == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى كتابة عنوان واختيار ملف PDF')),
                        );
                        return;
                      }

                      setModalState(() {
                        isUploading = true;
                      });

                      try {
                        await _repository.createPdfSlide(
                          stationId: widget.stationDbId ?? '',
                          title: title,
                          pdfPath: selectedFilePath!,
                        );

                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        await _loadContent();
                      } catch (e) {
                        debugPrint('Error uploading PDF: $e');
                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('فشل رفع ملف الـ PDF. يرجى المحاولة مرة أخرى.')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('رفع وحفظ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addNewSlideDialog() async {
    if (widget.stationDbId == null || widget.stationDbId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرف المحطة غير متوفر')),
      );
      return;
    }

    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;

    final result = await showDialog<SlideEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SlideEditorDialog(
        slide: null,
        currentSlides: _slides,
        isDark: isDark,
        onSave: (editorResult) async {
          await _repository.createSlide(
            stationId: widget.stationDbId!,
            title: editorResult.title,
            subtitle: editorResult.subtitle,
            questions: editorResult.questions,
            imagePath: editorResult.imagePath,
            imageBytes: editorResult.imageBytes,
            imageFileName: editorResult.imageFileName,
            imageContentType: editorResult.imageContentType,
            audioPath: editorResult.audioPath,
          );
        },
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة الشريحة بنجاح', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
        ),
      );
      await _loadContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isDark = provider.isDarkTheme;
    final brandColor = isDark ? const Color(0xFF9E86FF) : const Color(0xFF5B35F5);
    final canManageSlides = provider.isAdminOrOwner;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
        body: const Center(
          child: LogoSpinner(size: 78, logoSize: 42),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF171428) : const Color(0xFFF9F8FD),
      appBar: AppBar(
        title: Text(
          widget.stationName,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        actions: [
          if (provider.isAdminOrOwner &&
              widget.stationType != 'pdf' &&
              _slidesBySubtitle.keys.length > 1)
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: 'ترتيب الأقسام',
              onPressed: () => _showReorderSubtitlesDialog(isDark, brandColor),
            ),
        ],
      ),
      body: _slides.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.stationType == 'pdf'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.slideshow_outlined,
                      size: 64,
                      color: brandColor.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد محتويات متوفرة لهذه المحطة حالياً.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (canManageSlides) ...[
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: widget.stationType == 'pdf'
                            ? _addNewPdfDialog
                            : _addNewSlideDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(widget.stationType == 'pdf'
                            ? Icons.picture_as_pdf
                            : Icons.add_to_photos),
                        label: Text(
                          widget.stationType == 'pdf'
                              ? 'إضافة ملف PDF جديد'
                              : 'إضافة شريحة جديدة',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: widget.stationType == 'pdf'
                  ? _buildPdfList(isDark, brandColor)
                  : _buildSubtitlesList(isDark, brandColor),
            ),
      floatingActionButton: canManageSlides
          ? FloatingActionButton.extended(
              onPressed: widget.stationType == 'pdf'
                  ? _addNewPdfDialog
                  : _addNewSlideDialog,
              backgroundColor: brandColor,
              icon: Icon(
                widget.stationType == 'pdf'
                    ? Icons.picture_as_pdf
                    : Icons.add_to_photos,
                color: Colors.white,
              ),
              label: Text(
                widget.stationType == 'pdf'
                    ? 'إضافة ملف PDF'
                    : 'إضافة شريحة جديدة',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSubtitlesList(bool isDark, Color brandColor) {
    final subtitles = _slidesBySubtitle.keys.toList()
      ..sort((a, b) {
        final aIndex = _slidesBySubtitle[a]?.firstOrNull?.subtitleIndex ?? 0;
        final bIndex = _slidesBySubtitle[b]?.firstOrNull?.subtitleIndex ?? 0;
        return aIndex.compareTo(bIndex);
      });
    return ListView.builder(
      itemCount: subtitles.length,
      itemBuilder: (context, index) {
        final sub = subtitles[index];
        final count = _slidesBySubtitle[sub]?.length ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isDark ? const Color(0xFF242038) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(
              sub,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              '$count شرائح متوفرة',
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey,
              ),
            ),
            trailing: Icon(Icons.arrow_forward_ios, color: brandColor),
            onTap: () => _openSlideWorkspace(sub),
          ),
        );
      },
    );
  }

  Widget _buildDownloadProgressWidget(Color brandColor, double progress, bool isDark) {
    final faintColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : brandColor.withValues(alpha: 0.20);

    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress > 0.05 ? progress : null,
            strokeWidth: 3.5,
            backgroundColor: faintColor,
            valueColor: AlwaysStoppedAnimation<Color>(brandColor),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: brandColor,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfList(bool isDark, Color brandColor) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final canManage = provider.isAdminOrOwner;

    return ListView.builder(
      itemCount: _slides.length,
      itemBuilder: (context, index) {
        final pdfSlide = _slides[index];
        final pdfId = pdfSlide.id;
        final isDownloaded = _localPdfPaths.containsKey(pdfId);
        final downloading = _isDownloading[pdfId] == true;
        final progress = _downloadProgress[pdfId] ?? 0.0;

        Widget trailingWidget;
        if (downloading) {
          trailingWidget = _buildDownloadProgressWidget(brandColor, progress, isDark);
        } else if (canManage) {
          trailingWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                color: Colors.redAccent,
                tooltip: 'حذف الملف',
                onPressed: () => _confirmDeletePdf(pdfSlide),
              ),
              Icon(
                isDownloaded ? Icons.play_circle_fill : Icons.download_for_offline,
                color: brandColor,
                size: 32,
              ),
            ],
          );
        } else {
          trailingWidget = Icon(
            isDownloaded ? Icons.play_circle_fill : Icons.download_for_offline,
            color: brandColor,
            size: 32,
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isDark ? const Color(0xFF242038) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Icon(
              Icons.picture_as_pdf,
              size: 38,
              color: isDownloaded ? brandColor : Colors.grey,
            ),
            title: Text(
              pdfSlide.title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              pdfSlide.subtitle.isEmpty ? 'ملف مستند PDF' : pdfSlide.subtitle,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
            trailing: trailingWidget,
            onTap: () {
              if (downloading) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('جاري تنزيل الملف، يُرجى الانتظار...'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else if (isDownloaded) {
                _openPdfWorkspace(pdfSlide, _localPdfPaths[pdfId]!);
              } else {
                _downloadPdf(pdfSlide);
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePdf(WorkspaceSlide pdfSlide) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;
    final brandColor = isDark ? const Color(0xFF9E86FF) : const Color(0xFF5B35F5);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'حذف الملف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف "${pdfSlide.title}"؟\nلا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'حذف',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _repository.deleteSlide(pdfSlide.id);
      // Also remove local cached file if exists
      final localPath = _localPdfPaths[pdfSlide.id];
      if (localPath != null) {
        try {
          final file = File(localPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _slides.removeWhere((s) => s.id == pdfSlide.id);
          _localPdfPaths.remove(pdfSlide.id);
          _downloadProgress.remove(pdfSlide.id);
          _isDownloading.remove(pdfSlide.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الملف بنجاح', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حذف الملف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showReorderSubtitlesDialog(bool isDark, Color brandColor) async {
    final currentSubtitles = _slidesBySubtitle.keys.toList()
      ..sort((a, b) {
        final aIndex = _slidesBySubtitle[a]?.firstOrNull?.subtitleIndex ?? 0;
        final bIndex = _slidesBySubtitle[b]?.firstOrNull?.subtitleIndex ?? 0;
        return aIndex.compareTo(bIndex);
      });

    if (currentSubtitles.length <= 1) return;

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReorderSubtitlesDialog(
        subtitles: currentSubtitles,
        slidesBySubtitle: _slidesBySubtitle,
        isDark: isDark,
        brandColor: brandColor,
        onSave: (orderedList) async {
          if (widget.stationDbId == null || widget.stationDbId!.isEmpty) return;
          await _repository.reorderSubtitles(widget.stationDbId!, orderedList);
          await _loadContent();
        },
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ ترتيب الأقسام بنجاح', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class _ReorderSubtitlesDialog extends StatefulWidget {
  final List<String> subtitles;
  final Map<String, List<WorkspaceSlide>> slidesBySubtitle;
  final bool isDark;
  final Color brandColor;
  final Future<void> Function(List<String> ordered) onSave;

  const _ReorderSubtitlesDialog({
    required this.subtitles,
    required this.slidesBySubtitle,
    required this.isDark,
    required this.brandColor,
    required this.onSave,
  });

  @override
  State<_ReorderSubtitlesDialog> createState() => _ReorderSubtitlesDialogState();
}

class _ReorderSubtitlesDialogState extends State<_ReorderSubtitlesDialog> {
  late List<String> _subtitles;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _subtitles = List<String>.from(widget.subtitles);
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await widget.onSave(_subtitles);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ الترتيب: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final dialogBg = isDark ? const Color(0xFF1E1A2E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF28233D) : const Color(0xFFF7F5FE);
    final borderColor = isDark ? const Color(0xFF3B3356) : const Color(0xFFE2DCFA);
    final textColor = isDark ? Colors.white : Colors.black87;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 540,
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.swap_vert_rounded,
                      color: widget.brandColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ترتيب الأقسام الفرعية',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'قم بسحب وإفلات الأقسام لترتيبها',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _subtitles = _subtitles.reversed.toList();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم عكس ترتيب الأقسام. اضغط "حفظ الترتيب" لتأكيد الحفظ.',
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                                duration: Duration(seconds: 2),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.flip_camera_android_rounded, size: 16),
                    label: const Text(
                      'عكس الأقسام',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إلغاء',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Reorderable list
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _subtitles.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = _subtitles.removeAt(oldIndex);
                      _subtitles.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final sub = _subtitles[index];
                    final count = widget.slidesBySubtitle[sub]?.length ?? 0;

                    return KeyedSubtree(
                      key: ValueKey(sub),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor, width: 1),
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: widget.brandColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: widget.brandColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sub,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '$count شرائح',
                                    style: TextStyle(
                                      color: isDark ? Colors.white54 : Colors.black45,
                                      fontSize: 12,
                                      fontFamily: 'Cairo',
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

              const Divider(height: 1),
              const SizedBox(height: 16),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontSize: 15)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.brandColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(
                      _isSaving ? 'جاري الحفظ...' : 'حفظ الترتيب',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
