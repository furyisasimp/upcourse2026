import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'quiz_screen.dart';
import 'package:career_roadmap/services/supabase_service.dart';

class QuizIntroScreen extends StatefulWidget {
  final String categoryId; // treat as quizId
  final String storagePath; // Add this

  const QuizIntroScreen({
    Key? key,
    required this.categoryId,
    required this.storagePath,
  }) : super(key: key);

  @override
  State<QuizIntroScreen> createState() => _QuizIntroScreenState();
}

class _QuizIntroScreenState extends State<QuizIntroScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _loading = true;
  String? _error;

  // Header data (title, desc, due, total points, quizId)
  QuizHeader? _header;

  // Latest attempt (if any)
  Map<String, dynamic>? _latestAttempt;
  bool get _hasAttempt => _latestAttempt != null;

  // Can the user take the quiz right now? (bank gate)
  bool _canTakeGate = true;

  // Convenience getters
  bool get _isReturned => (_latestAttempt?['is_returned'] == true);
  bool get _isAwaitingReview => _hasAttempt && !_isReturned;

  int? get _correct =>
      (_latestAttempt?['correct'] is num)
          ? (_latestAttempt!['correct'] as num).toInt()
          : null;
  int? get _total =>
      (_latestAttempt?['total'] is num)
          ? (_latestAttempt!['total'] as num).toInt()
          : null;

  double? get _scorePct {
    final v = _latestAttempt?['score_pct'];
    if (v is num) return v.toDouble();
    final c = _correct;
    final t = _total;
    if (c != null && t != null && t > 0) return (c * 100.0) / t;
    return null;
  }

  String? get _statusText =>
      _latestAttempt?['status']?.toString(); // e.g. pending_review / returned

  String? get _returnedAtText {
    final raw = _latestAttempt?['returned_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return null;
    return DateFormat('MMM d, y • h:mm a').format(dt);
  }

  String? get _finishedAtText {
    final raw = _latestAttempt?['finished_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return null;
    return DateFormat('MMM d, y • h:mm a').format(dt);
  }

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );

    // These start immediately; they’re fine. No timers to cancel.
    _fadeController.forward();
    _slideController.forward();

    _load();
  }

  // 👈 Safety wrapper: any late setState calls after dispose() will be ignored.
  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Header (title, desc, due, total points)
      final header = await SupabaseService.fetchQuizHeader(
        quizId: widget.categoryId,
      );

      if (!mounted) return; // 👈 stop if user navigated away

      final effectiveId =
          header.quizId.isNotEmpty ? header.quizId : widget.categoryId;

      // Latest attempt – prefer exact JSON id, fallback to route id
      final latest = await SupabaseService.getLatestAttemptForQuiz(
        quizIdExact: effectiveId,
        altIdForFallback: widget.categoryId,
      );

      if (!mounted) return; // 👈 guard before next state change

      // Same gate as Categories/QuizScreen
      final canTake = await SupabaseService.canTakeBankQuiz(effectiveId);

      if (!mounted) return; // 👈 guard before setState

      setState(() {
        _header = header;
        _latestAttempt = latest;
        _canTakeGate = canTake;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return; // 👈 don’t touch state if disposed
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ---------- Navigation ----------
  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _startQuiz() {
    if (_header == null) return;
    final canStart =
        SupabaseService.quizIsOpenUtc(_header!.dueDateUtc) &&
        !_isAwaitingReview &&
        _canTakeGate &&
        !_hasAttempt;
    if (!canStart) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder:
            (_, animation, __) => FadeTransition(
              opacity: animation,
              child: QuizScreen(
                categoryId:
                    _header!.quizId.isNotEmpty
                        ? _header!.quizId
                        : widget.categoryId,
                storagePath: widget.storagePath, // Add this
              ),
            ),
      ),
    );
  }

  void _viewResults() {
    if (_header == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder:
            (_, animation, __) => FadeTransition(
              opacity: animation,
              child: QuizScreen(
                categoryId:
                    _header!.quizId.isNotEmpty
                        ? _header!.quizId
                        : widget.categoryId,
                storagePath: widget.storagePath, // Add this
              ),
            ),
      ),
    );
  }
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: Colors.blueAccent,
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: Colors.blueAccent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildBody(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _ErrorCard(message: _error!, onRetry: _load);
    }

    final h = _header!;
    final dueText = SupabaseService.formatDueLocal(h.dueDateUtc);
    final isOpen = SupabaseService.quizIsOpenUtc(h.dueDateUtc);

    final (statusLabel, statusColor) =
        isOpen
            ? (('Open until $dueText'), Colors.green)
            : (('Closed • $dueText'), Colors.red);

    final bool showStart = isOpen && _canTakeGate && !_hasAttempt;
    final String primaryLabel =
        _isReturned ? 'View Results' : 'View Submission';

    final String yourScoreRaw =
        !_hasAttempt
            ? '—'
            : _isAwaitingReview
            ? 'Awaiting review'
            : (_correct != null && _total != null
                ? '${_correct!}/${_total!}'
                : '—');

    final String overallScorePct =
        !_hasAttempt
            ? '—'
            : _isAwaitingReview
            ? 'Awaiting review'
            : (_scorePct != null ? '${_scorePct!.toStringAsFixed(0)}%' : '—');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueAccent.withOpacity(0.15),
          ),
          child: const Icon(Icons.quiz, size: 100, color: Colors.blueAccent),
        ),
        const SizedBox(height: 24),

        Text(
          h.title.isNotEmpty ? h.title : "Get Ready for the Quiz!",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        if (h.description.isNotEmpty)
          Text(
            h.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15.5,
              color: Colors.black87,
            ),
          )
        else
          const Text(
            "Answer a few questions and see what you discover about your interests and strengths!",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15.5,
              color: Colors.black87,
            ),
          ),
        const SizedBox(height: 16),

        // Status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withOpacity(0.4)),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Meta rows
        _MetaRow(
          label: 'Total Points',
          value: '${h.totalPoints}',
          icon: Icons.score_rounded,
        ),
        _MetaRow(
          label: 'Due',
          value: SupabaseService.formatDueLocal(h.dueDateUtc),
          icon: Icons.schedule_rounded,
        ),
        if (_hasAttempt)
          _MetaRow(
            label: 'Your Score (raw)',
            value: yourScoreRaw,
            icon: Icons.fact_check_rounded,
          ),
        if (_hasAttempt)
          _MetaRow(
            label: 'Overall Score (%)',
            value: overallScorePct,
            icon: Icons.percent_rounded,
          ),
        if (_hasAttempt && _finishedAtText != null)
          _MetaRow(
            label: 'Submitted',
            value: _finishedAtText!,
            icon: Icons.event_available_rounded,
          ),

        const SizedBox(height: 16),

        // Attempt details card
        if (_hasAttempt)
          _AttemptPanel(
            isReturned: _isReturned,
            isAwaitingReview: _isAwaitingReview,
            scorePct: _scorePct,
            correct: _correct,
            total: _total,
            returnedAtText: _returnedAtText,
            feedback: _latestAttempt?['feedback']?.toString(),
            statusText: _statusText,
          ),

        const SizedBox(height: 24),

        // Primary action:
        if (showStart)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startQuiz,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Start Quiz',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _viewResults,
              icon: Icon(
                _isReturned
                    ? Icons.visibility_rounded
                    : Icons.hourglass_bottom_rounded,
              ),
              label: Text(primaryLabel),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------- Small UI bits ----------

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetaRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14.5,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttemptPanel extends StatelessWidget {
  final bool isReturned;
  final bool isAwaitingReview;
  final double? scorePct;
  final int? correct;
  final int? total;
  final String? returnedAtText;
  final String? feedback;
  final String? statusText;

  const _AttemptPanel({
    required this.isReturned,
    required this.isAwaitingReview,
    required this.scorePct,
    required this.correct,
    required this.total,
    required this.returnedAtText,
    required this.feedback,
    required this.statusText,
  });

  String _prettyStatus(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim().toLowerCase();
    if (s == 'pending_review' || s == 'pending' || s == 'awaiting_review') {
      return 'Pending to be Reviewed';
    }
    if (s == 'returned') return 'Returned';
    // fallback: snake_case → Title Case
    return s
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cardColor =
        isReturned ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1);
    final title = isReturned ? 'Returned' : 'Submitted • Awaiting Review';
    final icon =
        isReturned
            ? Icons.check_circle_rounded
            : Icons.hourglass_bottom_rounded;
    final iconColor = isReturned ? Colors.green : Colors.orange;

    final scoreLine =
        (isReturned && correct != null && total != null)
            ? '${correct!}/${total!}${scorePct != null ? ' • ${scorePct!.toStringAsFixed(0)}%' : ''}'
            : (isAwaitingReview
                ? 'Awaiting review'
                : (scorePct != null
                    ? '${scorePct!.toStringAsFixed(0)}%'
                    : '—'));

    final prettyStatus = _prettyStatus(statusText);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isReturned ? Colors.green : Colors.orange).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (prettyStatus.isNotEmpty) ...[
            Text(
              'Status: $prettyStatus',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
            ),
            const SizedBox(height: 4),
          ],

          if (isAwaitingReview)
            const Text(
              'Your submission has been received. A teacher will review it and return the results here.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 14),
            ),

          if (!isAwaitingReview) ...[
            Row(
              children: const [
                Text(
                  'Score:',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
              child: Text(
                scoreLine,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
              ),
            ),
            if (returnedAtText != null)
              Row(
                children: [
                  const Text(
                    'Returned:',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    returnedAtText!,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                  ),
                ],
              ),
            if (feedback != null && feedback!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Feedback',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feedback!,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 64),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Failed to load quiz',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
