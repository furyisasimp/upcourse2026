// lib/quiz_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Add this import for Supabase instance

// Inline PDFs (+ open externally)
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

// Anti-cheat (Android/iOS/macOS only)
import 'package:screen_capture_event/screen_capture_event.dart';

import 'home_screen.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/services/quiz_security_service.dart';
import 'package:career_roadmap/services/ai_quiz_analysis_service.dart'; // Add this import

class Question {
  final String text;
  final List<String> options;

  // question_id so we can store answers by ID
  final String? questionId;

  // text-entry support
  final bool isText; // true when question_type == "text"
  final List<String> answerTexts; // accepted answers for text questions
  final bool textAnyCase; // loose/case-insensitive if true

  // media (optional; passed through from service)
  final List<Map<String, dynamic>> files; // pdfs or other files
  final List<Map<String, dynamic>> images; // image attachments

  // Single-answer legacy
  final int? rawIndex; // from answer_index / correct_index
  final String? correctText; // from correct / answer

  // Multi-answer support
  final bool allowMultiple; // from allow_multiple
  final List<int> correctIndexes; // from correct_answers (0-based)

  final String? explanation; // optional

  Question({
    required this.text,
    required this.options,
    this.questionId,
    this.isText = false,
    this.answerTexts = const <String>[],
    this.textAnyCase = true,
    this.rawIndex,
    this.correctText,
    this.explanation,
    this.allowMultiple = false,
    this.correctIndexes = const <int>[],
    this.files = const <Map<String, dynamic>>[],
    this.images = const <Map<String, dynamic>>[],
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final dynamic idxRaw = json['answer_index'] ?? json['correct_index'];
    final int? idx =
        (idxRaw is num) ? idxRaw.toInt() : int.tryParse('${idxRaw ?? ''}');
    final dynamic txtRaw = json['correct'] ?? json['answer'];
    final String? txt =
        (txtRaw is String && txtRaw.trim().isNotEmpty) ? txtRaw.trim() : null;

    final bool multi = json['allow_multiple'] == true;
    final List<int> idxs =
        (json['correct_answers'] is List)
            ? (json['correct_answers'] as List)
                .where((e) => e is num)
                .map((e) => (e as num).toInt())
                .toList()
            : const <int>[];

    // pass-through media
    List<Map<String, dynamic>> _listOfMap(dynamic v) =>
        (v is List)
            ? v
                .whereType<dynamic>()
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];

    // Detect text questions and lift accepted answers from choices
    final String qType = (json['question_type'] ?? '').toString().toLowerCase();
    final bool isText = json['is_text'] == true || qType == 'text';
    final List<String> choices =
        ((json['options'] ?? json['choices']) as List? ?? const [])
            .map((e) => '$e')
            .toList();

    return Question(
      text: (json['text'] ?? json['question_text'] ?? '').toString(),
      options: isText ? const <String>[] : choices,
      questionId: (json['question_id']?.toString()),
      isText: isText,
      answerTexts: isText ? choices : const <String>[],
      textAnyCase:
          (json['text_any_case'] == null)
              ? true
              : (json['text_any_case'] == true),
      // legacy + media
      rawIndex: idx,
      correctText: txt,
      explanation:
          (json['explanation'] is String &&
                  (json['explanation'] as String).trim().isNotEmpty)
              ? (json['explanation'] as String).trim()
              : null,
      allowMultiple: multi,
      correctIndexes: idxs,
      files: _listOfMap(json['files']),
      images: _listOfMap(json['images']),
    );
  }

  int? correctIndex0() {
    if (rawIndex == null) return null;
    final n = options.length;
    final idx = rawIndex!;
    if (idx >= 0 && idx < n) return idx; // already 0-based
    final asZero = idx - 1; // maybe 1-based
    if (asZero >= 0 && asZero < n) return asZero;
    return null;
  }
}

