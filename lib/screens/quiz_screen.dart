// lib/quiz_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'package:career_roadmap/services/supabase_service.dart';

class Question {
  final String text;
  final List<String> options;
  final int? rawIndex; // from answer_index / correct_index (unknown base)
  final String? correctText; // from correct / answer (text)
  final String? explanation; // optional: "explanation" key in JSON

  Question({
    required this.text,
    required this.options,
    this.rawIndex,
    this.correctText,
    this.explanation,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final dynamic idxRaw = json['answer_index'] ?? json['correct_index'];
    final int? idx =
        (idxRaw is num) ? idxRaw.toInt() : int.tryParse('${idxRaw ?? ''}');
    final dynamic txtRaw = json['correct'] ?? json['answer'];
    final String? txt =
        (txtRaw is String && txtRaw.trim().isNotEmpty) ? txtRaw.trim() : null;

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
    );
  }

  /// Try to normalize the index into 0-based within options length.
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
  /// Accepts legacy ids (e.g., "abm_stats") or new ids ("ABM", "GAS", "STEM", "TECHPRO")
  final String categoryId;
  const QuizScreen({Key? key, required this.categoryId}) : super(key: key);

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // --- Category metadata (UI) ---
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

  // --- State ---
  final Map<int, String> _answers = {}; // index -> chosen text
  final List<Question> _questions = [];
  final List<GlobalKey> _qKeys = [];
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _submitted = false;
  String? _loadError;

  // gating
  bool _blocked = false; // true if retake is not allowed
  String? _blockReason;

  // scoring snapshot after submit
  int _correct = 0;
  int _total = 0;
  int _scorePct = 0;

  // timer
  late final DateTime _startedAt = DateTime.now();
  int _elapsedSec = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _checkGateAndLoad();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkGateAndLoad() async {
    setState(() {
      _loading = true;
      _blocked = false;
      _blockReason = null;
      _loadError = null;
    });

    try {
      final allowed = await SupabaseService.canTakeQuiz(_programId);
      if (!allowed) {
        setState(() {
          _loading = false;
          _blocked = true;
          _blockReason = 'You have already taken this quiz.';
        });
        return;
      }

      // Load bank + TOS selection from Supabase Storage (always ~10 items)
      final selected = await SupabaseService.fetchQuizWithTOS(
        quizId: _programId, // ABM / GAS / STEM / TECHPRO
        bucket: 'quizzes',
      );

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

      // Start timer
      _ticker?.cancel();
      _elapsedSec = 0;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_submitted) {
          setState(() {
            _elapsedSec = DateTime.now().difference(_startedAt).inSeconds;
          });
        } else {
          _ticker?.cancel();
        }
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  String _canon(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> _submit() async {
    if (_answers.length != _questions.length) {
      // Jump to first unanswered to help the user
      final firstUnanswered = List.generate(
        _questions.length,
        (i) => i,
      ).firstWhere((i) => !_answers.containsKey(i), orElse: () => 0);
      _scrollTo(firstUnanswered);
      ScaffoldMessenger.of(context).showSnackBar(
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
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final selectedText = _canon(_answers[i]);
      final selIdx = q.options.indexWhere((o) => _canon(o) == selectedText);
      if (selIdx >= 0) chosenIndexes[i] = selIdx;

      bool isRight = false;
      final idx0 = q.correctIndex0();
      if (idx0 != null) {
        isRight = selIdx == idx0;
      } else if (q.correctText != null) {
        isRight = selectedText == _canon(q.correctText);
      }
      if (isRight) correct++;
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

    setState(() {
      _submitted = true;
      _correct = correct;
      _total = total;
      _scorePct = scorePct;
      _elapsedSec = elapsed;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Score: $correct/$total ($_scorePct%) • ${_elapsedSec}s',
          ),
        ),
      );
    }
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
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );
  }

  Future<bool> _confirmExit() async {
    if (_submitted) return true;
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
              'If you leave now, your answers will not be submitted. Are you sure you want to exit?',
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
                  'Continue Quiz',
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
    final answered = _answers.length;
    final total = _questions.length;
    final progress = total == 0 ? 0.0 : answered / total;

    // Responsive paddings
    final width = MediaQuery.of(context).size.width;
    final hPad =
        width >= 1100
            ? 24.0
            : width >= 700
            ? 18.0
            : 12.0;

    return WillPopScope(
      onWillPop: _confirmExit,
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
                    onPressed: () async {
                      final ok = await _confirmExit();
                      if (ok && mounted) Navigator.pop(context);
                    },
                  ),
        ),

        // Bottom submit
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
                            _answers.length == _questions.length
                                ? _submit
                                : null,
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
                    // Header: progress / timer + quick index bar
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

                    // Quick index: jump to questions
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
                            final sel = _answers[i];
                            if (sel == null) return false;
                            final idx0 = q.correctIndex0();
                            if (idx0 != null) {
                              final si = q.options.indexWhere(
                                (o) => _canon(o) == _canon(sel),
                              );
                              return si == idx0;
                            } else if (q.correctText != null) {
                              return _canon(sel) == _canon(q.correctText);
                            }
                            return false;
                          },
                          onTap: _scrollTo,
                        ),
                      ),

                    // Questions
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
                  submitted
                      ? '$label  •  ${_fmtTime(elapsedSec)}'
                      : '$label  •  ${_fmtTime(elapsedSec)}',
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
  final Map<int, String> answered;
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final answeredFlag = answered.containsKey(i);
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
  final String? selected;
  final bool submitted;
  final Color accent;
  final ValueChanged<String> onChanged;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.submitted,
    required this.accent,
    required this.onChanged,
  });

  String _canon(String? s) => (s ?? '').trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final hasAnswer = selected != null && selected!.isNotEmpty;

    final int? idx0 = question.correctIndex0();
    final String? correctByIndex =
        (idx0 != null && idx0 >= 0 && idx0 < question.options.length)
            ? question.options[idx0]
            : null;
    final String? correctText = question.correctText ?? correctByIndex;

    final bool isCorrect =
        submitted &&
        hasAnswer &&
        ((idx0 != null &&
                question.options.indexWhere(
                      (o) => _canon(o) == _canon(selected),
                    ) ==
                    idx0) ||
            (question.correctText != null &&
                _canon(selected) == _canon(question.correctText)));

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
            // Title row
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

            // Body
            if (!submitted)
              ...question.options.map(
                (opt) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        selected == opt
                            ? accent.withOpacity(0.08)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected == opt ? accent : Colors.grey.shade300,
                    ),
                  ),
                  child: RadioListTile<String>(
                    value: opt,
                    groupValue: selected,
                    onChanged: (v) => onChanged(v!),
                    dense: true,
                    activeColor: accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    title: Text(
                      opt,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                    ),
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isCorrect ? Colors.green : Colors.red)
                              .withOpacity(0.12),
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
                          selected ?? '—',
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
                  if (!isCorrect && correctText != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 18, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Correct answer: $correctText',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (question.explanation != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 18,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            question.explanation!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13.5,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
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
