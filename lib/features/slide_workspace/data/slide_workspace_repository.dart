import 'dart:async';
import 'dart:typed_data';

import '../../../core/services/cache_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/entities/slide_workspace_models.dart';

abstract class SlideWorkspaceRepository {
  Future<List<WorkspaceSlide>> getSlides(String? stationId);
  List<WorkspaceSlide> getCachedSlidesSync(String? stationId);
  Future<List<WorkspaceSlide>> getCachedSlides(String? stationId);
  Future<List<WorkspaceSlide>> refreshSlides(String? stationId);
  Future<WorkspaceSlide> createSlide({
    required String stationId,
    required String title,
    required String subtitle,
    required List<WorkspaceQuestion> questions,
    int? insertAfterSlideIndex,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
    String? audioPath,
  });
  Future<WorkspaceSlide> updateSlide({
    required String slideId,
    required String title,
    required String subtitle,
    required List<WorkspaceQuestion> questions,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
    String? audioPath,
  });
  Future<WorkspaceSlide> duplicateSlide(WorkspaceSlide slide);
  Future<WorkspaceSlide> createBlankSlide({required String stationId});
  Future<void> deleteSlide(String slideId);
  Future<WorkspaceSlide> setSlideHidden(String slideId, bool isHidden);
  Future<void> reorderSlides(String stationId, List<WorkspaceSlide> slides);
  Future<void> saveSlideStrokes(String slideId, List<WorkspaceObject> strokes,
      {bool isExamMode = false});
  Future<void> saveLastOpenedSlide(String stationId, String slideId);
  Future<String?> uploadWorkspaceImage(Uint8List bytes, String fileName);
  Future<bool> deleteWorkspaceImage(String publicUrl);
  Future<Map<int, List<WorkspaceObject>>> getPdfAnnotations(String pdfId);
  Future<void> savePdfAnnotations(String pdfId, String stationId, int pageNumber, List<WorkspaceObject> strokes);
  Future<void> savePdfLastOpenedPage(String pdfId, String stationId, int pageNumber);
}

class SupabaseSlideWorkspaceRepository implements SlideWorkspaceRepository {
  SupabaseSlideWorkspaceRepository({SupabaseService? supabase})
      : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;
  final CacheService _cache = CacheService();

  static final Map<String, List<WorkspaceSlide>> _memorySlidesCache = {};

  @override
  Future<List<WorkspaceSlide>> getSlides(String? stationId) async {
    final cached = await getCachedSlides(stationId);
    try {
      return await refreshSlides(stationId);
    } catch (_) {
      return cached;
    }
  }

  @override
  List<WorkspaceSlide> getCachedSlidesSync(String? stationId) {
    if (stationId == null || stationId.trim().isEmpty) return const [];
    if (_memorySlidesCache.containsKey(stationId)) {
      return _memorySlidesCache[stationId]!;
    }
    dynamic cached;
    try {
      cached = _cache.getCacheAllowExpired(_slidesCacheKey(stationId));
    } catch (_) {
      // CacheService may still be initializing during a cold app start.
      return const [];
    }
    if (cached is! Map) return const [];
    final items = cached['slides'];
    if (items is! List) return const [];
    final slides = items
        .whereType<Map>()
        .map((item) => _slideFromCache(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) {
          final cmpSubtitle = a.subtitleIndex.compareTo(b.subtitleIndex);
          if (cmpSubtitle != 0) return cmpSubtitle;
          final cmpSubtitleSlide =
              a.subtitleSlideIndex.compareTo(b.subtitleSlideIndex);
          if (cmpSubtitleSlide != 0) return cmpSubtitleSlide;
          return a.index.compareTo(b.index);
        });
    _memorySlidesCache[stationId] = slides;
    return slides;
  }

  @override
  Future<List<WorkspaceSlide>> getCachedSlides(String? stationId) async {
    return getCachedSlidesSync(stationId);
  }