class QuizScreen extends StatefulWidget {
  final String categoryId; // legacy or ABM/GAS/STEM/TECHPRO
  final String storagePath; // Add this
  const QuizScreen({
    Key? key,
    required this.categoryId,
    required this.storagePath,
  }) : super(key: key);

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // --- Category meta (UI)
  static const _categoryMeta = {
    'ABM': (
      title: 'ABM — Business & Finance',
      colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)],
      icon: Icons.payments_outlined,
    ),
    'GAS': (
      title: 'GAS — General Academic Strand',
      colors: [Color(0xFFD1C4E9), Color(0xFFB39DDB)],
      icon: Icons.menu_book_outlined,
    ),
    'STEM': (
      title: 'STEM — Science & Technology',
      colors: [Color(0xFFA5D6A7), Color(0xFF66BB6A)],
      icon: Icons.science_outlined,
    ),
    'TECHPRO': (
      title: 'TechPro — TVL / Tech-Voc',
      colors: [Color(0xFFFFCC80), Color(0xFFFFA726)],
      icon: Icons.build_circle_outlined,
    ),
  };

  String get _programId {
    final id = widget.categoryId.trim();
    if (id.toLowerCase().contains('abm')) return 'ABM';
    if (id.toLowerCase().contains('stem')) return 'STEM';
    if (id.toLowerCase().contains('gas')) return 'GAS';
    if (id.toLowerCase().contains('tech')) return 'TECHPRO';
    return id.toUpperCase();
  }

  // --- State
  final Map<int, dynamic> _answers = {}; // String or Set<int>
  final List<Question> _questions = [];
  final List<GlobalKey> _qKeys = [];
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _submitted = false; // results view mode (reveals correctness)
  String? _loadError;

  // gating
  bool _blocked = false;
  String? _blockReason;

  // results/attempt metadata
  Map<String, dynamic>? _latestAttempt; // raw attempt row
  DateTime? _submittedAt;
  DateTime? _returnedAt;
  bool get _awaitingReview =>
      _latestAttempt != null && _latestAttempt!['is_returned'] != true;

  // scoring (used when returned)
  int _correct = 0;
  int _total = 0;
  int _scorePct = 0;

  // timer
  late final DateTime _startedAt = DateTime.now();
  int _elapsedSec = 0;
  Timer? _ticker;

  // Anti-cheat (plugin is platform-gated)
  ScreenCaptureEvent? _screenCapture;
  int _cheatStrikes = 0;
  static const int _cheatMax = 3;
  bool _securityBusy = false; // debounce for security snackbars
  bool _leaving = false; // guard against late events while exiting

  // Cached messenger
  ScaffoldMessengerState? _scaffoldMessenger;

  // Add this new variable
  bool _moduleDialogShown = false;

  bool get _supportsScreenCapture =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  // EXACT quiz_id from the JSON (case preserved)
  String? _quizIdRawFromJson;

  // Extract quiz_id directly from loaded item maps (case preserved)
  String? _extractQuizIdFromSelected(List<Map<String, dynamic>> items) {
    String? pick(Map<String, dynamic> m) {
      final v = m['quiz_id'] ?? m['quizId'];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      final meta = m['meta'];
      if (meta is Map && meta['quiz_id'] is String) {
        final s = (meta['quiz_id'] as String).trim();
        if (s.isNotEmpty) return s;
      }
      final header = m['header'];
      if (header is Map && header['quiz_id'] is String) {
        final s = (header['quiz_id'] as String).trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    if (items.isEmpty) return null;
    // robust: try first, else first non-empty candidate
    final firstPick = pick(items.first);
    if (firstPick != null && firstPick.isNotEmpty) return firstPick;
    final cand = items
        .map(pick)
        .firstWhere((s) => s != null && s!.isNotEmpty, orElse: () => null);
    return cand;
  }

  @override
  void initState() {
    super.initState();
    if (_supportsScreenCapture) {
      try {
        _screenCapture = ScreenCaptureEvent();
        _initScreenCapture();
      } catch (e) {
        debugPrint('screen_capture_event init skipped: $e');
        _screenCapture = null;
      }
    }
    _checkGateAndLoad();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _screenCapture?.dispose();
    _scroll.dispose();
    _scaffoldMessenger?.clearSnackBars();
    super.dispose();
  }

  void _prepareForExit() {
    _leaving = true;
    _ticker?.cancel();
    _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
    _scaffoldMessenger?.clearSnackBars();
  }

  Future<void> _initScreenCapture() async {
    try {
      final prior = await QuizSecurityService.getStrikes(_programId);
      final locked = await QuizSecurityService.isLocked(_programId);
      if (!mounted) return;
      setState(() {
        _cheatStrikes = prior;
        if (locked) {
          _blocked = true;
          _blockReason =
              'This quiz is locked due to prior security violations.';
          _loading = false;
        }
      });
      if (locked) return;
    } catch (_) {
      // ignore – fail-open
    }

    _screenCapture?.addScreenShotListener((_) {
      _handleSecurityEvent('screenshot');
    });

    _screenCapture?.addScreenRecordListener((isRecording) {
      if (isRecording == true) {
        _handleSecurityEvent('screen_record_start');
      }
    });
  }

  Future<void> _handleSecurityEvent(String kind) async {
    if (!mounted || _submitted || _blocked || _securityBusy || _leaving) return;

    _securityBusy = true;
    final next = _cheatStrikes + 1;
    final willLock = next >= _cheatMax;

    try {
      try {
        await QuizSecurityService.recordStrike(
          quizId: _programId,
          strikes: next,
          lock: willLock,
          meta: {
            'kind': kind,
            'at': DateTime.now().toIso8601String(),
            'app': 'mobile',
            'screen': 'QuizScreen',
          },
        );
      } catch (_) {}

      if (!mounted || _leaving) return;
      setState(() => _cheatStrikes = next);

      if (willLock) {
        if (!mounted || _leaving) return;
        setState(() {
          _blocked = true;
          _blockReason =
              'Quiz locked: 3 security violations detected (screenshots/recording).';
        });
        if (!mounted || _leaving) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: const Text(
                  'Quiz Locked',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                content: const Text(
                  'Multiple screen capture attempts were detected. This quiz is now locked.',
                  style: TextStyle(fontFamily: 'Inter'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  ),
                ],
              ),
        );
      } else {
        if (!mounted || _leaving) return;
        final remaining = (_cheatMax - next).clamp(0, _cheatMax);
        _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
        _scaffoldMessenger?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text(
              '⚠️ Screenshot detected. '
              '${remaining == 0 ? 'Next will lock the quiz.' : '$remaining strike${remaining == 1 ? '' : 's'} left.'}',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
          ),
        );
      }
    } finally {
      _securityBusy = false;
    }
  }

  Future<void> _checkGateAndLoad() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _blocked = false;
        _blockReason = null;
        _loadError = null;
        _latestAttempt = null;
        _submitted = false;
        _returnedAt = null;
        _submittedAt = null;
      });
    }

    try {
      // high-level strand gate
      final allowed = await SupabaseService.canTakeBankQuiz(_programId);
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _loading = false;
          _blocked = true;
          _blockReason = 'This quiz is locked (completed or restricted).';
        });
        return;
      }

      final cheatLocked = await QuizSecurityService.isLocked(_programId);
      if (!mounted) return;
      if (cheatLocked) {
        setState(() {
          _loading = false;
          _blocked = true;
          _blockReason =
              'This quiz is locked due to prior security violations.';
        });
        return;
      }

      // Load ALL questions (no sampling)
      // Load ALL questions using the exact storage_path
      final selected = await SupabaseService.fetchQuizJsonByPath(
        widget.storagePath,
      ); // Use storagePath directly
      if (!mounted) return;

      if (selected == null || selected['questions'] == null) {
        throw Exception('Quiz not found at ${widget.storagePath}');
      }

      // Extract questions from the JSON
      final questionsJson = selected['questions'] as List;
      _questions
        ..clear()
        ..addAll(
          questionsJson.map(
            (e) => Question.fromJson(Map<String, dynamic>.from(e)),
          ),
        );
      _qKeys
        ..clear()
        ..addAll(List.generate(_questions.length, (_) => GlobalKey()));

      // Exact quiz_id from JSON (case preserved) - directly from the top-level Map
      _quizIdRawFromJson =
          (selected['quiz_id'] as String?) ?? (selected['quizId'] as String?);

      // --- Check latest attempt for this exact quiz_id ---
      final attempt = await SupabaseService.getLatestAttemptForQuiz(
        quizIdExact: _quizIdRawFromJson ?? _programId,
        altIdForFallback: _programId, // legacy rows may have used route id
      );
      _latestAttempt = attempt;

      if (attempt != null) {
        // Use columns from your schema
        final finishedAtStr = '${attempt['finished_at'] ?? ''}';
        final returnedAtStr = '${attempt['returned_at'] ?? ''}';
        _submittedAt = DateTime.tryParse(finishedAtStr);
        _returnedAt = DateTime.tryParse(returnedAtStr);

        // If returned, switch to results view and hydrate answers
        if (attempt['is_returned'] == true ||
            '${attempt['status']}'.toLowerCase() == 'returned') {
          _submitted = true;
          _correct =
              (attempt['correct'] is num)
                  ? (attempt['correct'] as num).toInt()
                  : _correct;
          _total =
              (attempt['total'] is num)
                  ? (attempt['total'] as num).toInt()
                  : _questions.length;
          final sc =
              (attempt['score'] is num)
                  ? (attempt['score'] as num).toInt()
                  : null;
          _scorePct = sc ?? (_total > 0 ? ((_correct * 100) ~/ _total) : 0);

          // Fill _answers from attempt JSON so the UI can render choices
          final Map<String, dynamic> ansJson =
              (attempt['answers'] is Map)
                  ? Map<String, dynamic>.from(attempt['answers'] as Map)
                  : <String, dynamic>{};
          _hydrateAnswersFromAttempt(ansJson);
          // NEW: Check for low score and offer module generation (only once per load)
          if (!_moduleDialogShown && _scorePct < 70) {
            _moduleDialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showModuleOfferDialog();
            });
          }
        } else {
          // Awaiting review -> lock answering, show Awaiting screen
          _blocked = true;
          final when =
              _submittedAt != null ? ' on ${_fmtDT(_submittedAt!)}' : '';
          _blockReason =
              'This attempt was already submitted$when and is awaiting your teacher’s review.';
        }
      }
      // ----------------------------------------------------

      // start screen timer (only used during answering)
      _ticker?.cancel();
      _elapsedSec = 0;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _leaving) return;
        if (_submitted) {
          _ticker?.cancel();
          return;
        }
        setState(() {
          _elapsedSec = DateTime.now().difference(_startedAt).inSeconds;
        });
      });

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  // Turn an attempt.answers payload back into this screen's _answers map
  void _hydrateAnswersFromAttempt(Map<String, dynamic> ansJson) {
    // Build a lookup: question_id (or 'q_i' fallback) -> index
    final Map<String, int> idToIndex = {};
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final qid = (q.questionId ?? '').trim();
      idToIndex[qid.isNotEmpty ? qid : 'q_$i'] = i;
    }

    for (final entry in ansJson.entries) {
      final key = entry.key;
      final val = entry.value;
      final idx = idToIndex[key];
      if (idx == null) continue;
      final q = _questions[idx];

      if (q.isText) {
        // accepted formats: string, {text: "..."}
        if (val is String) {
          _answers[idx] = val;
        } else if (val is Map && val['text'] is String) {
          _answers[idx] = val['text'];
        } else {
          _answers[idx] = '';
        }
        continue;
      }

      if (q.allowMultiple) {
        // acceptable val: [indices], ["labels"...], {idx:[...], text:[...]}
        final Set<int> picked = <int>{};

        if (val is List) {
          if (val.isNotEmpty && val.first is String) {
            // list of labels
            for (final s in val.cast<String>()) {
              final i = q.options.indexOf(s);
              if (i >= 0) picked.add(i);
            }
          } else {
            // list of indices
            for (final n in val) {
              if (n is num) {
                final i = n.toInt();
                if (i >= 0 && i < q.options.length) picked.add(i);
              }
            }
          }
        } else if (val is Map) {
          final idxs = val['idx'];
          final texts = val['text'];
          if (idxs is List) {
            for (final n in idxs) {
              if (n is num) {
                final i = n.toInt();
                if (i >= 0 && i < q.options.length) picked.add(i);
              }
            }
          } else if (texts is List) {
            for (final s in texts.cast<String>()) {
              final i = q.options.indexOf(s);
              if (i >= 0) picked.add(i);
            }
          }
        }
        _answers[idx] = picked;
      } else {
        // single-choice acceptable val: index, label, {idx:.., text:..}
        if (val is num) {
          final i = val.toInt();
          if (i >= 0 && i < q.options.length) {
            _answers[idx] = q.options[i];
          }
        } else if (val is String) {
          // label
          if (val.isNotEmpty) _answers[idx] = val;
        } else if (val is Map) {
          if (val['text'] is String && (val['text'] as String).isNotEmpty) {
            _answers[idx] = val['text'];
          } else if (val['idx'] is num) {
            final i = (val['idx'] as num).toInt();
            if (i >= 0 && i < q.options.length) {
              _answers[idx] = q.options[i];
            }
          }
        }
      }
    }
  }

  // Canonicalization for loose comparison
  String _canon(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    final squashed = t.replaceAll(RegExp(r'\s+'), ' ');
    final stripped = squashed.replaceAll(RegExp(r'[^\w\s]'), '');
    return stripped;
  }

  bool _isAnswered(int i) {
    final a = _answers[i];
    if (a == null) return false;
    if (a is String) return a.trim().isNotEmpty;
    if (a is Set<int>) return a.isNotEmpty;
    return false;
  }

  // ---------- Submit "for review" only (no correctness reveal here) ----------
  Future<void> _submit() async {
    if (_answers.length != _questions.length ||
        !_questions.asMap().keys.every(_isAnswered)) {
      final firstUnanswered = List.generate(
        _questions.length,
        (i) => i,
      ).firstWhere((i) => !_isAnswered(i), orElse: () => 0);
      _scrollTo(firstUnanswered);
      if (!mounted) return;
      _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
      _scaffoldMessenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Please answer all questions before submitting.',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      return;
    }

    // Build answers keyed by question_id (or fallback key)
    // Save labels "as is" for choices; free-text as typed.
    final Map<String, dynamic> userAnswers = {};
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final qid = (q.questionId ?? '').trim();
      final key = qid.isNotEmpty ? qid : 'q_$i';

      final ans = _answers[i];

      if (q.isText) {
        userAnswers[key] = (ans is String) ? ans : '';
        continue;
      }

      if (q.allowMultiple) {
        final selectedIdxs = (ans is Set<int>) ? ans : <int>{};
        final labels = <String>[];
        for (var idx = 0; idx < q.options.length; idx++) {
          if (selectedIdxs.contains(idx)) labels.add(q.options[idx]);
        }
        userAnswers[key] = labels; // e.g., ["A", "C"]
      } else {
        final sel = (ans is String) ? ans.trim() : '';
        userAnswers[key] = sel.isNotEmpty ? sel : null; // "B"
      }
    }

    final elapsed = DateTime.now().difference(_startedAt).inSeconds;

    try {
      await SupabaseService.saveAttemptForReview(
        quizIdOrPath: _programId, // route/program id
        quizIdFromJson: _quizIdRawFromJson, // EXACT JSON id wins if present
        userAnswers: userAnswers,
        durationSec: elapsed,
      );
    } catch (e) {
      if (!mounted) return;
      _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
      _scaffoldMessenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: Text(
            'Failed to submit for review: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    // Awaiting-review: freeze UI, keep answers visible, no auto-exit
    setState(() {
      _submitted = false; // do not reveal correctness
      _blocked = true; // disables editing + hides the submit button
      _submittedAt = DateTime.now();
      _latestAttempt = {
        ...?_latestAttempt,
        'is_returned': false,
        'status': 'pending_review',
        'finished_at': _submittedAt!.toIso8601String(),
      };
      _blockReason =
          'Submitted on ${_fmtDT(_submittedAt!)} • Awaiting teacher review.';
    });

    // stop ticking while blocked
    _ticker?.cancel();

    // toast
    _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
    _scaffoldMessenger?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Submitted for review. You’ll see your score once it’s returned.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
      ),
    );

    // make the awaiting banner visible
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // NOTE: removed the old delay + _returnHome() to prevent auto-exit
  }

  void _scrollTo(int index) {
    if (index < 0 || index >= _qKeys.length) return;
    final key = _qKeys[index];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _returnHome() {
    if (!mounted) return;
    _prepareForExit();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );
  }

  Future<bool> _confirmExit() async {
    if (_submitted) return true;
    if (!mounted) return true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Exit Quiz?',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              'If you leave now, your answers will not be saved. Are you sure you want to exit?',
              style: TextStyle(fontFamily: 'Inter'),
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Color(0xFF3EB6FF),
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Exit',
                  style: TextStyle(fontFamily: 'Inter'),
                ),
              ),
            ],
          ),
    );
    return shouldExit ?? false;
  }

  Future<void> _requestExit() async {
    if (!mounted) return;
    final ok = await _confirmExit();
    if (!mounted) return;
    if (ok) {
      _prepareForExit();
      if (context.mounted) Navigator.pop(context);
    }
  }

  // NEW: Helper to show module offer dialog
  Future<void> _showModuleOfferDialog() async {
    if (!mounted) return;
    final generate = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Improve Your Skills'),
            content: Text(
              'You scored $_scorePct% on this quiz, which is below passing. Want us to create a personalized module to help you review and improve?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No Thanks'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes, Generate Module'),
              ),
            ],
          ),
    );
    if (generate == true) {
      // Trigger AI module generation
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final module = await AIQuizAnalysisService.analyzeAndGenerateModule(
          userId,
        );
        if (module != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Personalized module created: ${module['title']}'),
            ),
          );
          // Optionally navigate to skills_screen.dart
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to generate module. Try again later.'),
            ),
          );
        }
      }
    }
  }

  (List<Color> colors, IconData icon, String title) _meta() {
    final meta = _categoryMeta[_programId];
    if (meta != null) return (meta.colors, meta.icon, meta.title);
    return (
      [const Color(0xFFB3E5FC), const Color(0xFF81D4FA)],
      Icons.quiz_outlined,
      'Quiz — $_programId',
    );
  }

  String _fmtDT(DateTime dt) {
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final (colors, icon, titleText) = _meta();
    _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);

    final answered =
        _answers.entries.where((e) {
          final v = e.value;
          if (v is String) return v.trim().isNotEmpty;
          if (v is Set<int>) return v.isNotEmpty;
          return false;
        }).length;

    final total = _questions.length;
    final progress = total == 0 ? 0.0 : answered / total;

    final width = MediaQuery.of(context).size.width;
    final hPad =
        width >= 1100
            ? 24.0
            : width >= 700
            ? 18.0
            : 12.0;

    final awaitingBanner =
        (_latestAttempt != null && _latestAttempt!['is_returned'] != true);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(
            _submitted
                ? 'Results Overview'
                : awaitingBanner
                ? 'Awaiting Review'
                : titleText,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading:
              _submitted || _blocked
                  ? null
                  : IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _requestExit,
                  ),
        ),

        // Hide submit button when blocked/awaiting or viewing results
        bottomNavigationBar:
            _loading ||
                    _submitted ||
                    _questions.isEmpty ||
                    _blocked ||
                    (_latestAttempt != null &&
                        _latestAttempt!['is_returned'] != true)
                ? null
                : SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          'Submit Quiz',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        onPressed:
                            answered == _questions.length ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          disabledBackgroundColor: Colors.black26,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? _ErrorState(message: _loadError!, onRetry: _checkGateAndLoad)
                : _blocked && _awaitingReview
                ? _AwaitingState(
                  icon: icon,
                  colors: colors,
                  submittedAt: _submittedAt,
                  onGoHome: _returnHome,
                  onRequestRetry: _checkGateAndLoad,
                )
                : _blocked && !_awaitingReview
                ? _BlockedState(
                  icon: icon,
                  colors: colors,
                  reason:
                      _blockReason ?? 'This quiz is locked after completion.',
                  onGoHome: _returnHome,
                  onRequestRetry: _checkGateAndLoad,
                )
                : _questions.isEmpty
                ? const _EmptyState()
                : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 8),
                      child: _HeaderCard(
                        colors: colors,
                        icon: icon,
                        submitted: _submitted,
                        correct: _correct,
                        total: _total,
                        scorePct: _scorePct,
                        progressValue:
                            _submitted
                                ? ((_scorePct / 100.0).clamp(0.0, 1.0)
                                    as double)
                                : progress,
                        label:
                            _submitted
                                ? 'Score: $_correct/$_total ($_scorePct%)'
                                : 'Progress',
                        sublabel:
                            _submitted
                                ? (_returnedAt != null
                                    ? 'Returned on ${_fmtDT(_returnedAt!)}'
                                    : 'Results saved to your progress')
                                : '$answered of $total answered',
                        elapsedSec: _elapsedSec,
                      ),
                    ),
                    if (!_submitted && !_blocked && _cheatStrikes > 0)
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE0E0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.redAccent.withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Security warning: $_cheatStrikes/$_cheatMax '
                                  '${_cheatStrikes >= _cheatMax - 1 ? '— Next violation will lock the quiz.' : '— Avoid screenshots or recording.'}',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_questions.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 6),
                        child: _IndexBar(
                          count: _questions.length,
                          isSubmitted: _submitted,
                          color: colors.last,
                          answered: _answers,
                          isCorrect: (i) {
                            if (!_submitted) return null;
                            final q = _questions[i];
                            final ans = _answers[i];
                            if (ans == null) return false;

                            // TEXT
                            if (q.isText) {
                              final List<String> pool =
                                  q.answerTexts.isNotEmpty
                                      ? List<String>.from(q.answerTexts)
                                      : (q.correctText != null
                                          ? <String>[q.correctText!]
                                          : const <String>[]);

                              final Set<String> allowed =
                                  pool
                                      .map<String>(
                                        (a) =>
                                            q.textAnyCase
                                                ? _canon(a)
                                                : a.trim(),
                                      )
                                      .toSet();

                              final String test =
                                  q.textAnyCase
                                      ? _canon(ans as String)
                                      : (ans as String).trim();
                              return allowed.contains(test);
                            }

                            if (q.allowMultiple) {
                              final Set<int> given =
                                  (ans is Set<int>) ? ans : <int>{};
                              final Set<int> correctSet =
                                  q.correctIndexes.toSet();
                              return given.isNotEmpty &&
                                  given.length == correctSet.length &&
                                  given.intersection(correctSet).length ==
                                      correctSet.length;
                            } else {
                              final idx0 = q.correctIndex0();
                              if (idx0 != null) {
                                if (ans is! String) return false;
                                final si = q.options.indexWhere(
                                  (o) => _canon(o) == _canon(ans),
                                );
                                return si == idx0;
                              } else if (q.correctText != null &&
                                  ans is String) {
                                return _canon(ans) == _canon(q.correctText);
                              }
                              return false;
                            }
                          },
                          onTap: _scrollTo,
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 16),
                        itemCount: _questions.length,
                        itemBuilder: (context, index) {
                          final q = _questions[index];
                          final readOnly =
                              _submitted ||
                              (_latestAttempt != null &&
                                  _latestAttempt!['is_returned'] !=
                                      true); // awaiting review: view-only
                          return KeyedSubtree(
                            key: _qKeys[index],
                            child: _QuestionCard(
                              index: index,
                              question: q,
                              selected: _answers[index],
                              submitted: _submitted,
                              accent: colors.last,
                              submittedAt: _submittedAt, // pass down
                              onChanged: (val) {
                                if (readOnly) return;
                                setState(() => _answers[index] = val);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    if (_submitted)
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.last, width: 1.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _returnHome,
                            child: Text(
                              _returnedAt != null
                                  ? 'Returned on ${_fmtDT(_returnedAt!)} — Home'
                                  : 'Return Home',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final bool submitted;
  final int correct;
  final int total;
  final int scorePct;
  final double progressValue;
  final String label;
  final String sublabel;
  final int elapsedSec;

  const _HeaderCard({
    required this.colors,
    required this.icon,
    required this.submitted,
    required this.correct,
    required this.total,
    required this.scorePct,
    required this.progressValue,
    required this.label,
    required this.sublabel,
    required this.elapsedSec,
  });

  String _fmtTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(icon, color: colors.last),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submitted
                      ? 'Results'
                      : 'Progress  •  ${_fmtTime(elapsedSec)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (submitted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$scorePct%',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: colors.last,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IndexBar extends StatelessWidget {
  final int count;
  final bool isSubmitted;
  final Color color;
  final Map<int, dynamic> answered; // String or Set<int>
  final bool? Function(int i) isCorrect;
  final void Function(int i) onTap;

  const _IndexBar({
    required this.count,
    required this.isSubmitted,
    required this.color,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
  });

  bool _hasAnswer(dynamic v) {
    if (v is String) return v.trim().isNotEmpty;
    if (v is Set<int>) return v.isNotEmpty;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final answeredFlag = _hasAnswer(answered[i]);
          final correctness = isSubmitted ? isCorrect(i) : null;

          Color bg;
          Color fg = Colors.white;
          if (isSubmitted) {
            if (correctness == true) {
              bg = Colors.green;
            } else if (correctness == false) {
              bg = Colors.redAccent;
            } else {
              bg = Colors.grey;
            }
          } else {
            bg = answeredFlag ? color : Colors.black26;
          }

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(i),
            child: Container(
              width: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final Question question;
  final dynamic selected; // String or Set<int>
  final bool submitted;
  final Color accent;
  final ValueChanged<dynamic>
  onChanged; // String for single/text, Set<int> for multi
  final DateTime? submittedAt; // timestamp from parent

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.submitted,
    required this.accent,
    required this.onChanged,
    this.submittedAt,
  });

  String _canon(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    final squashed = t.replaceAll(RegExp(r'\s+'), ' ');
    final stripped = squashed.replaceAll(RegExp(r'[^\w\s]'), '');
    return stripped;
  }

  // Extract a likely usable URL from a file/image map
  String? _urlFrom(Map<String, dynamic> m) {
    final raw = (m['public_url'] ?? m['url'] ?? m['path'] ?? '').toString();
    if (raw.startsWith('http')) return raw;
    return null;
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _fmtDT(DateTime dt) {
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAnswer =
        (() {
          if (selected is String) return (selected as String).trim().isNotEmpty;
          if (selected is Set<int>) return (selected as Set<int>).isNotEmpty;
          return false;
        })();

    final int? idx0 = question.correctIndex0();
    final String? correctByIndex =
        (idx0 != null && idx0 >= 0 && idx0 < question.options.length)
            ? question.options[idx0]
            : null;
    final String? correctText = question.correctText ?? correctByIndex;

    bool computeCorrect(dynamic sel) {
      if (!submitted || !hasAnswer) return false;

      // TEXT mode
      if (question.isText) {
        if (sel is! String || sel.trim().isEmpty) return false;

        final List<String> pool =
            question.answerTexts.isNotEmpty
                ? List<String>.from(question.answerTexts)
                : (question.correctText != null
                    ? <String>[question.correctText!]
                    : const <String>[]);

        final Set<String> allowed =
            pool
                .map<String>((a) => question.textAnyCase ? _canon(a) : a.trim())
                .toSet();

        final String test = question.textAnyCase ? _canon(sel) : sel.trim();
        return allowed.contains(test);
      }

      if (question.allowMultiple) {
        final Set<int> given = (sel is Set<int>) ? sel : <int>{};
        final Set<int> correctSet = question.correctIndexes.toSet();
        return given.isNotEmpty &&
            given.length == correctSet.length &&
            given.intersection(correctSet).length == correctSet.length;
      } else {
        if (idx0 != null) {
          final si = question.options.indexWhere(
            (o) => _canon(o) == _canon(sel as String?),
          );
          return si == idx0;
        } else if (question.correctText != null && sel is String) {
          return _canon(sel) == _canon(question.correctText);
        }
        return false;
      }
    }

    final bool isCorrect = computeCorrect(selected);

    // ---------- MEDIA (images + pdfs) ----------
    final List<Widget> media = [];

    // Images
    final imgs = question.images
        .map(_urlFrom)
        .whereType<String>()
        .toList(growable: false);
    for (final url in imgs) {
      media.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 240),
            width: double.infinity,
            color: Colors.black12.withOpacity(.04),
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: Image.network(
                url,
                filterQuality: FilterQuality.medium,
                loadingBuilder: (c, w, p) {
                  if (p == null) return w;
                  return SizedBox(
                    height: 180,
                    child: Center(
                      child: CircularProgressIndicator(
                        value:
                            p.expectedTotalBytes != null
                                ? p.cumulativeBytesLoaded /
                                    (p.expectedTotalBytes!)
                                : null,
                      ),
                    ),
                  );
                },
                errorBuilder:
                    (_, __, ___) => Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        'Image failed to load',
                        style: TextStyle(fontFamily: 'Inter'),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      media.add(const SizedBox(height: 10));
    }

    // PDFs (lazy)
    final pdfs = question.files
        .where(
          (f) =>
              (f['mime']?.toString().toLowerCase() ?? '').contains('pdf') ||
              (f['name']?.toString().toLowerCase() ?? '').endsWith('.pdf') ||
              (f['path']?.toString().toLowerCase() ?? '').endsWith('.pdf'),
        )
        .map(_urlFrom)
        .whereType<String>()
        .toList(growable: false);

    for (final url in pdfs) {
      media.add(
        _PdfInline(
          url: url,
          accent: accent,
          onOpenExternally: () => _openExternal(url),
        ),
      );
      media.add(const SizedBox(height: 10));
    }

    // Soft hint when file exists but no public URL
    if (question.files.isNotEmpty && pdfs.isEmpty) {
      media.add(
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'This question has a PDF attachment, but no public URL was provided. '
            'Ensure SupabaseService adds `public_url` to each file.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12.5),
          ),
        ),
      );
      media.add(const SizedBox(height: 10));
    }

    Widget _buildUnsubmitted() {
      final List<Widget> children = [...media];

      // TEXT input UI
      if (question.isText) {
        final controller = TextEditingController(
          text: (selected is String) ? selected as String : '',
        );
        children.add(
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: TextField(
                controller: controller,
                onChanged: (v) => onChanged(v),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type your answer…',
                ),
              ),
            ),
          ),
        );
        return Column(children: children);
      }

      if (question.allowMultiple) {
        children.addAll(
          List.generate(question.options.length, (i) {
            final bool isChecked =
                (selected is Set<int>) && (selected as Set<int>).contains(i);
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color:
                    isChecked ? accent.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isChecked ? accent : Colors.grey.shade300,
                ),
              ),
              child: CheckboxListTile(
                value: isChecked,
                onChanged: (v) {
                  final current =
                      (selected is Set<int>)
                          ? Set<int>.from(selected as Set<int>)
                          : <int>{};
                  if (v == true) {
                    current.add(i);
                  } else {
                    current.remove(i);
                  }
                  onChanged(current);
                },
                dense: true,
                activeColor: accent,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(
                  question.options[i],
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                ),
              ),
            );
          }),
        );
      } else {
        children.addAll(
          List.generate(question.options.length, (i) {
            final opt = question.options[i];
            final bool isSel = (selected is String) && selected == opt;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSel ? accent : Colors.grey.shade300,
                ),
              ),
              child: RadioListTile<String>(
                value: opt,
                groupValue: (selected is String) ? selected as String : null,
                onChanged: (v) => onChanged(v!),
                dense: true,
                activeColor: accent,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(
                  opt,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                ),
              ),
            );
          }),
        );
      }

      return Column(children: children);
    }

    Widget _buildSubmitted() {
      final String chosenLabel =
          (() {
            if (question.isText) {
              return (selected is String && (selected as String).isNotEmpty)
                  ? selected as String
                  : '—';
            }
            if (question.allowMultiple) {
              final given =
                  (selected is Set<int>) ? (selected as Set<int>) : <int>{};
              if (given.isEmpty) return '—';
              return given
                  .where((i) => i >= 0 && i < question.options.length)
                  .map((i) => question.options[i])
                  .join(', ');
            } else {
              return (selected is String && (selected as String).isNotEmpty)
                  ? selected as String
                  : '—';
            }
          })();

      final String revealLabel =
          (() {
            if (question.isText) {
              final pool =
                  question.answerTexts.isNotEmpty
                      ? question.answerTexts
                      : (question.correctText != null
                          ? [question.correctText!]
                          : const <String>[]);
              return pool.isEmpty ? '—' : pool.join(', ');
            }
            if (question.allowMultiple) {
              return question.correctIndexes
                  .where((i) => i >= 0 && i < question.options.length)
                  .map((i) => question.options[i])
                  .join(', ');
            } else {
              final idx0 = question.correctIndex0();
              if (idx0 != null && idx0 >= 0 && idx0 < question.options.length) {
                return question.options[idx0];
              }
              return correctText ?? '—';
            }
          })();

      final bool showReveal = !isCorrect;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...media,
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isCorrect ? Colors.green : Colors.red).withOpacity(
                    .12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  color: isCorrect ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chosenLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isCorrect ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (showReveal)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Correct answer${question.isText || question.allowMultiple ? 's' : ''}: $revealLabel',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                  ),
                ),
              ],
            ),
          if (question.explanation != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.menu_book_outlined, size: 18, color: Colors.black54),
                SizedBox(width: 6),
              ],
            ),
            Text(
              question.explanation!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                color: Colors.black87,
              ),
            ),
          ],
        ],
      );
    }

    final awaiting =
        (submitted == false) &&
        (submittedAt != null); // card-level banner when awaiting review

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (awaiting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(.5)),
                ),
                child: Text(
                  'Submitted${submittedAt != null ? ' on ${_fmtDT(submittedAt!)}' : ''}. '
                  'Awaiting teacher review. You can view your answers but cannot edit.',
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    question.text,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!submitted && !awaiting)
              _buildUnsubmitted()
            else
              _buildSubmitted(),
          ],
        ),
      ),
    );
  }
}

