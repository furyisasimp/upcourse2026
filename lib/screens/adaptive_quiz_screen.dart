import 'package:flutter/material.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/screens/skills_screen.dart';

class AdaptiveQuizScreen extends StatefulWidget {
  /// Can be a plain id like "biology" or a folder-aware id like "GAS/biology".
  final String quizId;
  final String title;

  const AdaptiveQuizScreen({
    super.key,
    required this.quizId,
    required this.title,
  });

  @override
  State<AdaptiveQuizScreen> createState() => _AdaptiveQuizScreenState();
}

class _AdaptiveQuizScreenState extends State<AdaptiveQuizScreen> {
  static const String _bucket = 'adaptive-quizzes';

  List<Map<String, dynamic>> questions = [];
  final Map<int, int> answers = {};
  bool submitted = false;
  int score = 0;
  bool _loading = true;
  String? _error;

  /// The id we actually ended up loading (after trying fallbacks).
  /// This is what we read/write into quiz_progress.
  late String _effectiveQuizId;

  /// Cached strand/course code for subtitle
  String? _subtitleStrand;

  @override
  void initState() {
    super.initState();
    _effectiveQuizId = widget.quizId;
    _loadQuiz();
  }

  // ---------- Helpers ----------

  String _basename(String id) {
    final idx = id.lastIndexOf('/');
    if (idx < 0) return id;
    return id.substring(idx + 1);
  }

  String? _prefixFolder(String id) {
    final idx = id.indexOf('/');
    if (idx <= 0) return null;
    return id.substring(0, idx);
  }