  @override
  Future<List<WorkspaceSlide>> refreshSlides(String? stationId) async {
    if (stationId == null || stationId.trim().isEmpty) return const [];
    await syncPendingSlideStrokes(stationId);

    final slideRows = await _supabase.client
        .from('slides')
        .select('*')
        .eq('station_id', stationId)
        .eq('is_active', true)
        .order('subtitle_index', ascending: true)
        .order('subtitle_slide_index', ascending: true)
        .order('slide_index', ascending: true);
    final slideRowList = List<Map<String, dynamic>>.from(slideRows);
    final hasCorruptedIndex = slideRowList.any(
      (row) => ((row['subtitle_index'] as num?)?.toInt() ?? 0) >= 1000000,
    );
    if (hasCorruptedIndex) {
      unawaited(_normalizeStationOrder(stationId));
    }

    final role = (await _supabase.getUserRole())?.trim().toLowerCase();
    final canManageSlides =
        role == 'owner' || role == 'admin' || role == 'manager';

    final slides = List<Map<String, dynamic>>.from(slideRows)
        .where((row) => canManageSlides || row['is_hidden'] != true)
        .map(_slideFromRow)
        .toList();
    if (slides.isEmpty) {
      await _cacheSlides(stationId, const []);
      return const [];
    }

    final user = _supabase.currentUser;
    if (user == null) {
      await _cacheSlides(stationId, slides);
      return slides;
    }

    final workspaceRows = await _supabase.client
        .from('user_slide_workspaces')
        .select('slide_id, notes_layer, exam_layer')
        .eq('user_id', user.id)
        .eq('station_id', stationId);
    final drawingBySlide = <String, List<WorkspaceObject>>{};
    final examDrawingBySlide = <String, List<WorkspaceObject>>{};
    for (final row in List<Map<String, dynamic>>.from(workspaceRows)) {
      drawingBySlide[row['slide_id'].toString()] =
          _objectsFromJson(row['notes_layer']);
      examDrawingBySlide[row['slide_id'].toString()] =
          _objectsFromJson(row['exam_layer']);
    }

    final pending = _pendingObjects(stationId, isExamMode: false);
    final pendingExam = _pendingObjects(stationId, isExamMode: true);
    final merged = [
      for (final slide in slides)
        slide.copyWith(
          strokes:
              pending[slide.id] ?? drawingBySlide[slide.id] ?? slide.strokes,
          examStrokes: pendingExam[slide.id] ??
              examDrawingBySlide[slide.id] ??
              slide.examStrokes,
        ),
    ]..sort((a, b) {
        final cmpSubtitle = a.subtitleIndex.compareTo(b.subtitleIndex);
        if (cmpSubtitle != 0) return cmpSubtitle;
        final cmpSubtitleSlide =
            a.subtitleSlideIndex.compareTo(b.subtitleSlideIndex);
        if (cmpSubtitleSlide != 0) return cmpSubtitleSlide;
        return a.index.compareTo(b.index);
      });
    await _cacheSlides(stationId, merged);
    return merged;
  }

  @override
  Future<WorkspaceSlide> createSlide({
    required String stationId,
    required String title,
    required String subtitle,
    required List<WorkspaceQuestion> questions,
    int? insertAfterSlideIndex,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
    String? audioPath,
  }) async {
    final existing = await _supabase.client
        .from('slides')
        .select(
            'id, slide_index, subtitle, subtitle_index, subtitle_slide_index')
        .eq('station_id', stationId)
        .eq('is_active', true)
        .order('subtitle_index', ascending: true)
        .order('subtitle_slide_index', ascending: true)
        .order('slide_index', ascending: true);
    final rows = List<Map<String, dynamic>>.from(existing);
    final usedIndexes = rows
        .map((row) => (row['slide_index'] as num?)?.toInt())
        .whereType<int>()
        .where((index) => index > 0)
        .toSet();
    var nextIndex = 1;
    if (insertAfterSlideIndex != null) {
      final insertionIndex =
          (insertAfterSlideIndex + 1).clamp(1, rows.length + 1);
      final rowsToShift = rows.where((row) {
        final index = (row['slide_index'] as num?)?.toInt();
        return index != null && index >= insertionIndex;
      }).toList()
        ..sort((a, b) => ((b['slide_index'] as num?)?.toInt() ?? 0)
            .compareTo((a['slide_index'] as num?)?.toInt() ?? 0));

      for (final row in rowsToShift) {
        final id = row['id']?.toString();
        final index = (row['slide_index'] as num?)?.toInt();
        if (id == null || index == null) continue;
        await _supabase.client
            .from('slides')
            .update({'slide_index': index + 1}).eq('id', id);
      }
      nextIndex = insertionIndex;
    } else {
      while (usedIndexes.contains(nextIndex)) {
        nextIndex++;
      }
    }

    final subtitleKey = subtitle.trim().toLowerCase();
    final sameSubtitle = rows.where(
      (row) =>
          (row['subtitle'] ?? '').toString().trim().toLowerCase() ==
          subtitleKey,
    );
    final subtitleIndex = sameSubtitle.isNotEmpty
        ? (sameSubtitle.first['subtitle_index'] as num?)?.toInt() ?? 1
        : rows
                .map((row) => (row['subtitle_index'] as num?)?.toInt() ?? 0)
                .fold<int>(0,
                    (maxValue, value) => value > maxValue ? value : maxValue) +
            1;
    final subtitleSlideIndex = sameSubtitle
            .map((row) => (row['subtitle_slide_index'] as num?)?.toInt() ?? 0)
            .fold<int>(
                0, (maxValue, value) => value > maxValue ? value : maxValue) +
        1;

    final hasSelectedImage =
        (imagePath != null && imagePath.trim().isNotEmpty) ||
            (imageBytes != null && imageBytes.isNotEmpty);
    final uploadedImageUrl = await _uploadSlideImage(
      imagePath: imagePath,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      imageContentType: imageContentType,
    );
    if (hasSelectedImage &&
        (uploadedImageUrl == null || uploadedImageUrl.isEmpty)) {
      throw Exception(_supabase.lastError ?? 'Image upload failed');
    }
    final uploadedAudioUrl = audioPath == null || audioPath.trim().isEmpty
        ? null
        : await _supabase.uploadFile(
            'question-audios',
            audioPath,
            folder: 'slides',
          );
    final qaItems = _qaItems(questions);

    final inserted = await _supabase.client
        .from('slides')
        .insert({
          'station_id': stationId,
          'slide_index': nextIndex,
          'subtitle_index': subtitleIndex,
          'subtitle_slide_index': subtitleSlideIndex,
          'title': title,
          'subtitle': subtitle,
          'image_url': uploadedImageUrl,
          'voice_url': uploadedAudioUrl,
          'questions': qaItems,
          'metadata': {
            if (uploadedAudioUrl != null) 'audio_url': uploadedAudioUrl,
            if (uploadedImageUrl != null) 'image_url': uploadedImageUrl,
          },
          'is_active': true,
          'is_hidden': false,
        })
        .select('*')
        .single();

    if (insertAfterSlideIndex != null) {
      await _reorderStationSlides(stationId);
    }
    await _syncStationSlideCount(stationId);
    return _slideFromRow(Map<String, dynamic>.from(inserted));
  }

