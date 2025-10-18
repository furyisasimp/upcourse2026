// lib/quiz_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_capture_event/screen_capture_event.dart';

import 'home_screen.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/services/quiz_security_service.dart';

class Question {
  final String text;
  final List<String> options;

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
    this.rawIndex,
    this.correctText,
    this.explanation,
    this.allowMultiple = false,
    this.correctIndexes = const <int>[],
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

    return Question(
      text: (json['text'] ?? '').toString(),
      options: (json['options'] as List).map((e) => '$e').toList(),
      rawIndex: idx,
      correctText: txt,
      explanation:
          (json['explanation'] is String &&
                  (json['explanation'] as String).trim().isNotEmpty)
              ? (json['explanation'] as String).trim()
              : null,
      allowMultiple: multi,
      correctIndexes: idxs,
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
  const QuizScreen({Key? key, required this.categoryId}) : super(key: key);

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
  // String for single-answer, Set<int> for multi-answer questions
  final Map<int, dynamic> _answers = {};
  final List<Question> _questions = [];
  final List<GlobalKey> _qKeys = [];
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _submitted = false;
  String? _loadError;

  // gating
  bool _blocked = false;
  String? _blockReason;

  // scoring
  int _correct = 0;
  int _total = 0;
  int _scorePct = 0;

  // timer
  late final DateTime _startedAt = DateTime.now();
  int _elapsedSec = 0;
  Timer? _ticker;

  // --- Anti-cheat (plugin is platform-gated)
  ScreenCaptureEvent? _screenCapture;
  int _cheatStrikes = 0;
  static const int _cheatMax = 3;
  bool _securityBusy = false; // debounce for security snackbars
  bool _leaving = false; // guard against late events while exiting

  // Cached messenger to avoid context lookups in dispose
  ScaffoldMessengerState? _scaffoldMessenger;

  bool get _supportsScreenCapture =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
  // Windows/Linux are explicitly NOT supported by the plugin.

  @override
  void initState() {
    super.initState();
    if (_supportsScreenCapture) {
      _screenCapture = ScreenCaptureEvent();
      _initScreenCapture();
    }
    _checkGateAndLoad();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _screenCapture?.dispose(); // safe: only when created
    _scroll.dispose();
    _scaffoldMessenger?.clearSnackBars(); // no context lookup here
    super.dispose();
  }

  // Stop all transient activity before leaving the route.
  void _prepareForExit() {
    _leaving = true; // tells listeners to ignore
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

    // Listeners exist ONLY when plugin is supported
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
      });
    }

    try {
      final allowed = await SupabaseService.canTakeQuiz(_programId);
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

      final selected = await SupabaseService.fetchQuizWithTOS(
        quizId: _programId,
        bucket: 'quizzes',
      );
      if (!mounted) return;

      if (selected.isEmpty) {
        throw Exception('Quiz is empty for $_programId');
      }

      _questions
        ..clear()
        ..addAll(
          selected.map((e) => Question.fromJson(Map<String, dynamic>.from(e))),
        );
      _qKeys
        ..clear()
        ..addAll(List.generate(_questions.length, (_) => GlobalKey()));

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

    int correct = 0;
    final Map<int, int> chosenIndexes = {};
    final Map<int, List<int>> chosenMulti = {};

    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final ans = _answers[i];

      if (q.allowMultiple) {
        final Set<int> given = (ans is Set<int>) ? ans : <int>{};
        final Set<int> correctSet = q.correctIndexes.toSet();

        if (given.isNotEmpty) {
          chosenIndexes[i] = given.first;
          final list = given.toList()..sort();
          chosenMulti[i] = list;
        }

        final isRight =
            given.isNotEmpty &&
            given.length == correctSet.length &&
            given.intersection(correctSet).length == correctSet.length;

        if (isRight) correct++;
      } else {
        final selectedText = _canon(ans is String ? ans : '');
        final selIdx = q.options.indexWhere((o) => _canon(o) == selectedText);
        if (selIdx >= 0) {
          chosenIndexes[i] = selIdx;
          chosenMulti[i] = [selIdx];
        }

        bool isRight = false;
        final idx0 = q.correctIndex0();
        if (idx0 != null) {
          isRight = selIdx == idx0;
        } else if (q.correctText != null) {
          isRight = selectedText == _canon(q.correctText);
        }
        if (isRight) correct++;
      }
    }

    final total = _questions.length;
    final scorePct = ((correct * 100) / (total == 0 ? 1 : total)).round();
    final elapsed = DateTime.now().difference(_startedAt).inSeconds;

    try {
      await SupabaseService.updateQuizProgress(
        _programId,
        status: 'completed',
        score: scorePct,
        answers: chosenIndexes,
        answersMulti: chosenMulti,
      );
    } catch (_) {}

    try {
      await SupabaseService.saveQuizAttempt(
        quizId: _programId,
        correct: correct,
        total: total,
        durationSec: elapsed,
        meta: {'app': 'mobile', 'source': 'QuizScreen'},
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _submitted = true;
      _correct = correct;
      _total = total;
      _scorePct = scorePct;
      _elapsedSec = elapsed;
    });

    if (!mounted) return;
    _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
    _scaffoldMessenger?.showSnackBar(
      SnackBar(
        content: Text('Score: $correct/$total ($_scorePct%) • ${_elapsedSec}s'),
      ),
    );
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

  // Kick off the confirm dialog & safely pop after quiescing the page.
  Future<void> _requestExit() async {
    if (!mounted) return;
    final ok = await _confirmExit();
    if (!mounted) return;
    if (ok) {
      _prepareForExit();
      if (context.mounted) Navigator.pop(context);
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
            _submitted ? 'Results Overview' : titleText,
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

        bottomNavigationBar:
            _loading || _submitted || _questions.isEmpty || _blocked
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
                : _blocked
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
                                ? (_scorePct / 100).clamp(0, 1)
                                : progress,
                        label:
                            _submitted
                                ? 'Score: $_correct/$_total ($_scorePct%)'
                                : 'Progress',
                        sublabel:
                            _submitted
                                ? 'Results saved to your progress'
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
                          return KeyedSubtree(
                            key: _qKeys[index],
                            child: _QuestionCard(
                              index: index,
                              question: q,
                              selected: _answers[index],
                              submitted: _submitted,
                              accent: colors.last,
                              onChanged: (val) {
                                if (_submitted) return;
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
                            child: const Text(
                              'Return Home',
                              style: TextStyle(
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
                  '$label  •  ${_fmtTime(elapsedSec)}',
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
  onChanged; // String for single, Set<int> for multi

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.submitted,
    required this.accent,
    required this.onChanged,
  });

  String _canon(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    final squashed = t.replaceAll(RegExp(r'\s+'), ' ');
    final stripped = squashed.replaceAll(RegExp(r'[^\w\s]'), '');
    return stripped;
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

    Widget _buildUnsubmitted() {
      if (question.allowMultiple) {
        return Column(
          children: List.generate(question.options.length, (i) {
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
        return Column(
          children: List.generate(question.options.length, (i) {
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
                groupValue: (selected is String) ? selected as String? : null,
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
    }

    Widget _buildSubmitted() {
      final String chosenLabel =
          (() {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isCorrect ? Colors.green : Colors.red).withOpacity(
                    0.12,
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
                    'Correct answer${question.allowMultiple ? 's' : ''}: $revealLabel',
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
            if (!submitted) _buildUnsubmitted() else _buildSubmitted(),
          ],
        ),
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
