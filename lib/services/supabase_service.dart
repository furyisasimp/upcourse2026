// lib/services/supabase_service.dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:intl/intl.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// Track models.
import 'package:career_roadmap/models/exploration_models.dart' show Track;

final supa = Supabase.instance.client;

/// Minimal header QuizIntroScreen.
class QuizHeader {
  final String quizId;
  final String title;
  final String description;
  final DateTime? dueDateUtc;
  final int totalPoints;
  final int questionCount;

  const QuizHeader({
    required this.quizId,
    required this.title,
    required this.description,
    required this.dueDateUtc,
    required this.totalPoints,
    required this.questionCount,
  });

  factory QuizHeader.fromMeta(Map<String, dynamic> m) {
    return QuizHeader(
      quizId: (m['quiz_id'] ?? '').toString(),
      title: (m['quiz_title'] ?? '').toString(),
      description: (m['quiz_description'] ?? '').toString(),
      dueDateUtc: m['due_date'] is DateTime ? m['due_date'] as DateTime : null,
      totalPoints:
          (m['total_points'] is num) ? (m['total_points'] as num).toInt() : 0,
      questionCount:
          (m['question_count'] is num)
              ? (m['question_count'] as num).toInt()
              : 0,
    );
  }
}

class DisabledAccountException implements Exception {
  final String message;
  const DisabledAccountException([
    this.message = 'Your account has been disabled.',
  ]);
  @override
  String toString() => message;
}

// ---- tiny debug helper (optional) ----
void _d(String msg) {
  // ignore: avoid_print
  print('[SupabaseService] $msg');
}

/// Table of Specifications model for fixed-count quizzes (legacy/simple).
/// Matches files like: quizzes/<QUIZ_ID>_tos.json with keys { easy, medium, hard, total }
class QuizSpec {
  final int easy, medium, hard, total;

  const QuizSpec({
    required this.easy,
    required this.medium,
    required this.hard,
    required this.total,
  });

  factory QuizSpec.fromJson(Map<String, dynamic> j) => QuizSpec(
    easy: (j['easy'] ?? 0) as int,
    medium: (j['medium'] ?? 0) as int,
    hard: (j['hard'] ?? 0) as int,
    total:
        (j['total'] ??
                ((j['easy'] ?? 0) + (j['medium'] ?? 0) + (j['hard'] ?? 0)))
            as int,
  );
}

// ==== START: Exploration models (Strand / Pathway) ====
// Kept local so this file is self-contained for Exploration features.

class SourceLink {
  final String name;
  final String url;
  const SourceLink({required this.name, required this.url});