  String _titleCase(String s) {
    final words =
        s
            .replaceAll('_', ' ')
            .trim()
            .split(RegExp(r'\s+'))
            .map(
              (w) =>
                  w.isEmpty
                      ? w
                      : (w[0].toUpperCase() +
                          (w.length > 1 ? w.substring(1).toLowerCase() : '')),
            )
            .toList();
    return words.join(' ');
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _loading = true;
      _error = null;
      questions = [];
      submitted = false;
      score = 0;
      answers.clear();
      _subtitleStrand = null;
    });

    try {
      // Try a few sensible ids so subfolders and plain ids both work.
      final strand =
          await SupabaseService.getUserStrandOrCourseCode(); // e.g., GAS
      final base = _basename(widget.quizId);

      final candidateIds =
          <String>{
            widget.quizId, // exact passed in (could be "GAS/biology")
            base, // basename ("biology")
            if (strand != null && strand.isNotEmpty)
              '$strand/$base', // "GAS/biology"
          }.toList();

      List<Map<String, dynamic>>? loaded;
      String? usedId;

      for (final id in candidateIds) {
        final data = await SupabaseService.fetchQuizWithTOS(
          quizId: id,
          bucket: _bucket,
          totalOverride: 15,
        );
        if (data.isNotEmpty) {
          loaded = data;
          usedId = id;
          break;
        }
      }

      if (!mounted) return;

      if (loaded == null || loaded.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              "No questions found for '${widget.quizId}'.\n\n"
              "Make sure a JSON exists in the '$_bucket' bucket as either:\n"
              "• ${widget.quizId}.json\n"
              "• ${_basename(widget.quizId)}.json\n"
              "• <STRAND>/${_basename(widget.quizId)}.json";
        });
        return;
      }

      // Normalize question shape (defensive)
      List<Map<String, dynamic>> normalized = [];
      for (final q in loaded) {
        final m = Map<String, dynamic>.from(q);
        // Ensure options is a List<String>
        final rawOpts = (m['options'] ?? m['choices']);
        final List<String> opts =
            rawOpts is List
                ? rawOpts.map((e) => e?.toString() ?? '').toList()
                : const <String>[];
        // Ensure correct_index is an int
        int? ci;
        final rawCi = m['correct_index'] ?? m['answer_index'];
        if (rawCi is int) {
          ci = rawCi;
        } else if (rawCi is num) {
          ci = rawCi.toInt();
        } else if (rawCi is String) {
          ci = int.tryParse(rawCi);
        }
        if (ci == null || ci < 0 || ci >= opts.length) {
          // If bad index, skip this question
          continue;
        }
        normalized.add({
          'text': (m['text'] ?? m['question'] ?? '').toString(),
          'options': opts,
          'correct_index': ci,
        });
      }

      if (normalized.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              "Quiz file was loaded but contained no valid questions.\n"
              "Check that each question has 'options' (list) and a valid 'correct_index'.";
        });
        return;
      }

      _effectiveQuizId = usedId ?? widget.quizId;
      _subtitleStrand =
          _prefixFolder(_effectiveQuizId) ??
          strand; // prefer the actual folder used, else user strand

      setState(() {
        questions = normalized;
        _loading = false;
      });

      // Load any previous completion for view-only mode
      final quizProgress = await SupabaseService.getQuizProgress();
      Map<String, dynamic> thisQuiz = {};

      // Try exact effective id first, then fallback to basename match
      thisQuiz = quizProgress.firstWhere(
        (q) => (q['quiz_id']?.toString() ?? '') == _effectiveQuizId,
        orElse: () => {},
      );
      if (thisQuiz.isEmpty) {
        final baseEff = _basename(_effectiveQuizId);
        thisQuiz = quizProgress.firstWhere(
          (q) => (q['quiz_id']?.toString() ?? '') == baseEff,
          orElse: () => {},
        );
      }

      if (!mounted) return;

      if (thisQuiz.isNotEmpty && thisQuiz['status'] == 'completed') {
        setState(() {
          submitted = true;
          score = thisQuiz['score'] ?? 0;
          if (thisQuiz['answers'] != null) {
            answers.addAll(
              (thisQuiz['answers'] as Map).map(
                (key, value) =>
                    MapEntry(int.parse(key.toString()), value as int),
              ),
            );
          }
        });
      } else {
        await SupabaseService.updateQuizProgress(
          _effectiveQuizId,
          status: "in_progress",
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load quiz: $e';
      });
    }
  }

  Future<void> _submit() async {
    int correct = 0;
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final selected = answers[i];
      final int ci = (q['correct_index'] as num).toInt();
      if (selected == ci) correct++;
    }

    setState(() {
      submitted = true;
      score = ((correct / questions.length) * 100).round();
    });

    await SupabaseService.updateQuizProgress(
      _effectiveQuizId,
      status: "completed",
      score: score,
      answers: answers,
    );
  }

  Future<bool> _onWillPop() async {
    if (submitted) return true; // allow exit if finished

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Exit Quiz?",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            "If you leave now, your progress will not be saved. "
            "Are you sure you want to quit the quiz?",
            style: TextStyle(fontFamily: 'Inter', fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                "Continue Quiz",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
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
                "Exit",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );

    return shouldExit ?? false;
  }

  // ---------- UI ----------

  PreferredSizeWidget _buildAppBar() {
    final prettyTitle = _titleCase(widget.title);
    final total = questions.length;
    final strandText = _subtitleStrand?.toUpperCase();
    final sub = [
      if (strandText != null && strandText.isNotEmpty) strandText,
      if (total > 0) '$total question${total == 1 ? '' : 's'}',
    ].join(' • ');

    return AppBar(
      automaticallyImplyLeading: true,
      backgroundColor: const Color(0xFF3EB6FF),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prettyTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
        ],
      ),
      bottom:
          submitted
              ? null
              : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value:
                      questions.isEmpty
                          ? 0
                          : (answers.length / questions.length).clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                  minHeight: 3,
                ),
              ),
      actions: [
        IconButton(
          tooltip: 'Reload quiz',
          onPressed: _loadQuiz,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _errorBody(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3ECFF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 36),
              const SizedBox(height: 12),
              Text(
                'Failed to load quiz',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.blueGrey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Inter'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadQuiz,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionCard({required int index, required Map<String, dynamic> q}) {
    final List opts = (q['options'] as List?) ?? const <dynamic>[];

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Q${index + 1}. ${q['text']}",
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            ...opts.asMap().entries.map((opt) {
              final optIndex = opt.key;
              final optText = opt.value?.toString() ?? '';
              final isSelected = answers[index] == optIndex;
              final isCorrect = (q['correct_index'] as num).toInt() == optIndex;

              Color? tileColor;
              if (submitted) {
                if (isCorrect) {
                  tileColor = Colors.green.withOpacity(0.15);
                } else if (isSelected && !isCorrect) {
                  tileColor = Colors.red.withOpacity(0.15);
                }
              }

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        isSelected
                            ? const Color(0xFF3EB6FF)
                            : Colors.grey.shade300,
                    width: 1.2,
                  ),
                ),
                child: RadioListTile<int>(
                  value: optIndex,
                  groupValue: answers[index],
                  title: Text(
                    optText,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  activeColor: const Color(0xFF3EB6FF),
                  onChanged:
                      submitted
                          ? null
                          : (val) => setState(() => answers[index] = val!),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(appBar: _buildAppBar(), body: _errorBody(_error!));
    }

    if (questions.isEmpty) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: _errorBody('No questions found for this quiz.'),
      );
    }

    final remaining = questions.length - answers.length;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: questions.length,
            itemBuilder:
                (context, i) => _questionCard(index: i, q: questions[i]),
          ),
        ),

        // Sticky bottom: submit or results
        bottomSheet: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child:
              submitted
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Your Score: $score%",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: score >= 60 ? Colors.green : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SkillsScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Back to Skill Development",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                  : Row(
                    children: [
                      Expanded(
                        child: Text(
                          remaining > 0
                              ? "$remaining question${remaining == 1 ? '' : 's'} left"
                              : "Ready to submit",
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed:
                            answers.length == questions.length ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3EB6FF),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(140, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Submit",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}