class _PdfInline extends StatefulWidget {
  final String url;
  final Color accent;
  final VoidCallback onOpenExternally;

  const _PdfInline({
    Key? key,
    required this.url,
    required this.accent,
    required this.onOpenExternally,
  }) : super(key: key);

  @override
  State<_PdfInline> createState() => _PdfInlineState();
}

class _PdfInlineState extends State<_PdfInline> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.onOpenExternally,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open PDF'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.close_fullscreen : Icons.picture_as_pdf),
          label: Text(_open ? 'Hide PDF' : 'Show PDF (inline)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.accent,
            side: BorderSide(color: widget.accent.withOpacity(.6)),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child:
              !_open
                  ? const SizedBox.shrink()
                  : Container(
                    key: const ValueKey('pdf'),
                    height: 360,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SfPdfViewer.network(
                        widget.url,
                        canShowScrollHead: true,
                        canShowScrollStatus: true,
                        enableDoubleTapZooming: true,
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}

class _AwaitingState extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final DateTime? submittedAt;
  final VoidCallback onGoHome;
  final Future<void> Function() onRequestRetry;

  const _AwaitingState({
    required this.icon,
    required this.colors,
    required this.submittedAt,
    required this.onGoHome,
    required this.onRequestRetry,
  });

  String _fmtDT(DateTime dt) {
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Icon(icon, color: colors.last),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Awaiting Review',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            submittedAt != null
                ? 'Submitted on ${_fmtDT(submittedAt!)}'
                : 'Submitted — time unavailable',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Inter'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onGoHome,
                child: const Text('Return Home'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => onRequestRetry(),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockedState extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final String reason;
  final VoidCallback onGoHome;
  final Future<void> Function() onRequestRetry;

  const _BlockedState({
    required this.icon,
    required this.colors,
    required this.reason,
    required this.onGoHome,
    required this.onRequestRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Icon(icon, color: colors.last),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Quiz Locked',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Inter'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onGoHome,
                child: const Text('Return Home'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => onRequestRetry(),
                child: const Text('Retry check'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
            const SizedBox(height: 10),
            const Text(
              'Could not load quiz',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No questions available.',
        style: TextStyle(fontFamily: 'Inter'),
      ),
    );
  }
}