  @override
  Future<WorkspaceSlide> updateSlide({
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
    final existing = await _supabase.client
        .from('slides')
        .select('station_id, subtitle, image_url, voice_url')
        .eq('id', slideId)
        .single();
    final stationId = (existing['station_id'] ?? '').toString();
    final previousSubtitle = (existing['subtitle'] ?? '').toString();
    final previousImageUrl = (existing['image_url'] as String?)?.trim() ?? '';
    final previousAudioUrl = (existing['voice_url'] as String?)?.trim() ?? '';
    final subtitleChanged =
        previousSubtitle.trim().toLowerCase() != subtitle.trim().toLowerCase();

    final hasSelectedImage =
        (imagePath != null && imagePath.trim().isNotEmpty) ||
            (imageBytes != null && imageBytes.isNotEmpty);
    final uploadedImageUrl = await _uploadSlideImage(
      imagePath: imagePath,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      imageContentType: imageContentType,
    );
    if (hasSelectedImage &&
        (uploadedImageUrl == null || uploadedImageUrl.isEmpty)) {
      throw Exception(_supabase.lastError ?? 'Image upload failed');
    }
    final uploadedAudioUrl = audioPath == null || audioPath.trim().isEmpty
        ? null
        : (audioPath == 'clear_audio'
            ? 'clear_audio'
            : await _supabase.uploadFile(
                'question-audios',
                audioPath,
                folder: 'slides',
              ));
    final qaItems = _qaItems(questions);

    // Fetch existing metadata to preserve other properties if any
    final existingSlide = await _supabase.client
        .from('slides')
        .select('metadata')
        .eq('id', slideId)
        .single();
    final previousMetadata =
        Map<String, dynamic>.from(existingSlide['metadata'] ?? {});

    if (uploadedImageUrl != null)
      previousMetadata['image_url'] = uploadedImageUrl;
    if (uploadedAudioUrl != null) {
      if (uploadedAudioUrl == 'clear_audio') {
        previousMetadata.remove('audio_url');
      } else {
        previousMetadata['audio_url'] = uploadedAudioUrl;
      }
    }

    final payload = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'questions': qaItems,
      if (uploadedImageUrl != null) 'image_url': uploadedImageUrl,
      if (uploadedAudioUrl != null)
        'voice_url':
            uploadedAudioUrl == 'clear_audio' ? null : uploadedAudioUrl,
      'metadata': previousMetadata,
    };

    if (subtitleChanged && stationId.isNotEmpty) {
      final rows = List<Map<String, dynamic>>.from(await _supabase.client
          .from('slides')
          .select('subtitle, subtitle_index, subtitle_slide_index')
          .eq('station_id', stationId)
          .eq('is_active', true)
          .neq('id', slideId)
          .order('subtitle_index', ascending: true)
          .order('subtitle_slide_index', ascending: true));
      final subtitleKey = subtitle.trim().toLowerCase();
      final matches = rows.where((row) =>
          (row['subtitle'] ?? '').toString().trim().toLowerCase() ==
          subtitleKey);
      payload['subtitle_index'] = matches.isNotEmpty
          ? (matches.first['subtitle_index'] as num?)?.toInt() ?? 1
          : rows.fold<int>(
                0,
                (maximum, row) =>
                    ((row['subtitle_index'] as num?)?.toInt() ?? 0) > maximum
                        ? ((row['subtitle_index'] as num?)?.toInt() ?? 0)
                        : maximum,
              ) +
              1;
      payload['subtitle_slide_index'] = matches.fold<int>(
            0,
            (maximum, row) =>
                ((row['subtitle_slide_index'] as num?)?.toInt() ?? 0) > maximum
                    ? ((row['subtitle_slide_index'] as num?)?.toInt() ?? 0)
                    : maximum,
          ) +
          1;
    }

    await _supabase.client.from('slides').update(payload).eq('id', slideId);

    // Clean up old image from storage if replaced
    if (uploadedImageUrl != null &&
        previousImageUrl.isNotEmpty &&
        previousImageUrl != uploadedImageUrl) {
      try {
        await _supabase.deleteStorageFile('question-images', previousImageUrl);
      } catch (e) {
        // Log the error but don't fail the update return
        print('Failed to delete old image file from storage: $e');
      }
    }
    // Clean up old audio from storage if replaced
    if (uploadedAudioUrl != null &&
        previousAudioUrl.isNotEmpty &&
        previousAudioUrl != uploadedAudioUrl) {
      try {
        await _supabase.deleteStorageFile('question-audios', previousAudioUrl);
      } catch (e) {
        print('Failed to delete old audio file from storage: $e');
      }
    }

    if (stationId.isNotEmpty) await _normalizeStationOrder(stationId);
    final updated = await _supabase.client
        .from('slides')
        .select('*')
        .eq('id', slideId)
        .single();
    return _slideFromRow(Map<String, dynamic>.from(updated));
  }

