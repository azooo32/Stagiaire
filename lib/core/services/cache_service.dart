import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  late SharedPreferences _prefs;

  // Initialize Cache Service (Call this in main.dart)
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Persistent Installation ID for session limits
  String getInstallationId() {
    const String key = 'installation_id';
    String? id = _prefs.getString(key);
    if (id == null) {
      final random = Random();
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      id = 'dev-$timestamp-${random.nextInt(999999)}';
      _prefs.setString(key, id);
    }
    return id;
  }

  // Generic Cache Methods with Timestamp
  Future<void> setCache(String key, dynamic data, Duration lifespan) async {
    final Map<String, dynamic> cacheWrapper = {
      'data': data,
      'expiry': DateTime.now().add(lifespan).millisecondsSinceEpoch,
    };
    await _prefs.setString(key, jsonEncode(cacheWrapper));
  }

  dynamic getCache(String key) {
    final String? cachedStr = _prefs.getString(key);
    if (cachedStr == null) return null;

    try {
      final Map<String, dynamic> cacheWrapper = jsonDecode(cachedStr);
      final int expiry = cacheWrapper['expiry'] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch > expiry) {
        return null;
      }
      return cacheWrapper['data'];
    } catch (e) {
      print('Error parsing cache for $key: $e');
      return null;
    }
  }

  dynamic getCacheAllowExpired(String key) {
    final String? cachedStr = _prefs.getString(key);
    if (cachedStr == null) return null;

    try {
      final Map<String, dynamic> cacheWrapper = jsonDecode(cachedStr);
      return cacheWrapper['data'];
    } catch (e) {
      print('Error parsing stale cache for $key: $e');
      return null;
    }
  }

  Future<void> invalidateCache(String key) async {
    await _prefs.remove(key);
  }

  Iterable<String> get keys => _prefs.getKeys();

  // Pre-configured Cache Timeout durations
  static const Duration subjectsLifespan = Duration(days: 7);
  static const Duration questionsLifespan = Duration(days: 7);
  static const Duration titlesLifespan = Duration(days: 7);
  static const Duration leaderboardLifespan = Duration(hours: 2);

  // Pre-configured keys matching JS config
  static const String keySubjects = 'all_subjects';
  static const String keyTitles = 'all_titles';
  static const String keyLeaderboard = 'leaderboard';
  static const String keyUnlockedSubjects = 'unlocked_subjects';
  static const String keyUnlockedClinicalSubjects = 'unlocked_clinical_subjects';

  String getQuestionsKey(String subject) =>
      'questions_${subject.trim().toLowerCase()}';
}
