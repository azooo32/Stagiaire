import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';

class ClinicalSection {
  final String id;
  final int subjectId;
  final String title;
  final String contentType; // 'voice', 'video', 'slide'
  final String? iconType;
  final int orderIndex;

  ClinicalSection({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.contentType,
    this.iconType,
    this.orderIndex = 0,
  });
}

class ClinicalVoiceNote {
  final String? dbId;
  final String title;
  final String durationText;
  final int? durationSeconds;
  final double initialProgress;
  final String progressTimeText;
  final String category; // 'History', 'Skills', 'Note' etc.
  final String subject;
  final bool isCompleted;
  final String speedPreference;
  final String? pdfUrl;
  final String? audioUrl;
  final String? updatedAt;
  final bool isUploading;
  final int orderIndex;
  final String? sectionId;

  ClinicalVoiceNote({
    this.dbId,
    required this.title,
    required this.durationText,
    this.durationSeconds,
    required this.initialProgress,
    required this.progressTimeText,
    required this.category,
    required this.subject,
    this.isCompleted = false,
    this.speedPreference = '1.0x',
    this.pdfUrl,
    this.audioUrl,
    this.updatedAt,
    this.isUploading = false,
    this.orderIndex = 0,
    this.sectionId,
  });
}

class ClinicalVideo {
  final String? dbId;
  final String title;
  final String durationText;
  final String subject;
  final bool isCompleted;
  final String? pdfUrl;
  final String? videoUrl;
  final int orderIndex;
  final String? sectionId;

  ClinicalVideo({
    this.dbId,
    required this.title,
    required this.durationText,
    required this.subject,
    this.isCompleted = false,
    this.pdfUrl,
    this.videoUrl,
    this.orderIndex = 0,
    this.sectionId,
  });
}

class ClinicalSlideStation {
  final int id;
  final String? dbId;
  final String title;
  final String progressText;
  final double progress;
  final String iconType; // 'scalpel', 'kidneys', 'stomach', etc.
  final String subject;
  final String? evaluation;
  final String? sectionId;

  ClinicalSlideStation({
    required this.id,
    this.dbId,
    required this.title,
    required this.progressText,
    required this.progress,
    required this.iconType,
    required this.subject,
    this.evaluation,
    this.sectionId,
  });
}

class ProgressStream extends Stream<List<int>> {
  final Stream<List<int>> _source;
  final int _totalBytes;
  final Function(double)? _onProgress;
  int _bytesSent = 0;

  ProgressStream(this._source, this._totalBytes, this._onProgress);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _source.listen(
      (chunk) {
        _bytesSent += chunk.length;
        if (_onProgress != null && _totalBytes > 0) {
          _onProgress!(_bytesSent / _totalBytes);
        }
        if (onData != null) {
          onData(chunk);
        }
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class AppProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService();
  final CacheService _cache = CacheService();

  int _safeIntVal(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val?.toString() ?? '') ?? 0;
  }

  int? _safeIntNullable(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString());
  }

  AppProvider() {
    _loadTheme();
  }

  void _loadTheme() {
    final cachedTheme = _cache.getCache('is_dark_theme');
    if (cachedTheme != null) {
      _isDarkTheme = cachedTheme as bool;
    }
  }

  // Bunny Stream credentials
  static const String _bunnyLibraryId = '704738';
  static const String _bunnyApiKey =
      '5ebc9d65-cbcd-428d-a0202995d7f6-bf5f-40ff';
  static const String _bunnyPullZone = 'vz-134db097-29b.b-cdn.net';

  /// Uploads a local video file to Bunny Stream and returns the playable HLS playlist URL.
  Future<String> uploadVideoToBunny(String filePath, String title,
      {Function(double)? onProgress}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Video file does not exist at path: $filePath');
    }

    final client = HttpClient();

    // 1. Create a video placeholder in Bunny Stream
    final createUri =
        Uri.parse('https://video.bunnycdn.com/library/$_bunnyLibraryId/videos');
    final createReq = await client.postUrl(createUri);
    createReq.headers.add('AccessKey', _bunnyApiKey);
    createReq.headers.add('Accept', 'application/json');
    createReq.headers.contentType = ContentType.json;
    createReq.write(jsonEncode({'title': title}));

    final createRes = await createReq.close();
    if (createRes.statusCode != 200) {
      final errBody = await createRes.transform(utf8.decoder).join();
      throw Exception(
          'Failed to create video placeholder on Bunny Stream: $errBody');
    }

    final createBody = await createRes.transform(utf8.decoder).join();
    final createJson = jsonDecode(createBody);
    final String videoId = createJson['guid'] as String;

    // 2. Upload the video bytes
    final fileLength = await file.length();
    final uploadUri = Uri.parse(
        'https://video.bunnycdn.com/library/$_bunnyLibraryId/videos/$videoId');
    final uploadReq = await client.putUrl(uploadUri);
    uploadReq.headers.add('AccessKey', _bunnyApiKey);
    uploadReq.headers.add('Accept', 'application/json');
    uploadReq.headers.contentType = ContentType('application', 'octet-stream');
    uploadReq.headers.contentLength = fileLength;

    // Stream the file and track progress using ProgressStream
    final fileStream = file.openRead();
    final progressStream = ProgressStream(fileStream, fileLength, onProgress);
    await uploadReq.addStream(progressStream);

    final uploadRes = await uploadReq.close();
    if (uploadRes.statusCode != 200) {
      final uploadErrBody = await uploadRes.transform(utf8.decoder).join();
      throw Exception(
          'Failed to upload video file to Bunny Stream: $uploadErrBody');
    }