  factory SourceLink.fromJson(Map<String, dynamic> j) => SourceLink(
    name: (j['name'] ?? '').toString(),
    url: (j['url'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

// ---- Study Guide listing (resources bucket) ----
enum GuideType { pdf, image, ppt }

class GuideItem {
  final String name; // e.g., "chapter_1.pdf"
  final String path; // e.g., "pdf/chapter_1.pdf"
  final int? size; // bytes (if available)
  final DateTime? updated; // last modified if available
  final GuideType type;

  const GuideItem({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.updated,
  });
}

/// Strand row (from view `v_strands_shs` OR table `strands`)
class Strand {
  final String code; // e.g., STEM, ABM, GAS, TECHPRO
  final String name; // Display name
  final String summary; // One-paragraph summary (shown on card/sheet)
  final String badgeColor; // hex, e.g. #1976D2
  final String gradientStart; // hex
  final String gradientEnd; // hex
  final List<String> points; // bullet points for the card
  final List<String> sampleCurriculum;
  final List<String> entryRoles;
  final List<String> skills;
  final List<SourceLink> sources;

  const Strand({
    required this.code,
    required this.name,
    required this.summary,
    required this.badgeColor,
    required this.gradientStart,
    required this.gradientEnd,
    required this.points,
    required this.sampleCurriculum,
    required this.entryRoles,
    required this.skills,
    required this.sources,
  });

  factory Strand.fromRow(Map<String, dynamic> r) => Strand(
    code: (r['code'] ?? r['strand_id'] ?? '').toString(),
    name: (r['name'] ?? '').toString(),
    summary: (r['summary'] ?? '').toString(),
    badgeColor: (r['badge_color'] ?? '#1976D2').toString(),
    gradientStart: (r['gradient_start'] ?? '#B3E5FC').toString(),
    gradientEnd: (r['gradient_end'] ?? '#81D4FA').toString(),
    points:
        ((r['points'] as List?) ?? const []).map((e) => e.toString()).toList(),
    sampleCurriculum:
        ((r['sample_curriculum'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
    entryRoles:
        ((r['entry_roles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
    skills:
        ((r['skills'] as List?) ?? const []).map((e) => e.toString()).toList(),
    sources:
        ((r['sources'] as List?) ?? const [])
            .map((e) => SourceLink.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
  );
}

/// Pathway row from public.pathways
class Pathway {
  final String code; // e.g., BSCS, BSIT, BSA
  final String name; // display
  final String subtitle; // short line under title
  final List<String> outcomes; // what you'll learn
  final List<String> entryRoles; // sample roles
  final List<String> stackSuggestions; // chip list
  final List<SourceLink> sources;

  const Pathway({
    required this.code,
    required this.name,
    required this.subtitle,
    required this.outcomes,
    required this.entryRoles,
    required this.stackSuggestions,
    required this.sources,
  });

  factory Pathway.fromRow(Map<String, dynamic> r) => Pathway(
    code: (r['code'] ?? '').toString(),
    name: (r['name'] ?? '').toString(),
    subtitle: (r['subtitle'] ?? '').toString(),
    outcomes:
        ((r['outcomes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
    entryRoles:
        ((r['entry_roles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
    stackSuggestions:
        ((r['stack_suggestions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
    sources:
        ((r['sources'] as List?) ?? const [])
            .map((e) => SourceLink.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
  );
}

class PathwayMatch {
  final Pathway pathway;
  final String matchLabel;
  const PathwayMatch(this.pathway, this.matchLabel);
}
// ==== END: Exploration models ====

class SupabaseService {
  // ---------- AUTH ----------
  static String? get authUserId => supa.auth.currentUser?.id;
  static String? get authEmail => supa.auth.currentUser?.email;
  static bool get isLoggedIn => supa.auth.currentUser != null;

  static Future<AuthResponse> registerUser(
    String email,
    String password,
  ) async {
    final res = await supa.auth.signUp(email: email, password: password);

    if (res.user != null) {
      final uid = res.user!.id;

      await supa.from('users').upsert({
        'supabase_id': uid,
        'email': email,
        'created_at': DateTime.now().toIso8601String(),
        'is_disabled': false, // ← ensure a concrete default
      });

      await supa.from('skill_progress').upsert([
        {
          'user_id': uid,
          'module_id': 'programming_fundamentals',
          'lessons_completed': 0,
          'lessons_total': 20,
        },
        {
          'user_id': uid,
          'module_id': 'problem_solving',
          'lessons_completed': 0,
          'lessons_total': 20,
        },
        {
          'user_id': uid,
          'module_id': 'communication_skills',
          'lessons_completed': 0,
          'lessons_total': 20,
        },
      ], onConflict: 'user_id,module_id');

      await supa.from('quiz_progress').upsert([
        {
          'user_id': uid,
          'quiz_id': 'basic_programming_quiz',
          'status': 'unlocked',
          'score': null,
          'answers': null,
        },
        {
          'user_id': uid,
          'quiz_id': 'logic_algorithms',
          'status': 'locked',
          'score': null,
          'answers': null,
        },
        {
          'user_id': uid,
          'quiz_id': 'advanced_concepts',
          'status': 'locked',
          'score': null,
          'answers': null,
        },
      ], onConflict: 'user_id,quiz_id');
    }
    return res;
  }

  static Future<AuthResponse> loginUser(String email, String password) async {
    // Sign in first (Supabase needs a session before we can read the users table via RLS)
    final res = await supa.auth.signInWithPassword(
      email: email,
      password: password,
    );

    // If sign-in succeeded, immediately check the flag
    if (res.user != null) {
      final disabled = await _isCurrentUserDisabled();
      if (disabled) {
        // Kill the session so the app is locked out
        await supa.auth.signOut();
        // Surface a friendly, typed error the UI can catch and show
        throw const DisabledAccountException(
          'Your account has been disabled. Please contact your school or the system administrator.',
        );
      }
    }

    return res;
  }

  static Future<void> signOut() async {
    await supa.auth.signOut();
  }

  /// List a single folder from a bucket.
  static Future<List<FileObject>> listFolder({
    required String bucket,
    required String folder,
  }) async {
    return await supa.storage.from(bucket).list(path: folder);
  }

  /// Read images/, pdf/, ppt/ under the `resources` bucket and normalize them.
  static Future<List<GuideItem>> listStudyGuides() async {
    const bucket = 'resources';

    // visibility & extension filters
    bool _isVisible(FileObject f) =>
        !f.name.endsWith('/') && !f.name.startsWith('.');

    bool _hasExt(FileObject f, List<String> exts) {
      final n = f.name.toLowerCase();
      return exts.any((e) => n.endsWith(e));
    }

    // fetch + filter per folder
    final images =
        (await listFolder(bucket: bucket, folder: 'images'))
            .where(_isVisible)
            .where(
              (f) => _hasExt(f, [
                '.png',
                '.jpg',
                '.jpeg',
                '.gif',
                '.webp',
                '.bmp',
                '.tiff',
                '.svg',
              ]),
            )
            .toList();

    final pdfs =
        (await listFolder(
          bucket: bucket,
          folder: 'pdf',
        )).where(_isVisible).where((f) => _hasExt(f, ['.pdf'])).toList();

    final ppts =
        (await listFolder(bucket: bucket, folder: 'ppt'))
            .where(_isVisible)
            .where((f) => _hasExt(f, ['.ppt', '.pptx', '.key']))
            .toList();

    // coercers
    DateTime? _dt(dynamic v) =>
        v is DateTime ? v : (v is String ? DateTime.tryParse(v) : null);
    int? _size(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');

    GuideItem mapObj(FileObject o, GuideType t, String folder) => GuideItem(
      name: o.name,
      path: '$folder/${o.name}',
      type: t,
      size: _size(o.metadata?['size']),
      updated: _dt(o.updatedAt) ?? _dt(o.createdAt),
    );

    final out = <GuideItem>[
      ...images.map((o) => mapObj(o, GuideType.image, 'images')),
      ...pdfs.map((o) => mapObj(o, GuideType.pdf, 'pdf')),
      ...ppts.map((o) => mapObj(o, GuideType.ppt, 'ppt')),
    ];

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<bool> _isCurrentUserDisabled() async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return false; // not signed in yet
    try {
      final row =
          await supa
              .from('users')
              .select('is_disabled')
              .eq('supabase_id', uid)
              .maybeSingle();

      // Treat only TRUE as disabled. NULL or FALSE => allowed.
      return row != null && (row['is_disabled'] == true);
    } catch (_) {
      // Fail-open on read error; you can flip this to fail-closed if you prefer
      return false;
    }
  }

  /// Singleton client accessor
  static SupabaseClient get supa => Supabase.instance.client;

  // Build a QuizHeader from your existing getQuizIntroMeta() JSON loader.
  static Future<QuizHeader> fetchQuizHeader({
    required String quizId,
    String bucket = 'quizzes',
  }) async {
    final meta = await SupabaseService.getQuizIntroMeta(
      quizId: quizId,
      bucket: bucket,
    );
    return QuizHeader.fromMeta(meta);
  }

  // Load only the intro metadata from a quiz JSON in Storage.
  // Returns a normalized map usable by QuizHeader.fromMeta(...)
  static Future<Map<String, dynamic>> getQuizIntroMeta({
    required String quizId,
    String bucket = 'quizzes',
  }) async {
    // ---- local helpers (file-name probing) ----
    String _squash(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    String _hyphenize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    String _normalizeId(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final norm = _normalizeId(quizId);
    final hyph = _hyphenize(quizId);
    final normHyph = _hyphenize(norm);

    final candidates =
        <String>{
          '$norm.json',
          '$hyph.json',
          '$normHyph.json',
          'quiz_$norm.json',
          'quiz-$norm.json',
          'quiz_$hyph.json',
          '${norm}_quiz.json',
          '${hyph}_quiz.json',
          '${hyph}-quiz.json',
        }.toList();

    Uint8List? payload;

    // 1) try direct candidates
    for (final p in candidates) {
      try {
        payload = await supa.storage.from(bucket).download(p);
        break;
      } catch (_) {
        /* try next */
      }
    }

    // 2) fuzzy fallback
    if (payload == null) {
      final entries = await supa.storage.from(bucket).list(path: '');
      final jsonFiles =
          entries
              .where((e) => e.name.toLowerCase().endsWith('.json'))
              .map((e) => e.name)
              .toList();

      if (jsonFiles.isEmpty) {
        throw 'No .json quizzes in bucket root.';
      }

      final goal = _squash(quizId);
      String best = '';
      int bestScore = -1;

      for (final f in jsonFiles) {
        final s = _squash(f.replaceAll('.json', ''));
        int score = 0;
        final n = s.length < goal.length ? s.length : goal.length;
        for (int k = 1; k <= n; k++) {
          if (goal.contains(s.substring(0, k))) score = k;
        }
        if (s.contains('quiz') && goal.contains('quiz')) score += 3;
        if (score > bestScore) {
          bestScore = score;
          best = f;
        }
      }

      payload = await supa.storage.from(bucket).download(best);
    }

    // --- decode + compute meta
    final decoded = json.decode(utf8.decode(payload!));

    final metaOut = <String, dynamic>{
      'quiz_id': quizId,
      'quiz_title': null,
      'quiz_description': null,
      'due_date': null, // DateTime? (we parse if present)
      'total_points': 0, // int
      'question_count': 0, // int
    };

    if (decoded is Map) {
      final root = Map<String, dynamic>.from(decoded);

      metaOut['quiz_id'] = root['quiz_id'] ?? metaOut['quiz_id'];
      metaOut['quiz_title'] = root['quiz_title'];
      metaOut['quiz_description'] = root['quiz_description'];

      final due = root['due_date']?.toString();
      if (due != null && due.isNotEmpty) {
        try {
          metaOut['due_date'] = DateTime.parse(due);
        } catch (_) {
          /* ignore parse errors */
        }
      }

      if (root['questions'] is List) {
        final qs =
            (root['questions'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        metaOut['question_count'] = qs.length;

        int totalPts = 0;
        for (final q in qs) {
          final p = (q['points'] is num) ? (q['points'] as num).toInt() : 0;
          totalPts += p;
        }
        metaOut['total_points'] = totalPts;
      }

      return metaOut;
    }

    if (decoded is List) {
      final qs = decoded.whereType<Map>().toList();
      metaOut['question_count'] = qs.length;

      int totalPts = 0;
      for (final q in qs) {
        final p = (q['points'] is num) ? (q['points'] as num).toInt() : 0;
        totalPts += p;
      }
      metaOut['total_points'] = totalPts;
      return metaOut;
    }

    return metaOut;
  }

  /// Prefer the exact quiz_id from the JSON (case preserved). If there's no row,
  /// optionally fall back to an alternate id (e.g., the route/program id).
  /// - Case-insensitive matching (ILIKE) so "quiz_ABC" == "QUIZ_abc"
  /// - Safe numeric coercion for score_pct (numeric → double)
  /// - Backfills score_pct if null using correct/total
  static Future<Map<String, dynamic>?> getLatestAttemptForQuiz({
    required String quizIdExact,
    String? altIdForFallback,
  }) async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return null;

    // Coerce Postgres numeric/json into nice Dart types.
    Map<String, dynamic> _coerce(Map<String, dynamic> row) {
      // score_pct may arrive as num, String, or null (though it's STORED)
      double? pct;
      final rawPct = row['score_pct'];
      if (rawPct is num) {
        pct = rawPct.toDouble();
      } else if (rawPct is String) {
        pct = double.tryParse(rawPct);
      }

      // If score_pct is null for any reason, compute from correct/total
      if (pct == null) {
        final c = row['correct'];
        final t = row['total'];
        if (c is num && t is num && t > 0) {
          pct = (c.toDouble() * 100.0) / t.toDouble();
        }
      }

      return {
        'id': row['id'],
        'user_id': row['user_id'],
        'quiz_id': row['quiz_id'],
        'correct': row['correct'],
        'total': row['total'],
        'score': row['score'],
        'score_pct': pct, // ← normalized double or null
        'duration_sec': row['duration_sec'],
        'finished_at': row['finished_at'],
        'is_returned': row['is_returned'] == true,
        'returned_at': row['returned_at'],
        'feedback': row['feedback'],
        'answers': row['answers'],
        'status': row['status'],
      };
    }

    // Single fetch attempt using ILIKE for case-insensitive equality.
    Future<Map<String, dynamic>?> _fetchIlike(String qid) async {
      final res =
          await supa
              .from('quiz_attempts')
              .select('''
            id,
            user_id,
            quiz_id,
            correct,
            total,
            score,
            score_pct,
            duration_sec,
            finished_at,
            is_returned,
            returned_at,
            feedback,
            answers,
            status
          ''')
              .eq('user_id', uid)
              .ilike('quiz_id', qid) // case-insensitive "equals" when no % used
              .order('finished_at', ascending: false)
              .limit(1)
              .maybeSingle();

      return (res == null) ? null : _coerce(Map<String, dynamic>.from(res));
    }

    // Try exact id first (case-insensitive)
    final exact = await _fetchIlike(quizIdExact);
    if (exact != null) return exact;

    // Optional fallback (also case-insensitive)
    if (altIdForFallback != null && altIdForFallback.trim().isNotEmpty) {
      final fallback = await _fetchIlike(altIdForFallback.trim());
      if (fallback != null) return fallback;
    }

    // Final tiny normalization attempts (defensive): lower and upper forms.
    final lower = await _fetchIlike(quizIdExact.toLowerCase());
    if (lower != null) return lower;

    final upper = await _fetchIlike(quizIdExact.toUpperCase());
    if (upper != null) return upper;

    return null;
  }

  // Time helpers used by the intro screen UI.
  static bool quizIsOpenUtc(DateTime? dueUtc) {
    if (dueUtc == null) return true;
    return dueUtc.isAfter(DateTime.now().toUtc());
  }

  static String formatDueLocal(DateTime? dueUtc) {
    if (dueUtc == null) return 'No deadline';
    final local = dueUtc.toLocal();
    return DateFormat('MMM d, y • h:mm a').format(local);
  }

  // Prefer the quiz_id from JSON exactly as authored.
  // If not provided, fall back to a path/URL stem without ".json" (case preserved).
  static String _resolveQuizId(String inputOrPath, {String? jsonQuizId}) {
    // 1) If JSON had quiz_id, use it verbatim.
    if (jsonQuizId != null) {
      final v = jsonQuizId.trim();
      if (v.isNotEmpty) return v; // exact characters/casing preserved
    }

    // 2) Fallback: keep original characters, only strip path/query/fragment and .json
    final s = inputOrPath.trim();
    final lastSeg = s.split('/').last; // last path segment
    final noQuery = lastSeg.split('?').first.split('#').first; // remove ?...
    final stem = noQuery.replaceAll(
      RegExp(r'\.json$', caseSensitive: false),
      '',
    );
    return stem; // exact casing preserved
  }

  // ---------- Review-first attempt saving (no answer key leakage) ----------
  static Future<void> saveAttemptForReview({
    required String quizIdOrPath, // can be filename, URL, or id
    String? quizIdFromJson, // pass j['quiz_id'] here if available
    required Map<String, dynamic> userAnswers, // question_id -> selection
    required int durationSec,
    Map<String, dynamic>? meta,
  }) async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;

    final resolvedId = _resolveQuizId(
      quizIdOrPath,
      jsonQuizId: quizIdFromJson, // EXACT JSON id wins
    );

    await supa.from('quiz_attempts').insert({
      'quiz_id': resolvedId, // stored exactly as resolved
      'user_id': uid,
      'answers': userAnswers, // JSONB
      'duration_sec': durationSec,
      'status': 'pending_review',
      'score': 0, // keep only if schema requires
      'total': 0,
      'correct': 0,
      'meta': {
        'app': 'mobile',
        'quiz_id_source':
            (quizIdFromJson != null && quizIdFromJson.trim().isNotEmpty)
                ? 'json'
                : 'path',
        ...?meta,
      },
    });
  }

  // ---------- Non-adaptive gate to avoid name clash with your adaptive flow ----------
  static Future<bool> canTakeBankQuiz(String quizId) async {
    try {
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return true;

      final resp =
          await supa
              .from('quiz_progress')
              .select('status')
              .eq('user_id', uid)
              .eq('quiz_id', quizId)
              .limit(1)
              .maybeSingle();

      final status = (resp?['status'] ?? '').toString().toLowerCase();
      // Block if completed or locked; otherwise allow
      return !(status == 'completed' || status == 'locked');
    } catch (_) {
      // Fail-open on service error
      return true;
    }
  }

  // ---------- USERS ----------
  static Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = authUserId;
    if (uid == null) return null;

    final row =
        await supa
            .from('users')
            .select(
              'first_name,middle_name,last_name,grade_level,profile_picture,'
              'strand,course,track_id,course_id,section,' // ⬅️ added section
              'tracks:track_id(track_name),'
              'courses:course_id(name)',
            )
            .eq('supabase_id', uid)
            .maybeSingle();

    if (row == null) return null;

    final m = Map<String, dynamic>.from(row);

    String _pluckEmbedded(Map data, String relKey, String field) {
      final rel = data[relKey];
      if (rel is Map && rel[field] != null) return rel[field].toString();
      if (rel is List && rel.isNotEmpty && rel.first is Map) {
        final v = (rel.first as Map)[field];
        if (v != null) return v.toString();
      }
      return '';
    }

    final trackFromRel = _pluckEmbedded(m, 'tracks', 'track_name').trim();
    final courseFromRel = _pluckEmbedded(m, 'courses', 'name').trim();

    final trackFallback =
        (m['track_id']?.toString().trim().isNotEmpty ?? false)
            ? m['track_id'].toString().trim()
            : (m['strand']?.toString().trim() ?? '');

    final courseFallback = (m['course']?.toString().trim() ?? '');

    m['track_label'] = (trackFromRel.isNotEmpty ? trackFromRel : trackFallback);
    m['course_label'] =
        (courseFromRel.isNotEmpty ? courseFromRel : courseFallback);

    for (final k in const [
      'first_name',
      'middle_name',
      'last_name',
      'grade_level',
      'profile_picture',
      'strand',
      'course',
      'track_id',
      'course_id',
      'section', // ⬅️ normalize section too
      'track_label',
      'course_label',
    ]) {
      m[k] = (m[k] ?? '').toString();
    }

    return m;
  }

  static Future<void> upsertMyProfile(Map<String, dynamic> patch) async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    patch['supabase_id'] = uid;
    await supa.from('users').upsert(patch);
  }

  // ===== Helpers ===============================================================

  // Detect UUID so we can resolve users.track_id → tracks.code (e.g., TECHPRO)
  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  /// Resolve a track UUID (or pass-through a human code).
  static Future<String?> _resolveTrackCode(dynamic raw) async {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    // If it's already a human code (TECHPRO/ACADEMIC/etc.), just use it
    if (!_uuidRe.hasMatch(s) && s.length <= 24) return s;

    // Otherwise assume UUID and look up in tracks
    try {
      final row =
          await supa
              .from('tracks')
              .select('code, track_code')
              .or('id.eq.$s,track_id.eq.$s') // support either PK
              .limit(1)
              .maybeSingle();

      if (row == null) return null;
      for (final k in const ['code', 'track_code']) {
        final v = row[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return null;
  }

  // ================= PATHWAYS via RPC =================
  //
  // Uses your SQL function: fn_pathways_for_track(p_code text)
  // which joins strand_pathways → pathways and returns:
  //
  // pathway_code, match_label, name, subtitle, outcomes, entry_roles,
  // stack_suggestions, sources
  //
  // Works for ANY code you pass: ACADEMIC, TECHPRO, STEM, ABM, etc.
  static Future<List<PathwayMatch>> listPathwaysForStrand(
    String strandOrTrackCode,
  ) async {
    try {
      // Newer SDKs: rpc(...).select() returns a plain List.
      dynamic res;
      try {
        res =
            await supa
                .rpc(
                  'fn_pathways_for_track',
                  params: {'p_code': strandOrTrackCode},
                )
                .select();
      } catch (_) {
        // Older SDKs: rpc(...) returns object with { data: [...] }
        res = await supa.rpc(
          'fn_pathways_for_track',
          params: {'p_code': strandOrTrackCode},
        );
      }

      final rows = _rowsFromRpc(res);

      return rows.map((r) {
        final path = Pathway(
          code: (r['pathway_code'] ?? r['code'] ?? '').toString(),
          name: (r['name'] ?? '').toString(),
          subtitle: (r['subtitle'] ?? '').toString(),
          outcomes: _toStringList(r['outcomes']),
          entryRoles: _toStringList(r['entry_roles']),
          stackSuggestions: _toStringList(r['stack_suggestions']),
          sources: _toSources(r['sources']),
        );

        final label = (r['match_label'] ?? 'Match').toString();
        return PathwayMatch(path, label);
      }).toList();
    } catch (e) {
      _d('listPathwaysForStrand("$strandOrTrackCode") failed: $e');
      return const [];
    }
  }

  /// Alias so the rest of your app can call either name.
  static Future<List<PathwayMatch>> listPathwaysForTrackCode(String code) =>
      listPathwaysForStrand(code);

  // ===== START: Tracks (normalized user code + catalog + courses) =============

  // Common aliases → canonical codes (tweak to your data)
  static final _CODE_MAP = <String, String>{
    'ACAD': 'ACADEMIC',
    'ACADTRACK': 'ACADEMIC',
    'ACADEMIC': 'ACADEMIC',
    'TVL': 'TECHPRO',
    'TVLICT': 'TECHPRO',
    'TECHPRO': 'TECHPRO',
  };

  static String _normalizeCode(String raw) {
    final k = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
    return _CODE_MAP[k] ?? k;
  }

  /// Get the current user's track code. Looks in `users` first, resolves any UUID,
  /// falls back to strand-like fields. Returns a canonical (normalized) code or null.
  static Future<String?> getUserTrackCode() async {
    final uid = authUserId;
    if (uid == null) return null;

    try {
      final row =
          await supa
              .from('users')
              .select('track_code, track_id, strand_code, strand_id, strand')
              .eq('supabase_id', uid)
              .maybeSingle();
      if (row == null) return null;

      // 1) explicit track_code wins
      final tc = row['track_code'];
      if (tc is String && tc.trim().isNotEmpty) {
        return _normalizeCode(tc);
      }

      // 2) resolve UUID if present
      final resolved = await _resolveTrackCode(row['track_id']);
      if (resolved != null && resolved.isNotEmpty) {
        return _normalizeCode(resolved);
      }

      // 3) fallbacks from strand-ish fields
      for (final k in const ['strand_code', 'strand_id', 'strand']) {
        final v = row[k];
        if (v is String && v.trim().isNotEmpty) {
          return _normalizeCode(v);
        }
      }
    } catch (e) {
      _d('getUserTrackCode error: $e');
    }

    return null;
  }

  /// Same as getUserTrackCode() but guarantees a code so UI can render.
  static Future<String> getUserTrackCodeOrDefault() async {
    final c = await getUserTrackCode();
    if (c != null && c.isNotEmpty) return _normalizeCode(c);

    // Prefer whatever exists in strands; else default to ACADEMIC.
    try {
      final rows = await supa.from('strands').select('code').limit(10);
      final list = (rows as List?) ?? const [];
      for (final r in list) {
        final code = (r['code'] ?? '').toString().trim();
        if (code.isNotEmpty) return _normalizeCode(code);
      }
    } catch (_) {}
    return 'ACADEMIC';
  }

  /// Load a Track object by any of: track_code, track_id (UUID), or strand code.
  static Future<Track?> getTrackByCode(String codeOrId) async {
    final probe = codeOrId.trim();
    if (probe.isEmpty) return null;

    final normalized = _normalizeCode(probe);

    // 1) tracks (canonical)
    try {
      final r =
          await supa
              .from('tracks')
              .select('*')
              .or(
                'track_code.eq.$normalized,code.eq.$normalized,track_id.eq.$probe',
              )
              .limit(1)
              .maybeSingle();
      if (r != null) {
        return Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(r)));
      }
    } catch (_) {}

    // 2) optional view
    try {
      final r =
          await supa
              .from('v_tracks_shs')
              .select('*')
              .or(
                'track_code.eq.$normalized,code.eq.$normalized,track_id.eq.$probe',
              )
              .limit(1)
              .maybeSingle();
      if (r != null) {
        return Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(r)));
      }
    } catch (_) {}

    // 3) strands (fallback-as-tracks)
    try {
      final r =
          await supa
              .from('strands')
              .select('*')
              .or('code.eq.$normalized,id.eq.$probe')
              .limit(1)
              .maybeSingle();
      if (r != null) {
        return Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(r)));
      }
    } catch (_) {}

    // 4) optional view
    try {
      final r =
          await supa
              .from('v_strands_shs')
              .select('*')
              .or('code.eq.$normalized,strand_id.eq.$probe')
              .limit(1)
              .maybeSingle();
      if (r != null) {
        return Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(r)));
      }
    } catch (_) {}

    return null;
  }

  /// List available tracks for “Recommended Tracks”.
  /// Prefer `strands` (ACADEMIC/TECHPRO) and fall back gracefully.
  static Future<List<Track>> listTracks() async {
    // 1) Prefer strands table – explicit ACADEMIC/TECHPRO if present
    try {
      final rows = await supa
          .from('strands')
          .select('*')
          .or(_orEq('code', const ['ACADEMIC', 'TECHPRO']))
          .order('name', ascending: true);

      final list = (rows as List?) ?? const [];
      if (list.isNotEmpty) {
        return list
            .map(
              (e) =>
                  Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(e))),
            )
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('listTracks strands(filtered) error: $e');
    }

    // 2) All strands
    try {
      final rows = await supa
          .from('strands')
          .select('*')
          .order('name', ascending: true);

      final list = (rows as List?) ?? const [];
      if (list.isNotEmpty) {
        return list
            .map(
              (e) =>
                  Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(e))),
            )
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('listTracks strands(all) error: $e');
    }

    // 3) tracks table
    try {
      final rows = await supa
          .from('tracks')
          .select('*')
          .order('track_name', ascending: true);

      final list = (rows as List?) ?? const [];
      if (list.isNotEmpty) {
        return list
            .map(
              (e) =>
                  Track.fromRow(_coerceTrackRow(Map<String, dynamic>.from(e))),
            )
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('listTracks tracks error: $e');
    }

    // 4) views as last resort
    for (final view in const ['v_strands_shs', 'v_tracks_shs']) {
      try {
        final rows = await supa.from(view).select('*');
        final list = (rows as List?) ?? const [];
        if (list.isNotEmpty) {
          return list
              .map(
                (e) => Track.fromRow(
                  _coerceTrackRow(Map<String, dynamic>.from(e)),
                ),
              )
              .toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('listTracks $view error: $e');
      }
    }

    return const [];
  }

  /// Courses filtered for a given track/strand code or UUID.
  /// Returns only active (or rows without an `active` flag).
  static Future<List<Map<String, dynamic>>> listCoursesForTrackCode(
    String codeOrId,
  ) async {
    final normalized = _normalizeCode(codeOrId);

    final sel = supa
        .from('courses')
        .select(
          'course_id,name,summary,tags,sources,riasec_primary,track_id,track_code,strand_id,active',
        )
        .or(
          'track_code.eq.$normalized,track_id.eq.$codeOrId,strand_id.eq.$codeOrId',
        )
        .order('name', ascending: true);

    List<dynamic> rows;
    try {
      rows = await sel;
    } catch (e) {
      _d('listCoursesForTrackCode error: $e');
      rows = const [];
    }

    final out = <Map<String, dynamic>>[];
    for (final r in rows.cast<Map>()) {
      final m = Map<String, dynamic>.from(r as Map);
      final hasActive = m.containsKey('active');
      if (!hasActive || m['active'] == true) out.add(m);
    }
    return out;
  }
  // ===== END: Tracks ===========================================================

  // ---------- QUESTIONNAIRE ----------
  static Future<void> saveQuestionnaireResponses(Map<int, int> answers) async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    await supa.from('questionnaire_responses').insert({
      'response_id': "${uid}_${DateTime.now().millisecondsSinceEpoch}",
      'user_id': uid,
      'timestamp': DateTime.now().toIso8601String(),
      'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
    });
  }

  static Future<Map<String, dynamic>?> getLatestResponse() async {
    final uid = authUserId;
    if (uid == null) return null;

    return await supa
        .from('questionnaire_responses')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> loadQuestionnaire() async {
    final data = await supa.storage
        .from('ncae-preassessment-data')
        .download('questionnaire.json');

    final decoded = json.decode(utf8.decode(data));
    final list = (decoded as List).cast<Map<String, dynamic>>();

    list.shuffle(Random());
    return list;
  }

  static List<Map<String, dynamic>> processResults(
    Map<String, dynamic> answersJson,
    List<Map<String, dynamic>> questionnaire,
  ) {
    final Map<String, int> totalScores = {};
    final Map<String, int> maxScores = {};

    for (int i = 0; i < questionnaire.length; i++) {
      final q = questionnaire[i];
      final category = q['category'] as String;
      final correctIndex = q['correct_index'] as int;

      maxScores[category] = (maxScores[category] ?? 0) + 1;

      if (answersJson.containsKey('$i')) {
        final selected = answersJson['$i'];
        if (selected == correctIndex) {
          totalScores[category] = (totalScores[category] ?? 0) + 1;
        }
      }
    }

    final results = <Map<String, dynamic>>[];
    maxScores.forEach((category, max) {
      final score = totalScores[category] ?? 0;
      final pct = (score / max) * 100;
      final level = _getLevel(pct);

      results.add({
        'category': category,
        'score': score,
        'percentage': pct.toStringAsFixed(1),
        'level': level,
        'rank': 0,
      });
    });

    results.sort(
      (a, b) => double.parse(
        b['percentage'],
      ).compareTo(double.parse(a['percentage'])),
    );
    for (var i = 0; i < results.length; i++) {
      results[i]['rank'] = i + 1;
    }
    return results;
  }

  static String _getLevel(double pct) {
    if (pct >= 70) return 'HP';
    if (pct >= 51) return 'MP';
    return 'LP';
  }

  // ---------- QUESTIONNAIRE RESULTS ----------
  static Future<void> saveProcessedResults(
    List<Map<String, dynamic>> results,
  ) async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    await supa.from('questionnaire_results').insert({
      'result_id': "${uid}_${DateTime.now().millisecondsSinceEpoch}",
      'user_id': uid,
      'timestamp': DateTime.now().toIso8601String(),
      'results': results,
    });
  }

  static Future<Map<String, dynamic>?> getLatestProcessedResults() async {
    final uid = authUserId;
    if (uid == null) return null;

    return await supa
        .from('questionnaire_results')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ---------- SKILL PROGRESS ----------
  static Future<void> updateSkillProgress(
    String moduleId,
    int lessonsCompleted,
    int lessonsTotal,
  ) async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    await supa.from('skill_progress').upsert({
      'user_id': uid,
      'module_id': moduleId,
      'lessons_completed': lessonsCompleted,
      'lessons_total': lessonsTotal,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,module_id');
  }

  static Future<List<Map<String, dynamic>>> getSkillProgress() async {
    final uid = authUserId;
    if (uid == null) return [];
    return await supa.from('skill_progress').select().eq('user_id', uid);
  }

  // ---------- QUIZ PROGRESS ----------
  static const Set<String> _dbAllowedQuizStatuses = {
    'locked',
    'in_progress',
    'completed',
  };

  static String _coerceQuizStatus(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (_dbAllowedQuizStatuses.contains(s)) return s;

    switch (s) {
      case 'unlocked':
      case 'start':
      case 'started':
      case 'in-progress':
      case 'progress':
      case 'ongoing':
        return 'in_progress';
      case 'done':
      case 'finished':
      case 'complete':
        return 'completed';
      case 'lock':
        return 'locked';
      default:
        return 'in_progress';
    }
  }

  static Future<void> updateQuizProgress(
    String quizId, {
    String status = 'in_progress',
    int? score,
    Map<int, int>? answers, // legacy single
    Map<int, List<int>>? answersMulti, // NEW multi
  }) async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    final coerced = _coerceQuizStatus(status);

    await supa.from('quiz_progress').upsert({
      'user_id': uid,
      'quiz_id': quizId,
      'status': coerced,
      'score': score,
      'answers':
          answers != null
              ? answers.map((k, v) => MapEntry(k.toString(), v))
              : null,
      'answers_multi':
          answersMulti != null
              ? answersMulti.map((k, v) => MapEntry(k.toString(), v))
              : null,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,quiz_id');
  }

  static Future<List<Map<String, dynamic>>> getQuizProgress() async {
    final uid = authUserId;
    if (uid == null) return [];
    return await supa.from('quiz_progress').select().eq('user_id', uid);
  }

  // ---------- LOAD LESSONS ----------
  static String _normalizeId(String s) {
    final noExt = s.trim().toLowerCase().replaceAll(RegExp(r'\.json$'), '');
    final squashed = noExt.replaceAll(RegExp(r'[^a-z0-9/]+'), '_');
    return squashed.replaceAll(RegExp(r'_+'), '_');
  }

  static Future<void> debugDumpAdaptive({String folder = ''}) async {
    const bucket = 'adaptive-quizzes';
    final s = supa.storage.from(bucket);

    Future<List<String>> _ls(String p) async {
      try {
        final list = await s.list(path: p);
        return list.map((e) => e.name).toList();
      } catch (_) {
        return const [];
      }
    }

    final root = await _ls('');
    // ignore: avoid_print
    print('---- [$bucket] root ----');
    for (final n in root) {
      print('  • $n');
    }

    if (folder.isNotEmpty) {
      for (final f in {folder, folder.toUpperCase(), folder.toLowerCase()}) {
        final sub = await _ls(f);
        // ignore: avoid_print
        print('---- [$bucket/$f] ----');
        for (final n in sub) {
          print('  • $n');
        }
      }
    }
  }

  static Future<Uint8List> _downloadFirstFound({
    required String bucket,
    required List<String> candidates,
  }) async {
    final s = supa.storage.from(bucket);
    final tried = <String>[];

    for (final p in candidates) {
      try {
        final bytes = await s.download(p);
        // ignore: avoid_print
        print('[storage] ✅ $bucket/$p');
        return bytes;
      } on StorageException catch (e) {
        tried.add('$bucket/$p → ${e.message}');
      } catch (e) {
        tried.add('$bucket/$p → $e');
      }
    }

    Future<List<String>> _ls(String path) async {
      try {
        final list = await s.list(path: path);
        return list.map((e) => e.name).toList();
      } catch (_) {
        return const <String>[];
      }
    }

    final root = await _ls('');
    final folders = <String>{};
    for (final c in candidates) {
      final i = c.indexOf('/');
      if (i > 0) folders.add(c.substring(0, i));
    }
    final folderLists = <String, List<String>>{};
    for (final f in folders) {
      folderLists[f] = await _ls(f);
    }

    final diag =
        StringBuffer()
          ..writeln('Storage 404. File not found.')
          ..writeln('Tried paths:')
          ..writeln(tried.map((t) => ' • $t').join('\n'))
          ..writeln('\n[Bucket "$bucket" @ "/"] → $root');
    for (final f in folderLists.keys) {
      diag.writeln('[Bucket "$bucket" @ "$f/"] → ${folderLists[f]}');
    }

    throw diag.toString();
  }

  /// storage://<bucket>/<path>  → returns (bucket, path)
  static (String bucket, String path) _parseStorageUrl(String url) {
    final u = url.trim();
    if (!u.startsWith('storage://')) {
      throw 'Unsupported content_url: $url';
    }
    final rest = u.substring('storage://'.length);
    final firstSlash = rest.indexOf('/');
    if (firstSlash <= 0) throw 'Invalid storage URL: $url';
    final bucket = rest.substring(0, firstSlash);
    final path = rest.substring(firstSlash + 1);
    return (bucket, path);
  }

  static Future<String?> _tryDownloadText(String bucket, String path) async {
    try {
      final bytes = await supa.storage.from(bucket).download(path);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _topLevelFolders(String bucket) async {
    try {
      final entries = await supa.storage.from(bucket).list(path: '');
      final out = <String>[];
      for (final e in entries) {
        if (!e.name.contains('.')) {
          final probe = await supa.storage.from(bucket).list(path: e.name);
          if (probe.isNotEmpty) out.add(e.name);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<Map<String, dynamic>>> loadSkillModule(
    String moduleId,
  ) async {
    const bucket = 'skill-modules';
    final code =
        await getUserStrandOrCourseCode(); // e.g., GAS or a course code
    final snake = _normalizeId(moduleId);
    final jsonFile = '$snake.json';

    final candidates = <String>[
      if (code != null && code.isNotEmpty) '$code/$jsonFile',
      if (code != null && code.isNotEmpty) '$code/$snake/module.json',
      jsonFile,
    ];

    for (final f in await _topLevelFolders(bucket)) {
      candidates.add('$f/$jsonFile');
      candidates.add('$f/$snake/module.json');
    }

    try {
      final bytes = await _downloadFirstFound(
        bucket: bucket,
        candidates: candidates,
      );
      final decoded = json.decode(utf8.decode(bytes));

      final List<dynamic> rawLessons;
      if (decoded is Map<String, dynamic> && decoded['lessons'] is List) {
        rawLessons = decoded['lessons'] as List<dynamic>;
      } else if (decoded is List) {
        rawLessons = decoded;
      } else {
        return [];
      }

      final out = <Map<String, dynamic>>[];
      for (final e in rawLessons) {
        final m = Map<String, dynamic>.from(e as Map);
        final url = (m['content_url'] ?? '').toString().trim();

        if (url.startsWith('storage://')) {
          var (bkt, pth) = _parseStorageUrl(url);
          if (bkt == 'skills-module') bkt = 'skill-modules'; // legacy typo
          final txt = await _tryDownloadText(bkt, pth);
          m['content_md'] =
              txt ?? (m['content_md'] ?? '*Content coming soon.*');
        }

        out.add(m);
      }

      return out;
    } catch (_) {}

    final folders = <String>[
      if (code != null && code.isNotEmpty) code,
      ...await _topLevelFolders(bucket),
    ];

    for (final f in folders) {
      final sub = '$f/$snake';
      try {
        final items = await supa.storage.from(bucket).list(path: sub);
        final lessonFiles =
            items
                .map((e) => e.name)
                .where(
                  (n) =>
                      n.toLowerCase().endsWith('.md') &&
                      n.toLowerCase().startsWith('l'),
                )
                .toList()
              ..sort();

        if (lessonFiles.isEmpty) continue;

        final lessons = <Map<String, dynamic>>[];
        for (final name in lessonFiles) {
          final md = await _tryDownloadText(bucket, '$sub/$name') ?? '';
          lessons.add({
            'title': name.replaceAll('.md', '').toUpperCase(),
            'content_md': md.isEmpty ? '*Content coming soon.*' : md,
          });
        }
        return lessons;
      } catch (_) {}
    }

    return [];
  }

  // ---- LOAD QUIZ (folder-aware + adaptive pools/TOS) -----------------
  static Future<List<Map<String, dynamic>>> loadQuiz(String quizId) async {
    const bucket = 'adaptive-quizzes';

    final raw = quizId.trim();
    final hasFolder = raw.contains('/');
    final parts = raw.split('/');
    final baseId = hasFolder ? parts.last : raw;

    final normBase = _normalizeId(baseId);
    final fileExact = '$normBase.json';
    final fileLower = fileExact.toLowerCase();

    final candidates = <String>[];

    if (hasFolder) {
      final folder = parts.first;
      for (final f in {folder, folder.toUpperCase(), folder.toLowerCase()}) {
        candidates.add('$f/$fileExact');
        candidates.add('$f/$fileLower');
      }
    } else {
      final code = await getUserStrandOrCourseCode();
      if (code != null && code.isNotEmpty) {
        for (final f in {code, code.toUpperCase(), code.toLowerCase()}) {
          candidates.add('$f/$fileExact');
          candidates.add('$f/$fileLower');
        }
      }
      candidates.add(fileExact);
      candidates.add(fileLower);
    }

    try {
      final bytes = await _downloadFirstFound(
        bucket: bucket,
        candidates: candidates,
      );
      final decoded = json.decode(utf8.decode(bytes));

      if (decoded is Map<String, dynamic> && decoded['questions'] is List) {
        return (decoded['questions'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (decoded is Map<String, dynamic> && decoded['pools'] is Map) {
        final pools = <String, List<Map<String, dynamic>>>{
          'easy':
              (((decoded['pools'] as Map)['easy'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
          'medium':
              (((decoded['pools'] as Map)['medium'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
          'hard':
              (((decoded['pools'] as Map)['hard'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
        };
        final sel =
            (decoded['selection'] is Map)
                ? Map<String, dynamic>.from(decoded['selection'])
                : <String, dynamic>{};
        final total =
            (sel['count'] is num) ? (sel['count'] as num).toInt() : 15;

        Map<String, int> counts = {'easy': 0, 'medium': 0, 'hard': 0};

        if (decoded['tos'] is Map) {
          final tos = Map<String, dynamic>.from(decoded['tos']);
          counts['easy'] = (tos['easy'] ?? 0) as int;
          counts['medium'] = (tos['medium'] ?? 0) as int;
          counts['hard'] = (tos['hard'] ?? 0) as int;

          counts['easy'] = counts['easy']!.clamp(0, pools['easy']!.length);
          counts['medium'] = counts['medium']!.clamp(
            0,
            pools['medium']!.length,
          );
          counts['hard'] = counts['hard']!.clamp(0, pools['hard']!.length);

          int sum = counts.values.fold(0, (a, b) => a + b);
          while (sum > total) {
            for (final k in ['hard', 'medium', 'easy']) {
              if (counts[k]! > 0 && sum > total) {
                counts[k] = counts[k]! - 1;
                sum--;
              }
            }
          }
          final room = {
            'easy': pools['easy']!.length - counts['easy']!,
            'medium': pools['medium']!.length - counts['medium']!,
            'hard': pools['hard']!.length - counts['hard']!,
          };
          while (sum < total) {
            final next = (['easy', 'medium', 'hard']..sort(
              (a, b) => room[b]!.compareTo(room[a]!),
            )).firstWhere((k) => room[k]! > 0, orElse: () => 'easy');
            counts[next] = counts[next]! + 1;
            room[next] = room[next]! - 1;
            sum++;
          }
        } else {
          final all = <Map<String, dynamic>>[
            ...pools['easy']!,
            ...pools['medium']!,
            ...pools['hard']!,
          ]..shuffle();
          return all.take(total.clamp(0, all.length)).toList();
        }

        List<T> pick<T>(List<T> list, int n) {
          if (n <= 0 || list.isEmpty) return [];
          final copy = List<T>.of(list)..shuffle();
          return copy.take(n.clamp(0, copy.length)).toList();
        }

        var selected = <Map<String, dynamic>>[
          ...pick(pools['easy']!, counts['easy']!),
          ...pick(pools['medium']!, counts['medium']!),
          ...pick(pools['hard']!, counts['hard']!),
        ];

        if (selected.length < total) {
          final used = selected.map((q) => q['id'] ?? q['question']).toSet();
          final leftovers = <Map<String, dynamic>>[
            ...pools['easy']!.where(
              (q) => !used.contains(q['id'] ?? q['question']),
            ),
            ...pools['medium']!.where(
              (q) => !used.contains(q['id'] ?? q['question']),
            ),
            ...pools['hard']!.where(
              (q) => !used.contains(q['id'] ?? q['question']),
            ),
          ]..shuffle();
          selected.addAll(leftovers.take(total - selected.length));
        } else if (selected.length > total) {
          selected.shuffle();
          selected = selected.take(total).toList();
        }

        selected.shuffle();
        return selected;
      }

      return [];
    } catch (e) {
      // ignore: avoid_print
      print('Error loading quiz $quizId from $bucket: $e');
      rethrow;
    }
  }

  // ---------- STORAGE (generic) ----------
  static Future<List<String>> listFiles({
    required String bucket,
    String path = '',
  }) async {
    final List<FileObject> entries = await supa.storage
        .from(bucket)
        .list(path: path);
    return entries.map((f) => f.name).toList();
  }

  static Future<String> uploadAvatar({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uid = authUserId ?? (throw 'Not logged in');
    final path = '$uid/$fileName';

    await supa.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            cacheControl: '3600',
            contentType: _guessContentType(fileName),
          ),
        );

    return supa.storage.from('avatars').getPublicUrl(path);
  }

  /// Back-compat: original screen used a dedicated `my-study-guides` bucket.
  /// We now keep files in `resources/pdf`. This tries the new location first,
  /// then falls back to the legacy bucket so old content still works.
  static Future<List<FileObject>> listPdfFiles() async {
    // NEW preferred location
    try {
      final list = await supa.storage.from('resources').list(path: 'pdf');
      if (list.isNotEmpty) return list;
    } catch (_) {}
    // Legacy
    return await supa.storage.from('my-study-guides').list(path: '');
  }

  static Future<String?> getPdfUrl(String key) async {
    // If caller passes a bare filename, assume `resources/pdf/<name>`
    // If caller already passed a path, honor it.
    final looksLikePath = key.contains('/');
    final path = looksLikePath ? key : 'pdf/$key';

    // Try signed (works even if you later make bucket private); fall back to public.
    try {
      return await supa.storage.from('resources').createSignedUrl(path, 3600);
    } catch (_) {
      try {
        return supa.storage.from('resources').getPublicUrl(path);
      } catch (_) {
        // Legacy fallback
        try {
          return supa.storage.from('my-study-guides').getPublicUrl(key);
        } catch (e) {
          _d('getPdfUrl fallback failed: $e');
          return null;
        }
      }
    }
  }

  static Future<List<FileObject>> listVideoFiles() async {
    return await supa.storage.from('study-guide-videos').list(path: '');
  }

  static Future<String?> getVideoUrl(String key) async {
    return supa.storage.from('study-guide-videos').getPublicUrl(key);
  }

  static Future<String?> getFileUrl({
    required String bucket,
    required String path,
    int expiresIn = 86400,
  }) async {
    try {
      final signed = await supa.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn);
      return signed;
    } catch (_) {
      try {
        return supa.storage.from(bucket).getPublicUrl(path);
      } catch (e) {
        _d('getFileUrl failed for $bucket/$path: $e');
        return null;
      }
    }
  }

  // ---- QUIZ: BANK + TOS LOADER (root-bucket + admin JSON aware; ALL when totalOverride<=0) ----
  static Future<List<Map<String, dynamic>>> fetchQuizWithTOS({
    required String quizId,
    String bucket = 'quizzes',
    int? seed,
    int totalOverride = 10, // <=0 means ALL
  }) async {
    // helpers
    String _squash(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

    String _hyphenize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    // used by direct filename guesses (underscored id)
    String _normalizeId(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // ensure public_url on media lists
    Map<String, dynamic> _ensurePublicUrls(
      Map<String, dynamic> q, {
      required String bucket,
    }) {
      List<Map<String, dynamic>> _fixList(dynamic val) {
        final list = (val is List) ? val : const <dynamic>[];
        return list.map<Map<String, dynamic>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final path = (m['path'] ?? '').toString();
          final bkt = (m['bucket'] ?? bucket).toString();
          if ((m['public_url'] == null || '${m['public_url']}'.isEmpty) &&
              path.isNotEmpty) {
            try {
              final pub = supa.storage.from(bkt).getPublicUrl(path);
              m['public_url'] = pub;
            } catch (_) {
              // ignore
            }
          }
          return m;
        }).toList();
      }

      final out = Map<String, dynamic>.from(q);
      out['images'] = _fixList(q['images']);
      out['files'] = _fixList(q['files']);
      return out;
    }

    // normalize admin question → app shape (keeps media + difficulty + allow_multiple)
    // Supports: "choice" and "text"
    Map<String, dynamic> _normalizeAdminQ(Map<String, dynamic> src) {
      final m = Map<String, dynamic>.from(src);
      final String type =
          (m['question_type'] ?? 'choice').toString().toLowerCase();

      List _asList(v) => (v is List) ? v : const <dynamic>[];

      // TEXT question
      if (type == 'text') {
        final out = <String, dynamic>{
          'text': (m['question_text'] ?? '').toString(),
          'is_text': true,
          'answer_texts':
              _asList(m['choices']).map((e) => e.toString()).toList(),
          'text_any_case': m['text_any_case'] == true,
          'enable_math': m['enable_math'] == true,
          'images': _asList(m['images']),
          'files': _asList(m['files']),
          'question_id': m['question_id'],
          'points': m['points'],
          'required': m['required'],
          'difficulty': (m['difficulty'] ?? '').toString(),
        };
        if ((out['text'] as String).trim().isEmpty) {
          return const <String, dynamic>{};
        }
        return _ensurePublicUrls(out, bucket: bucket);
      }

      // MULTIPLE CHOICE
      if (type != 'choice') return const <String, dynamic>{}; // skip others

      final List<String> options =
          _asList(m['choices']).map((e) => e.toString()).toList();

      final List<int> idxs =
          _asList(
            m['correct_answers'],
          ).whereType<num>().map((n) => n.toInt()).toList();

      final out = <String, dynamic>{
        'text': (m['question_text'] ?? '').toString(),
        'options': options,
        'difficulty': (m['difficulty'] ?? '').toString(),
        'allow_multiple': m['allow_multiple'] == true,
        if ((m['allow_multiple'] == true) && idxs.isNotEmpty)
          'correct_answers': idxs,
        if (!(m['allow_multiple'] == true) && idxs.isNotEmpty)
          'answer_index': idxs.first,
        'images': _asList(m['images']),
        'files': _asList(m['files']),
        'question_id': m['question_id'],
        'points': m['points'],
        'required': m['required'],
        'enable_math': m['enable_math'],
      };

      if ((out['text'] as String).trim().isEmpty || options.isEmpty) {
        return const <String, dynamic>{};
      }
      return _ensurePublicUrls(out, bucket: bucket);
    }

    final rnd = seed == null ? Random() : Random(seed);
    List<T> pick<T>(List<T> list, int n) {
      if (n <= 0 || list.isEmpty) return <T>[];
      final copy = List<T>.of(list);
      for (int i = copy.length - 1; i > 0; i--) {
        final j = rnd.nextInt(i + 1);
        final tmp = copy[i];
        copy[i] = copy[j];
        copy[j] = tmp;
      }
      final cnt = n < 0 ? 0 : (n > copy.length ? copy.length : n);
      return copy.take(cnt).toList();
    }

    Map<String, int> _safeCounts({
      required Map<String, int> want,
      required Map<String, List<Map<String, dynamic>>> pools,
      required int total,
    }) {
      final counts = <String, int>{...want};
      for (final k in counts.keys.toList()) {
        final poolLen = pools[k]?.length ?? 0;
        final v = counts[k] ?? 0;
        counts[k] = v.clamp(0, poolLen);
      }

      int sum = counts.values.fold(0, (a, b) => a + b);

      // trim hardest-first if overshoot
      while (sum > total) {
        for (final k in const ['hard', 'medium', 'easy']) {
          final v = counts[k] ?? 0;
          if (v > 0 && sum > total) {
            counts[k] = v - 1;
            sum--;
          }
        }
      }

      // refill from buckets with most room
      final room = <String, int>{
        for (final k in ['easy', 'medium', 'hard'])
          k: (pools[k]?.length ?? 0) - (counts[k] ?? 0),
      };
      while (sum < total) {
        final order = ['easy', 'medium', 'hard']
          ..sort((a, b) => (room[b] ?? 0).compareTo(room[a] ?? 0));
        final next = order.firstWhere(
          (k) => (room[k] ?? 0) > 0,
          orElse: () => 'easy',
        );
        counts[next] = (counts[next] ?? 0) + 1;
        room[next] = (room[next] ?? 0) - 1;
        sum++;
      }
      return counts;
    }

    // 1) try direct filename guesses in ROOT
    final norm = _normalizeId(quizId); // underscores
    final hyph = _hyphenize(quizId); // hyphens
    final normHyph = _hyphenize(norm);

    final directCandidates =
        <String>{
          '$norm.json',
          '$hyph.json',
          '$normHyph.json',
          'quiz_$norm.json',
          'quiz-$norm.json',
          'quiz_$hyph.json',
          '${norm}_quiz.json',
          '${hyph}_quiz.json',
          '${hyph}-quiz.json',
        }.toList();

    String? foundPath;
    Uint8List? payload;

    for (final p in directCandidates) {
      try {
        payload = await supa.storage.from(bucket).download(p);
        foundPath = p;
        // ignore: avoid_print
        print('[storage] ✅ $bucket/$p');
        break;
      } catch (_) {
        /* try next */
      }
    }

    // 2) fuzzy search all jsons in root if not found
    if (payload == null) {
      final entries = await supa.storage.from(bucket).list(path: '');
      final jsonFiles =
          entries
              .where((e) => e.name.toLowerCase().endsWith('.json'))
              .map((e) => e.name)
              .toList();

      if (jsonFiles.isEmpty) throw 'No .json quizzes in bucket root.';

      final goal = _squash(quizId);
      String best = '';
      int bestScore = -1;

      for (final f in jsonFiles) {
        final s = _squash(f.replaceAll('.json', ''));
        int score = 0;
        final n = min(s.length, goal.length);
        for (int k = 1; k <= n; k++) {
          if (goal.contains(s.substring(0, k))) score = k;
        }
        if (s.contains('quiz') && goal.contains('quiz')) score += 3;
        if (score > bestScore) {
          bestScore = score;
          best = f;
        }
      }

      try {
        payload = await supa.storage.from(bucket).download(best);
        foundPath = best;
        // ignore: avoid_print
        print('[storage] 🔎 fuzzy matched $bucket/$best for "$quizId"');
      } catch (e) {
        final diag =
            StringBuffer()
              ..writeln('Storage 404. File not found for "$quizId".')
              ..writeln('Tried direct: $directCandidates')
              ..writeln(
                '[Bucket "$bucket" @ "/"] → ${jsonFiles.take(20).toList()}',
              );
        throw diag.toString();
      }
    }

    final decoded = json.decode(utf8.decode(payload!));

    // Case 0: raw list bank
    if (decoded is List) {
      final bank =
          decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((q) => _ensurePublicUrls(q, bucket: bucket))
              .toList();
      if (bank.isEmpty) return const <Map<String, dynamic>>[];
      if (totalOverride <= 0) return bank; // ALL
      final target = min(totalOverride, bank.length);
      final copy = List<Map<String, dynamic>>.of(bank)..shuffle(rnd);
      return copy.take(target).toList();
    }

    if (decoded is! Map) return const <Map<String, dynamic>>[];
    final root = Map<String, dynamic>.from(decoded);

    // Case A: admin wrapper with questions[]
    if (root['questions'] is List) {
      final rawQs =
          (root['questions'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      // normalize + add public_url; skip unsupported types
      final bank = <Map<String, dynamic>>[];
      for (final q in rawQs) {
        final m = _normalizeAdminQ(q);
        if (m.isNotEmpty) bank.add(m);
      }
      if (bank.isEmpty) return const <Map<String, dynamic>>[];

      // pools/tos logic (optional)
      if (root['pools'] is Map) {
        final poolsRaw = Map<String, dynamic>.from(root['pools']);

        List<Map<String, dynamic>> _normPool(List? lst) {
          final src = (lst ?? const <dynamic>[]);
          final out = <Map<String, dynamic>>[];
          for (final e in src) {
            final m = _normalizeAdminQ(Map<String, dynamic>.from(e as Map));
            if (m.isNotEmpty) out.add(m);
          }
          return out;
        }

        final pools = <String, List<Map<String, dynamic>>>{
          'easy': _normPool(poolsRaw['easy'] as List?),
          'medium': _normPool(poolsRaw['medium'] as List?),
          'hard': _normPool(poolsRaw['hard'] as List?),
        };

        if (totalOverride <= 0) {
          return <Map<String, dynamic>>[
            ...pools['easy']!,
            ...pools['medium']!,
            ...pools['hard']!,
          ];
        }

        final sel =
            (root['selection'] is Map)
                ? Map<String, dynamic>.from(root['selection'])
                : <String, dynamic>{};
        final int total =
            (sel['count'] is num)
                ? (sel['count'] as num).toInt()
                : totalOverride;

        if (root['tos'] is Map) {
          final tos = Map<String, dynamic>.from(root['tos']);
          final want = <String, int>{
            'easy': (tos['easy'] ?? 0) as int,
            'medium': (tos['medium'] ?? 0) as int,
            'hard': (tos['hard'] ?? 0) as int,
          };
          final counts = _safeCounts(want: want, pools: pools, total: total);
          var selected = <Map<String, dynamic>>[
            ...pick(pools['easy']!, counts['easy']!),
            ...pick(pools['medium']!, counts['medium']!),
            ...pick(pools['hard']!, counts['hard']!),
          ];

          if (selected.length < total) {
            final used = selected.map((q) => q['text']).toSet();
            final leftovers = <Map<String, dynamic>>[
              ...pools['easy']!.where((q) => !used.contains(q['text'])),
              ...pools['medium']!.where((q) => !used.contains(q['text'])),
              ...pools['hard']!.where((q) => !used.contains(q['text'])),
              ...bank.where((q) => !used.contains(q['text'])),
            ]..shuffle(rnd);
            selected.addAll(leftovers.take(total - selected.length));
          } else if (selected.length > total) {
            selected.shuffle(rnd);
            selected = selected.take(total).toList();
          }
          selected.shuffle(rnd);
          return selected;
        }

        final all = <Map<String, dynamic>>[
          ...pools['easy']!,
          ...pools['medium']!,
          ...pools['hard']!,
        ]..shuffle(rnd);
        return all.take(min(total, all.length)).toList();
      }

      // No pools/tos: ALL or trimmed
      if (totalOverride <= 0) return bank; // ALL
      final target = min(totalOverride, bank.length);
      final copy = List<Map<String, dynamic>>.of(bank)..shuffle(rnd);
      return copy.take(target).toList();
    }

    // Case B: legacy pools-only file (no wrapper list)
    if (root['pools'] is Map) {
      final poolsRaw = Map<String, dynamic>.from(root['pools']);
      List<Map<String, dynamic>> _asList(dynamic v) =>
          (v is List)
              ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : <Map<String, dynamic>>[];

      // ensure media urls if present (legacy format)
      List<Map<String, dynamic>> _fixMedia(List<Map<String, dynamic>> src) =>
          src.map((m) => _ensurePublicUrls(m, bucket: bucket)).toList();

      final easy = _fixMedia(_asList(poolsRaw['easy']));
      final medium = _fixMedia(_asList(poolsRaw['medium']));
      final hard = _fixMedia(_asList(poolsRaw['hard']));

      if (totalOverride <= 0) {
        return <Map<String, dynamic>>[...easy, ...medium, ...hard];
      }

      final sel =
          (root['selection'] is Map)
              ? Map<String, dynamic>.from(root['selection'])
              : <String, dynamic>{};
      final int total =
          (sel['count'] is num) ? (sel['count'] as num).toInt() : totalOverride;

      if (root['tos'] is Map) {
        final tos = Map<String, dynamic>.from(root['tos']);
        final counts = _safeCounts(
          want: {
            'easy': (tos['easy'] ?? 0) as int,
            'medium': (tos['medium'] ?? 0) as int,
            'hard': (tos['hard'] ?? 0) as int,
          },
          pools: {'easy': easy, 'medium': medium, 'hard': hard},
          total: total,
        );

        var selected = <Map<String, dynamic>>[
          ...pick(easy, counts['easy']!),
          ...pick(medium, counts['medium']!),
          ...pick(hard, counts['hard']!),
        ];

        if (selected.length < total) {
          final used = selected.map((q) => q['id'] ?? q['text']).toSet();
          final leftovers = <Map<String, dynamic>>[
            ...easy.where((q) => !used.contains(q['id'] ?? q['text'])),
            ...medium.where((q) => !used.contains(q['id'] ?? q['text'])),
            ...hard.where((q) => !used.contains(q['id'] ?? q['text'])),
          ]..shuffle(rnd);
          selected.addAll(leftovers.take(total - selected.length));
        } else if (selected.length > total) {
          selected.shuffle(rnd);
          selected = selected.take(total).toList();
        }
        selected.shuffle(rnd);
        return selected;
      }

      final all = <Map<String, dynamic>>[...easy, ...medium, ...hard]
        ..shuffle(rnd);
      return all.take(min(total, all.length)).toList();
    }

    return const <Map<String, dynamic>>[];
  }

  // ---------- HELPERS ----------
  static String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  // ---------- RIASEC TEST: LOADERS & SCORING ----------
  static Future<Map<String, dynamic>> loadRiasecItems({
    String bucket = 'riasec-test',
    String path = 'items.json',
    bool shuffle = true,
  }) async {
    final bytes = await supa.storage.from(bucket).download(path);
    final decoded = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final items =
        (decoded['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    if (shuffle) items.shuffle(Random());

    return {
      'items': items,
      'scale_min': (decoded['scale_min'] ?? 1) as int,
      'scale_max': (decoded['scale_max'] ?? 5) as int,
      'likert_labels':
          (decoded['likert_labels'] as List?)?.map((e) => '$e').toList() ??
          [
            'Strongly Disagree',
            'Disagree',
            'Neutral',
            'Agree',
            'Strongly Agree',
          ],
    };
  }

  static Map<String, int> scoreRiasecToPercent({
    required List<Map<String, dynamic>> items,
    required Map<int, int> answers,
    int scaleMin = 1,
    int scaleMax = 5,
  }) {
    final codes = ['R', 'I', 'A', 'S', 'E', 'C'];
    final raw = {for (final c in codes) c: 0.0};
    final counts = {for (final c in codes) c: 0};

    int inv(int v) => (scaleMax + scaleMin) - v;

    for (final it in items) {
      final id = (it['id'] as num).toInt();
      final code = (it['code'] as String).toUpperCase();
      if (!codes.contains(code)) continue;

      final val = answers[id];
      if (val == null) continue;

      final isReverse = (it['reverse'] == true);
      final usedVal = isReverse ? inv(val) : val.toDouble();

      raw[code] = (raw[code] ?? 0) + usedVal;
      counts[code] = (counts[code] ?? 0) + 1;
    }

    int toPct(double sum, int n) {
      if (n == 0) return 0;
      final minSum = n * scaleMin;
      final maxSum = n * scaleMax;
      final pct = 100 * (sum - minSum) / (maxSum - minSum);
      final clipped = pct.isNaN ? 0.0 : pct.clamp(0, 100);
      return clipped.round();
    }

    return {
      'R': toPct(raw['R']!, counts['R']!),
      'I': toPct(raw['I']!, counts['I']!),
      'A': toPct(raw['A']!, counts['A']!),
      'S': toPct(raw['S']!, counts['S']!),
      'E': toPct(raw['E']!, counts['E']!),
      'C': toPct(raw['C']!, counts['C']!),
    };
  }

  // ---------- RIASEC + NCAE + PATH ----------
  static Future<void> insertRiasec({
    required String userId,
    required int r,
    required int i,
    required int a,
    required int s,
    required int e,
    required int c,
  }) async {
    await supa.from('riasec_results').insert({
      'user_id': userId,
      'r': r,
      'i': i,
      'a': a,
      's': s,
      'e': e,
      'c': c,
    });
  }

  static Future<void> insertNcae({
    required String userId,
    required int math,
    required int sci,
    required int eng,
    required int business,
    required int techvoc,
    required int humanities,
  }) async {
    await supa.from('ncae_results').insert({
      'user_id': userId,
      'math_percentile': math,
      'sci_percentile': sci,
      'eng_percentile': eng,
      'business_percentile': business,
      'techvoc_percentile': techvoc,
      'humanities_percentile': humanities,
    });
  }

  // --- NEW: Recommendations based on SQL function `recommend_courses` ---
  static Future<List<Map<String, dynamic>>> recommendCourses() async {
    final uid = authUserId ?? (throw Exception('Not logged in'));
    final res = await supa.rpc('recommend_courses', params: {'p_user': uid});
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  static Future<List<Map<String, dynamic>>> topRecommendations({
    int n = 5,
  }) async {
    final rows = await recommendCourses();
    return rows.take(n).toList();
  }

  static Future<Map<String, dynamic>?> previewRecommendation() async {
    final list = await topRecommendations(n: 1);
    return list.isEmpty ? null : list.first;
  }

  static Future<Map<String, dynamic>?> previewLearningPath() async {
    final res = await supa.rpc('compute_learning_path_preview'); // no params
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first);
    }
    return null;
  }

  static Future<void> finalizeLearningPath() async {
    final uid = authUserId ?? (throw Exception('Not logged in'));
    await supa.rpc('finalize_learning_path', params: {'p_user': uid});
  }

  static Future<bool> hasSavedPath() async {
    final uid = authUserId;
    if (uid == null) return false;
    final row =
        await supa
            .from('user_learning_path')
            .select('user_id')
            .eq('user_id', uid)
            .limit(1)
            .maybeSingle();
    return row != null;
  }

  static Future<Map<String, dynamic>?> getSavedPath() async {
    final uid = authUserId;
    if (uid == null) return null;
    final row =
        await supa
            .from('user_learning_path')
            .select('strand_id, track_id, course_id, courses:course_id(name)')
            .eq('user_id', uid)
            .maybeSingle();
    return row;
  }

  // ------------------- ASSESSMENT STATUS + FETCHERS -------------------
  static Future<Map<String, dynamic>> getAssessmentStatus() async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    final latestRIASEC = await getLatestRiasecRow();
    final latestNCAE = await getLatestNcaeRow();

    final hasRiasec = latestRIASEC != null;
    final hasNcae = latestNCAE != null;

    Map<String, dynamic>? preview;
    if (hasRiasec && hasNcae) {
      preview = await previewRecommendation();
    }

    return {'has_riasec': hasRiasec, 'has_ncae': hasNcae, 'preview': preview};
  }

  static Future<Map<String, dynamic>?> getLatestRiasecRow() async {
    final uid = authUserId;
    if (uid == null) return null;
    return await supa
        .from('riasec_results')
        .select()
        .eq('user_id', uid)
        .order('taken_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  static Future<Map<String, dynamic>?> getLatestNcaeRow() async {
    final uid = authUserId;
    if (uid == null) return null;
    return await supa
        .from('ncae_results')
        .select()
        .eq('user_id', uid)
        .order('taken_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ------------------- NCAE: questionnaire → ncae_results -------------------
  static Future<Map<String, int>?>
  getLatestNcaePercentilesFromQuestionnaire() async {
    final uid = authUserId;
    if (uid == null) return null;

    final qr =
        await supa
            .from('questionnaire_results')
            .select('results')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (qr == null) return null;

    final List<dynamic> results = (qr['results'] ?? []) as List<dynamic>;
    if (results.isEmpty) return null;

    int pct(String category) {
      final row = results.firstWhere(
        (e) =>
            (e is Map) &&
            (e['category']?.toString().toLowerCase() == category.toLowerCase()),
        orElse: () => null,
      );
      if (row == null) return 0;
      final p = row['percentage'];
      final num v = (p is num) ? p : num.tryParse(p?.toString() ?? '0') ?? 0;
      final clipped = v.clamp(0, 100);
      return clipped.round();
    }

    return {
      'math_percentile': pct('Math'),
      'sci_percentile': pct('Science'),
      'eng_percentile': pct('English'),
      'business_percentile': pct('Business'),
      'techvoc_percentile': pct('Tech-Voc'),
      'humanities_percentile': pct('Humanities'),
    };
  }

  static Future<bool> upsertNcaeFromQuestionnaire() async {
    final uid = authUserId;
    if (uid == null) throw 'Not logged in';

    final m = await getLatestNcaePercentilesFromQuestionnaire();
    if (m == null) return false;

    await supa.from('ncae_results').insert({
      'user_id': uid,
      'math_percentile': m['math_percentile'],
      'sci_percentile': m['sci_percentile'],
      'eng_percentile': m['eng_percentile'],
      'business_percentile': m['business_percentile'],
      'techvoc_percentile': m['techvoc_percentile'],
      'humanities_percentile': m['humanities_percentile'],
    });
    return true;
  }

  static Future<bool> finalizeIfReady() async {
    final status = await getAssessmentStatus();
    if (status['has_riasec'] == true && status['has_ncae'] == true) {
      await finalizeLearningPath();
      return true;
    }
    return false;
  }

  static Future<bool> userHasRiasecResult(String userId) async {
    final row =
        await supa
            .from('riasec_results')
            .select('id')
            .eq('user_id', userId)
            .order('taken_at', ascending: false)
            .limit(1)
            .maybeSingle();
    return row != null;
  }

  static Future<bool> userHasNcaeResult(String userId) async {
    final row =
        await supa
            .from('ncae_results')
            .select('id')
            .eq('user_id', userId)
            .order('taken_at', ascending: false)
            .limit(1)
            .maybeSingle();
    return row != null;
  }

  // ---------- Attempts / Limits ----------
  static Future<void> saveQuizAttempt({
    required String quizId,
    required int correct,
    required int total,
    int? durationSec,
    Map<String, dynamic>? meta,
  }) async {
    final uid = authUserId ?? (throw 'Not logged in');
    await supa.from('quiz_attempts').insert({
      'user_id': uid,
      'quiz_id': quizId,
      'correct': correct,
      'total': total,
      if (durationSec != null) 'duration_sec': durationSec,
      if (meta != null) 'meta': meta,
    });
  }

  static Future<bool> canTakeQuiz(String quizId) async {
    final res = await supa.rpc(
      'fn_can_take_quiz',
      params: {'p_quiz_id': quizId},
    );
    if (res == null) return false;
    if (res is bool) return res;
    if (res is num) return res != 0;
    return false;
  }

  static Future<void> setMyQuizOverride({
    required String quizId,
    required int maxAttempts,
  }) async {
    final uid = authUserId ?? (throw 'Not logged in');
    await supa.from('quiz_limits_user').upsert({
      'user_id': uid,
      'quiz_id': quizId,
      'max_attempts': maxAttempts,
    });
  }

  // ======= Exploration helpers (user strand & strands listing) =================

  static Future<String?> getUserStrandOrCourseCode() async {
    final uid = authUserId;
    if (uid == null) return null;

    // Prefer explicit track fields (since your UI stores TECHPRO), then strand, then course.
    final probes = <List<String>>[
      ['track_code'],
      ['track_id'], // might be a UUID → resolve below
      ['strand_code', 'course_code'],
      ['strand_id', 'course_id'],
      ['strand', 'course'],
      ['shs_strand_code', 'course_code'],
      ['shs_strand', 'course_code'],
    ];

    for (final cols in probes) {
      try {
        final row =
            await supa
                .from('users')
                .select(cols.join(','))
                .eq('supabase_id', uid)
                .maybeSingle();
        if (row == null) continue;

        for (final c in cols) {
          final v = row[c];
          if (v == null) continue;

          if (c == 'track_id') {
            final resolved = await _resolveTrackCode(v);
            if (resolved != null && resolved.isNotEmpty) return resolved;
          }

          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      } catch (_) {
        /* keep probing */
      }
    }
    return null;
  }

  static Future<List<Strand>> listStrands({
    List<String> codes = const ['ACADEMIC', 'TECHPRO'],
  }) async {
    // Prefer the base table
    try {
      final q = supa.from('strands').select('*');
      final rows =
          codes.isEmpty
              ? await q
              : (codes.length == 1
                  ? await q.eq('code', codes.first)
                  : await _eqOrIn(q, 'code', codes));
      final list = (rows as List?) ?? const [];
      if (list.isNotEmpty) {
        return list
            .map((e) => Strand.fromRow(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    // Fallback to view if present (maps to column strand_id)
    try {
      final q = supa.from('v_strands_shs').select('*');
      final rows =
          codes.isEmpty
              ? await q
              : (codes.length == 1
                  ? await q.eq('strand_id', codes.first)
                  : await _eqOrIn(q, 'strand_id', codes));
      final list = (rows as List?) ?? const [];
      return list
          .map((e) => Strand.fromRow(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Strand?> getStrandByCode(String code) async {
    // Table first
    try {
      final tblRow =
          await supa.from('strands').select('*').eq('code', code).maybeSingle();
      if (tblRow != null) {
        return Strand.fromRow(Map<String, dynamic>.from(tblRow));
      }
    } catch (_) {}

    // Then view
    try {
      final viewRow =
          await supa
              .from('v_strands_shs')
              .select('*')
              .eq('strand_id', code)
              .maybeSingle();
      if (viewRow != null) {
        return Strand.fromRow(Map<String, dynamic>.from(viewRow));
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> listCoursesForStrandCode(
    String strandCode,
  ) async {
    final rows = await supa
        .from('courses')
        .select(
          'course_id,name,summary,tags,sources,riasec_primary,strand_id,active',
        )
        .eq('strand_id', strandCode)
        .eq('active', true)
        .order('name');
    return (rows as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  // ---- Normalizers -----------------------------------------------------------

  static List<String> _toStringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => '$e').toList();
    if (v is String) {
      // try to parse JSON text like '["a","b"]'
      try {
        final j = jsonDecode(v);
        if (j is List) return j.map((e) => '$e').toList();
      } catch (_) {}
      return v.isEmpty ? const [] : <String>[v];
    }
    return const [];
  }

  static List<SourceLink> _toSources(dynamic v) {
    if (v == null) return const [];
    List list;
    if (v is List) {
      list = v;
    } else if (v is String) {
      try {
        final j = jsonDecode(v);
        if (j is List) {
          list = j;
        } else if (j is Map) {
          list = [j];
        } else {
          return const [];
        }
      } catch (_) {
        return const [];
      }
    } else {
      return const [];
    }

    return list
        .map((e) {
          if (e is Map) {
            return SourceLink.fromJson(Map<String, dynamic>.from(e));
          }
          if (e is String) {
            try {
              final m = jsonDecode(e);
              if (m is Map) {
                return SourceLink.fromJson(Map<String, dynamic>.from(m));
              }
            } catch (_) {}
          }
          return const SourceLink(name: '', url: '');
        })
        .where((s) => s.name.isNotEmpty || s.url.isNotEmpty)
        .toList();
  }

  // Safely extract a list of rows from an RPC response across SDK versions.
  static List<Map<String, dynamic>> _rowsFromRpc(dynamic res) {
    dynamic raw;
    if (res is List) {
      raw = res;
    } else if (res is Map && res['data'] is List) {
      raw = res['data'];
    } else {
      raw = const [];
    }
    return (raw as List)
        .whereType<dynamic>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}

// ===================== TOP-LEVEL HELPERS FOR TRACK COERCION =====================

// Build an OR expression like: code.eq.A,code.eq.B
String _orEq(String column, List<String> values) {
  return values.map((v) => "$column.eq.$v").join(",");
}

// Portable helper: use eq for 1 value, else filter('in', '("a","b")')
Future<List<dynamic>> _eqOrIn(
  PostgrestFilterBuilder<dynamic> q,
  String column,
  List<String> values,
) async {
  if (values.isEmpty) return await q;
  if (values.length == 1) return await q.eq(column, values.first);
  final inList = '(${values.map((v) => '"$v"').join(",")})';
  return await q.filter(column, 'in', inList);
}

// Coerce dynamic → List<String>
List<String> _asStringList(dynamic v) {
  if (v == null) return const [];
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String && v.trim().isNotEmpty) {
    try {
      final d = json.decode(v);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return const [];
}

// Coerce dynamic → List<SourceLink>
List<SourceLink> _asSources(dynamic v) {
  if (v == null) return const [];
  final out = <SourceLink>[];
  if (v is List) {
    for (final e in v) {
      if (e is Map) out.add(SourceLink.fromJson(Map<String, dynamic>.from(e)));
    }
    return out;
  }
  if (v is String && v.trim().isNotEmpty) {
    try {
      final d = json.decode(v);
      if (d is List) {
        for (final e in d) {
          if (e is Map) {
            out.add(SourceLink.fromJson(Map<String, dynamic>.from(e)));
          }
        }
        return out;
      }
    } catch (_) {}
  }
  return const [];
}

/// Normalize various table/view row shapes into what `Track.fromRow` expects.
Map<String, dynamic> _coerceTrackRow(Map<String, dynamic> r) {
  String pickStr(List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = r[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return def;
  }

  List<String> _asStrList(dynamic v) =>
      (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];

  // different name to avoid shadowing the global helper
  List<Map<String, dynamic>> _asSourcesMapList(dynamic v) =>
      (v is List)
          ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : const <Map<String, dynamic>>[];

  return <String, dynamic>{
    'code': pickStr(['code', 'track_code', 'track_id', 'strand_id']),
    'name': pickStr(['name', 'track_name', 'title']),
    'summary': pickStr(['summary', 'description']),
    'badge_color': pickStr(['badge_color'], def: '#1976D2'),
    'gradient_start': pickStr(['gradient_start'], def: '#B3E5FC'),
    'gradient_end': pickStr(['gradient_end'], def: '#81D4FA'),
    'points': _asStrList(r['points']),
    'sample_curriculum': _asStrList(r['sample_curriculum']),
    'entry_roles': _asStrList(r['entry_roles']),
    'skills': _asStrList(r['skills']),
    'sources': _asSourcesMapList(r['sources']),
  };
}
