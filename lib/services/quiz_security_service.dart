// lib/services/quiz_security_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final _supa = Supabase.instance.client;
String? get _authUserId => _supa.auth.currentUser?.id;

class QuizSecurityService {
  /// Returns current strike count (0..3) for this quiz.
  static Future<int> getStrikes(String quizId) async {
    final uid = _authUserId;
    if (uid == null) return 0;
    final row =
        await _supa
            .from('quiz_security')
            .select('strikes, locked')
            .eq('supabase_id', uid)
            .eq('quiz_id', quizId)
            .maybeSingle();
    if (row == null) return 0;
    final strikes = (row['strikes'] ?? 0) as int;
    final locked = row['locked'] == true;
    return locked ? (strikes > 3 ? 3 : strikes) : strikes;
  }

  /// True if this quiz is locked for the current user.
  static Future<bool> isLocked(String quizId) async {
    final uid = _authUserId;
    if (uid == null) return false;
    final row =
        await _supa
            .from('quiz_security')
            .select('locked')
            .eq('supabase_id', uid)
            .eq('quiz_id', quizId)
            .maybeSingle();
    return row?['locked'] == true;
  }

  /// Record a strike; when [lock] is true, the quiz is locked.
  static Future<void> recordStrike({
    required String quizId,
    required int strikes,
    required bool lock,
    Map<String, dynamic>? meta,
  }) async {
    final uid = _authUserId;
    if (uid == null) return;

    await _supa.from('quiz_security').upsert({
      'supabase_id': uid,
      'quiz_id': quizId,
      'strikes': strikes,
      'locked': lock,
      'last_event': meta ?? {},
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'supabase_id,quiz_id');

    // OPTIONAL: if you have a quiz_progress table, keep it in sync
    if (lock) {
      try {
        await _supa
            .from('quiz_progress')
            .update({'status': 'locked_cheating'})
            .eq('supabase_id', uid)
            .eq('quiz_id', quizId);
      } catch (_) {
        /* ignore if table not present */
      }
    }
  }
}