    // Return the playable HLS URL
    return 'https://$_bunnyPullZone/$videoId/playlist.m3u8';
  }

  // Clinical Dynamic Data Lists
  final List<ClinicalVoiceNote> _clinicalVoiceNotes = [];
  final List<ClinicalVideo> _clinicalVideos = [];
  final List<ClinicalSlideStation> _clinicalSlideStations = [];

  // Clinical Sections List
  List<ClinicalSection> _clinicalSections = [];
  List<ClinicalSection> get clinicalSections => _clinicalSections;

  bool _isClinicalLoading = false;
  bool get isClinicalLoading => _isClinicalLoading;

  List<ClinicalVoiceNote> _dbVoiceNotes = [];
  List<ClinicalVideo> _dbVideos = [];
  List<ClinicalSlideStation> _dbSlideStations = [];
  RealtimeChannel? _clinicalRealtimeChannel;
  Timer? _clinicalRealtimeDebounce;
  int? _activeClinicalSubjectId;
  String? _activeClinicalSubjectName;

  final Map<String, double> _clinicalSubjectProgress = {};
  Map<String, double> get clinicalSubjectProgress => _clinicalSubjectProgress;

  double getClinicalSubjectProgress(List<String> dbNames) {
    if (_clinicalSubjectProgress.isEmpty) return 0.0;
    double sum = 0.0;
    int count = 0;
    for (var name in dbNames) {
      final key = name.toLowerCase().trim();
      if (_clinicalSubjectProgress.containsKey(key)) {
        sum += _clinicalSubjectProgress[key]!;
        count++;
      }
    }
    return count > 0 ? sum / count : 0.0;
  }

  String _normalizeClinicalSubjectName(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<int?> _resolveClinicalSubjectId(String subjectName) async {
    final normalized = _normalizeClinicalSubjectName(subjectName);
    for (final subject in _clinicalSubjects) {
      if (_normalizeClinicalSubjectName(subject.name) == normalized) {
        return subject.id;
      }
    }

    try {
      final response = await _supabase.client
          .from('clinical_subjects')
          .select('id, name')
          .ilike('name', subjectName)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      if (response != null) return response['id'] as int?;
    } catch (e) {
      print('Error resolving clinical subject id: $e');
    }
    return null;
  }

  int _durationSecondsFromText(String durationText) {
    final parts = durationText
        .split(':')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    if (parts.length == 3)
      return (parts[0] * 3600) + (parts[1] * 60) + parts[2];
    if (parts.length == 2) return (parts[0] * 60) + parts[1];
    if (parts.length == 1) return parts[0];
    return 0;
  }

  String _durationTextFromSeconds(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final secs = safeSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  List<ClinicalVoiceNote> getClinicalVoiceNotes(String subject) {
    if (_dbVoiceNotes.isNotEmpty && _dbVoiceNotes.first.subject == subject) {
      return _dbVoiceNotes;
    }
    return _clinicalVoiceNotes.where((vn) => vn.subject == subject).toList();
  }

  List<ClinicalVideo> getClinicalVideos(String subject) {
    if (_dbVideos.isNotEmpty && _dbVideos.first.subject == subject) {
      return _dbVideos;
    }
    return _clinicalVideos.where((v) => v.subject == subject).toList();
  }

  List<ClinicalSlideStation> getClinicalSlideStations(String subject) {
    if (_dbSlideStations.isNotEmpty &&
        _dbSlideStations.first.subject == subject) {
      return _dbSlideStations;
    }
    return _clinicalSlideStations.where((s) => s.subject == subject).toList();
  }

  String _getClinicalCacheKey(int subjectId) =>
      'clinical_data_subject_$subjectId';

  void _mapClinicalData(
    String subjectName,
    List<dynamic> sectionsList,
    List<dynamic> stationsList,
    List<dynamic> voiceNotesList,
    List<dynamic> videosList,
    List<dynamic> userVoiceProg,
    List<dynamic> userVideoProg,
    List<dynamic> userStationProg,
  ) {
    final voiceProgressMap = {
      for (var p in userVoiceProg) p['voice_note_id'] as String: p
    };
    final videoProgressMap = {
      for (var p in userVideoProg) p['video_id'] as String: p
    };
    final stationProgressMap = {
      for (var p in userStationProg) p['station_id'] as String: p
    };

    _clinicalSections = sectionsList.map((map) {
      return ClinicalSection(
        id: map['id'] as String,
        subjectId: map['subject_id'] as int,
        title: map['title'] as String,
        contentType: map['content_type'] as String,
        iconType: map['icon_type'] as String?,
        orderIndex: map['order_index'] as int? ?? 0,
      );
    }).toList();

    _dbSlideStations = stationsList.asMap().entries.map((entry) {
      final int index = entry.key;
      final map = entry.value;
      final String stationId = map['id'] as String;
      final prog = stationProgressMap[stationId];

      final int completedSlides =
          prog != null ? (prog['current_slide_index'] as int) : 1;
      final int totalSlides = map['slides_count'] as int;

      return ClinicalSlideStation(
        id: index + 1,
        dbId: stationId,
        title: map['title'] as String,
        progressText: '$completedSlides / $totalSlides Slides',
        progress: totalSlides > 0 ? (completedSlides / totalSlides) : 0.0,
        iconType: map['icon_type'] as String,
        subject: subjectName,
        evaluation: prog != null ? prog['evaluation'] as String? : null,
        sectionId: map['section_id'] as String?,
      );
    }).toList();

    _dbVoiceNotes = voiceNotesList.map((map) {
      final String voiceId = map['id'] as String;
      final prog = voiceProgressMap[voiceId];

      final double initialProgress = prog != null
          ? (prog['playback_progress'] is int
              ? (prog['playback_progress'] as int).toDouble()
              : prog['playback_progress'] as double)
          : 0.0;
      final bool isCompleted =
          prog != null ? (prog['is_completed'] as bool) : false;

      return ClinicalVoiceNote(
        dbId: voiceId,
        title: map['title'] as String,
        durationText: (map['duration_text'] as String?) ??
            _durationTextFromSeconds(
                (map['duration_seconds'] as num?)?.toInt() ?? 0),
        durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
        initialProgress: initialProgress,
        progressTimeText: '00:00',
        category: map['category'] as String,
        subject: subjectName,
        isCompleted: isCompleted,
        speedPreference:
            prog != null ? (prog['playback_speed'] as String) : '1.0x',
        pdfUrl: map['pdf_url'] as String?,
        audioUrl: map['audio_url'] as String?,
        updatedAt: map['updated_at']?.toString(),
        isUploading: false,
        orderIndex: map['order_index'] as int? ?? 0,
        sectionId: map['section_id'] as String?,
      );
    }).toList();

    _dbVideos = videosList.map((map) {
      final String videoId = map['id'] as String;
      final prog = videoProgressMap[videoId];
      final bool isCompleted =
          prog != null ? (prog['is_completed'] as bool) : false;

      return ClinicalVideo(
        dbId: videoId,
        title: map['title'] as String,
        durationText: map['duration_text'] as String,
        subject: subjectName,
        isCompleted: isCompleted,
        pdfUrl: map['pdf_url'] as String?,
        videoUrl: map['video_url'] as String?,
        orderIndex: map['order_index'] as int? ?? 0,
        sectionId: map['section_id'] as String?,
      );
    }).toList();

    calculateAllClinicalProgress();
  }

  // Load Clinical Data from Supabase with Cache-first then background sync strategy
  Future<void> loadClinicalData(String subjectName) async {
    final subjectId = await _resolveClinicalSubjectId(subjectName);
    if (subjectId == null) {
      _dbVoiceNotes = getClinicalVoiceNotes(subjectName);
      _dbVideos = getClinicalVideos(subjectName);
      _dbSlideStations = getClinicalSlideStations(subjectName);
      _isClinicalLoading = false;
      notifyListeners();
      return;
    }

    final String cacheKey = _getClinicalCacheKey(subjectId);
    final cachedData =
        _cache.getCache(cacheKey) ?? _cache.getCacheAllowExpired(cacheKey);

    if (cachedData != null) {
      try {
        final cachedSectionsList = cachedData['sections'] as List;
        final cachedStationsList = cachedData['stations'] as List;
        final cachedVoiceNotesList = cachedData['voice_notes'] as List;
        final cachedVideosList = cachedData['videos'] as List;
        final cachedUserVoiceProg =
            cachedData['user_voice_progress'] as List? ?? [];
        final cachedUserVideoProg =
            cachedData['user_video_progress'] as List? ?? [];
        final cachedUserStationProg =
            cachedData['user_station_progress'] as List? ?? [];

        _mapClinicalData(
          subjectName,
          cachedSectionsList,
          cachedStationsList,
          cachedVoiceNotesList,
          cachedVideosList,
          cachedUserVoiceProg,
          cachedUserVideoProg,
          cachedUserStationProg,
        );
        _isClinicalLoading = false;
        notifyListeners();
        unawaited(_refreshClinicalDataCache(subjectName, subjectId, cacheKey));
        return;
      } catch (e) {
        print('Error reading cached clinical data: $e');
      }
    } else {
      _isClinicalLoading = true;
      notifyListeners();
    }

    try {
      final user = _supabase.currentUser;

      // 2. Fetch sections, slide stations, voice notes, and videos in parallel with timeout
      final results = await Future.wait([
        _supabase.client
            .from('slide_stations')
            .select('*')
            .eq('subject_id', subjectId),
        _supabase.client
            .from('voice_notes')
            .select('*')
            .eq('subject_id', subjectId)
            .order('order_index', ascending: true),
        _supabase.client
            .from('videos')
            .select('*')
            .eq('subject_id', subjectId)
            .order('order_index', ascending: true),
        _supabase.client
            .from('clinical_sections')
            .select('*')
            .eq('subject_id', subjectId)
            .order('order_index', ascending: true),
      ]).timeout(const Duration(seconds: 3));

      final stationsList = results[0] as List;
      final voiceNotesList = results[1] as List;
      final videosList = results[2] as List;
      final sectionsList = results[3] as List;

      // 3. Fetch User Progress (if user is authenticated) in parallel with timeout
      List<dynamic> userVoiceProg = [];
      List<dynamic> userVideoProg = [];
      List<dynamic> userStationProg = [];

      if (user != null) {
        final progressResults = await Future.wait([
          _supabase.client
              .from('user_voice_progress')
              .select('*')
              .eq('user_id', user.id),
          _supabase.client
              .from('user_video_progress')
              .select('*')
              .eq('user_id', user.id),
          _supabase.client
              .from('user_station_progress')
              .select('*')
              .eq('user_id', user.id),
        ]).timeout(const Duration(seconds: 3));

        userVoiceProg = progressResults[0] as List;
        userVideoProg = progressResults[1] as List;
        userStationProg = progressResults[2] as List;
      }

      // 4. Cache this fresh data
      final Map<String, dynamic> freshCacheData = {
        'sections': sectionsList,
        'stations': stationsList,
        'voice_notes': voiceNotesList,
        'videos': videosList,
        'user_voice_progress': userVoiceProg,
        'user_video_progress': userVideoProg,
        'user_station_progress': userStationProg,
      };

      await _cache.setCache(cacheKey, freshCacheData, const Duration(days: 7));

      // 5. Map the fresh records to local variables
      _mapClinicalData(
        subjectName,
        sectionsList,
        stationsList,
        voiceNotesList,
        videosList,
        userVoiceProg,
        userVideoProg,
        userStationProg,
      );
    } catch (e) {
      print('Error loading clinical data from Supabase: $e');
      if (cachedData == null) {
        _dbVoiceNotes = getClinicalVoiceNotes(subjectName);
        _dbVideos = getClinicalVideos(subjectName);
        _dbSlideStations = getClinicalSlideStations(subjectName);
      }
    } finally {
      _isClinicalLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshClinicalDataCache(
      String subjectName, int subjectId, String cacheKey) async {
    try {
      final user = _supabase.currentUser;

      final sectionsFuture = _supabase.client
          .from('clinical_sections')
          .select('*')
          .eq('subject_id', subjectId)
          .order('order_index', ascending: true);

      final stationsFuture = _supabase.client
          .from('slide_stations')
          .select('*')
          .eq('subject_id', subjectId);

      final voiceFuture = _supabase.client
          .from('voice_notes')
          .select('*')
          .eq('subject_id', subjectId)
          .order('order_index', ascending: true);

      final videoFuture = _supabase.client
          .from('videos')
          .select('*')
          .eq('subject_id', subjectId)
          .order('order_index', ascending: true);

      final results = await Future.wait([
        stationsFuture,
        voiceFuture,
        videoFuture,
        sectionsFuture,
      ]).timeout(const Duration(seconds: 30));

      final stationsList = results[0] as List;
      final voiceNotesList = results[1] as List;
      final videosList = results[2] as List;
      final sectionsList = results[3] as List;

      List<dynamic> userVoiceProg = [];
      List<dynamic> userVideoProg = [];
      List<dynamic> userStationProg = [];

      if (user != null) {
        final progressResults = await Future.wait([
          _supabase.client
              .from('user_voice_progress')
              .select('*')
              .eq('user_id', user.id),
          _supabase.client
              .from('user_video_progress')
              .select('*')
              .eq('user_id', user.id),
          _supabase.client
              .from('user_station_progress')
              .select('*')
              .eq('user_id', user.id),
        ]).timeout(const Duration(seconds: 30));
        userVoiceProg = progressResults[0] as List;
        userVideoProg = progressResults[1] as List;
        userStationProg = progressResults[2] as List;
      }

      await _cache.setCache(
          cacheKey,
          {
            'sections': sectionsList,
            'stations': stationsList,
            'voice_notes': voiceNotesList,
            'videos': videosList,
            'user_voice_progress': userVoiceProg,
            'user_video_progress': userVideoProg,
            'user_station_progress': userStationProg,
          },
          const Duration(days: 7));
    } catch (e) {
      print('Background clinical sync failed for $subjectName: $e');
    }
  }

  Future<void> invalidateClinicalCache(String subject) async {
    final subjectId = await _resolveClinicalSubjectId(subject);
    if (subjectId == null) return;
    final String cacheKey = _getClinicalCacheKey(subjectId);
    await _cache.invalidateCache(cacheKey);
  }

  Future<void> subscribeToClinicalRealtime(String subjectName) async {
    final subjectId = await _resolveClinicalSubjectId(subjectName);
    if (subjectId == null) return;
    if (_activeClinicalSubjectId == subjectId &&
        _clinicalRealtimeChannel != null) return;

    await unsubscribeFromClinicalRealtime();
    _activeClinicalSubjectId = subjectId;
    _activeClinicalSubjectName = subjectName;
    _clinicalRealtimeChannel =
        _supabase.client.channel('clinical_subject_$subjectId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'voice_notes',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'subject_id',
                value: subjectId),
            callback: (_) => _scheduleClinicalRealtimeRefresh(subjectId),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'videos',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'subject_id',
                value: subjectId),
            callback: (_) => _scheduleClinicalRealtimeRefresh(subjectId),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'clinical_sections',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'subject_id',
                value: subjectId),
            callback: (_) => _scheduleClinicalRealtimeRefresh(subjectId),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'slide_stations',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'subject_id',
                value: subjectId),
            callback: (_) => _scheduleClinicalRealtimeRefresh(subjectId),
          )
          ..subscribe();
  }

  void _scheduleClinicalRealtimeRefresh(int subjectId) {
    if (_activeClinicalSubjectId != subjectId ||
        _activeClinicalSubjectName == null) return;
    _clinicalRealtimeDebounce?.cancel();
    _clinicalRealtimeDebounce =
        Timer(const Duration(milliseconds: 700), () async {
      await _cache.invalidateCache(_getClinicalCacheKey(subjectId));
      await loadClinicalData(_activeClinicalSubjectName!);
    });
  }

  Future<void> unsubscribeFromClinicalRealtime() async {
    _clinicalRealtimeDebounce?.cancel();
    _clinicalRealtimeDebounce = null;
    final channel = _clinicalRealtimeChannel;
    _clinicalRealtimeChannel = null;
    _activeClinicalSubjectId = null;
    _activeClinicalSubjectName = null;
    if (channel != null) {
      await _supabase.client.removeChannel(channel);
    }
  }

  // Mutations
  Future<void> addClinicalVoiceNote(
      String subject, String title, String category, String duration,
      {String? pdfUrl,
      String? audioUrl,
      String? audioFileName,
      Uint8List? audioBytes,
      Uint8List? pdfBytes,
      String? sectionId,
      int? durationSeconds}) async {
    final tempId = 'uploading_${DateTime.now().microsecondsSinceEpoch}';
    final pendingNote = ClinicalVoiceNote(
      dbId: tempId,
      title: title,
      durationText: duration,
      durationSeconds: durationSeconds ?? _durationSecondsFromText(duration),
      initialProgress: 0.0,
      progressTimeText: '00:00',
      category: category,
      subject: subject,
      pdfUrl: pdfUrl,
      audioUrl: audioUrl,
      updatedAt: DateTime.now().toIso8601String(),
      isUploading: true,
      sectionId: sectionId,
      orderIndex: getClinicalVoiceNotes(subject).isEmpty
          ? 0
          : getClinicalVoiceNotes(subject)
                  .map((vn) => vn.orderIndex)
                  .reduce((a, b) => a > b ? a : b) +
              1,
    );

    _clinicalVoiceNotes.add(pendingNote);
    if (_dbVoiceNotes.isNotEmpty && _dbVoiceNotes.first.subject == subject) {
      _dbVoiceNotes.add(pendingNote);
      _dbVoiceNotes.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
    notifyListeners();

    try {
      String? finalAudioUrl = audioUrl;
      if (audioBytes != null) {
        // Build a unique filename with timestamp to avoid storage collisions
        // Prefer explicit audioFileName (from file picker) over extracting from path/URL
        final rawName = audioFileName??
            audioUrl?.split('/').last.split('\\').last ??
            'voice_note';
        final ext = rawName.contains('.') ? rawName.split('.').last.toLowerCase() : 'mp3';
        final baseName = rawName.contains('.') ? rawName.substring(0, rawName.lastIndexOf('.')) : rawName;
        final uniqueName = '${baseName}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        // Map extension to correct MIME type
        final mimeType = const {
          'mp3': 'audio/mpeg',
          'm4a': 'audio/mp4',
          'aac': 'audio/aac',
          'wav': 'audio/wav',
          'ogg': 'audio/ogg',
          'webm': 'audio/webm',
          'opus': 'audio/opus',
        }[ext] ?? 'audio/mpeg';

        final uploaded = await _supabase.uploadFileBytes(
          'question-audios',
          audioBytes,
          uniqueName,
          folder: 'voice-notes',
          contentType: mimeType,
        );
        if (uploaded != null) {
          finalAudioUrl = uploaded;
        } else {
          throw Exception(_supabase.lastError ?? 'Failed to upload audio bytes.');
        }
      } else if (audioUrl != null && audioUrl.isNotEmpty) {
        if (!audioUrl.startsWith('http://') &&
            !audioUrl.startsWith('https://')) {
          final uploaded = await _supabase
              .uploadFile('question-audios', audioUrl, folder: 'voice-notes');
          if (uploaded != null) {
            finalAudioUrl = uploaded;
          } else {
            throw Exception(_supabase.lastError ?? 'Failed to upload audio file.');
          }
        }
      }

      String? finalPdfUrl = pdfUrl;
      if (pdfBytes != null) {
        final uploaded = await _supabase.uploadFileBytes(
          'question-images',
          pdfBytes,
          pdfUrl?.split('/').last.split('\\').last ?? 'voice_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf',
          folder: 'voice-pdfs',
          contentType: 'application/pdf',
        );
        if (uploaded != null) {
          finalPdfUrl = uploaded;
        } else {
          throw Exception(_supabase.lastError ?? 'Failed to upload PDF bytes.');
        }
      } else if (pdfUrl != null && pdfUrl.isNotEmpty) {
        if (!pdfUrl.startsWith('http://') && !pdfUrl.startsWith('https://')) {
          final uploaded = await _supabase.uploadFile('question-images', pdfUrl,
              folder: 'voice-pdfs');
          if (uploaded != null) {
            finalPdfUrl = uploaded;
          } else {
            throw Exception(_supabase.lastError ?? 'Failed to upload PDF file.');
          }
        }
      }

      final subjectId = await _resolveClinicalSubjectId(subject);
      if (subjectId != null) {
        final existingNotes = getClinicalVoiceNotes(subject)
            .where((vn) => !vn.isUploading)
            .toList();
        final int nextOrderIndex = existingNotes.isEmpty
            ? 0
            : existingNotes
                    .map((vn) => vn.orderIndex)
                    .reduce((a, b) => a > b ? a : b) +
                1;

        await _supabase.client.from('voice_notes').insert({
          'subject_id': subjectId,
          'title': title,
          'category': category,
          'duration_text': duration,
          'duration_seconds':
              durationSeconds ?? _durationSecondsFromText(duration),
          'audio_url': finalAudioUrl ??
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
          'pdf_url': finalPdfUrl,
          'order_index': nextOrderIndex,
          'section_id': sectionId,
        });
        await invalidateClinicalCache(subject);
        await loadClinicalData(subject);
      }
    } catch (e) {
      _clinicalVoiceNotes.removeWhere((vn) => vn.dbId == tempId);
      _dbVoiceNotes.removeWhere((vn) => vn.dbId == tempId);
      notifyListeners();
      print('Error saving voice note: $e');
    }
  }

  Future<void> addClinicalVideo(String subject, String title, String duration,
      {String? pdfUrl, String? videoUrl, String? sectionId}) async {
    try {
      String? finalPdfUrl = pdfUrl;
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        if (!pdfUrl.startsWith('http://') && !pdfUrl.startsWith('https://')) {
          final uploaded = await _supabase.uploadFile('question-images', pdfUrl);
          if (uploaded != null) {
            finalPdfUrl = uploaded;
          } else {
            throw Exception('Failed to upload PDF file');
          }
        }
      }

      final subjectVideos = getClinicalVideos(subject);
      final nextOrderIndex = subjectVideos.isEmpty
          ? 1
          : subjectVideos
                  .map((v) => v.orderIndex)
                  .reduce((a, b) => a > b ? a : b) +
              1;

      final subjectId = await _resolveClinicalSubjectId(subject);
      if (subjectId != null) {
        await _supabase.client.from('videos').insert({
          'subject_id': subjectId,
          'title': title,
          'video_url': videoUrl ??
              'https://assets.mixkit.co/videos/preview/mixkit-forest-stream-in-the-sunlight-529-large.mp4',
          'duration_text': duration,
          'pdf_url': finalPdfUrl,
          'order_index': nextOrderIndex,
          'section_id': sectionId,
        });

        _clinicalVideos.add(ClinicalVideo(
          title: title,
          durationText: duration,
          subject: subject,
          pdfUrl: finalPdfUrl,
          videoUrl: videoUrl,
          orderIndex: nextOrderIndex,
          sectionId: sectionId,
        ));
        notifyListeners();

        await invalidateClinicalCache(subject);
        await loadClinicalData(subject);
      }
    } catch (e) {
      print('Error saving video: $e');
      rethrow;
    }
  }

  Future<void> addClinicalSlideStation(
      String subject, String title, int slidesCount, String iconType,
      {String? sectionId}) async {
    final subjectStations = getClinicalSlideStations(subject);
    final nextId = subjectStations.isEmpty
        ? 1
        : subjectStations.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
    _clinicalSlideStations.add(ClinicalSlideStation(
      id: nextId,
      title: title,
      progressText: '1 / $slidesCount Slides',
      progress: 1.0 / slidesCount,
      iconType: iconType,
      subject: subject,
      sectionId: sectionId,
    ));
    notifyListeners();

    try {
      final subjectId = await _resolveClinicalSubjectId(subject);
      if (subjectId != null) {
        await _supabase.client.from('slide_stations').insert({
          'subject_id': subjectId,
          'title': title,
          'icon_type': iconType,
          'slides_count': slidesCount,
          'section_id': sectionId,
        });
        await invalidateClinicalCache(subject);
        await loadClinicalData(subject);
      }
    } catch (e) {
      print('Error saving station: $e');
    }
  }

  Future<void> addClinicalSection(String subject, String title,
      String contentType, String? iconType) async {
    try {
      final subjectId = await _resolveClinicalSubjectId(subject);
      if (subjectId != null) {
        final existingSecs =
            _clinicalSections.where((s) => s.subjectId == subjectId).toList();
        final int nextOrderIndex = existingSecs.isEmpty
            ? 1
            : existingSecs
                    .map((s) => s.orderIndex)
                    .reduce((a, b) => a > b ? a : b) +
                1;

        await _supabase.client.from('clinical_sections').insert({
          'subject_id': subjectId,
          'title': title,
          'content_type': contentType,
          'icon_type': iconType,
          'order_index': nextOrderIndex,
        });
        await invalidateClinicalCache(subject);
        await loadClinicalData(subject);
      }
    } catch (e) {
      print('Error saving clinical section: $e');
    }
  }

  Future<void> deleteClinicalSection(String sectionId, String subject) async {
    try {
      await _supabase.client
          .from('clinical_sections')
          .delete()
          .eq('id', sectionId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error deleting clinical section: $e');
    }
  }

  // Progress Sync mutations
  Future<void> updateVoiceProgress(
      String voiceDbId, double progress, String speed, bool completed) async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      await _supabase.client.from('user_voice_progress').upsert({
        'user_id': user.id,
        'voice_note_id': voiceDbId,
        'playback_progress': progress,
        'playback_speed': speed,
        'is_completed': completed,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final idx = _dbVoiceNotes.indexWhere((vn) => vn.dbId == voiceDbId);
      if (idx != -1) {
        final old = _dbVoiceNotes[idx];
        _dbVoiceNotes[idx] = ClinicalVoiceNote(
          dbId: old.dbId,
          title: old.title,
          durationText: old.durationText,
          durationSeconds: old.durationSeconds,
          initialProgress: progress,
          progressTimeText: old.progressTimeText,
          category: old.category,
          subject: old.subject,
          isCompleted: completed,
          speedPreference: speed,
          pdfUrl: old.pdfUrl,
          audioUrl: old.audioUrl,
          updatedAt: old.updatedAt,
          isUploading: old.isUploading,
          orderIndex: old.orderIndex,
          sectionId: old.sectionId,
        );
        notifyListeners();
      }
      calculateAllClinicalProgress();
    } catch (e) {
      print('Error syncing voice progress: $e');
    }
  }

  Future<void> updateVideoProgress(String videoDbId, bool completed) async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      await _supabase.client.from('user_video_progress').upsert({
        'user_id': user.id,
        'video_id': videoDbId,
        'is_completed': completed,
        'playback_progress': completed ? 1.0 : 0.0,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final idx = _dbVideos.indexWhere((v) => v.dbId == videoDbId);
      if (idx != -1) {
        final old = _dbVideos[idx];
        _dbVideos[idx] = ClinicalVideo(
          dbId: old.dbId,
          title: old.title,
          durationText: old.durationText,
          subject: old.subject,
          isCompleted: completed,
          videoUrl: old.videoUrl,
          pdfUrl: old.pdfUrl,
          sectionId: old.sectionId,
          orderIndex: old.orderIndex,
        );
        notifyListeners();
      }
      calculateAllClinicalProgress();
    } catch (e) {
      print('Error syncing video progress: $e');
    }
  }

  Future<void> updateStationProgress(
      String stationDbId, int currentSlide, String? evaluation) async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      final Map<String, dynamic> data = {
        'user_id': user.id,
        'station_id': stationDbId,
        'current_slide_index': currentSlide,
        'updated_at': DateTime.now().toIso8601String(),
        'evaluation': evaluation?.toLowerCase(),
      };
      await _supabase.client.from('user_station_progress').upsert(data);
      calculateAllClinicalProgress();
    } catch (e) {
      print('Error syncing station progress: $e');
    }
  }

  Future<void> saveUserNote(
      String targetType, String targetId, String noteContent) async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      await _supabase.client.from('user_notes').upsert({
        'user_id': user.id,
        'target_type': targetType.toLowerCase(),
        'target_id': targetId,
        'note_content': noteContent,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving user note: $e');
    }
  }

  Future<String?> getUserNote(String targetType, String targetId) async {
    final user = _supabase.currentUser;
    if (user == null) return null;
    try {
      final res = await _supabase.client
          .from('user_notes')
          .select('note_content')
          .eq('user_id', user.id)
          .eq('target_type', targetType.toLowerCase())
          .eq('target_id', targetId)
          .maybeSingle();
      if (res != null) {
        return res['note_content'] as String?;
      }
    } catch (e) {
      print('Error loading user note: $e');
    }
    return null;
  }

  List<Subject> _subjects = [];
  List<Subject> get subjects => _subjects;

  List<Subject> _clinicalSubjects = [];
  List<Subject> get clinicalSubjects => _clinicalSubjects;

  Future<void> fetchClinicalSubjectsCacheFirst() async {
    const cacheKey = 'clinical_subjects_cache_v1';
    final cached =
        _cache.getCache(cacheKey) ?? _cache.getCacheAllowExpired(cacheKey);

    if (cached is List && cached.isNotEmpty) {
      _clinicalSubjects = cached
          .map((s) => Subject.fromJson(Map<String, dynamic>.from(s)))
          .toList();
      notifyListeners();
      unawaited(_syncClinicalSubjectsFromNetwork(cacheKey));
      return;
    }

    await _syncClinicalSubjectsFromNetwork(cacheKey);
  }

  Future<void> _syncClinicalSubjectsFromNetwork(String cacheKey) async {
    try {
      final List<dynamic> clinicalData = await _supabase.client
          .from('clinical_subjects')
          .select('*')
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      final fetched = clinicalData
          .map((s) => {
                'id': s['id'],
                'name': s['name'],
                'description': s['description'] ?? '',
                'total_questions': 0,
                'stage': s['stage'],
                'university': s['university'],
              })
          .toList();

      await _cache.setCache(cacheKey, fetched, const Duration(days: 30));

      _clinicalSubjects = fetched
          .map((s) => Subject.fromJson(Map<String, dynamic>.from(s)))
          .toList();
      notifyListeners();
    } catch (e) {
      print('Background sync for clinical subjects failed: $e');
    }
  }

  List<Question> _questions = [];
  List<Question> get questions => _questions;

  // Active session questions for the Question Viewer
  List<Question> _practiceQuestions = [];
  List<Question> get practiceQuestions => _practiceQuestions;

  List<int> _favorites = [];
  List<int> get favorites => _favorites;

  final Set<String> _clinicalBookmarks = <String>{};
  Set<String> get clinicalBookmarks => _clinicalBookmarks;

  String _clinicalBookmarkKey(String itemType, String itemId) =>
      '$itemType:$itemId';

  bool isClinicalBookmarked(String itemType, String? itemId) {
    if (itemId == null || itemId.isEmpty) return false;
    return _clinicalBookmarks.contains(_clinicalBookmarkKey(itemType, itemId));
  }

  static const String _cachedUserAnswersKey = 'user_answers_cache_v1';
  static const String _pendingUserAnswersKey = 'pending_user_answers_v1';

  Map<String, dynamic> _userAnswers = {};
  Map<String, dynamic> get userAnswers => _userAnswers;
  bool _isSyncingPendingAnswers = false;
  Timer? _pendingAnswerSyncTimer;

  bool _recordPracticeProgress = true;

  Map<String, dynamic> _highlights = {};
  Map<String, dynamic> get highlights => _highlights;

  Map<String, dynamic>? _studyPlan;
  Map<String, dynamic>? get studyPlan => _studyPlan;

  String? _selectedSubject;
  String? get selectedSubject => _selectedSubject;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isQuestionsLoading = false;
  bool get isQuestionsLoading => _isQuestionsLoading;

  bool _isDarkTheme = false; // Defaults to light mode
  bool get isDarkTheme => _isDarkTheme;

  bool _isAnswersRevealed = false;
  bool get isAnswersRevealed => _isAnswersRevealed;

  void toggleAnswersRevealed(bool value) {
    _isAnswersRevealed = value;
    notifyListeners();
  }

  String _viewMode = 'topic'; // 'topic' or 'chapter'
  String get viewMode => _viewMode;

  void setViewMode(String val) {
    _viewMode = val;
    _cache.setCache('view_mode', val, const Duration(days: 36500));
    notifyListeners();
  }

  String _sourceFilterKey(String subjectName) =>
      'source_filters_${subjectName.trim().toLowerCase()}';

  List<String>? getSavedSourceFilters(String subjectName) {
    final cached = _cache.getCache(_sourceFilterKey(subjectName)) ??
        _cache.getCacheAllowExpired(_sourceFilterKey(subjectName));
    if (cached is List) {
      return cached.map((item) => item.toString()).toList();
    }
    return null;
  }

  Future<void> saveSourceFilters(
      String subjectName, List<String> sources) async {
    await _cache.setCache(
      _sourceFilterKey(subjectName),
      sources,
      const Duration(days: 36500),
    );
  }

  int _currentTab = 2; // Home tab is active by default
  int get currentTab => _currentTab;

  void setCurrentTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  String? _userRole;
  String? get userRole => _userRole;

  List<Map<String, dynamic>> _recentTopics = [];
  List<Map<String, dynamic>> get recentTopics => _recentTopics;

  // Leaderboard statistics synced from DB table public.leaderboard
  Timer? _sessionCheckTimer;
  bool _isSessionInvalidated = false;
  bool get isSessionInvalidated => _isSessionInvalidated;

  int _leaderboardTotalAnswers = 0;
  int _leaderboardCorrectAnswers = 0;
  double _leaderboardAccuracy = 0.0;

  Map<String, dynamic>? _userDetails;
  Map<String, dynamic>? get userDetails => _userDetails;

  bool get isAdminOrOwner {
    if (_userRole == null) return false;
    final r = _userRole!.toLowerCase();
    return r == 'admin' || r == 'owner' || r == 'manager';
  }

  Set<int> _unlockedSubjectIds = {};
  Set<int> get unlockedSubjectIds => _unlockedSubjectIds;

  Set<int> _unlockedClinicalSubjectIds = {};
  Set<int> get unlockedClinicalSubjectIds => _unlockedClinicalSubjectIds;

  bool isSubjectUnlocked(int id) {
    if (isAdminOrOwner) return true;
    return _unlockedSubjectIds.contains(id);
  }

  bool isClinicalSubjectUnlocked(int id) {
    if (isAdminOrOwner) return true;
    return _unlockedClinicalSubjectIds.contains(id);
  }

  bool isSubjectUnlockedByName(String subjectName) {
    if (isAdminOrOwner) return true;
    final subject = _subjects.firstWhere(
      (s) => s.name.toLowerCase().trim() == subjectName.toLowerCase().trim(),
      orElse: () => Subject(id: -1, name: '', description: '', totalQuestions: 0),
    );
    if (subject.id == -1) return true;
    return _unlockedSubjectIds.contains(subject.id);
  }

  bool isClinicalSubjectUnlockedByName(String subjectName) {
    if (isAdminOrOwner) return true;
    final subject = _clinicalSubjects.firstWhere(
      (s) => s.name.toLowerCase().trim() == subjectName.toLowerCase().trim(),
      orElse: () => Subject(id: -1, name: '', description: '', totalQuestions: 0),
    );
    if (subject.id == -1) return true;
    return _unlockedClinicalSubjectIds.contains(subject.id);
  }

  Future<void> fetchUnlockedSubjects() async {
    if (!_supabase.isAuthenticated) {
      _unlockedSubjectIds = {};
      _unlockedClinicalSubjectIds = {};
      notifyListeners();
      return;
    }

    try {
      final scientificResponse = await _supabase.client
          .from('accessible_subjects')
          .select('subject_id');
      
      _unlockedSubjectIds = List<Map<String, dynamic>>.from(scientificResponse)
          .map((row) => row['subject_id'] as int)
          .toSet();

      final clinicalResponse = await _supabase.client
          .from('accessible_clinical_subjects')
          .select('clinical_subject_id');
      
      _unlockedClinicalSubjectIds = List<Map<String, dynamic>>.from(clinicalResponse)
          .map((row) => row['clinical_subject_id'] as int)
          .toSet();

      await _cache.setCache(CacheService.keyUnlockedSubjects, _unlockedSubjectIds.toList(), const Duration(days: 7));
      await _cache.setCache(CacheService.keyUnlockedClinicalSubjects, _unlockedClinicalSubjectIds.toList(), const Duration(days: 7));
      
      notifyListeners();
    } catch (e) {
      print('Error fetching unlocked subjects from network: $e');
      final cachedUnlocked = _cache.getCache(CacheService.keyUnlockedSubjects) ??
          _cache.getCacheAllowExpired(CacheService.keyUnlockedSubjects);
      if (cachedUnlocked is List) {
        _unlockedSubjectIds = List<int>.from(cachedUnlocked).toSet();
      }

      final cachedUnlockedClinical = _cache.getCache(CacheService.keyUnlockedClinicalSubjects) ??
          _cache.getCacheAllowExpired(CacheService.keyUnlockedClinicalSubjects);
      if (cachedUnlockedClinical is List) {
        _unlockedClinicalSubjectIds = List<int>.from(cachedUnlockedClinical).toSet();
      }
      notifyListeners();
    }
  }

  // --- Admin Subscriptions Management methods ---
  Future<List<Map<String, dynamic>>> searchUsers(String query) => _supabase.searchUsers(query);
  Future<List<Map<String, dynamic>>> getUserSubscriptions(String userId) => _supabase.getUserSubscriptions(userId);
  Future<bool> addUserSubscription({
    required String userId,
    int? subjectId,
    int? clinicalSubjectId,
    required String status,
    DateTime? expiresAt,
  }) => _supabase.addUserSubscription(
    userId: userId,
    subjectId: subjectId,
    clinicalSubjectId: clinicalSubjectId,
    status: status,
    expiresAt: expiresAt,
  );
  Future<bool> deleteUserSubscription(String subscriptionId) => _supabase.deleteUserSubscription(subscriptionId);
  Future<List<Map<String, dynamic>>> getUniversityAccessList() => _supabase.getUniversityAccessList();
  Future<bool> addUniversityAccess({
    required String university,
    int? subjectId,
    int? clinicalSubjectId,
    bool? allScientific,
    bool? allPractical,
    required String status,
    DateTime? expiresAt,
  }) => _supabase.addUniversityAccess(
    university: university,
    subjectId: subjectId,
    clinicalSubjectId: clinicalSubjectId,
    allScientific: allScientific,
    allPractical: allPractical,
    status: status,
    expiresAt: expiresAt,
  );
  Future<bool> deleteUniversityAccess(String accessId) => _supabase.deleteUniversityAccess(accessId);

  // Supabase current user getter
  User? get currentUser => _supabase.currentUser;
  String? get lastSupabaseError => _supabase.lastError;

  // Statistics getters (linked to public.leaderboard table values)
  int get totalAnswered => _leaderboardTotalAnswers;
  int get totalCorrect => _leaderboardCorrectAnswers;
  double get accuracy => _leaderboardAccuracy;

  Map<String, dynamic> _cachedMap(String key) {
    final cached = _cache.getCache(key) ?? _cache.getCacheAllowExpired(key);
    if (cached is Map) {
      return Map<String, dynamic>.from(cached);
    }
    return <String, dynamic>{};
  }

  Future<void> _cacheUserAnswers() async {
    await _cache.setCache(
      _cachedUserAnswersKey,
      _userAnswers,
      const Duration(days: 36500),
    );
  }

  void _recalculateLocalAnswerStats() {
    _leaderboardTotalAnswers = _userAnswers.length;
    _leaderboardCorrectAnswers = _userAnswers.values.where((answer) {
      return answer is Map && answer['is_correct'] == true;
    }).length;
    _leaderboardAccuracy = _leaderboardTotalAnswers > 0
        ? (_leaderboardCorrectAnswers / _leaderboardTotalAnswers) * 100.0
        : 0.0;
  }

  Future<void> _queuePendingAnswer(
    int questionId,
    Map<String, dynamic> answerData,
  ) async {
    final pending = _cachedMap(_pendingUserAnswersKey);
    pending[questionId.toString()] = answerData;
    await _cache.setCache(
      _pendingUserAnswersKey,
      pending,
      const Duration(days: 36500),
    );
  }

  void _startPendingAnswerSyncTimer() {
    _pendingAnswerSyncTimer ??=
        Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_syncPendingAnswers());
    });
  }

  Future<void> _syncPendingAnswers() async {
    if (_isSyncingPendingAnswers || !_supabase.isAuthenticated) return;

    final pending = _cachedMap(_pendingUserAnswersKey);
    if (pending.isEmpty) return;

    _isSyncingPendingAnswers = true;
    final remaining = Map<String, dynamic>.from(pending);

    try {
      for (final entry in pending.entries) {
        if (entry.value is! Map) {
          remaining.remove(entry.key);
          continue;
        }
        final answer = Map<String, dynamic>.from(entry.value as Map);
        final questionId = int.tryParse(entry.key);
        final selectedAnswer = answer['answer'];
        final isCorrect = answer['is_correct'];
        final timeTaken = answer['time_taken'];
        final subject = answer['subject']?.toString();

        if (questionId == null ||
            selectedAnswer is! int ||
            isCorrect is! bool ||
            subject == null ||
            subject.isEmpty) {
          remaining.remove(entry.key);
          continue;
        }

        await _supabase.saveUserAnswer(
          questionId: questionId,
          selectedAnswer: selectedAnswer,
          isCorrect: isCorrect,
          timeTaken: timeTaken is int ? timeTaken : 10,
          subject: subject,
        );
        remaining.remove(entry.key);
        await _cache.setCache(
          _pendingUserAnswersKey,
          remaining,
          const Duration(days: 36500),
        );
      }
    } catch (e) {
      print('Pending answer sync paused: $e');
    } finally {
      _isSyncingPendingAnswers = false;
    }
  }

  void _startSessionCheckTimer(String userId, String deviceId) {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      await checkSessionValidity(userId, deviceId);
    });
  }

  void _stopSessionCheckTimer() {
    _sessionCheckTimer?.cancel();
  }

  Future<void> checkSessionValidity(String userId, String deviceId) async {
    if (!_supabase.isAuthenticated) return;
    final isValid = await _supabase.isSessionValid(userId, deviceId);
    if (!isValid) {
      _isSessionInvalidated = true;
      _stopSessionCheckTimer();
      await signOut();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pendingAnswerSyncTimer?.cancel();
    _sessionCheckTimer?.cancel();
    super.dispose();
  }

  // Initialize and load subjects & progress
  Future<void> initializeData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _startPendingAnswerSyncTimer();

      final cachedUnlocked = _cache.getCache(CacheService.keyUnlockedSubjects) ??
          _cache.getCacheAllowExpired(CacheService.keyUnlockedSubjects);
      if (cachedUnlocked is List) {
        _unlockedSubjectIds = List<int>.from(cachedUnlocked).toSet();
      }
      final cachedUnlockedClinical = _cache.getCache(CacheService.keyUnlockedClinicalSubjects) ??
          _cache.getCacheAllowExpired(CacheService.keyUnlockedClinicalSubjects);
      if (cachedUnlockedClinical is List) {
        _unlockedClinicalSubjectIds = List<int>.from(cachedUnlockedClinical).toSet();
      }

      final cachedPlan = _cache.getCache('study_plan_cache') ??
          _cache.getCacheAllowExpired('study_plan_cache');
      if (cachedPlan is Map) {
        _studyPlan = Map<String, dynamic>.from(cachedPlan);
      }
      final cachedRole = _cache.getCache('user_role_cache') ??
          _cache.getCacheAllowExpired('user_role_cache');
      if (cachedRole is String) {
        _userRole = cachedRole;
      }
      final cachedDetails = _cache.getCache('user_details_cache') ??
          _cache.getCacheAllowExpired('user_details_cache');
      if (cachedDetails is Map) {
        _userDetails = Map<String, dynamic>.from(cachedDetails);
      }
      final cachedProgress = _cache.getCache('clinical_subject_progress_cache') ??
          _cache.getCacheAllowExpired('clinical_subject_progress_cache');
      if (cachedProgress is Map) {
        cachedProgress.forEach((k, v) {
          _clinicalSubjectProgress[k.toString()] = (v as num).toDouble();
        });
      }

      final cachedFavorites = _cache.getCache('user_favorites_cache') ??
          _cache.getCacheAllowExpired('user_favorites_cache');
      if (cachedFavorites is List) {
        _favorites = List<int>.from(cachedFavorites);
      }
      final cachedBookmarks = _cache.getCache('clinical_bookmarks_cache') ??
          _cache.getCacheAllowExpired('clinical_bookmarks_cache');
      if (cachedBookmarks is List) {
        _clinicalBookmarks
          ..clear()
          ..addAll(List<String>.from(cachedBookmarks));
      }

      final cachedAnswers = _cachedMap(_cachedUserAnswersKey);
      final pendingAnswers = _cachedMap(_pendingUserAnswersKey);
      if (cachedAnswers.isNotEmpty || pendingAnswers.isNotEmpty) {
        _userAnswers = {
          ...cachedAnswers,
          ...pendingAnswers,
        };
        _recalculateLocalAnswerStats();
      }

      // 1. Load subjects from cache or Supabase
      final cachedSubjects = _cache.getCache(CacheService.keySubjects) ??
          _cache.getCacheAllowExpired(CacheService.keySubjects);
      if (cachedSubjects != null &&
          cachedSubjects is List &&
          cachedSubjects.isNotEmpty) {
        _subjects = cachedSubjects
            .map((s) => Subject.fromJson(Map<String, dynamic>.from(s)))
            .toList();
      } else {
        final List<Map<String, dynamic>> data = await _supabase.getSubjects();
        _subjects = data.map((s) => Subject.fromJson(s)).toList();
        await _cache.setCache(
            CacheService.keySubjects, data, CacheService.subjectsLifespan);
      }

      // Load clinical subjects (Cache-first with background sync)
      await fetchClinicalSubjectsCacheFirst();

      // Clear questions cache once to fetch questions with comprehensive subject name case matching
      final hasResetCache = _cache.getCache('reset_questions_cache_v5');
      if (hasResetCache == null) {
        for (var subject in _subjects) {
          final key = _cache.getQuestionsKey(subject.name);
          await _cache.invalidateCache(key);
        }
        await _cache.setCache(
            'reset_questions_cache_v5', true, const Duration(days: 36500));
      }

      // 2. Load user progress from Supabase
      if (_supabase.isAuthenticated) {
        final user = _supabase.currentUser;
        if (user != null) {
          final deviceId = _cache.getInstallationId();
          final deviceName = kIsWeb
              ? 'Web'
              : (defaultTargetPlatform == TargetPlatform.android
                  ? 'Android'
                  : (defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Desktop'));
          unawaited(_supabase.registerOrUpdateSession(user.id, deviceId, deviceName));
          _startSessionCheckTimer(user.id, deviceId);
        }

        final cachedViewMode = _cache.getCache('view_mode') as String?;
        if (cachedViewMode != null) {
          _viewMode = cachedViewMode;
        }

        final recent = _cache.getCache('recent_topics') ??
            _cache.getCacheAllowExpired('recent_topics');
        if (recent != null) {
          _recentTopics = List<Map<String, dynamic>>.from(
              (recent as List).map((item) => Map<String, dynamic>.from(item)));
        }

        // Fetch progress, leaderboard, study plan, role, details, and unlocked subjects in parallel with a timeout
        try {
          await Future.wait([
            _supabase.getUserProgress().then((progress) async {
              if (progress != null) {
                _favorites = List<int>.from(progress['favorites'] ?? []);
                await _cache.setCache('user_favorites_cache', _favorites, const Duration(days: 30));
                
                final remoteAnswers = Map<String, dynamic>.from(progress['answers'] ?? {});
                final pendingAnswers = _cachedMap(_pendingUserAnswersKey);
                _userAnswers = {
                  ...remoteAnswers,
                  ..._userAnswers,
                  ...pendingAnswers,
                };
                await _cacheUserAnswers();
                _highlights = Map<String, dynamic>.from(progress['highlights'] ?? {});
              }
            }),
            loadClinicalBookmarks(),
            _supabase.getUserLeaderboardStats().then((leaderboardStats) {
              if (leaderboardStats != null) {
                _leaderboardTotalAnswers = leaderboardStats['total_answers'] ?? 0;
                _leaderboardCorrectAnswers = leaderboardStats['correct_answers'] ?? 0;
                final rawAcc = leaderboardStats['accuracy'];
                if (rawAcc is num) {
                  _leaderboardAccuracy = rawAcc.toDouble();
                } else if (rawAcc is String) {
                  _leaderboardAccuracy = double.tryParse(rawAcc) ?? 0.0;
                }
              } else {
                // Fallback to answers length if not in leaderboard yet
                _leaderboardTotalAnswers = _userAnswers.length;
                _leaderboardCorrectAnswers =
                    _userAnswers.values.where((a) => a['is_correct'] == true).length;
                if (_leaderboardTotalAnswers > 0) {
                  _leaderboardAccuracy =
                      (_leaderboardCorrectAnswers / _leaderboardTotalAnswers) * 100.0;
                } else {
                  _leaderboardAccuracy = 0.0;
                }
              }
            }),
            _supabase.getActiveStudyPlan().then((plan) async {
              if (plan != null) {
                _studyPlan = plan;
                await _cache.setCache('study_plan_cache', plan, const Duration(days: 7));
                await checkAndUpdateDailyPlan();
              }
            }),
            _supabase.getUserRole().then((role) async {
              if (role != null) {
                _userRole = role;
                await _cache.setCache('user_role_cache', role, const Duration(days: 7));
              }
            }),
            _supabase.getUserDetails().then((details) async {
              if (details != null) {
                _userDetails = details;
                await _cache.setCache('user_details_cache', details, const Duration(days: 7));
              }
            }),
            fetchUnlockedSubjects(),
          ]).timeout(const Duration(seconds: 2));
        } catch (e) {
          print('Background initialization sync timed out or failed: $e');
        }

        // Calculate all clinical subjects progress on startup in the background
        unawaited(calculateAllClinicalProgress());
        unawaited(_syncPendingAnswers());
      }
    } catch (e) {
      print('Error loading Stagiaire initial data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Select subject and fetch questions (Cache-first with background sync)
  Future<void> selectSubject(String subjectName) async {
    _selectedSubject = subjectName;
    _isQuestionsLoading = true;
    notifyListeners();

    final cacheKey = _cache.getQuestionsKey(subjectName);
    final cachedQs =
        _cache.getCache(cacheKey) ?? _cache.getCacheAllowExpired(cacheKey);

    if (cachedQs is List && cachedQs.isNotEmpty) {
      await _applyQuestionsForSubject(
          subjectName, List<Map<String, dynamic>>.from(cachedQs));
      _isQuestionsLoading = false;
      notifyListeners();
      unawaited(_refreshSubjectQuestionsCache(subjectName, cacheKey));
      return;
    }

    try {
      final rawQuestions = await _supabase
          .getQuestions(subjectName)
          .timeout(const Duration(seconds: 60));
      await _cache.setCache(
          cacheKey, rawQuestions, CacheService.questionsLifespan);
      await _applyQuestionsForSubject(subjectName, rawQuestions);
    } catch (e) {
      print('Error loading questions for $subjectName: $e');
      final fallbackQs = _cache.getCacheAllowExpired(cacheKey);
      if (fallbackQs is List && fallbackQs.isNotEmpty) {
        await _applyQuestionsForSubject(
            subjectName, List<Map<String, dynamic>>.from(fallbackQs));
      }
    } finally {
      _isQuestionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshSubjectQuestionsCache(
      String subjectName, String cacheKey) async {
    try {
      final cachedQs =
          _cache.getCache(cacheKey) ?? _cache.getCacheAllowExpired(cacheKey);
      List<Map<String, dynamic>> rawQuestions = cachedQs is List
          ? List<Map<String, dynamic>>.from(cachedQs)
          : <Map<String, dynamic>>[];

      if (rawQuestions.isEmpty) {
        rawQuestions = await _supabase
            .getQuestions(subjectName)
            .timeout(const Duration(seconds: 30));
      } else {
        String? maxUpdatedAt;
        for (final q in rawQuestions) {
          final updatedAtStr = q['updated_at']?.toString();
          if (updatedAtStr != null && updatedAtStr.isNotEmpty) {
            if (maxUpdatedAt == null ||
                updatedAtStr.compareTo(maxUpdatedAt) > 0) {
              maxUpdatedAt = updatedAtStr;
            }
          }
        }

        if (maxUpdatedAt != null) {
          final deltaQuestions = await _supabase
              .getQuestionsUpdatedAfter(subjectName, maxUpdatedAt)
              .timeout(const Duration(seconds: 30));
          for (final dq in deltaQuestions) {
            final id = _safeIntVal(dq['id']);
            final isDeleted = dq['is_deleted'] == true;
            if (isDeleted) {
              rawQuestions.removeWhere((q) => _safeIntVal(q['id']) == id);
            } else {
              final idx = rawQuestions.indexWhere((q) => _safeIntVal(q['id']) == id);
              if (idx != -1) {
                rawQuestions[idx] = dq;
              } else {
                rawQuestions.add(dq);
              }
            }
          }
        }
      }

      rawQuestions.sort((a, b) => _safeIntVal(a['id']).compareTo(_safeIntVal(b['id'])));
      await _cache.setCache(
          cacheKey, rawQuestions, CacheService.questionsLifespan);

      if (_selectedSubject == subjectName) {
        await _applyQuestionsForSubject(subjectName, rawQuestions);
        if (_practiceQuestions.isNotEmpty) {
          final refreshedById = {for (final q in _questions) q.id: q};
          _practiceQuestions = _practiceQuestions
              .map((q) => refreshedById[q.id] ?? q)
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
        }
        notifyListeners();
      }
    } catch (e) {
      print('Background questions sync failed for $subjectName: $e');
    }
  }

  Map<String, int> _topicOrders = {};
  Map<String, int> _subTopicOrders = {};
  Map<String, int> get topicOrders => _topicOrders;
  Map<String, int> get subTopicOrders => _subTopicOrders;

  Future<void> fetchTitlesOrders(String subjectName) async {
    try {
      final titlesData = await _supabase.getTitlesForSubject(subjectName);
      final Map<String, int> newTopicOrders = {};
      final Map<String, int> newSubTopicOrders = {};

      for (final row in titlesData) {
        final String name = row['name']?.toString() ?? '';
        final String? subTitle = row['sub_title']?.toString();
        final int? titleOrder = _safeIntNullable(row['title_order']);
        final int? subOrder = _safeIntNullable(row['subtitle_order']);

        if (name.isNotEmpty && titleOrder != null && titleOrder > 0) {
          if (!newTopicOrders.containsKey(name) ||
              titleOrder < newTopicOrders[name]!) {
            newTopicOrders[name] = titleOrder;
          }
        }
        if (name.isNotEmpty &&
            subTitle != null &&
            subTitle.isNotEmpty &&
            subOrder != null &&
            subOrder > 0) {
          newSubTopicOrders['$name:$subTitle'] = subOrder;
        }
      }
      _topicOrders = newTopicOrders;
      _subTopicOrders = newSubTopicOrders;
      notifyListeners();
    } catch (e) {
      print('Error fetching titles orders for $subjectName: $e');
    }
  }

  Future<void> saveTitlesOrder({
    required String subjectName,
    required List<Map<String, dynamic>> updates,
  }) async {
    final subjectId = await _supabase.getSubjectIdByName(subjectName);
    if (subjectId == null) {
      throw Exception('Subject ID not found for $subjectName');
    }

    await _supabase.updateTitlesOrder(subjectId: subjectId, updates: updates);
    await fetchTitlesOrders(subjectName);
    notifyListeners();
  }

  Future<void> _applyQuestionsForSubject(
      String subjectName, List<Map<String, dynamic>> rawQuestions) async {
    _questions = rawQuestions.map((q) => Question.fromJson(q)).toList();
    _questions.sort((a, b) => a.id.compareTo(b.id));

    // Fetch titles ordering in background so UI renders questions immediately without waiting for network
    unawaited(fetchTitlesOrders(subjectName));

    for (final q in _questions) {
      if (_userAnswers.containsKey(q.id.toString())) {
        final userAns = _userAnswers[q.id.toString()];
        q.isSolved = true;
        final storedAns = userAns['answer'] as int?;
        final isCorrectVal = userAns['is_correct'] == true;
        if (storedAns != null) {
          var healedAns = storedAns;
          if (isCorrectVal) {
            healedAns = q.correct;
          } else {
            if (storedAns == q.correct) {
              healedAns = storedAns - 1;
            } else if (storedAns > q.correct) {
              healedAns = storedAns - 1;
            }
          }
          if (healedAns < 0) healedAns = 0;
          if (healedAns >= q.options.length) healedAns = q.options.length - 1;
          q.userAnswer = healedAns;
          userAns['answer'] = healedAns;
        }
      }
    }

    var changed = false;
    for (var i = 0; i < _recentTopics.length; i++) {
      final item = _recentTopics[i];
      if (item['subject'] == subjectName) {
        final tName = item['topic'];
        final topicQs = _questions.where((q) => q.topic == tName).toList();
        if (topicQs.isNotEmpty) {
          final total = topicQs.length;
          final solved = topicQs.where((q) => q.isSolved).length;
          if (solved >= total) {
            _recentTopics.removeAt(i);
            i--;
            changed = true;
          } else if (item['total'] != total || item['solved'] != solved) {
            _recentTopics[i] = {...item, 'total': total, 'solved': solved};
            changed = true;
          }
        }
      }
    }
    if (changed) {
      await _cache.setCache(
          'recent_topics', _recentTopics, const Duration(days: 36500));
    }
  }

// Set the specific questions list for the practice session
  void startPracticeSession(List<Question> sessionQuestions,
      {bool recordProgress = true}) {
    _recordPracticeProgress = recordProgress;
    _practiceQuestions = List<Question>.from(sessionQuestions);
    _practiceQuestions.sort((a, b) => a.id.compareTo(b.id));
    notifyListeners();
  }

  // Answer a question and sync with database
  Future<void> answerQuestion(Question q, int selectedIdx) async {
    if (q.isSolved) return;

    final bool isCorrect = selectedIdx == q.correct;
    q.isSolved = true;
    q.userAnswer = selectedIdx;

    // Update local answers distribution to reflect user's answer immediately
    final currentStats = q.answersDistribution[selectedIdx] ??
        OptionStats(count: 0, percent: 0.0);
    q.answersDistribution[selectedIdx] = OptionStats(
        count: currentStats.count + 1, percent: currentStats.percent);

    int totalCount = 0;
    q.answersDistribution.forEach((key, val) {
      totalCount += val.count;
    });

    if (totalCount > 0) {
      q.answersDistribution.keys.toList().forEach((key) {
        final val = q.answersDistribution[key]!;
        final newPercent = (val.count / totalCount) * 100.0;
        q.answersDistribution[key] = OptionStats(
          count: val.count,
          percent: double.parse(newPercent.toStringAsFixed(1)),
        );
      });
    }

    if (!_recordPracticeProgress) {
      notifyListeners();
      return;
    }

    // Immediately persist locally before any network attempt.
    final answerData = {
      'answer': selectedIdx,
      'is_correct': isCorrect,
      'time_taken': 10,
      'answered_at': DateTime.now().toIso8601String(),
      'subject': q.subject,
    };
    _userAnswers[q.id.toString()] = answerData;
    await _cacheUserAnswers();
    await _queuePendingAnswer(q.id, answerData);

    // Update local leaderboard counters for real-time update
    _leaderboardTotalAnswers++;
    if (isCorrect) {
      _leaderboardCorrectAnswers++;
    }
    if (_leaderboardTotalAnswers > 0) {
      _leaderboardAccuracy =
          (_leaderboardCorrectAnswers / _leaderboardTotalAnswers) * 100.0;
    }

    notifyListeners();

    if (q.topic != null && q.topic!.trim().isNotEmpty) {
      _updateRecentTopic(q.subject, q.topic!);
    }

    // Sync in background. If offline, the pending queue stays cached and retries silently.
    unawaited(_syncPendingAnswers());
  }

  Future<void> loadClinicalBookmarks() async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      final response = await _supabase.client
          .from('user_bookmarks')
          .select('item_type, item_id')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 3));
      _clinicalBookmarks
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(response).map((row) {
          return _clinicalBookmarkKey(
              row['item_type'].toString(), row['item_id'].toString());
        }));
      await _cache.setCache('clinical_bookmarks_cache', _clinicalBookmarks.toList(), const Duration(days: 30));
      notifyListeners();
    } catch (e) {
      print('Error loading clinical bookmarks: $e');
    }
  }

  Future<void> toggleClinicalBookmark(String itemType, String? itemId) async {
    final user = _supabase.currentUser;
    if (user == null || itemId == null || itemId.isEmpty) return;
    final key = _clinicalBookmarkKey(itemType, itemId);
    final wasBookmarked = _clinicalBookmarks.contains(key);
    if (wasBookmarked) {
      _clinicalBookmarks.remove(key);
    } else {
      _clinicalBookmarks.add(key);
    }
    notifyListeners();

    try {
      if (wasBookmarked) {
        await _supabase.client
            .from('user_bookmarks')
            .delete()
            .eq('user_id', user.id)
            .eq('item_type', itemType)
            .eq('item_id', itemId);
      } else {
        await _supabase.client.from('user_bookmarks').upsert({
          'user_id': user.id,
          'item_type': itemType,
          'item_id': itemId,
        }, onConflict: 'user_id,item_type,item_id');
      }
      await _cache.setCache('clinical_bookmarks_cache', _clinicalBookmarks.toList(), const Duration(days: 30));
    } catch (e) {
      if (wasBookmarked) {
        _clinicalBookmarks.add(key);
      } else {
        _clinicalBookmarks.remove(key);
      }
      notifyListeners();
      print('Error toggling clinical bookmark: $e');
    }
  }
  bool isStationCompleted(String? stationDbId) {
    if (stationDbId == null || stationDbId.isEmpty) return false;
    final station = _dbSlideStations.firstWhere(
      (s) => s.dbId == stationDbId,
      orElse: () => _clinicalSlideStations.firstWhere(
        (s) => s.dbId == stationDbId,
        orElse: () => ClinicalSlideStation(
          id: 0,
          title: '',
          progressText: '',
          progress: 0.0,
          iconType: '',
          subject: '',
        ),
      ),
    );
    return station.evaluation != null || station.progress >= 1.0;
  }

  Future<void> toggleStationCompletion(String? stationDbId, {int totalSlides = 10}) async {
    if (stationDbId == null || stationDbId.isEmpty) return;

    // Find the station to get its subject name
    final station = _dbSlideStations.firstWhere(
      (s) => s.dbId == stationDbId,
      orElse: () => _clinicalSlideStations.firstWhere(
        (s) => s.dbId == stationDbId,
        orElse: () => ClinicalSlideStation(
          id: 0,
          title: '',
          progressText: '',
          progress: 0.0,
          iconType: '',
          subject: '',
        ),
      ),
    );

    final isDone = isStationCompleted(stationDbId);
    if (isDone) {
      await updateStationProgress(stationDbId, 1, null);
    } else {
      await updateStationProgress(stationDbId, totalSlides, 'completed');
    }

    if (station.subject.isNotEmpty) {
      await invalidateClinicalCache(station.subject);
      await loadClinicalData(station.subject);
    }
  }

  // Toggle favorite bookmark state
  Future<void> toggleFavorite(int questionId) async {
    if (_favorites.contains(questionId)) {
      _favorites.remove(questionId);
    } else {
      _favorites.add(questionId);
    }
    notifyListeners();

    try {
      _favorites = await _supabase.toggleFavorite(questionId);
      await _cache.setCache('user_favorites_cache', _favorites, const Duration(days: 30));
      notifyListeners();
    } catch (e) {
      print('Error syncing favorite status: $e');
    }
  }

  // Switch dark/light theme mode
  void toggleTheme() {
    _isDarkTheme = !_isDarkTheme;
    _cache.setCache('is_dark_theme', _isDarkTheme, const Duration(days: 36500));
    notifyListeners();
  }

  // Reset user progress for the current subject, either for a specific topic or all
  Future<void> resetProgress({String? topicName}) async {
    if (_selectedSubject == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      List<Question> targetQs;
      if (topicName == null || topicName == '__ALL__') {
        targetQs = _questions;
      } else {
        targetQs = _questions.where((q) => q.topic == topicName).toList();
      }

      for (var q in targetQs) {
        q.isSolved = false;
        q.userAnswer = null;
        _userAnswers.remove(q.id.toString());
      }

      // Recalculate leaderboard counters
      int correct = 0;
      int total = 0;
      _userAnswers.forEach((key, val) {
        if (val['is_correct'] == true) {
          correct++;
        }
        total++;
      });
      _leaderboardCorrectAnswers = correct;
      _leaderboardTotalAnswers = total;
      _leaderboardAccuracy = total > 0 ? (correct / total) * 100.0 : 0.0;

      await _cacheUserAnswers();

      // Update Database
      await _supabase.updateUserProgressAnswers(_userAnswers);

      // Save updated questions cache
      final cacheKey = _cache.getQuestionsKey(_selectedSubject!);
      await _cache.setCache(
          cacheKey,
          _questions.map((q) => q.toJson()).toList(),
          CacheService.questionsLifespan);

      // Re-trigger selectSubject to refresh all caches and dynamic lists cleanly
      await selectSubject(_selectedSubject!);
    } catch (e) {
      print('Error resetting subject progress: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign out user and clean cache states
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      _stopSessionCheckTimer();
      _isSessionInvalidated = false;
      await _supabase.signOut();
      _favorites = [];
      _clinicalBookmarks.clear();
      _userAnswers = {};
      _highlights = {};
      _userDetails = null;
      _userRole = null;
      _leaderboardTotalAnswers = 0;
      _leaderboardCorrectAnswers = 0;
      _leaderboardAccuracy = 0.0;
      await _cache.invalidateCache(_cachedUserAnswersKey);
      await _cache.invalidateCache(_pendingUserAnswersKey);
    } catch (e) {
      print('Error during sign out: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete user account from remote DB and clean cache states
  Future<void> deleteAccount() async {
    _isLoading = true;
    notifyListeners();
    try {
      _stopSessionCheckTimer();
      _isSessionInvalidated = false;
      await _supabase.deleteAccount();
      _favorites = [];
      _clinicalBookmarks.clear();
      _userAnswers = {};
      _highlights = {};
      _userDetails = null;
      _userRole = null;
      _leaderboardTotalAnswers = 0;
      _leaderboardCorrectAnswers = 0;
      _leaderboardAccuracy = 0.0;
      await _cache.invalidateCache(_cachedUserAnswersKey);
      await _cache.invalidateCache(_pendingUserAnswersKey);
    } catch (e) {
      print('Error during account deletion: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }


  Future<bool> updateQuestionExplanationFormat(
    int questionId,
    String fieldName,
    List<Map<String, dynamic>> ranges,
  ) async {
    final success = await _supabase.updateQuestionExplanationFormat(
        questionId, fieldName, ranges);
    if (!success) return false;
    return updateQuestion(questionId, {fieldName: ranges}, syncRemote: false);
  }

  // Delete question from local state and remote DB (for admin users)
  Future<bool> deleteQuestion(int questionId) async {
    final bool success = await _supabase.deleteQuestion(questionId);
    if (success) {
      _questions.removeWhere((q) => q.id == questionId);
      _practiceQuestions.removeWhere((q) => q.id == questionId);
      _userAnswers.remove(questionId.toString());
      notifyListeners();
    }
    return success;
  }

  // Update question in local state and remote DB (for admin users)
  Future<bool> updateQuestion(int questionId, Map<String, dynamic> updateData,
      {bool syncRemote = true}) async {
    final bool success = syncRemote
        ? await _supabase.updateQuestion(questionId, updateData)
        : true;
    if (success) {
      // Find and update question in _questions
      final qIdx = _questions.indexWhere((q) => q.id == questionId);
      if (qIdx != -1) {
        final origQ = _questions[qIdx];
        final List<String> parsedOptions = [];
        for (int i = 1; i <= 11; i++) {
          final opt = updateData['answer_$i'];
          if (opt != null && opt.toString().trim().isNotEmpty) {
            parsedOptions.add(opt.toString().trim());
          }
        }
        final finalOptions =
            parsedOptions.isNotEmpty ? parsedOptions : origQ.options;

        _questions[qIdx] = Question(
          id: origQ.id,
          text: updateData['question'] ?? origQ.text,
          options: finalOptions,
          correct: updateData['correct_answer'] != null
              ? (updateData['correct_answer'] as int) - 1
              : origQ.correct,
          explanation: updateData['explanation'] ?? origQ.explanation,
          subject: origQ.subject,
          topic: updateData['title'] ?? origQ.topic,
          subTopic: updateData['sub_title'] ?? origQ.subTopic,
          ref: origQ.ref,
          audioUrl: updateData.containsKey('audio_url')
              ? updateData['audio_url'] as String?
              : origQ.audioUrl,
          audioDurationSeconds: updateData.containsKey('audio_duration_seconds')
              ? (updateData['audio_duration_seconds'] as num?)?.toInt()
              : origQ.audioDurationSeconds,
          audioHighlights: updateData.containsKey('audio_highlights')
              ? Question.fromJson({
                  'id': origQ.id,
                  'audio_highlights': updateData['audio_highlights']
                }).audioHighlights
              : origQ.audioHighlights,
          explanationBoldRanges:
              updateData.containsKey('explanation_bold_ranges')
                  ? Question.fromJson({
                      'id': origQ.id,
                      'explanation_bold_ranges':
                          updateData['explanation_bold_ranges']
                    }).explanationBoldRanges
                  : origQ.explanationBoldRanges,
          explanationUnderlineRanges:
              updateData.containsKey('explanation_underline_ranges')
                  ? Question.fromJson({
                      'id': origQ.id,
                      'explanation_underline_ranges':
                          updateData['explanation_underline_ranges']
                    }).explanationUnderlineRanges
                  : origQ.explanationUnderlineRanges,
          updatedAt: DateTime.now().toIso8601String(),
          isSolved: origQ.isSolved,
          userAnswer: origQ.userAnswer,
          answersDistribution: origQ.answersDistribution,
        );
      }

      // Also update in _practiceQuestions
      final pqIdx = _practiceQuestions.indexWhere((q) => q.id == questionId);
      if (pqIdx != -1) {
        final origQ = _practiceQuestions[pqIdx];
        final List<String> parsedOptions = [];
        for (int i = 1; i <= 11; i++) {
          final opt = updateData['answer_$i'];
          if (opt != null && opt.toString().trim().isNotEmpty) {
            parsedOptions.add(opt.toString().trim());
          }
        }
        final finalOptions =
            parsedOptions.isNotEmpty ? parsedOptions : origQ.options;

        _practiceQuestions[pqIdx] = Question(
          id: origQ.id,
          text: updateData['question'] ?? origQ.text,
          options: finalOptions,
          correct: updateData['correct_answer'] != null
              ? (updateData['correct_answer'] as int) - 1
              : origQ.correct,
          explanation: updateData['explanation'] ?? origQ.explanation,
          subject: origQ.subject,
          topic: updateData['title'] ?? origQ.topic,
          subTopic: updateData['sub_title'] ?? origQ.subTopic,
          ref: origQ.ref,
          audioUrl: updateData.containsKey('audio_url')
              ? updateData['audio_url'] as String?
              : origQ.audioUrl,
          audioDurationSeconds: updateData.containsKey('audio_duration_seconds')
              ? (updateData['audio_duration_seconds'] as num?)?.toInt()
              : origQ.audioDurationSeconds,
          audioHighlights: updateData.containsKey('audio_highlights')
              ? Question.fromJson({
                  'id': origQ.id,
                  'audio_highlights': updateData['audio_highlights']
                }).audioHighlights
              : origQ.audioHighlights,
          explanationBoldRanges:
              updateData.containsKey('explanation_bold_ranges')
                  ? Question.fromJson({
                      'id': origQ.id,
                      'explanation_bold_ranges':
                          updateData['explanation_bold_ranges']
                    }).explanationBoldRanges
                  : origQ.explanationBoldRanges,
          explanationUnderlineRanges:
              updateData.containsKey('explanation_underline_ranges')
                  ? Question.fromJson({
                      'id': origQ.id,
                      'explanation_underline_ranges':
                          updateData['explanation_underline_ranges']
                    }).explanationUnderlineRanges
                  : origQ.explanationUnderlineRanges,
          updatedAt: DateTime.now().toIso8601String(),
          isSolved: origQ.isSolved,
          userAnswer: origQ.userAnswer,
          answersDistribution: origQ.answersDistribution,
        );
      }

      String? subjectForCache = _selectedSubject;
      if (subjectForCache == null) {
        for (final q in _questions) {
          if (q.id == questionId) {
            subjectForCache = q.subject;
            break;
          }
        }
      }
      if (subjectForCache == null) {
        for (final q in _practiceQuestions) {
          if (q.id == questionId) {
            subjectForCache = q.subject;
            break;
          }
        }
      }
      if (subjectForCache != null) {
        final cacheKey = _cache.getQuestionsKey(subjectForCache);
        final cachedQs =
            _cache.getCache(cacheKey) ?? _cache.getCacheAllowExpired(cacheKey);
        if (cachedQs is List) {
          final rawQuestions = List<Map<String, dynamic>>.from(
            cachedQs.map((item) => Map<String, dynamic>.from(item as Map)),
          );
          final idx = rawQuestions.indexWhere((q) => q['id'] == questionId);
          if (idx != -1) {
            rawQuestions[idx] = {
              ...rawQuestions[idx],
              ...updateData,
              'updated_at': DateTime.now().toIso8601String(),
            };
            await _cache.setCache(
                cacheKey, rawQuestions, CacheService.questionsLifespan);
          }
        }
      }

      notifyListeners();
    }
    return success;
  }

  static const String _highlightRangePrefix = '__range__:';

  Map<String, dynamic>? _decodeHighlightRangeToken(String value) {
    if (!value.startsWith(_highlightRangePrefix)) return null;
    final parts = value.substring(_highlightRangePrefix.length).split(':');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null || start < 0 || end <= start) {
      return null;
    }
    return {'start': start, 'end': end};
  }

  String _encodeHighlightRangeToken(int start, int end) =>
      '$_highlightRangePrefix$start:$end';

  String _newHighlightId() =>
      'h_${DateTime.now().microsecondsSinceEpoch}_${_highlights.length}';

  int _textVersionForQuestion(int questionId) {
    for (final question in [..._practiceQuestions, ..._questions]) {
      if (question.id == questionId) {
        final updatedAt = question.updatedAt;
        if (updatedAt == null || updatedAt.trim().isEmpty) return 1;
        return DateTime.tryParse(updatedAt)?.millisecondsSinceEpoch ?? 1;
      }
    }
    return 1;
  }

  List<Map<String, dynamic>> _parseHighlightItems(dynamic record) {
    final List<Map<String, dynamic>> items = [];

    void addRangeItem(Map raw) {
      final start = (raw['start'] as num?)?.toInt();
      final end = (raw['end'] as num?)?.toInt() ??
          (start != null && raw['length'] is num
              ? start + (raw['length'] as num).toInt()
              : null);
      final textValue =
          (raw['selectedText'] ?? raw['selected_text'] ?? raw['text'])
                  ?.toString() ??
              '';
      final rangeFromText = _decodeHighlightRangeToken(textValue);
      final safeStart = start ?? (rangeFromText?['start'] as int?);
      final safeEnd = end ?? (rangeFromText?['end'] as int?);

      if (safeStart != null &&
          safeEnd != null &&
          safeStart >= 0 &&
          safeEnd > safeStart) {
        items.add({
          'id': raw['id']?.toString() ?? _newHighlightId(),
          'start': safeStart,
          'end': safeEnd,
          'selectedText': rangeFromText == null ? textValue : '',
          'color': raw['color']?.toString() ?? 'yellow',
          'elementType': raw['elementType']?.toString() ?? 'question',
          'optionIndex': raw['optionIndex'],
          'createdAt': raw['createdAt'] ?? raw['timestamp'],
        });
      } else if (textValue.trim().isNotEmpty) {
        items.add({
          'id': raw['id']?.toString() ?? _newHighlightId(),
          'selectedText': textValue,
          'color': raw['color']?.toString() ?? 'yellow',
          'elementType': raw['elementType']?.toString() ?? 'question',
          'optionIndex': raw['optionIndex'],
          'createdAt': raw['createdAt'] ?? raw['timestamp'],
          'legacy': raw['legacy'] ?? true,
        });
      }
    }

    try {
      final map = record is Map<String, dynamic>
          ? record
          : record is Map
              ? Map<String, dynamic>.from(record)
              : <String, dynamic>{};

      final v2Highlights = map['highlights'];
      if (v2Highlights is List) {
        for (final item in v2Highlights) {
          if (item is Map) addRangeItem(item);
        }
        return items;
      }

      final textVal = map['text'];
      if (textVal is String) {
        final decoded = jsonDecode(textVal);
        if (decoded is Map && decoded['ranges'] is List) {
          for (final item in decoded['ranges'] as List) {
            if (item is Map) addRangeItem(item);
          }
          return items;
        }
      }
    } catch (_) {
      // Fall through to legacy plain-text parsing below.
    }

    final textVal =
        record is Map ? record['text']?.toString() : record?.toString();
    if (textVal == null || textVal.trim().isEmpty) return items;
    final legacyValues = textVal.contains('|||HIGHLIGHT_SEPARATOR|||')
        ? textVal.split('|||HIGHLIGHT_SEPARATOR|||')
        : <String>[textVal];
    for (final value in legacyValues) {
      if (value.trim().isNotEmpty) {
        items.add({
          'id': _newHighlightId(),
          'selectedText': value.trim(),
          'color': 'yellow',
          'elementType': 'question',
          'optionIndex': null,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    return items;
  }

  Map<String, dynamic> _buildHighlightRecord(
      int questionId, List<Map<String, dynamic>> items) {
    return {
      'version': 2,
      'textVersion': _textVersionForQuestion(questionId),
      'highlights': items,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Add one highlight. Range tokens are stored as v2 start/end records;
  // legacy text highlights are preserved for old saved data.
  Future<void> addHighlight(int questionId, String phrase) async {
    final user = _supabase.currentUser;
    if (user == null) return;

    final key = questionId.toString();
    final currentItems = _parseHighlightItems(_highlights[key]);
    final decodedRange = _decodeHighlightRangeToken(phrase);
    debugPrint(
      '[QuestionHighlight] provider add start questionId=$questionId '
      'phrase=$phrase decoded=$decodedRange before=${currentItems.length}',
    );

    final alreadyExists = currentItems.any((item) {
      if (decodedRange != null) {
        return item['start'] == decodedRange['start'] &&
            item['end'] == decodedRange['end'];
      }
      return (item['selectedText'] ?? item['text'])?.toString().toLowerCase() ==
          phrase.toLowerCase();
    });
    if (alreadyExists) {
      debugPrint(
          '[QuestionHighlight] provider add duplicate questionId=$questionId phrase=$phrase');
      return;
    }

    if (decodedRange != null) {
      currentItems.add({
        'id': _newHighlightId(),
        'start': decodedRange['start'],
        'end': decodedRange['end'],
        'color': 'yellow',
        'elementType': 'question',
        'optionIndex': null,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else if (phrase.trim().isNotEmpty) {
      currentItems.add({
        'id': _newHighlightId(),
        'selectedText': phrase.trim(),
        'color': 'yellow',
        'elementType': 'question',
        'optionIndex': null,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _highlights[key] = _buildHighlightRecord(questionId, currentItems);
    notifyListeners();

    try {
      await _supabase.client.from('user_progress').upsert({
        'user_id': user.id,
        'highlights': _highlights,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      print('Error saving highlights: $e');
    }
  }

  // Remove one highlighted range/text from a question.
  Future<void> removeHighlight(int questionId, String phrase) async {
    final user = _supabase.currentUser;
    if (user == null) return;

    final key = questionId.toString();
    final currentItems = _parseHighlightItems(_highlights[key]);
    if (currentItems.isEmpty) {
      debugPrint(
          '[QuestionHighlight] provider remove empty questionId=$questionId phrase=$phrase');
      return;
    }

    final decodedRange = _decodeHighlightRangeToken(phrase);
    debugPrint(
      '[QuestionHighlight] provider remove start questionId=$questionId '
      'phrase=$phrase decoded=$decodedRange before=${currentItems.length}',
    );
    currentItems.removeWhere((item) {
      if (decodedRange != null) {
        return item['start'] == decodedRange['start'] &&
            item['end'] == decodedRange['end'];
      }
      return item['id']?.toString() == phrase ||
          (item['selectedText'] ?? item['text'])?.toString().toLowerCase() ==
              phrase.toLowerCase();
    });

    if (currentItems.isEmpty) {
      _highlights.remove(key);
    } else {
      _highlights[key] = _buildHighlightRecord(questionId, currentItems);
    }
    debugPrint(
      '[QuestionHighlight] provider remove local-saved questionId=$questionId '
      'after=${currentItems.length}',
    );
    notifyListeners();

    try {
      await _supabase.client.from('user_progress').upsert({
        'user_id': user.id,
        'highlights': _highlights,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      print('Error removing highlight: $e');
    }
  }

  // Clear highlights for a question
  Future<void> clearHighlights(int questionId) async {
    final user = _supabase.currentUser;
    if (user == null) return;

    final String key = questionId.toString();
    if (!_highlights.containsKey(key)) return;

    _highlights.remove(key);
    notifyListeners();

    try {
      await _supabase.client.from('user_progress').upsert({
        'user_id': user.id,
        'highlights': _highlights,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      print('Error clearing highlights: $e');
    }
  }

  // Get highlights for a question. v2 ranges are returned as range tokens for
  // the existing question viewer; legacy text highlights still render by text.
  List<String> getQuestionHighlights(
    int questionId, {
    String elementType = 'question',
    int? optionIndex,
  }) {
    final String key = questionId.toString();
    if (!_highlights.containsKey(key)) return [];
    final items = _parseHighlightItems(_highlights[key]).where((item) {
      final itemElementType = item['elementType']?.toString() ?? 'question';
      if (itemElementType != elementType) return false;
      if (elementType == 'option') {
        final rawOptionIndex = item['optionIndex'];
        final itemOptionIndex = rawOptionIndex is num
            ? rawOptionIndex.toInt()
            : int.tryParse(rawOptionIndex?.toString() ?? '');
        return itemOptionIndex == optionIndex;
      }
      return true;
    });

    return items
        .map((item) {
          final start = (item['start'] as num?)?.toInt();
          final end = (item['end'] as num?)?.toInt();
          if (start != null && end != null && start >= 0 && end > start) {
            return _encodeHighlightRangeToken(start, end);
          }
          return (item['selectedText'] ?? item['text'])?.toString() ?? '';
        })
        .where((value) => value.trim().isNotEmpty)
        .toList();
  }

  // Get unsolved questions for a subject
  int getUnsolvedQuestionsCount(String subjectName) {
    final subject = _subjects.firstWhere(
      (s) => s.name == subjectName,
      orElse: () =>
          Subject(id: 0, name: subjectName, description: '', totalQuestions: 0),
    );
    final totalQuestions = subject.totalQuestions;
    final completedCount =
        _userAnswers.values.where((a) => a['subject'] == subjectName).length;
    return (totalQuestions - completedCount).clamp(0, totalQuestions);
  }

  // Create study plan
  Future<void> createStudyPlan(String subjectName, int totalDays) async {
    final unsolved = getUnsolvedQuestionsCount(subjectName);
    if (unsolved <= 0) return;

    final plan = {
      'subjectId': subjectName,
      'subjectName': subjectName,
      'totalDays': totalDays,
      'questionsPerDay': (unsolved / totalDays).ceil(),
      'totalQuestions': unsolved,
      'startDate': DateTime.now().toIso8601String(),
      'currentDay': 1,
      'completedToday': 0,
      'lastResetDate': DateTime.now().toIso8601String(),
      'remainingQuestions': unsolved,
      'dailyProgress': <String, dynamic>{},
      'isActive': true,
      'isRealPlan': true,
    };

    _studyPlan = plan;
    notifyListeners();

    if (_supabase.isAuthenticated) {
      await _supabase.saveStudyPlan(plan);
    }
  }

  // Check and update daily study plan (reset target if day passed)
  Future<void> checkAndUpdateDailyPlan() async {
    if (_studyPlan == null || _studyPlan!['isActive'] != true) return;

    final now = DateTime.now();
    final lastReset = DateTime.parse(
        _studyPlan!['lastResetDate'] ?? _studyPlan!['startDate']);

    if (now.difference(lastReset).inHours >= 24) {
      final subjectName = _studyPlan!['subjectName'];
      final totalComp =
          _userAnswers.values.where((a) => a['subject'] == subjectName).length;
      final totalQuestions = _studyPlan!['totalQuestions'] ?? 0;

      final remaining = (totalQuestions - totalComp).clamp(0, totalQuestions);
      _studyPlan!['remainingQuestions'] = remaining;
      _studyPlan!['lastResetDate'] = now.toIso8601String();

      if (remaining == 0) {
        _studyPlan!['isActive'] = false;
      } else {
        final startDate = DateTime.parse(_studyPlan!['startDate']);
        final dPassed = now.difference(startDate).inDays;
        final totalDays = _studyPlan!['totalDays'] ?? 1;
        final remDays = (totalDays - dPassed).clamp(1, totalDays);

        _studyPlan!['questionsPerDay'] = (remaining / remDays).ceil();
        _studyPlan!['currentDay'] = dPassed + 1;
      }

      notifyListeners();
      if (_supabase.isAuthenticated) {
        await _supabase.saveStudyPlan(_studyPlan);
      }
    }
  }

  // Get completed questions count for today
  int getCompletedTodayQuestions() {
    if (_studyPlan == null || _studyPlan!['isActive'] != true) return 0;

    final subjectName = _studyPlan!['subjectName'];
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    final count = _userAnswers.values.where((a) {
      if (a['subject'] != subjectName) return false;
      final answeredAt = a['answered_at'];
      if (answeredAt == null) return false;
      return answeredAt.toString().startsWith(todayStr);
    }).length;

    _studyPlan!['completedToday'] = count;
    return count;
  }

  // Delete study plan
  Future<void> deleteStudyPlan() async {
    _studyPlan = null;
    notifyListeners();
    if (_supabase.isAuthenticated) {
      await _supabase.saveStudyPlan(null);
    }
  }

  Future<void> _updateRecentTopic(String subjectName, String topicName) async {
    final topicQs = _questions.where((q) => q.topic == topicName).toList();
    if (topicQs.isEmpty) return;

    final int total = topicQs.length;
    final int solved = topicQs.where((q) => q.isSolved).length;

    _recentTopics.removeWhere(
        (item) => item['topic'] == topicName && item['subject'] == subjectName);

    if (solved < total) {
      _recentTopics.insert(0, {
        'topic': topicName,
        'subject': subjectName,
        'total': total,
        'solved': solved,
        'last_solved_at': DateTime.now().toIso8601String(),
      });
    }

    if (_recentTopics.length > 10) {
      _recentTopics = _recentTopics.sublist(0, 10);
    }

    await _cache.setCache(
        'recent_topics', _recentTopics, const Duration(days: 36500));
    notifyListeners();
  }

  Future<void> calculateAllClinicalProgress() async {
    if (!_supabase.isAuthenticated) return;
    try {
      final user = _supabase.currentUser;
      if (user == null) return;

      // 1. Fetch clinical subjects if not already fetched
      if (_clinicalSubjects.isEmpty) {
        final List<dynamic> clinicalData = await _supabase.client
            .from('clinical_subjects')
            .select('*')
            .order('name', ascending: true)
            .timeout(const Duration(seconds: 3));
        _clinicalSubjects = clinicalData
            .map((s) => Subject(
                  id: s['id'] as int,
                  name: s['name'] as String,
                  description: s['description'] as String? ?? '',
                  totalQuestions: 0,
                ))
            .toList();
      }

      // 2. Fetch all clinical contents & user progress in parallel
      final results = await Future.wait([
        _supabase.client
            .from('slide_stations')
            .select('id, subject_id, slides_count'),
        _supabase.client.from('voice_notes').select('id, subject_id'),
        _supabase.client.from('videos').select('id, subject_id'),
        _supabase.client
            .from('user_voice_progress')
            .select('voice_note_id, is_completed, playback_progress')
            .eq('user_id', user.id),
        _supabase.client
            .from('user_video_progress')
            .select('video_id, is_completed, playback_progress')
            .eq('user_id', user.id),
        _supabase.client
            .from('user_station_progress')
            .select('station_id, current_slide_index, evaluation')
            .eq('user_id', user.id),
      ]).timeout(const Duration(seconds: 3));

      final stationsRes = results[0] as List;
      final voicesRes = results[1] as List;
      final videosRes = results[2] as List;
      final userVoiceRes = results[3] as List;
      final userVideoRes = results[4] as List;
      final userStationRes = results[5] as List;

      final voiceProgMap = {
        for (var p in userVoiceRes) p['voice_note_id'] as String: p
      };
      final videoProgMap = {
        for (var p in userVideoRes) p['video_id'] as String: p
      };
      final stationProgMap = {
        for (var p in userStationRes) p['station_id'] as String: p
      };

      _clinicalSubjectProgress.clear();

      for (var subj in _clinicalSubjects) {
        final subjectId = subj.id;

        final subjStations = (stationsRes)
            .where((s) => s['subject_id'] == subjectId)
            .toList();
        final subjVoices = (voicesRes)
            .where((v) => v['subject_id'] == subjectId)
            .toList();
        final subjVideos = (videosRes)
            .where((v) => v['subject_id'] == subjectId)
            .toList();

        double totalCompleted = 0.0;
        final double totalItems =
            (subjStations.length + subjVoices.length + subjVideos.length)
                .toDouble();

        if (totalItems > 0) {
          // Stations
          for (var s in subjStations) {
            final String id = s['id'] as String;
            final prog = stationProgMap[id];
            if (prog != null) {
              if (prog['evaluation'] != null) {
                totalCompleted += 1.0;
              } else {
                final current = prog['current_slide_index'] as int? ?? 1;
                final total = s['slides_count'] as int? ?? 10;
                totalCompleted +=
                    total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
              }
            }
          }

          // Voices
          for (var v in subjVoices) {
            final String id = v['id'] as String;
            final prog = voiceProgMap[id];
            if (prog != null) {
              if (prog['is_completed'] == true) {
                totalCompleted += 1.0;
              } else {
                final playback = prog['playback_progress'] ?? 0.0;
                final double val = playback is int
                    ? playback.toDouble()
                    : (playback as double? ?? 0.0);
                totalCompleted += val.clamp(0.0, 1.0);
              }
            }
          }

          // Videos
          for (var v in subjVideos) {
            final String id = v['id'] as String;
            final prog = videoProgMap[id];
            if (prog != null) {
              if (prog['is_completed'] == true) {
                totalCompleted += 1.0;
              } else {
                final playback = prog['playback_progress'] ?? 0.0;
                final double val = playback is int
                    ? playback.toDouble()
                    : (playback as double? ?? 0.0);
                totalCompleted += val.clamp(0.0, 1.0);
              }
            }
          }

          _clinicalSubjectProgress[subj.name.toLowerCase().trim()] =
              totalCompleted / totalItems;
        } else {
          _clinicalSubjectProgress[subj.name.toLowerCase().trim()] = 0.0;
        }
      }
      await _cache.setCache('clinical_subject_progress_cache', _clinicalSubjectProgress, const Duration(days: 30));
      notifyListeners();
    } catch (e) {
      print('Error calculating clinical progress: $e');
    }
  }

  Future<void> editVoiceNote(String voiceDbId, String newTitle,
      String newCategory, String subject) async {
    try {
      await _supabase.client.from('voice_notes').update({
        'title': newTitle,
        'category': newCategory,
      }).eq('id', voiceDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error editing voice note: $e');
    }
  }

  Future<void> deleteVoiceNote(String voiceDbId, String subject) async {
    try {
      await _supabase.client.from('voice_notes').delete().eq('id', voiceDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error deleting voice note: $e');
    }
  }

  Future<void> updateVoiceOrderIndex(
      String voiceDbId, int newIndex, String subject) async {
    try {
      await _supabase.client.from('voice_notes').update({
        'order_index': newIndex,
      }).eq('id', voiceDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error updating voice note order index: $e');
    }
  }

  Future<void> deleteClinicalVideo(String videoDbId, String subject) async {
    try {
      await _supabase.client.from('videos').delete().eq('id', videoDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error deleting video: $e');
    }
  }

  Future<void> updateClinicalVideo(
      String videoDbId, String subject, String title, String duration,
      {String? pdfUrl, String? videoUrl}) async {
    try {
      String? finalPdfUrl = pdfUrl;
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        if (!pdfUrl.startsWith('http://') && !pdfUrl.startsWith('https://')) {
          final uploaded = await _supabase.uploadFile('question-images', pdfUrl);
          if (uploaded != null) {
            finalPdfUrl = uploaded;
          } else {
            throw Exception('Failed to upload PDF file');
          }
        }
      }

      await _supabase.client.from('videos').update({
        'title': title,
        'duration_text': duration,
        'pdf_url': finalPdfUrl,
        'video_url': videoUrl,
      }).eq('id', videoDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error updating video: $e');
      rethrow;
    }
  }

  Future<void> updateVideoOrderIndex(
      String videoDbId, int newIndex, String subject) async {
    try {
      await _supabase.client.from('videos').update({
        'order_index': newIndex,
      }).eq('id', videoDbId);
      await invalidateClinicalCache(subject);
      await loadClinicalData(subject);
    } catch (e) {
      print('Error updating video order index: $e');
    }
  }

  Future<void> addClinicalSubject(
      String name, String description, String iconName,
      {String? stage, String? university}) async {
    try {
      await _supabase.client.from('clinical_subjects').insert({
        'name': name,
        'description': '$iconName - $description',
        'stage': stage,
        'university': university,
      });
      await initializeData();
    } catch (e) {
      print('Error adding dynamic subject: $e');
    }
  }

  Future<void> editClinicalSubject(
      int subjectId, String name, String iconName, String description,
      {String? stage, String? university}) async {
    try {
      await _supabase.client.from('clinical_subjects').update({
        'name': name,
        'description': '$iconName - $description',
        'stage': stage,
        'university': university,
      }).eq('id', subjectId);
      await initializeData();
    } catch (e) {
      print('Error editing clinical subject: $e');
    }
  }
}
