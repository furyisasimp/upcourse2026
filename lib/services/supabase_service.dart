// lib/services/supabase_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

final supa = Supabase.instance.client;

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

/// Pathway row from public.pathways (kept for future use)
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
    return await supa.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await supa.auth.signOut();
  }

  // ---------- USERS ----------
  static Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = authUserId;
    if (uid == null) return null;

    // Pull exactly what the Profile screen needs + embedded labels.
    final row =
        await supa
            .from('users')
            .select(
              'first_name,middle_name,last_name,grade_level,school,profile_picture,'
              'strand,course,track_id,course_id,'
              'tracks:track_id(track_name),' // embedded track label
              'courses:course_id(name)', // embedded course label
            )
            .eq('supabase_id', uid)
            .maybeSingle();

    if (row == null) return null;

    // Normalise + make safe for the UI (everything as String),
    // and compute robust display labels with fallbacks.
    final m = Map<String, dynamic>.from(row);

    // Helper: embedded object can be a Map or a 1-row List depending on client.
    String _pluckEmbedded(Map data, String relKey, String field) {
      final rel = data[relKey];
      if (rel is Map && rel[field] != null) return rel[field].toString();
      if (rel is List && rel.isNotEmpty && rel.first is Map) {
        final v = (rel.first as Map)[field];
        if (v != null) return v.toString();
      }
      return '';
    }

    // Prefer embedded human names…
    final trackFromRel = _pluckEmbedded(m, 'tracks', 'track_name').trim();
    final courseFromRel = _pluckEmbedded(m, 'courses', 'name').trim();

    // …then fall back to IDs / legacy text if needed.
    final trackFallback =
        (m['track_id']?.toString().trim().isNotEmpty ?? false)
            ? m['track_id'].toString().trim()
            : (m['strand']?.toString().trim() ?? '');

    final courseFallback = (m['course']?.toString().trim() ?? '');

    m['track_label'] = (trackFromRel.isNotEmpty ? trackFromRel : trackFallback);
    m['course_label'] =
        (courseFromRel.isNotEmpty ? courseFromRel : courseFallback);

    // Ensure all string fields the UI reads exist (avoids null noise downstream).
    for (final k in const [
      'first_name',
      'middle_name',
      'last_name',
      'grade_level',
      'school',
      'profile_picture',
      'strand',
      'course',
      'track_id',
      'course_id',
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

  // ==== START: Exploration fetchers (user strand, strands, courses/pathways) ====
  static Future<String?> getUserStrandOrCourseCode() async {
    final uid = authUserId;
    if (uid == null) return null;

    final List<List<String>> columnSets = [
      ['strand_code', 'course_code'],
      ['strand_id', 'course_id'],
      ['strand', 'course'],
      ['shs_strand_code', 'course_code'],
      ['shs_strand', 'course_code'],
    ];

    for (final cols in columnSets) {
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
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Future<List<Strand>> listStrands({
    List<String> codes = const ['STEM', 'ABM', 'GAS', 'TECHPRO'],
  }) async {
    final sel = supa.from('v_strands_shs').select('*');

    List<dynamic> rows;
    if (codes.isEmpty) {
      rows = await sel;
    } else if (codes.length == 1) {
      rows = await sel.eq('strand_id', codes.first);
    } else {
      final orExpr = codes.map((c) => 'strand_id.eq.$c').join(',');
      rows = await sel.or(orExpr);
    }

    final list = (rows as List?) ?? const [];
    return list
        .map((e) => Strand.fromRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Strand?> getStrandByCode(String code) async {
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
    final tblRow =
        await supa.from('strands').select('*').eq('code', code).maybeSingle();
    if (tblRow == null) return null;
    return Strand.fromRow(Map<String, dynamic>.from(tblRow));
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

  static Future<List<PathwayMatch>> listPathwaysForStrand(
    String strandCode,
  ) async {
    final links = await supa
        .from('strand_pathways')
        .select('pathway_code, match_label, sort_order')
        .eq('strand_code', strandCode)
        .order('sort_order', ascending: true);

    final linkList = (links as List?) ?? const [];
    if (linkList.isEmpty) return const [];

    final codes =
        linkList
            .map((e) => (e as Map)['pathway_code']?.toString())
            .where((e) => e != null && e.isNotEmpty)
            .cast<String>()
            .toList();

    if (codes.isEmpty) return const [];

    final query = supa.from('pathways').select('*');
    List<dynamic> rows;
    if (codes.length == 1) {
      rows = await query.eq('code', codes.first);
    } else {
      final orExpr = codes.map((c) => 'code.eq.$c').join(',');
      rows = await query.or(orExpr);
    }

    final byCode = <String, Pathway>{
      for (final r in ((rows as List?) ?? const []))
        (r as Map)['code'].toString(): Pathway.fromRow(
          Map<String, dynamic>.from(r),
        ),
    };

    final out = <PathwayMatch>[];
    for (final l in linkList) {
      final m = Map<String, dynamic>.from(l as Map);
      final pCode = (m['pathway_code'] ?? '').toString();
      final label = (m['match_label'] ?? 'Match').toString();
      final p = byCode[pCode];
      if (p != null) out.add(PathwayMatch(p, label));
    }
    return out;
  }
  // ==== END: Exploration fetchers ====

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
    Map<int, int>? answers,
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
        final pools = Map<String, dynamic>.from(decoded['pools']);

        List<Map<String, dynamic>> _asList(String k) {
          final v = pools[k];
          if (v is List) {
            return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
          return <Map<String, dynamic>>[];
        }

        final easy = _asList('easy');
        final medium = _asList('medium');
        final hard = _asList('hard');

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

          counts['easy'] = counts['easy']!.clamp(0, easy.length);
          counts['medium'] = counts['medium']!.clamp(0, medium.length);
          counts['hard'] = counts['hard']!.clamp(0, hard.length);

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
            'easy': easy.length - counts['easy']!,
            'medium': medium.length - counts['medium']!,
            'hard': hard.length - counts['hard']!,
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
          final all = <Map<String, dynamic>>[...easy, ...medium, ...hard]
            ..shuffle();
          return all.take(total.clamp(0, all.length)).toList();
        }

        List<T> pick<T>(List<T> list, int n) {
          if (n <= 0 || list.isEmpty) return [];
          final copy = List<T>.of(list)..shuffle();
          return copy.take(n.clamp(0, copy.length)).toList();
        }

        var selected = <Map<String, dynamic>>[
          ...pick(easy, counts['easy']!),
          ...pick(medium, counts['medium']!),
          ...pick(hard, counts['hard']!),
        ];

        if (selected.length < total) {
          final used = selected.map((q) => q['id'] ?? q['question']).toSet();
          final leftovers = <Map<String, dynamic>>[
            ...easy.where((q) => !used.contains(q['id'] ?? q['question'])),
            ...medium.where((q) => !used.contains(q['id'] ?? q['question'])),
            ...hard.where((q) => !used.contains(q['id'] ?? q['question'])),
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

  static Future<List<FileObject>> listPdfFiles() async {
    return await supa.storage.from('my-study-guides').list(path: '');
  }

  static Future<String?> getPdfUrl(String key) async {
    return supa.storage.from('my-study-guides').getPublicUrl(key);
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
        // ignore: avoid_print
        print('getFileUrl failed for $bucket/$path: $e');
        return null;
      }
    }
  }

  // ---- QUIZ: BANK + TOS LOADER ----
  static Future<List<Map<String, dynamic>>> fetchQuizWithTOS({
    required String quizId,
    String bucket = 'quizzes',
    int? seed,
    int totalOverride = 10,
  }) async {
    final bankBytes = await supa.storage.from(bucket).download('$quizId.json');
    final dynamic bankDecoded = json.decode(utf8.decode(bankBytes));
    final List<Map<String, dynamic>> bank =
        bankDecoded is List
            ? (bankDecoded as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : List<Map<String, dynamic>>.from((bankDecoded['questions'] ?? []));

    if (bank.isEmpty) return [];

    final int target = min(totalOverride, bank.length);

    Map<String, dynamic>? specData;
    try {
      final tosBytes = await supa.storage
          .from(bucket)
          .download('${quizId}_tos.json');
      specData = json.decode(utf8.decode(tosBytes)) as Map<String, dynamic>;
    } catch (_) {
      final rnd = seed == null ? Random() : Random(seed);
      final copy = List<Map<String, dynamic>>.of(bank)..shuffle(rnd);
      return copy.take(target).toList();
    }

    final Map<String, List<Map<String, dynamic>>> byDiff = {
      'easy': [],
      'medium': [],
      'hard': [],
    };
    for (final q in bank) {
      final d = (q['difficulty'] ?? '').toString().toLowerCase();
      if (byDiff.containsKey(d)) byDiff[d]!.add(q);
    }

    final rnd = seed == null ? Random() : Random(seed);
    List<T> pick<T>(List<T> list, int n) {
      if (n <= 0 || list.isEmpty) return [];
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

    final bool isWeighted =
        (specData['mode']?.toString().toLowerCase() == 'weighted') ||
        (specData.containsKey('weights'));

    var counts = <String, int>{'easy': 0, 'medium': 0, 'hard': 0};

    if (!isWeighted) {
      counts['easy'] = (specData['easy'] ?? 0) as int;
      counts['medium'] = (specData['medium'] ?? 0) as int;
      counts['hard'] = (specData['hard'] ?? 0) as int;

      for (final k in counts.keys) {
        counts[k] = counts[k]!.clamp(0, byDiff[k]!.length);
      }

      int sum = counts.values.fold(0, (a, b) => a + b);
      while (sum > target) {
        for (final k in ['hard', 'medium', 'easy']) {
          if (counts[k]! > 0 && sum > target) {
            counts[k] = counts[k]! - 1;
            sum--;
          }
        }
      }
    } else {
      final Map<String, dynamic> wRaw = Map<String, dynamic>.from(
        specData['weights'] ?? {},
      );
      final Map<String, double> weights = {
        'easy': (wRaw['easy'] ?? 1.0).toDouble(),
        'medium': (wRaw['medium'] ?? 1.0).toDouble(),
        'hard': (wRaw['hard'] ?? 1.0).toDouble(),
      };

      final Map<String, dynamic> minRaw = Map<String, dynamic>.from(
        specData['min'] ?? {},
      );
      final Map<String, dynamic> maxRaw = Map<String, dynamic>.from(
        specData['max'] ?? {},
      );

      final avail = <String, int>{
        'easy': byDiff['easy']!.length,
        'medium': byDiff['medium']!.length,
        'hard': byDiff['hard']!.length,
      };

      var minC = <String, int>{
        'easy':
            (minRaw['easy'] ?? 0) is int
                ? minRaw['easy'] as int
                : int.tryParse('${minRaw['easy']}') ?? 0,
        'medium':
            (minRaw['medium'] ?? 0) is int
                ? minRaw['medium'] as int
                : int.tryParse('${minRaw['medium']}') ?? 0,
        'hard':
            (minRaw['hard'] ?? 0) is int
                ? minRaw['hard'] as int
                : int.tryParse('${minRaw['hard']}') ?? 0,
      };
      var maxC = <String, int>{
        'easy':
            (maxRaw['easy'] ?? target) is int
                ? maxRaw['easy'] as int
                : int.tryParse('${maxRaw['easy']}') ?? target,
        'medium':
            (maxRaw['medium'] ?? target) is int
                ? maxRaw['medium'] as int
                : int.tryParse('${maxRaw['medium']}') ?? target,
        'hard':
            (maxRaw['hard'] ?? target) is int
                ? maxRaw['hard'] as int
                : int.tryParse('${maxRaw['hard']}') ?? target,
      };

      for (final k in ['easy', 'medium', 'hard']) {
        minC[k] = min(minC[k]!, avail[k]!);
        maxC[k] = min(maxC[k]!, avail[k]!);
      }

      int sumMin = minC.values.fold(0, (a, b) => a + b);
      while (sumMin > target) {
        for (final k in ['hard', 'medium', 'easy']) {
          if (minC[k]! > 0) {
            minC[k] = minC[k]! - 1;
            sumMin--;
            break;
          }
        }
      }

      counts = {
        'easy': minC['easy']!,
        'medium': minC['medium']!,
        'hard': minC['hard']!,
      };
      int remaining = target - counts.values.fold(0, (a, b) => a + b);

      double sumWeightsFor(Iterable<String> ks) {
        double s = 0;
        for (final k in ks) {
          final v = weights[k] ?? 0;
          if (v > 0) s += v;
        }
        return s > 0 ? s : ks.length.toDouble();
      }

      String drawWeighted(List<String> candidates) {
        final positive =
            candidates.where((k) => (weights[k] ?? 0) > 0).toList();
        final pool = positive.isNotEmpty ? positive : candidates;
        final totalW = sumWeightsFor(pool);
        double r = rnd.nextDouble() * totalW;
        for (final k in pool) {
          final w =
              (weights[k] ?? 0) > 0 ? (weights[k]!) : (totalW / pool.length);
          if (r < w) return k;
          r -= w;
        }
        return pool.last;
      }

      while (remaining > 0) {
        final cands =
            [
              'easy',
              'medium',
              'hard',
            ].where((k) => counts[k]! < maxC[k]!).toList();
        if (cands.isEmpty) break;
        final pickK = drawWeighted(cands);
        counts[pickK] = counts[pickK]! + 1;
        remaining--;
      }
    }

    var selected = <Map<String, dynamic>>[
      ...pick(byDiff['easy']!, counts['easy']!),
      ...pick(byDiff['medium']!, counts['medium']!),
      ...pick(byDiff['hard']!, counts['hard']!),
    ];

    if (selected.length < target) {
      final used = selected.map((q) => q['id'] ?? q['text']).toSet();
      final leftover =
          bank.where((q) => !used.contains(q['id'] ?? q['text'])).toList();
      selected.addAll(pick(leftover, target - selected.length));
    } else if (selected.length > target) {
      selected.shuffle(rnd);
      selected = selected.take(target).toList();
    }

    selected.shuffle(rnd);
    return selected;
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
          .whereType<Map>() // guard against odd payloads
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

  // Use the paramless API wrapper you created: api.compute_learning_path
  static Future<Map<String, dynamic>?> previewLearningPath() async {
    final res = await supa.rpc('compute_learning_path_preview'); // no params
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty)
      return Map<String, dynamic>.from(res.first);
    return null;
  }

  // Must pass the uid to the uuid-version function
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
      // use new recommender preview
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
            .maybeSingle(); // -> Map<String, dynamic>? or null
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
}
