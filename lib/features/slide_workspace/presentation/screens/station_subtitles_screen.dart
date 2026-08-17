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

  @override
  void initState() {
    super.initState();
    _loadContent();
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
        final file = File(localPath);
        if (await file.exists()) {
          _localPdfPaths[slide.id] = localPath;
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

  void _openPdfWorkspace(WorkspaceSlide pdfSlide, String path) {
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

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/cached_pdfs');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final localPath = '${cacheDir.path}/${slide.id}.pdf';

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final total = response.contentLength;

      final file = File(localPath);
      final sink = file.openWrite();

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
      client.close();

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
            localPath,
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
          final pdfDoc = await PdfDocument.openFile(localPath);
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
      setState(() {
        _isDownloading[slide.id] = false;
      });
      if (mounted) {
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
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isDark = provider.isDarkTheme;

    final result = await showDialog<SlideEditorResult>(
      context: context,
      builder: (dialogContext) => SlideEditorDialog(
        slide: null,
        currentSlides: _slides,
        isDark: isDark,
      ),
    );

    if (result == null || !mounted) return;

    if (widget.stationDbId == null || widget.stationDbId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرف المحطة غير متوفر')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _repository.createSlide(
        stationId: widget.stationDbId!,
        title: result.title,
        subtitle: result.subtitle,
        questions: result.questions,
        imagePath: result.imagePath,
        imageBytes: result.imageBytes,
        imageFileName: result.imageFileName,
        imageContentType: result.imageContentType,
        audioPath: result.audioPath,
      );

      await _loadContent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت إضافة الشريحة بنجاح', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error adding slide from StationSubtitlesScreen: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل إضافة الشريحة. يرجى المحاولة مرة أخرى.', style: TextStyle(fontFamily: 'Cairo')),
          ),
        );
      }
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
    final subtitles = _slidesBySubtitle.keys.toList();
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

  Widget _buildPdfList(bool isDark, Color brandColor) {
    return ListView.builder(
      itemCount: _slides.length,
      itemBuilder: (context, index) {
        final pdfSlide = _slides[index];
        final pdfId = pdfSlide.id;
        final isDownloaded = _localPdfPaths.containsKey(pdfId);
        final downloading = _isDownloading[pdfId] == true;
        final progress = _downloadProgress[pdfId] ?? 0.0;

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
            trailing: downloading
                ? SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                    ),
                  )
                : Icon(
                    isDownloaded ? Icons.play_circle_fill : Icons.download_for_offline,
                    color: brandColor,
                    size: 32,
                  ),
            onTap: () {
              if (isDownloaded) {
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
}
