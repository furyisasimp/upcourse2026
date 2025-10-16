// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:career_roadmap/services/supabase_service.dart';

// Screens you already have
import 'package:career_roadmap/screens/questionnaire_intro_screen.dart';
import 'package:career_roadmap/screens/exploration_screen.dart';
import 'package:career_roadmap/screens/skills_screen.dart';
import 'package:career_roadmap/screens/resources_screen.dart';

// DIRECT assessment screens (these are your files)
import 'package:career_roadmap/screens/riasec_test_screen.dart';
import 'package:career_roadmap/screens/questionnaire_screen.dart';

// Panel
import 'package:career_roadmap/widgets/career_setup_panel.dart';

import '../widgets/custom_taskbar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  String _firstName = 'Guest';
  String _gradeLevel = '';
  int _topNavIndex = 0; // 0=Home, 1=Assessment, 2=Exploration, 3=Skills

  // Career setup flags (RIASEC only for this screen)
  bool _loadingFlags = true;
  bool _riasecDone = false;

  // ---- Quiz progress state (ONLY quizzes) ----
  // switched to completed + total (instead of in_progress)
  Map<String, int> _quizStats = const {'completed': 0, 'total': 0};
  final List<_QuizRow> _quizRows = [];
  bool _loadingQuizzes = true;

  // Pretty titles for common ids
  static const Map<String, String> _metaTitle = {
    'ABM': 'ABM — Practice Quiz',
    'GAS': 'GAS — General Academic Strand',
    'STEM': 'STEM — Practice Quiz',
    'TECHPRO': 'TechPro — TVL / Tech-Voc',
  };

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await Future.wait([
      _loadProfile(),
      _loadCompletionFlags(),
      _loadQuizProgress(),
    ]);
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.getMyProfile();
      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _firstName = profile['first_name'] ?? 'Guest';
          _gradeLevel = profile['grade_level']?.toString() ?? '';
        });
      } else {
        setState(() {
          _firstName = SupabaseService.authEmail ?? 'Guest';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _firstName = SupabaseService.authEmail ?? 'Guest';
      });
    }
  }

  /// Loads whether the user finished **RIASEC** only (NCAE not tracked here).
  Future<void> _loadCompletionFlags() async {
    final uid = SupabaseService.authUserId;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _riasecDone = false;
        _loadingFlags = false;
      });
      return;
    }

    final supa = Supabase.instance.client;
    try {
      final r = await supa
          .from('riasec_results')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1);
      final hasRiasec = (r is List && r.isNotEmpty);

      if (!mounted) return;
      setState(() {
        _riasecDone = hasRiasec;
        _loadingFlags = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _riasecDone = false;
        _loadingFlags = false;
      });
    }
  }

  /// Build quiz progress from:
  /// - Storage bucket 'quizzes' (discover quiz ids)
  /// - Table 'quiz_progress' (user rows) with fields: user_id, quiz_id, status, score
  Future<void> _loadQuizProgress() async {
    setState(() {
      _loadingQuizzes = true;
      _quizRows.clear();
      _quizStats = const {'completed': 0, 'total': 0};
    });

    final uid = SupabaseService.authUserId;
    final supa = Supabase.instance.client;

    try {
      // Discover quizzes from storage (file names *.json)
      final files = await SupabaseService.listFiles(
        bucket: 'quizzes',
        path: '',
      );
      final ids =
          files
              .where((f) => f.toLowerCase().endsWith('.json'))
              .map((f) => f.substring(0, f.length - 5).toUpperCase())
              .toSet()
              .toList();

      if (ids.isEmpty) {
        // Fallback to known quiz ids if storage is empty.
        ids.addAll(['ABM', 'GAS', 'STEM', 'TECHPRO']);
      }

      Map<String, dynamic> byQuiz = {};
      if (uid != null) {
        final rows = await supa
            .from('quiz_progress')
            .select('quiz_id,status,score')
            .eq('user_id', uid);
        if (rows is List) {
          for (final r in rows) {
            final qid = (r['quiz_id'] ?? '').toString().toUpperCase();
            byQuiz[qid] = r;
          }
        }
      }

      int completed = 0;

      for (final id in ids) {
        final row = byQuiz[id] ?? {};
        final status =
            (row['status'] ?? 'not_started').toString().toLowerCase();
        final int? score =
            row['score'] is num ? (row['score'] as num).toInt() : null;

        if (status == 'completed') {
          completed++;
        }

        _quizRows.add(
          _QuizRow(
            id: id,
            title: _metaTitle[id] ?? '$id — Practice Quiz',
            status: status, // completed | in_progress | not_started
            score: score,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _quizStats = {'completed': completed, 'total': ids.length};
        _loadingQuizzes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingQuizzes = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load quiz progress: $e')),
      );
    }
  }

  // ---------- Navigation helpers ----------
  Future<T?> _goTo<T>(Widget screen, {bool replace = false}) {
    final route = _buildPageRoute<T>(screen);
    if (replace) {
      return Navigator.pushReplacement<T, T?>(context, route);
    } else {
      return Navigator.push<T>(context, route);
    }
  }

  Future<void> _startRiasecFlow() async {
    final result = await _goTo<bool>(const RiasecTestScreen());
    if (result == true) {
      await _loadCompletionFlags();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('RIASEC saved.')));
    }
  }

  Future<void> _startNcaeFlow() async {
    // Still navigable if you keep the screen, but not counted in progress
    final result = await _goTo<bool>(const QuestionnaireScreen());
    if (result == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pre-Assessment saved.')));
    }
  }

  Future<void> _onTopNavTap(int idx) async {
    setState(() => _topNavIndex = idx);
    switch (idx) {
      case 0:
        break;
      case 1:
        final result = await _goTo<bool>(const QuestionnaireIntroScreen());
        if (result == true) await _loadCompletionFlags();
        break;
      case 2:
        await _goTo(const ExplorationScreen());
        break;
      case 3:
        await _goTo(const SkillsScreen(), replace: true);
        break;
    }
  }

  void _onBottomItemTapped(int index) {
    switch (index) {
      case 0:
        break;
      case 1:
        _goTo(const ExplorationScreen());
        break;
      case 2:
        _goTo(const SkillsScreen(), replace: true);
        break;
      case 3:
        _goTo(const ResourcesScreen());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double buttonWidth =
        (MediaQuery.of(context).size.width - 20 * 2 - 12) / 2;

    final bool showCareerSetup = !_loadingFlags && (!_riasecDone);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadProfile();
            await _loadCompletionFlags();
            await _loadQuizProgress();
          },
          color: const Color(0xFF3EB6FF),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // ── Top header ───────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4CC7FF), Color(0xFF3EB6FF)],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _headerWelcome(_firstName, _gradeLevel)),
                      InkWell(
                        onTap: () {},
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(
                            Icons.notifications,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Career Setup Panel (RIASEC + Preview only) ─────────────
                if (showCareerSetup)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: CareerSetupPanel(
                      onCompleted: () async {
                        await _loadCompletionFlags();
                        await _loadQuizProgress();
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8FFF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB6F2D3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF1FA971)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Career setup complete! Your strand and course are saved.',
                              style: TextStyle(fontFamily: 'Inter'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Navigation pills ───────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _navPill(
                            icon: Icons.home,
                            label: 'Home',
                            selected: _topNavIndex == 0,
                            onTap: () => _onTopNavTap(0),
                          ),
                          _navPill(
                            icon: Icons.receipt_long,
                            label: 'Assessment',
                            selected: _topNavIndex == 1,
                            onTap: () => _onTopNavTap(1),
                          ),
                          _navPill(
                            icon: Icons.explore,
                            label: 'Exploration',
                            selected: _topNavIndex == 2,
                            onTap: () => _onTopNavTap(2),
                          ),
                          _navPill(
                            icon: Icons.fitness_center,
                            label: 'Skills',
                            selected: _topNavIndex == 3,
                            onTap: () => _onTopNavTap(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Quick Actions ─────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _quickActionButton(
                            width: buttonWidth,
                            icon: Icons.psychology_alt,
                            label: 'Take RIASEC',
                            onTap: _startRiasecFlow,
                          ),
                          _quickActionButton(
                            width: buttonWidth,
                            icon: Icons.fact_check_outlined,
                            label: 'Pre-Assessment',
                            onTap: _startNcaeFlow,
                          ),
                          _quickActionButton(
                            width: buttonWidth,
                            icon: Icons.chat_bubble_outline,
                            label: 'Chat AI',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Chat AI coming soon!'),
                                ),
                              );
                            },
                          ),
                          _quickActionButton(
                            width: buttonWidth,
                            icon: Icons.show_chart,
                            label: 'Market Insights',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Market Insights coming soon!'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Main Progress Card (QUIZ-only) ─────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _progressCard(),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomTaskbar(
        selectedIndex: 0,
        onItemTapped: _onBottomItemTapped,
      ),
    );
  }

  // ---------- UI pieces ----------

  Widget _headerWelcome(String name, String gradeLevel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, $name',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            gradeLevel.isNotEmpty ? 'Grade $gradeLevel – Student' : 'Student',
            key: ValueKey(gradeLevel),
            style: const TextStyle(
              fontFamily: 'Inter',
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _navPill({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF8FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? const Color(0xFF3EB6FF) : Colors.grey[700],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: selected ? const Color(0xFF3EB6FF) : Colors.grey[800],
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionButton({
    required double width,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: const Color(0xFF3EB6FF)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ======= STAT CHIP (responsive, no overflow) =======
  Widget _statChip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final completed = _quizStats['completed'] ?? 0;
    final total = _quizStats['total'] ?? 0;
    final safeTotal = total == 0 ? 1 : total;

    // Average score among completed quizzes only
    final avgScore =
        _quizRows
            .where((r) => r.status == 'completed' && r.score != null)
            .map((r) => r.score!)
            .fold<int>(0, (p, s) => p + s) /
        (completed == 0 ? 1 : completed);

    final completionPct = (completed / safeTotal).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Quiz Progress',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          // ── Stats chips (Completed / Total) ─────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _statChip(
                icon: Icons.check_circle,
                label: '$completed Completed',
                bg: const Color(0xFFEFF9F2),
                fg: const Color(0xFF2E7D32),
              ),
              _statChip(
                icon: Icons.list_alt_rounded,
                label: '$total Total Quizzes',
                bg: const Color(0xFFFFF8E1),
                fg: const Color(0xFFB28704),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Big ring + average score (with labels) ─────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              CircularPercentIndicator(
                radius: 54,
                lineWidth: 10,
                percent: completionPct,
                center: Text(
                  '${(completionPct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                progressColor: const Color(0xFF3EB6FF),
                backgroundColor: Colors.grey.shade200,
                footer: const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Completion',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12.5),
                  ),
                ),
              ),
              CircularPercentIndicator(
                radius: 54,
                lineWidth: 10,
                percent: (avgScore / 100).clamp(0.0, 1.0),
                center: Text(
                  '${avgScore.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                progressColor: const Color(0xFF3EB6FF),
                backgroundColor: Colors.grey.shade200,
                footer: const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Average Score',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── List of quizzes with status ───────────
          if (_loadingQuizzes)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Column(
              children:
                  _quizRows
                      .map(
                        (r) => _quizListTile(
                          title: r.title,
                          status: r.status,
                          score: r.score,
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }

  Widget _quizListTile({
    required String title,
    required String status,
    int? score,
  }) {
    Color badgeBg;
    Color badgeFg;
    String badgeText;

    switch (status) {
      case 'completed':
        badgeBg = const Color(0xFFEFF9F2);
        badgeFg = const Color(0xFF2E7D32);
        badgeText = score != null ? 'Completed • $score%' : 'Completed';
        break;
      case 'in_progress':
        badgeBg = const Color(0xFFEFF3FF);
        badgeFg = const Color(0xFF2A6FE4);
        badgeText = 'In progress';
        break;
      default:
        badgeBg = Colors.grey.shade100;
        badgeFg = Colors.grey.shade700;
        badgeText = 'Not started';
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: badgeFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NOTE: generic Route<T> so Navigator.push<T> is happy.
  static Route<T> _buildPageRoute<T>(Widget screen) {
    return PageRouteBuilder<T>(
      pageBuilder: (c, a, sa) => screen,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (c, anim, sa, child) {
        final slide = Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        final fade = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));
        return SlideTransition(
          position: anim.drive(slide),
          child: FadeTransition(opacity: anim.drive(fade), child: child),
        );
      },
    );
  }
}

// ── Small model for the list ─────────────────────────────────────────
class _QuizRow {
  final String id;
  final String title;
  final String status; // completed | in_progress | not_started
  final int? score;
  _QuizRow({
    required this.id,
    required this.title,
    required this.status,
    this.score,
  });
}