  @override
  Future<WorkspaceSlide> duplicateSlide(WorkspaceSlide slide) async {
    final stationId = (slide.metadata['station_id'] ?? '').toString();
    if (stationId.isEmpty) throw Exception('Missing station id for duplicate');

    final existing = await _supabase.client
        .from('slides')
        .select('slide_index, subtitle_index, subtitle_slide_index')
        .eq('station_id', stationId)
        .eq('is_active', true);
    final rows = List<Map<String, dynamic>>.from(existing);
    final usedIndexes = rows
        .map((row) => (row['slide_index'] as num?)?.toInt())
        .whereType<int>()
        .where((index) => index > 0)
        .toSet();
    var nextIndex = 1;
    while (usedIndexes.contains(nextIndex)) {
      nextIndex++;
    }

    final subtitleIndex = slide.subtitleIndex;
    final subtitleSlideIndex = rows
            .where((row) =>
                (row['subtitle_index'] as num?)?.toInt() == subtitleIndex)
            .map((row) => (row['subtitle_slide_index'] as num?)?.toInt() ?? 0)
            .fold<int>(
                0, (maxValue, value) => value > maxValue ? value : maxValue) +
        1;

    final qaItems = _qaItems(slide.questions);
    final inserted = await _supabase.client
        .from('slides')
        .insert({
          'station_id': stationId,
          'slide_index': nextIndex,
          'subtitle_index': subtitleIndex,
          'subtitle_slide_index': subtitleSlideIndex,
          'title': slide.title,
          'subtitle': slide.subtitle,
          'image_url': slide.imageAsset.isEmpty ? null : slide.imageAsset,
          'voice_url': slide.audioUrl.isEmpty ? null : slide.audioUrl,
          'questions': qaItems,
          'metadata': {
            ...slide.metadata,
            'station_id': stationId,
            if (slide.imageAsset.isNotEmpty) 'image_url': slide.imageAsset,
            if (slide.audioUrl.isNotEmpty) 'audio_url': slide.audioUrl,
          },
          'is_active': true,
          'is_hidden': slide.isHidden,
        })
        .select('*')
        .single();
    await _syncStationSlideCount(stationId);
    return _slideFromRow(Map<String, dynamic>.from(inserted));
  }

  @override
  Future<WorkspaceSlide> createBlankSlide({required String stationId}) {
    return createSlide(
      stationId: stationId,
      title: 'Untitled Slide',
      subtitle: '',
      questions: const [],
    );
  }

  Future<WorkspaceSlide> createPdfSlide({
    required String stationId,
    required String title,
    required String pdfPath,
    void Function(double progress)? onProgress,
  }) async {
    final pdfUrl = await _supabase.uploadFile(
      'pdf-documents',
      pdfPath,
      folder: 'stations',
      onProgress: onProgress,
    );
    if (pdfUrl == null || pdfUrl.isEmpty) {
      throw Exception('PDF upload failed');
    }

    final existingSlides = await _supabase.client
        .from('slides')
        .select('id')
        .eq('station_id', stationId);
    final nextIndex = (existingSlides as List).length + 1;

    final inserted = await _supabase.client
        .from('slides')
        .insert({
          'station_id': stationId,
          'title': title,
          'subtitle': '',
          'pdf_url': pdfUrl,
          'slide_index': nextIndex,
          'subtitle_index': 1,
          'subtitle_slide_index': 1,
          'questions': [],
        })
        .select()
        .single();

    return _slideFromRow(inserted);
  }

