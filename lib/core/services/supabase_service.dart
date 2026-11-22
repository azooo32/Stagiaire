import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_keys.dart';
import '../constants/app_config.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient client = Supabase.instance.client;
  String? lastError;
  String _safeStorageFileName(String originalFileName) {
    final rawName = originalFileName.split('/').last.split('\\').last;
    final dotIndex = rawName.lastIndexOf('.');
    final rawExtension = dotIndex >= 0 ? rawName.substring(dotIndex + 1) : '';
    final extension =
        rawExtension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
    final safeExtension = extension.isEmpty ? 'bin' : extension;
    return '${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
  }

  // Returns a cleaned subject name for exact IN-filter matching (no LIKE escaping)
  String _cleanSubjectName(String name) => name.trim();

  // Returns the set of exact subject name strings to match against the 'subject' column
  List<String> _subjectMatchPatterns(String subjectName) {
    final trimmed = subjectName.trim();
    final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    // Always include exactly what the caller passed
    final patterns = <String>{_cleanSubjectName(trimmed)};

    if (normalized.contains('surg')) {
      patterns.add('Surgery');
      patterns.add('surgery');
    }
    if (normalized.contains('pediatr') || normalized.contains('paediatr')) {
      patterns.add('Paediatric');
      patterns.add('Pediatric');
      patterns.add('Paediatrics');
      patterns.add('Pediatrics');
    }
    if (normalized.contains('internal') || normalized.contains('medici')) {
      patterns.add('internal medicine');
      patterns.add('Internal Medicine');
    }
    if (normalized.contains('obstetric')) {
      patterns.add('Obstetric');
      patterns.add('Obstetrics');
    }
    if (normalized.contains('gynec') || normalized.contains('gynaec')) {
      patterns.add('Gynecology');
      patterns.add('Gynaecology');
    }

    return patterns.toList();
  }

  // Initialize Supabase (Call this in main.dart)
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: ApiKeys.supabaseUrl,
      anonKey: ApiKeys.supabaseAnonKey,
    );
  }

  // Auth Methods
  User? get currentUser => client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Future<void> signOut() async {
    await client.auth.signOut();
    // Forget the chosen Google account so the next Google login shows the
    // account picker (students sharing a phone / switching accounts).
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  Future<void> deleteAccount() async {
    await client.rpc('delete_user_account');
  }

  // Fetch user details from the 'users' table
  Future<Map<String, dynamic>?> getUserDetails() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final response = await client
          .from('users')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error getting user details: $e');
      return null;
    }
  }

  /// Update the user's stage in the 'users' table
  Future<bool> updateStage(String newStage) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      await client.from('users').update({
        'stage': newStage,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      try {
        await client.auth.updateUser(
          UserAttributes(data: {'stage': newStage}),
        );
      } catch (authErr) {
        print('Warning updating auth metadata: $authErr');
      }
      return true;
    } catch (e) {
      print('Error updating stage: $e');
      return false;
    }
  }

  /// Update any user's stage in the 'users' table (for admin/owner)
  Future<bool> updateUserStage(String userId, String newStage) async {
    try {
      await client.from('users').update({
        'stage': newStage,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      return true;
    } catch (e) {
      print('Error updating user stage: $e');
      return false;
    }
  }

  /// Update the user's university in the 'users' table.
  /// Only the owner sees this option in the app; the DB trigger rejects
  /// anyone else, which lands in the catch below (returns false).
  Future<bool> updateUniversity(String newUniversity) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      await client.from('users').update({
        'university': newUniversity,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      try {
        await client.auth.updateUser(
          UserAttributes(data: {'university': newUniversity}),
        );
      } catch (authErr) {
        print('Warning updating auth metadata: $authErr');
      }
      return true;
    } catch (e) {
      print('Error updating university: $e');
      return false;
    }
  }

  // Sign Up with email, password and user metadata
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String university,
    required String stage,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': name,
        'university': university,
        'stage': stage,
      },
    );
    // Note: createUserRecord is intentionally NOT called here.
    // When email confirmation is enabled, the user has no active session
    // at this point, so any DB writes would fail silently due to RLS.
    // createUserRecord is called in verify_screen.dart after OTP confirmation.
    return response;
  }

  // Create User Record in 'users' and 'user_progress' tables (matches JS createUserRecord)
  Future<void> createUserRecord({
    required String userId,
    required String email,
    required String name,
    required String university,
    required String stage,
  }) async {
    try {
      // 1. Create/Update user details
      await client.from('users').upsert({
        'id': userId,
        'email': email,
        'name': name,
        'university': university,
        'stage': stage,
        'role': 'student',
        'status': 'inactive',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Initialize progress stats row
      await client.from('user_progress').upsert({
        'user_id': userId,
        'answers': {},
        'favorites': [],
        'total_questions_answered': 0,
        'total_correct_answers': 0,
        'total_incorrect_answers': 0,
        'last_activity': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error initializing user records in DB: $e');
    }
  }

  // Sign In with email and password
  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  bool _googleInitialized = false;

  /// Sign In with Google (Android). Returns null when the user closes the
  /// Google account picker. If an account with the same verified email already
  /// exists (old email/password account), Supabase links Google to THAT
  /// account, so the student keeps progress and subscription.
  Future<AuthResponse?> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await googleSignIn.initialize(
        // iOS needs its own OAuth client; Android uses the SHA-1 registration.
        clientId: Platform.isIOS ? GoogleAuthConfig.iosClientId : null,
        serverClientId: GoogleAuthConfig.webClientId,
      );
      _googleInitialized = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Google did not return an ID token');
    }

    // Access token is optional; fetch it only if available without extra UI.
    String? accessToken;
    try {
      final authorization = await account.authorizationClient
          .authorizationForScopes(const ['email', 'profile']);
      accessToken = authorization?.accessToken;
    } catch (_) {}

    return client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  /// Sign In with Apple (iOS, native sheet). Returns null when the user
  /// closes the Apple sheet. Same-email accounts link like Google; if the
  /// student hides the email (privaterelay.appleid.com) it is a new account.
  Future<AuthResponse?> signInWithApple() async {
    // Supabase checks the token against the raw nonce; Apple gets its hash.
    final rawNonce = client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Apple did not return an ID token');
    }

    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple sends the name ONLY on the very first sign-in and it is not in
    // the token → keep it in metadata so the profile step can prefill it.
    final fullName = [credential.givenName, credential.familyName]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .join(' ');
    if (fullName.isNotEmpty) {
      try {
        await client.auth
            .updateUser(UserAttributes(data: {'full_name': fullName}));
      } catch (e) {
        print('Warning saving Apple name: $e');
      }
    }
    return response;
  }

  /// Name, stage and university are mandatory before the app opens.
  /// true  = the 'users' row has all three.
  /// false = no row, or one of them is empty (new Google accounts — a DB
  ///         trigger may create the row without stage/university — and old
  ///         accounts that skipped the step in earlier versions).
  /// null  = could not check (offline / timeout) → caller lets the user in
  ///         and the check runs again on the next launch.
  Future<bool?> isProfileComplete() async {
    final user = currentUser;
    if (user == null) return false;
    try {
      final row = await client
          .from('users')
          .select('name, stage, university')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return false;
      bool filled(dynamic v) => v != null && v.toString().trim().isNotEmpty;
      return filled(row['name']) &&
          filled(row['stage']) &&
          filled(row['university']);
    } catch (e) {
      print('Error checking profile completeness: $e');
      return null;
    }
  }

  /// Saves the mandatory profile fields for the signed-in user.
  /// Existing row → updates ONLY name/stage, and university ONLY if it is
  /// still empty — a student can fill a missing university but never change
  /// one (changing it is owner-only). Role, status, email, progress and
  /// subscription stay untouched.
  /// Missing row → creates it like the email sign-up does.
  /// Throws on failure so the screen can show an error.
  Future<void> saveRequiredProfile({
    required String name,
    required String stage,
    required String university,
  }) async {
    final user = currentUser;
    if (user == null) throw const AuthException('Not signed in');
    final now = DateTime.now().toIso8601String();

    final existing = await client
        .from('users')
        .select('id, university')
        .eq('id', user.id)
        .maybeSingle();
    final savedUniversity = existing?['university']?.toString().trim() ?? '';
    if (existing == null) {
      await client.from('users').insert({
        'id': user.id,
        'email': user.email ?? '',
        'name': name,
        'university': university,
        'stage': stage,
        'role': 'student',
        'status': 'inactive',
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await client.from('users').update({
        'name': name,
        'stage': stage,
        if (savedUniversity.isEmpty) 'university': university,
        'updated_at': now,
      }).eq('id', user.id);
    }
    final finalUniversity =
        savedUniversity.isNotEmpty ? savedUniversity : university;

    // Progress row: create only if missing — never reset existing answers.
    try {
      final progress = await client
          .from('user_progress')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (progress == null) {
        await client.from('user_progress').insert({
          'user_id': user.id,
          'answers': {},
          'favorites': [],
          'total_questions_answered': 0,
          'total_correct_answers': 0,
          'total_incorrect_answers': 0,
          'last_activity': now,
        });
      }
    } catch (e) {
      print('Warning initializing user_progress: $e');
    }

    // Same metadata keys as the email sign-up (used as fallbacks in the app).
    try {
      await client.auth.updateUser(UserAttributes(data: {
        'full_name': name,
        'stage': stage,
        'university': finalUniversity,
      }));
    } catch (e) {
      print('Warning updating auth metadata: $e');
    }
  }

  // Verify OTP confirmation code
  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
    OtpType type = OtpType.signup,
  }) async {
    return await client.auth.verifyOTP(
      type: type,
      email: email,
      token: token,
    );
  }

  // Send password reset email
  Future<void> resetPasswordForEmail(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  // Update password after password reset recovery
  Future<UserResponse> updatePassword(String newPassword) async {
    return await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // Fetch all subjects. Falls back to distinct question subjects because the subjects table may be empty.
  Future<List<Map<String, dynamic>>> getSubjects() async {
    final response = await client
        .from('subjects')
        .select('id, name, description, total_questions, stage, university, stage_question_counts')
        .order('name');

    final subjects = List<Map<String, dynamic>>.from(response);
    if (subjects.isNotEmpty) return subjects;

    final questionsResponse = await client
        .from('questions')
        .select('subject')
        .not('subject', 'is', null);
    final subjectCounts = <String, int>{};
    for (final row in List<Map<String, dynamic>>.from(questionsResponse)) {
      final subject = row['subject']?.toString().trim();
      if (subject == null || subject.isEmpty) continue;
      subjectCounts[subject] = (subjectCounts[subject] ?? 0) + 1;
    }

    var id = 1;
    final List<Map<String, dynamic>> dynamicSubjects = subjectCounts.entries
        .map<Map<String, dynamic>>((entry) => {
              'id': id++,
              'name': entry.key,
              'description': '',
              'total_questions': entry.value,
            })
        .toList();
    dynamicSubjects.sort((a, b) => a['name']
        .toString()
        .toLowerCase()
        .compareTo(b['name'].toString().toLowerCase()));
    return dynamicSubjects;
  }

  // Fetch questions for a specific subject with automatic pagination (bypasses 1000-row Supabase limit)
  Future<List<Map<String, dynamic>>> getQuestions(String subjectName) async {
    final patterns = _subjectMatchPatterns(subjectName);
    final allQuestions = <Map<String, dynamic>>[];
    const pageSize = 1000;
    int from = 0;

    while (true) {
      final response = await client
          .from('questions')
          .select('*')
          .inFilter('subject', patterns)
          .eq('is_deleted', false)
          .order('id')
          .range(from, from + pageSize - 1);
      final list = List<Map<String, dynamic>>.from(response);
      allQuestions.addAll(list);
      if (list.length < pageSize) break;
      from += pageSize;
    }
    return allQuestions;
  }

  // Fetch all titles/topics
  Future<List<Map<String, dynamic>>> getTitles() async {
    final response = await client.from('titles').select('*, subjects(name)');
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch titles for a specific subject with order
  Future<List<Map<String, dynamic>>> getTitlesForSubject(
      String subjectName) async {
    try {
      final response = await client
          .from('titles')
          .select('*, subjects!inner(name)')
          .inFilter('subjects.name', _subjectMatchPatterns(subjectName))
          .order('title_order', ascending: true, nullsFirst: false)
          .order('subtitle_order', ascending: true, nullsFirst: false)
          .timeout(const Duration(seconds: 3));
      final list = List<Map<String, dynamic>>.from(response);
      if (list.isNotEmpty) return list;
    } catch (e) {
      print('Error fetching titles via join for subject $subjectName: $e');
    }

    // Direct fallback by subject_id
    try {
      final subjectId = await getSubjectIdByName(subjectName);
      if (subjectId != null) {
        final response = await client
            .from('titles')
            .select('*')
            .eq('subject_id', subjectId)
            .order('title_order', ascending: true, nullsFirst: false)
            .order('subtitle_order', ascending: true, nullsFirst: false)
            .timeout(const Duration(seconds: 3));
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      print('Error fetching titles via subject_id for $subjectName: $e');
    }
    return [];
  }

  // Get subject ID by subject name
  Future<int?> getSubjectIdByName(String subjectName) async {
    try {
      final response = await client
          .from('subjects')
          .select('id')
          .inFilter('name', _subjectMatchPatterns(subjectName))
          .limit(1)
          .maybeSingle();
      if (response != null && response['id'] != null) {
        return response['id'] as int;
      }
    } catch (e) {
      print('Error getting subject id for $subjectName: $e');
    }
    return null;
  }

  // Update or insert title and subtitle order
  Future<void> updateTitlesOrder({
    required int subjectId,
    required List<Map<String, dynamic>> updates,
  }) async {
    for (final item in updates) {
      final String name = item['name'];
      final String? subTitle = item['sub_title'];
      final int titleOrder = item['title_order'];
      final int subtitleOrder = item['subtitle_order'];

      var query = client
          .from('titles')
          .update({
            'title_order': titleOrder,
            'subtitle_order': subtitleOrder,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('subject_id', subjectId)
          .eq('name', name);

      if (subTitle != null && subTitle.isNotEmpty) {
        query = query.eq('sub_title', subTitle);
      } else {
        query = query.filter('sub_title', 'is', null);
      }

      final res = await query.select();
      if ((res as List).isEmpty) {
        await client.from('titles').insert({
          'subject_id': subjectId,
          'name': name,
          'sub_title': subTitle,
          'title_order': titleOrder,
          'subtitle_order': subtitleOrder,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  // Get user progress row (answers, favorites, study_plan)
  Future<Map<String, dynamic>?> getUserProgress() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await client
        .from('user_progress')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();
    return response;
  }

  // Get user leaderboard stats
  Future<Map<String, dynamic>?> getUserLeaderboardStats() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await client
          .from('leaderboard')
          .select('correct_answers, total_answers, accuracy')
          .eq('user_id', user.id)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching user leaderboard stats: $e');
      return null;
    }
  }

  /// Average accuracy (0-100) of visible leaderboard users with at least 20 answers.
  /// Returns null when there is not enough data or the request fails.
  Future<double?> getCommunityAverageAccuracy() async {
    try {
      final rows = await client
          .from('leaderboard')
          .select('accuracy')
          .gte('total_answers', 20)
          .limit(5000);
      final values = (rows as List)
          .map((r) => double.tryParse('${r['accuracy']}'))
          .whereType<double>()
          .toList();
      if (values.length < 10) return null;
      return values.reduce((a, b) => a + b) / values.length;
    } catch (e) {
      print('Error fetching community average accuracy: $e');
      return null;
    }
  }

  // Get active study plan from study_plans table
  Future<Map<String, dynamic>?> getActiveStudyPlan() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await client
          .from('study_plans')
          .select('*')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;

      return {
        'id': response['id'],
        'subjectId': response['subject_name'],
        'subjectName': response['subject_name'],
        'totalDays': response['total_days'],
        'questionsPerDay': response['questions_per_day'],
        'totalQuestions': response['total_questions'],
        'startDate': response['start_date'],
        'currentDay': response['current_day'],
        'completedToday': response['completed_today'],
        'lastResetDate': response['last_reset_date'],
        'remainingQuestions': response['remaining_questions'],
        'isActive': response['is_active'],
        'isRealPlan': true,
      };
    } catch (e) {
      print('Error getting active study plan: $e');
      return null;
    }
  }

  // Save/Update study plan inside study_plans table
  Future<void> saveStudyPlan(Map<String, dynamic>? plan) async {
    final user = currentUser;
    if (user == null) return;

    try {
      if (plan == null) {
        // Deactivate active study plan
        await client
            .from('study_plans')
            .update({'is_active': false})
            .eq('user_id', user.id)
            .eq('is_active', true);
      } else {
        final dbPlan = {
          'user_id': user.id,
          'subject_name': plan['subjectName'],
          'total_days': plan['totalDays'],
          'questions_per_day': plan['questionsPerDay'],
          'total_questions': plan['totalQuestions'],
          'remaining_questions': plan['remainingQuestions'],
          'start_date': plan['startDate'],
          'current_day': plan['currentDay'],
          'completed_today': plan['completedToday'],
          'last_reset_date': plan['lastResetDate'],
          'is_active': plan['isActive'],
          'updated_at': DateTime.now().toIso8601String(),
        };

        if (plan['id'] != null) {
          dbPlan['id'] = plan['id'];
        }

        await client.from('study_plans').upsert(dbPlan);
      }
    } catch (e) {
      print('Error saving study plan: $e');
    }
  }

  // Save user answer (atomic RPC call)
  Future<void> saveUserAnswer({
    required int questionId,
    required int selectedAnswer,
    required bool isCorrect,
    required int timeTaken,
    required String subject,
  }) async {
    final user = currentUser;
    if (user == null) return;

    try {
      await client.rpc('update_user_answer', params: {
        'p_user_id': user.id,
        'p_question_id': questionId,
        'p_answer_data': {
          'answer': selectedAnswer, // 0-based index standard
          'is_correct': isCorrect,
          'time_taken': timeTaken,
          'answered_at': DateTime.now().toIso8601String(),
          'subject': subject,
        }
      });

      // Update leaderboard stats asynchronously
      client.rpc('update_leaderboard_stats', params: {
        'p_user_id': user.id,
        'is_correct': isCorrect,
      }).catchError((err) {
        print('Error updating leaderboard: $err');
      });
    } catch (e) {
      print('RPC update failed, falling back to legacy upsert: $e');
      await _saveUserAnswerLegacy(
        questionId: questionId,
        selectedAnswer: selectedAnswer,
        isCorrect: isCorrect,
        timeTaken: timeTaken,
        subject: subject,
      );
    }
  }

  // Legacy fallback for saving answers
  Future<void> _saveUserAnswerLegacy({
    required int questionId,
    required int selectedAnswer,
    required bool isCorrect,
    required int timeTaken,
    required String subject,
  }) async {
    final user = currentUser;
    if (user == null) return;

    final progress = await getUserProgress();
    final Map<String, dynamic> currentAnswers =
        Map<String, dynamic>.from(progress?['answers'] ?? {});

    currentAnswers[questionId.toString()] = {
      'answer': selectedAnswer, // 0-based index standard
      'is_correct': isCorrect,
      'time_taken': timeTaken,
      'answered_at': DateTime.now().toIso8601String(),
      'subject': subject,
    };

    await client.from('user_progress').upsert({
      'user_id': user.id,
      'answers': currentAnswers,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  // Update all answers in user_progress table
  Future<void> updateUserProgressAnswers(Map<String, dynamic> answers) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('user_progress').upsert({
        'user_id': user.id,
        'answers': answers,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      print('Error updating user progress answers in DB: $e');
    }
  }

  // Toggle favorite status of a question
  Future<List<int>> toggleFavorite(int questionId) async {
    final user = currentUser;
    if (user == null) return [];

    final progress = await getUserProgress();
    final List<int> currentFavorites =
        List<int>.from(progress?['favorites'] ?? []);

    if (currentFavorites.contains(questionId)) {
      currentFavorites.remove(questionId);
    } else {
      currentFavorites.add(questionId);
    }

    await client.from('user_progress').upsert({
      'user_id': user.id,
      'favorites': currentFavorites,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');

    return currentFavorites;
  }

  // Fetch question images with their position (matches JS getQuestionImages)
  Future<List<Map<String, dynamic>>> getQuestionImages(int questionId) async {
    try {
      final response = await client
          .from('question_image_relations')
          .select('position, is_question_image, show_right, question_images(*)')
          .eq('question_id', questionId)
          .order('position');
      final rows = List<Map<String, dynamic>>.from(response);
      if (rows.isNotEmpty) return rows;
    } catch (e) {
      print('Error fetching related question images: $e');
    }

    try {
      final response = await client
          .from('question_image_relations')
          .select('*')
          .eq('question_id', questionId)
          .order('position');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching raw question image relations: $e');
      return [];
    }
  }

  // Delete a question from the backend (for administrators) - uses soft-delete
  Future<bool> deleteQuestion(int questionId) async {
    try {
      await client.from('questions').update({
        'is_deleted': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', questionId);
      return true;
    } catch (e) {
      print('Error deleting question from Supabase: $e');
      return false;
    }
  }

  // Get current user role from 'users' table
  Future<String?> getUserRole() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final response = await client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return response?['role'] as String?;
    } catch (e) {
      print('Error getting user role: $e');
      return null;
    }
  }

  // Update a question in Supabase
  Future<bool> updateQuestion(
      int questionId, Map<String, dynamic> updateData) async {
    try {
      lastError = null;
      final payload = {
        ...updateData,
        'updated_at': DateTime.now().toIso8601String(),
      };
      print(
          '[SupabaseService.updateQuestion] id=$questionId fields=${payload.keys.join(', ')}');
      await client.from('questions').update(payload).eq('id', questionId);
      return true;
    } catch (e) {
      lastError = e.toString();
      print('Error updating question in Supabase: $e');
      return false;
    }
  }

  Future<bool> updateQuestionExplanationFormat(
    int questionId,
    String fieldName,
    List<Map<String, dynamic>> ranges,
  ) async {
    try {
      lastError = null;
      print(
          '[SupabaseService.updateQuestionExplanationFormat] id=$questionId field=$fieldName ranges=${ranges.length}');
      await client.rpc('update_question_explanation_format', params: {
        'p_question_id': questionId,
        'p_field_name': fieldName,
        'p_ranges': ranges,
      });
      return true;
    } catch (e) {
      lastError = e.toString();
      print('Error updating question explanation format: $e');
      return false;
    }
  }

  // Fetch questions of a subject that were updated at or after a specific timestamp.
  // Using `gte` (>=) instead of `gt` (>) to avoid missing questions that share the
  // exact same updated_at value as the cached maximum — a common scenario when many
  // questions are batch-imported with the same timestamp.
  Future<List<Map<String, dynamic>>> getQuestionsUpdatedAfter(
      String subjectName, String timestamp) async {
    try {
      final response = await client
          .from('questions')
          .select('*')
          .inFilter('subject', _subjectMatchPatterns(subjectName))
          .gte('updated_at', timestamp);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching updated questions: $e');
      return [];
    }
  }

  // Fetch only percentages/distribution for questions of a specific subject
  Future<List<Map<String, dynamic>>> getQuestionsDistribution(
      String subjectName) async {
    try {
      final response = await client
          .from('questions')
          .select('id, answers_distribution, total_answers')
          .inFilter('subject', _subjectMatchPatterns(subjectName));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching questions distribution: $e');
      return [];
    }
  }

  // Fetch lightweight audio metadata for questions of a specific subject.
  // This keeps cached question audio fresh even when external edits do not bump updated_at.
  Future<List<Map<String, dynamic>>> getQuestionsAudioMetadata(
      String subjectName) async {
    try {
      final response = await client
          .from('questions')
          .select(
              'id, audio_url, audio_duration_seconds, audio_highlights, updated_at')
          .inFilter('subject', _subjectMatchPatterns(subjectName));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching questions audio metadata: $e');
      return [];
    }
  }

  // Upload a local file to a Supabase storage bucket
  Future<String?> uploadFile(
    String bucketName,
    String localPath, {
    String? folder,
    void Function(double progress)? onProgress,
  }) async {
    try {
      lastError = null;
      final file = File(localPath);
      if (!await file.exists()) {
        lastError = 'File does not exist: $localPath';
        print(lastError);
        return null;
      }

      final rawFileName = file.path.split('/').last.split('\\').last;
      final fileName = _safeStorageFileName(rawFileName);
      final storagePath = folder != null && folder.trim().isNotEmpty
          ? '${folder.trim().replaceAll(RegExp(r'^/+|/+$'), '')}/$fileName'
          : fileName;

      onProgress?.call(0.1);

      await client.storage.from(bucketName).upload(
            storagePath,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      onProgress?.call(1.0);

      final String publicUrl =
          client.storage.from(bucketName).getPublicUrl(storagePath);
      print('File uploaded successfully. Public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      lastError = 'Error uploading file to Supabase storage: $e';
      print(lastError);
      return null;
    }
  }

  Future<String?> uploadFileBytes(
    String bucketName,
    Uint8List bytes,
    String originalFileName, {
    String? folder,
    String? contentType,
  }) async {
    try {
      lastError = null;
      final safeOriginalName =
          originalFileName.split('/').last.split('\\').last;
      final fileName = _safeStorageFileName(safeOriginalName);
      final storagePath = folder != null && folder.trim().isNotEmpty
          ? '${folder.trim().replaceAll(RegExp(r'^/+|/+$'), '')}/$fileName'
          : fileName;

      await client.storage.from(bucketName).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: contentType,
            ),
          );

      final String publicUrl =
          client.storage.from(bucketName).getPublicUrl(storagePath);
      print('File bytes uploaded successfully. Public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      lastError = 'Error uploading file bytes to Supabase storage: $e';
      print(lastError);
      return null;
    }
  }

  Future<bool> deleteStorageFile(
      String bucketName, String publicUrlOrPath) async {
    try {
      var storagePath = publicUrlOrPath.trim();
      final marker = '/$bucketName/';
      final markerIndex = storagePath.indexOf(marker);
      if (markerIndex >= 0) {
        storagePath = storagePath.substring(markerIndex + marker.length);
      }
      storagePath =
          storagePath.split('?').first.replaceFirst(RegExp(r'^/+'), '');
      if (storagePath.isEmpty) return false;
      await client.storage.from(bucketName).remove([storagePath]);
      return true;
    } catch (e) {
      print('Error deleting file from Supabase storage: $e');
      return false;
    }
  }

  // --- Admin Subscriptions Management methods ---

  // Search for users by name or email
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final response = await client
          .from('users')
          .select('id, name, email, university')
          .or('name.ilike.%$query%,email.ilike.%$query%')
          .limit(25);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Get active subscriptions for a specific user
  Future<List<Map<String, dynamic>>> getUserSubscriptions(String userId) async {
    try {
      final response = await client
          .from('user_subscriptions')
          .select(
              'id, user_id, subject_id, clinical_subject_id, status, expires_at')
          .eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting user subscriptions: $e');
      return [];
    }
  }

  // Add user subscription
  Future<bool> addUserSubscription({
    required String userId,
    int? subjectId,
    int? clinicalSubjectId,
    required String status,
    DateTime? expiresAt,
  }) async {
    try {
      await client.from('user_subscriptions').insert({
        'user_id': userId,
        'subject_id': subjectId,
        'clinical_subject_id': clinicalSubjectId,
        'status': status,
        'expires_at': expiresAt?.toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error adding user subscription: $e');
      return false;
    }
  }

  // Delete user subscription
  Future<bool> deleteUserSubscription(String subscriptionId) async {
    try {
      await client.from('user_subscriptions').delete().eq('id', subscriptionId);
      return true;
    } catch (e) {
      print('Error deleting user subscription: $e');
      return false;
    }
  }

  // Get all university access rules
  Future<List<Map<String, dynamic>>> getUniversityAccessList() async {
    try {
      final response = await client
          .from('university_access')
          .select('*')
          .order('university');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting university access list: $e');
      return [];
    }
  }

  // Add university access rule
  Future<bool> addUniversityAccess({
    required String university,
    int? subjectId,
    int? clinicalSubjectId,
    bool? allScientific,
    bool? allPractical,
    required String status,
    DateTime? expiresAt,
  }) async {
    try {
      await client.from('university_access').insert({
        'university': university,
        'subject_id': subjectId,
        'clinical_subject_id': clinicalSubjectId,
        'all_scientific': allScientific,
        'all_practical': allPractical,
        'status': status,
        'expires_at': expiresAt?.toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error adding university access rule: $e');
      return false;
    }
  }

  // Delete university access rule
  Future<bool> deleteUniversityAccess(String accessId) async {
    try {
      await client.from('university_access').delete().eq('id', accessId);
      return true;
    } catch (e) {
      print('Error deleting university access: $e');
      return false;
    }
  }

  // Enforce session limit of 2 devices
  Future<bool> registerOrUpdateSession(
      String userId, String deviceId, String deviceName) async {
    try {
      final existing = await client
          .from('user_sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .maybeSingle();

      if (existing != null) {
        // Update last active
        await client
            .from('user_sessions')
            .update({'last_active_at': DateTime.now().toIso8601String()}).eq(
                'id', existing['id']);
        return true;
      }

      // Count sessions
      final allSessions = await client
          .from('user_sessions')
          .select('id, last_active_at')
          .eq('user_id', userId)
          .order('last_active_at', ascending: true);

      final sessionList = List<Map<String, dynamic>>.from(allSessions);

      if (sessionList.length >= 2) {
        // Delete oldest sessions to keep under 2
        final toDeleteCount =
            sessionList.length - 1; // leave 1 slot so adding new makes it 2
        for (int i = 0; i < toDeleteCount; i++) {
          await client
              .from('user_sessions')
              .delete()
              .eq('id', sessionList[i]['id']);
        }
      }

      // Insert new session
      await client.from('user_sessions').insert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'last_active_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error in registerOrUpdateSession: $e');
      return true; // fail open
    }
  }

  // Check if current session is still active/valid
  Future<bool> isSessionValid(String userId, String deviceId) async {
    try {
      final existing = await client
          .from('user_sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .maybeSingle();
      if (existing == null) {
        return false; // Session was knocked out!
      }
      // Update last active
      await client
          .from('user_sessions')
          .update({'last_active_at': DateTime.now().toIso8601String()}).eq(
              'id', existing['id']);
      return true;
    } catch (e) {
      print('Error in isSessionValid: $e');
      return true; // fail open
    }
  }
}
