import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  late SharedPreferences _prefs;

  // Anti-tampering internal HMAC secret
  static final List<int> _hmacKey =
      utf8.encode('stagiaire_cache_anti_tamper_#9928@sec_key_v1');

  static String _generateSignature(String payload) {
    final hmac = Hmac(sha256, _hmacKey);
    return hmac.convert(utf8.encode(payload)).toString();
  }

  static bool _verifySignature(String payload, String expectedSig) {
    final sig = _generateSignature(payload);
    return sig == expectedSig;
  }

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

  // Generic Cache Methods with Timestamp and HMAC Integrity Signature
  Future<void> setCache(String key, dynamic data, Duration lifespan) async {
    final int expiry = DateTime.now().add(lifespan).millisecondsSinceEpoch;
    final String encodedData = jsonEncode(data);
    final String payloadToSign = '$key:$expiry:$encodedData';
    final String signature = _generateSignature(payloadToSign);

    final Map<String, dynamic> cacheWrapper = {
      'data': data,
      'expiry': expiry,
      'sig': signature,
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

      // Anti-tamper verification: if signature exists, verify it
      final String? sig = cacheWrapper['sig'];
      if (sig != null) {
        final String encodedData = jsonEncode(cacheWrapper['data']);
        final String payload = '$key:$expiry:$encodedData';
        if (!_verifySignature(payload, sig)) {
          // Data was tampered with! Discard immediately
          invalidateCache(key);
          return null;
        }
      }

      return cacheWrapper['data'];
    } catch (e) {
      return null;
    }
  }

  dynamic getCacheAllowExpired(String key) {
    final String? cachedStr = _prefs.getString(key);
    if (cachedStr == null) return null;

    try {
      final Map<String, dynamic> cacheWrapper = jsonDecode(cachedStr);

      // Anti-tamper verification
      final String? sig = cacheWrapper['sig'];
      final int expiry = cacheWrapper['expiry'] ?? 0;
      if (sig != null) {
        final String encodedData = jsonEncode(cacheWrapper['data']);
        final String payload = '$key:$expiry:$encodedData';
        if (!_verifySignature(payload, sig)) {
          invalidateCache(key);
          return null;
        }
      }

      return cacheWrapper['data'];
    } catch (e) {
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