  @override
  Future<void> deleteSlide(String slideId) async {
    // 1. Fetch the row to get station_id, image_url, and voice_url before deleting
    final row = await _supabase.client
        .from('slides')
        .select('station_id, image_url, voice_url, metadata')
        .eq('id', slideId)
        .maybeSingle();

    if (row == null) return;

    final stationId = row['station_id'].toString();

    // 2. Extract image URL and audio URL from column or metadata JSON
    final imageUrl = (row['image_url'] as String?)?.trim().isNotEmpty == true
        ? row['image_url'] as String
        : ((row['metadata'] as Map<String, dynamic>?)?['image_url'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true
            ? (row['metadata'] as Map<String, dynamic>)['image_url'] as String
            : null;

    final audioUrl = (row['voice_url'] as String?)?.trim().isNotEmpty == true
        ? row['voice_url'] as String
        : ((row['metadata'] as Map<String, dynamic>?)?['audio_url'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true
            ? (row['metadata'] as Map<String, dynamic>)['audio_url'] as String
            : null;

    // 3. Delete the slide row permanently from the database
    await _supabase.client.from('slides').delete().eq('id', slideId);

    // 4. Delete files from Supabase Storage (best-effort, don't block on failure)
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        await _supabase.deleteStorageFile('question-images', imageUrl);
      } catch (e) {
        print('Failed to delete slide image during deletion: $e');
      }
    }
    if (audioUrl != null && audioUrl.isNotEmpty) {
      try {
        await _supabase.deleteStorageFile('question-audios', audioUrl);
      } catch (e) {
        print('Failed to delete slide audio during deletion: $e');
      }
    }

    // 5. Sync slide count and reorder remaining slides
    await _syncStationSlideCount(stationId);
    await _reorderStationSlides(stationId);
  }

  @override
  Future<WorkspaceSlide> setSlideHidden(String slideId, bool isHidden) async {
    final updated = await _supabase.client
        .from('slides')
        .update({'is_hidden': isHidden})
        .eq('id', slideId)
        .select('*')
        .single();
    return _slideFromRow(Map<String, dynamic>.from(updated));
  }

  @override
  Future<void> reorderSlides(
      String stationId, List<WorkspaceSlide> slides) async {
    // 1. Assign unique negative indexes first to avoid unique constraint collisions
    for (var i = 0; i < slides.length; i++) {
      final slide = slides[i];
      await _supabase.client
          .from('slides')
          .update({'slide_index': -(i + 1)}).eq('id', slide.id);
    }

    // 2. Assign the final positive indexes
    for (var i = 0; i < slides.length; i++) {
      final slide = slides[i];
      await _supabase.client
          .from('slides')
          .update({'slide_index': i + 1}).eq('id', slide.id);
    }

    // 3. Let the RPC clean everything up atomically
    await _reorderStationSlides(stationId);
  }

  /// Calls the Supabase RPC function that atomically reorders all active slides
  /// for a station with clean sequential indexes (1, 2, 3...) using
  /// a two-phase SQL UPDATE to avoid unique constraint conflicts.
  Future<void> _reorderStationSlides(String stationId) async {
    await _supabase.client.rpc(
      'reorder_station_slides',
      params: {'p_station_id': stationId},
    );
  }

  /// @deprecated Use _reorderStationSlides instead.
  Future<void> _normalizeStationOrder(String stationId) =>
      _reorderStationSlides(stationId);

  Future<String?> _uploadSlideImage({
    String? imagePath,
    Uint8List? imageBytes,
    String? imageFileName,
    String? imageContentType,
  }) async {
    if (imagePath != null && imagePath.trim().isNotEmpty) {
      return _supabase.uploadFile(
        'question-images',
        imagePath,
        folder: 'slides',
      );
    }
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return _supabase.uploadFileBytes(
        'question-images',
        imageBytes,
        imageFileName?.trim().isNotEmpty == true
            ? imageFileName!.trim()
            : 'slide_image.png',
        folder: 'slides',
        contentType: imageContentType,
      );
    }
    return null;
  }

  @override
  Future<void> saveLastOpenedSlide(String stationId, String slideId) async {
    final user = _supabase.currentUser;
    if (user == null) return;
    await _supabase.client.from('user_slide_workspaces').upsert({
      'user_id': user.id,
      'slide_id': slideId,
      'station_id': stationId,
      'last_opened_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,slide_id');
  }

  @override
  Future<String?> uploadWorkspaceImage(Uint8List bytes, String fileName) async {
    final user = _supabase.currentUser;
    final folder =
        user != null ? 'student-workspace/${user.id}' : 'student-workspace';
    return _supabase.uploadFileBytes(
      'question-images',
      bytes,
      fileName,
      folder: folder,
    );
  }

  @override
  Future<bool> deleteWorkspaceImage(String publicUrl) async {
    return _supabase.deleteStorageFile('question-images', publicUrl);
  }

  @override
  Future<Map<int, List<WorkspaceObject>>> getPdfAnnotations(String pdfId) async {
    final user = _supabase.currentUser;
    if (user == null) return const {};

    try {
      final row = await _supabase.client
          .from('user_pdf_workspaces')
          .select('annotations')
          .eq('user_id', user.id)
          .eq('pdf_id', pdfId)
          .maybeSingle();

      if (row == null) return const {};
      final annotationsMap = Map<String, dynamic>.from(row['annotations'] as Map? ?? {});
      final results = <int, List<WorkspaceObject>>{};
      for (final entry in annotationsMap.entries) {
        final pageNum = int.tryParse(entry.key);
        if (pageNum != null) {
          results[pageNum] = _objectsFromJson(entry.value);
        }
      }
      return results;
    } catch (e) {
      print('Error fetching PDF annotations: $e');
      return const {};
    }
  }

  @override
  Future<void> savePdfAnnotations(
    String pdfId,
    String stationId,
    int pageNumber,
    List<WorkspaceObject> strokes,
  ) async {
    final user = _supabase.currentUser;
    if (user == null) return;

    try {
      final existing = await _supabase.client
          .from('user_pdf_workspaces')
          .select('annotations')
          .eq('user_id', user.id)
          .eq('pdf_id', pdfId)
          .maybeSingle();

      final currentAnnotations = Map<String, dynamic>.from(
        (existing != null ? existing['annotations'] : null) as Map? ?? {},
      );

      currentAnnotations[pageNumber.toString()] = {
        'objects': strokes.map((obj) => obj.toJson()).toList(),
      };

      await _supabase.client.from('user_pdf_workspaces').upsert({
        'user_id': user.id,
        'pdf_id': pdfId,
        'station_id': stationId,
        'annotations': currentAnnotations,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,pdf_id');
    } catch (e) {
      print('Error saving PDF annotations: $e');
    }
  }

  @override
  Future<void> savePdfLastOpenedPage(
    String pdfId,
    String stationId,
    int pageNumber,
  ) async {
    final user = _supabase.currentUser;
    if (user == null) return;

    try {
      await _supabase.client.from('user_pdf_workspaces').upsert({
        'user_id': user.id,
        'pdf_id': pdfId,
        'station_id': stationId,
        'last_opened_page': pageNumber,
        'last_opened_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,pdf_id');
    } catch (e) {
      print('Error saving PDF last opened page: $e');
    }
  }

  @override
  Future<void> saveSlideStrokes(String slideId, List<WorkspaceObject> strokes,
      {bool isExamMode = false}) async {
    final stationId = await _stationIdForSlide(slideId);
    if (stationId != null) {
      await _updateCachedStrokes(stationId, slideId, strokes,
          isExamMode: isExamMode);
    }

    final user = _supabase.currentUser;
    if (user == null || stationId == null) return;

    final fieldName = isExamMode ? 'exam_layer' : 'notes_layer';
    try {
      await _supabase.client.from('user_slide_workspaces').upsert({
        'user_id': user.id,
        'slide_id': slideId,
        'station_id': stationId,
        fieldName: {
          'objects': strokes.map((stroke) => stroke.toJson()).toList(),
        },
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,slide_id');
      await _removePendingStrokes(stationId, slideId, isExamMode: isExamMode);
    } catch (_) {
      await _setPendingStrokes(stationId, slideId, strokes,
          isExamMode: isExamMode);
    }
  }

  Future<void> syncPendingSlideStrokes(String stationId) async {
    final user = _supabase.currentUser;
    if (user == null || stationId.trim().isEmpty) return;

    for (final isExam in [false, true]) {
      final pending = _pendingObjects(stationId, isExamMode: isExam);
      if (pending.isEmpty) continue;

      final fieldName = isExam ? 'exam_layer' : 'notes_layer';
      final remaining = Map<String, List<WorkspaceObject>>.from(pending);
      for (final entry in pending.entries) {
        try {
          await _supabase.client.from('user_slide_workspaces').upsert({
            'user_id': user.id,
            'slide_id': entry.key,
            'station_id': stationId,
            fieldName: {
              'objects': entry.value.map((obj) => obj.toJson()).toList(),
            },
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id,slide_id');
          remaining.remove(entry.key);
        } catch (_) {
          break;
        }
      }

      await _cache.setCache(
        _pendingStrokesKey(stationId, isExamMode: isExam),
        {
          for (final entry in remaining.entries)
            entry.key: {
              'objects': entry.value.map((obj) => obj.toJson()).toList(),
            },
        },
        const Duration(days: 36500),
      );
    }
  }

  String _slidesCacheKey(String stationId) => 'slide_workspace_$stationId';
  String _pendingStrokesKey(String stationId, {bool isExamMode = false}) =>
      isExamMode
          ? 'pending_exam_slide_strokes_$stationId'
          : 'pending_slide_strokes_$stationId';

  Future<void> _cacheSlides(String stationId, List<WorkspaceSlide> slides) {
    _memorySlidesCache[stationId] = slides;
    return _cache.setCache(
      _slidesCacheKey(stationId),
      {
        'station_id': stationId,
        'cached_at': DateTime.now().toIso8601String(),
        'slides': slides.map(_slideToCache).toList(),
      },
      const Duration(days: 30),
    );
  }

  Map<String, dynamic> _slideToCache(WorkspaceSlide slide) => {
        'id': slide.id,
        'index': slide.index,
        'subtitle_index': slide.subtitleIndex,
        'subtitle_slide_index': slide.subtitleSlideIndex,
        'title': slide.title,
        'subtitle': slide.subtitle,
        'image_asset': slide.imageAsset,
        'audio_url': slide.audioUrl,
        'pdf_url': slide.pdfUrl,
        'is_hidden': slide.isHidden,
        'questions': slide.questions
            .map((question) => {
                  'prompt': question.prompt,
                  'answer': question.answer,
                  'answer_lines': question.answerLines,
                })
            .toList(),
        'metadata': slide.metadata,
        'strokes': {
          'objects': slide.strokes.map((obj) => obj.toJson()).toList(),
        },
        'exam_strokes': {
          'objects': slide.examStrokes.map((obj) => obj.toJson()).toList(),
        },
      };

  WorkspaceSlide _slideFromCache(Map<String, dynamic> row) => WorkspaceSlide(
        id: row['id'].toString(),
        index: ((row['index'] ?? 1) as num).toInt(),
        subtitleIndex: ((row['subtitle_index'] ?? 1) as num).toInt(),
        subtitleSlideIndex:
            ((row['subtitle_slide_index'] ?? row['index'] ?? 1) as num).toInt(),
        title: (row['title'] ?? 'Untitled Slide').toString(),
        subtitle: (row['subtitle'] ?? '').toString(),
        imageAsset: (row['image_asset'] ?? '').toString(),
        audioUrl: (row['audio_url'] ?? '').toString(),
        pdfUrl: (row['pdf_url'] ?? '').toString().isEmpty ? null : row['pdf_url'].toString(),
        isHidden: row['is_hidden'] == true,
        questions: _questionsFromCache(row['questions']),
        metadata: Map<String, dynamic>.from(row['metadata'] as Map? ?? {}),
        strokes: _objectsFromJson(row['strokes']),
        examStrokes:
            _objectsFromJson(row['exam_strokes'] ?? row['exam_drawing_data']),
      );

  List<WorkspaceQuestion> _questionsFromCache(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return WorkspaceQuestion(
        prompt: (map['prompt'] ?? map['question'] ?? '').toString(),
        answer: (map['answer'] ?? '').toString(),
        answerLines:
            ((map['answer_lines'] ?? map['answerLines'] ?? 4) as num).toInt(),
      );
    }).toList();
  }

  Map<String, List<WorkspaceObject>> _pendingObjects(String stationId,
      {bool isExamMode = false}) {
    final raw = _cache.getCacheAllowExpired(
        _pendingStrokesKey(stationId, isExamMode: isExamMode));
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): _objectsFromJson(entry.value),
    };
  }

  Future<void> _setPendingStrokes(
      String stationId, String slideId, List<WorkspaceObject> strokes,
      {bool isExamMode = false}) {
    final pending = _pendingObjects(stationId, isExamMode: isExamMode);
    return _cache.setCache(
      _pendingStrokesKey(stationId, isExamMode: isExamMode),
      {
        for (final entry in pending.entries)
          entry.key: {
            'objects': entry.value.map((obj) => obj.toJson()).toList(),
          },
        slideId: {
          'objects': strokes.map((obj) => obj.toJson()).toList(),
        },
      },
      const Duration(days: 36500),
    );
  }

  Future<void> _removePendingStrokes(String stationId, String slideId,
      {bool isExamMode = false}) {
    final pending = _pendingObjects(stationId, isExamMode: isExamMode)
      ..remove(slideId);
    return _cache.setCache(
      _pendingStrokesKey(stationId, isExamMode: isExamMode),
      {
        for (final entry in pending.entries)
          entry.key: {
            'objects': entry.value.map((obj) => obj.toJson()).toList(),
          },
      },
      const Duration(days: 36500),
    );
  }

  Future<void> _updateCachedStrokes(
      String stationId, String slideId, List<WorkspaceObject> strokes,
      {bool isExamMode = false}) async {
    final slides = await getCachedSlides(stationId);
    if (slides.isEmpty) return;
    await _cacheSlides(stationId, [
      for (final slide in slides)
        slide.id == slideId
            ? (isExamMode
                ? slide.copyWith(examStrokes: strokes)
                : slide.copyWith(strokes: strokes))
            : slide,
    ]);
  }

  Future<String?> _stationIdForSlide(String slideId) async {
    for (final key
        in _cache.keys.where((key) => key.startsWith('slide_workspace_'))) {
      final stationId = key.substring('slide_workspace_'.length);
      final slides = await getCachedSlides(stationId);
      if (slides.any((slide) => slide.id == slideId)) return stationId;
    }
    try {
      final slide = await _supabase.client
          .from('slides')
          .select('station_id')
          .eq('id', slideId)
          .maybeSingle();
      return slide?['station_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  WorkspaceSlide _slideFromRow(Map<String, dynamic> row) {
    final questions = _questionsFromJson(row['questions']);
    return WorkspaceSlide(
      id: row['id'].toString(),
      index: ((row['slide_index'] ?? row['index'] ?? 1) as num).toInt(),
      subtitleIndex: ((row['subtitle_index'] ?? 1) as num).toInt(),
      subtitleSlideIndex:
          ((row['subtitle_slide_index'] ?? row['slide_index'] ?? 1) as num)
              .toInt(),
      title: (row['title'] ?? 'Untitled Slide').toString(),
      subtitle: (row['subtitle'] ?? row['description'] ?? '').toString(),
      imageAsset: _imageUrlFromRow(row),
      audioUrl: (row['voice_url'] ??
              Map<String, dynamic>.from(
                  row['metadata'] as Map? ?? {})['audio_url'] ??
              '')
          .toString(),
      pdfUrl: (row['pdf_url'] ?? '').toString().trim().isEmpty ? null : _pdfUrlFromRow(row),
      isHidden: row['is_hidden'] == true,
      questions: questions,
      metadata: {
        ...Map<String, dynamic>.from(row['metadata'] as Map? ?? {}),
        'station_id': (row['station_id'] ?? '').toString()
      },
      strokes: const [],
    );
  }

  String _pdfUrlFromRow(Map<String, dynamic> row) {
    final raw = (row['pdf_url'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return _supabase.client.storage.from('question-images').getPublicUrl(raw);
  }

  String _imageUrlFromRow(Map<String, dynamic> row) {
    final metadata = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    final raw =
        (row['image_url'] ?? metadata['image_url'] ?? row['image_asset'] ?? '')
            .toString()
            .trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return _supabase.client.storage.from('question-images').getPublicUrl(raw);
  }

  List<Map<String, dynamic>> _qaItems(List<WorkspaceQuestion> questions) =>
      questions
          .where((item) =>
              item.prompt.trim().isNotEmpty || item.answer.trim().isNotEmpty)
          .map((item) => {
                'question': item.prompt.trim(),
                'prompt': item.prompt.trim(),
                'answer': item.answer.trim(),
                'answer_lines': item.answerLines,
              })
          .toList();

  List<WorkspaceQuestion> _questionsFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) {
          if (item is String) {
            return WorkspaceQuestion(
              prompt: item,
              answer: '',
            );
          }
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            return WorkspaceQuestion(
              prompt: (map['prompt'] ?? map['question'] ?? '').toString(),
              answer: (map['answer'] ?? '').toString(),
              answerLines:
                  ((map['answer_lines'] ?? map['answerLines'] ?? 4) as num)
                      .toInt(),
            );
          }
          return null;
        })
        .whereType<WorkspaceQuestion>()
        .where((question) => question.prompt.trim().isNotEmpty)
        .toList();
  }

  List<WorkspaceObject> _objectsFromJson(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) =>
              WorkspaceObject.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    if (raw is Map) {
      final objects = raw['objects'];
      if (objects is List) {
        return objects
            .whereType<Map>()
            .map((item) =>
                WorkspaceObject.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }
    return const [];
  }

  Future<void> _syncStationSlideCount(String stationId) async {
    final rows = await _supabase.client
        .from('slides')
        .select('id')
        .eq('station_id', stationId)
        .eq('is_active', true);
    await _supabase.client.from('slide_stations').update({
      'slides_count': (rows as List).length,
    }).eq('id', stationId);
  }
}
