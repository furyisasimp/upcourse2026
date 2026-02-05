import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'quiz_intro_screen.dart';
import '../widgets/custom_taskbar.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // NEW

class QuizCategoriesScreen extends StatefulWidget {
  const QuizCategoriesScreen({Key? key}) : super(key: key);

  @override
  State<QuizCategoriesScreen> createState() => _QuizCategoriesScreenState();
}

class _QuizCategoriesScreenState extends State<QuizCategoriesScreen> {
  // UI meta for known strands
  static const Map<String, ({String title, IconData icon, Color color})> _meta =
      {
        'ABM': (
          title: 'ABM — Business & Finance',
          icon: Icons.payments_outlined,
          color: Color(0xFF3EB6FF),
        ),
        'GAS': (
          title: 'GAS — General Academic Strand',
          icon: Icons.menu_book_outlined,
          color: Color(0xFF7E57C2),
        ),
        'STEM': (
          title: 'STEM — Science & Technology',
          icon: Icons.science_outlined,
          color: Color(0xFF4CAF50),
        ),
        'TECHPRO': (
          title: 'TechPro — TVL / Tech-Voc',
          icon: Icons.build_circle_outlined,
          color: Color(0xFFFF7043),
        ),
      };

  // Discovered quizzes (raw)
  List<Map<String, dynamic>> _categories = [];

  // Partitioned lists
  List<Map<String, dynamic>> _available = []; // no attempt yet + gate allows
  List<Map<String, dynamic>> _answered =
      []; // attempt exists (awaiting or returned)

  // Hover state keyed by quiz id (web nicety)
  final Map<String, bool> _hovering = {};

  // UI state
  bool _loading = true;
  bool _checkingLocks = false;
  String? _error;
  int _selectedIndex = 2;

  // Search & filter
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _categories = [];
      _available = [];
      _answered = [];
      _hovering.clear();
    });

    await _loadCategoriesFromStorage();
    if (mounted && _categories.isNotEmpty) {
      await _partitionByStatus();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCategoriesFromStorage() async {
    try {
      final files = await SupabaseService.listFiles(
        bucket: 'quizzes',
        path: '',
      );

      String _toId(String name) {
        final base =
            name.toLowerCase().endsWith('.json')
                ? name.substring(0, name.length - 5)
                : name;
        final noPrefix =
            base.startsWith('quiz_') ? base.substring('quiz_'.length) : base;
        return noPrefix.toUpperCase(); // ABM, GAS, STEM, TECHPRO or custom ids
      }

      final ids =
          files
              .where((f) => f.toLowerCase().endsWith('.json'))
              .map(_toId)
              .toSet()
              .toList();

      if (ids.isEmpty) {
        _applyFallback();
      } else {
        _categories =
            ids.map((id) {
              final info =
                  _meta[id] ??
                  (
                    title: '$id — Practice Quiz',
                    icon: Icons.quiz_outlined,
                    color: const Color(0xFF81D4FA),
                  );
              return {
                'id': id,
                'title': info.title,
                'icon': info.icon,
                'color': info.color,
              };
            }).toList();
      }
    } catch (e) {
      _applyFallback();
      _error = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Showing default categories (fetch failed): $e'),
          ),
        );
      }
    }
  }

  // Decide Available / Awaiting / Returned using both the gate and the latest attempt.
  Future<void> _partitionByStatus() async {
    setState(() => _checkingLocks = true);
    try {
      final cards = await Future.wait(
        _categories.map((cat) async {
          final id = cat['id'] as String;

          // Gate (can the student currently take this bank quiz?)
          bool canTake = true;
          try {
            canTake = await SupabaseService.canTakeBankQuiz(id);
          } catch (_) {
            canTake = true; // fail-open on errors
          }

          // Latest attempt (case-insensitive by your updated service)
          Map<String, dynamic>? latest;
          try {
            latest = await SupabaseService.getLatestAttemptForQuiz(
              quizIdExact: id,
              altIdForFallback: id,
            );
          } catch (_) {
            latest = null;
          }

          final hasAttempt = latest != null;
          final isReturned = latest?['is_returned'] == true;

          _QuizStatus status;
          if (!hasAttempt && canTake) {
            status = _QuizStatus.available;
          } else if (hasAttempt && !isReturned) {
            status = _QuizStatus.awaiting;
          } else {
            status = _QuizStatus.returned;
          }

          return _CardModel(
            id: id,
            title: cat['title'] as String,
            icon: cat['icon'] as IconData,
            color: cat['color'] as Color,
            status: status,
          ).toMap();
        }),
      );

      _available = [];
      _answered = [];
      for (final m in cards) {
        final status = m['status'] as String;
        if (status == _QuizStatus.available.name) {
          _available.add(m);
        } else {
          _answered.add(m);
        }
        _hovering[m['id'] as String] = false;
      }
    } finally {
      if (mounted) setState(() => _checkingLocks = false);
    }
  }

  void _applyFallback() {
    _categories =
        _meta.entries
            .map(
              (e) => {
                'id': e.key,
                'title': e.value.title,
                'icon': e.value.icon,
                'color': e.value.color,
              },
            )
            .toList();
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  void _navigateToIntro(String categoryId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                QuizIntroScreen(categoryId: categoryId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  // Responsive helpers
  (double hPad, int cols, double aspect) _layoutSpec(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1400) return (32, 4, 1.05);
    if (w >= 1100) return (28, 4, 1.02);
    if (w >= 900) return (24, 3, 1.0);
    if (w >= 700) return (22, 2, 0.95);
    if (w >= 520) return (18, 2, 0.9);
    return (16, 1, 1.55);
  }

  List<Map<String, dynamic>> _applySearchAndFilter() {
    List<Map<String, dynamic>> src;
    switch (_filter) {
      case _Filter.available:
        src = _available;
        break;
      case _Filter.completed: // maps to answered (awaiting + returned)
        src = _answered;
        break;
      default:
        src = [..._available, ..._answered];
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((e) {
      final id = (e['id'] ?? '').toString().toLowerCase();
      final title = (e['title'] ?? '').toString().toLowerCase();
      return id.contains(q) || title.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _checkingLocks;
    final (hPad, cols, aspect) = _layoutSpec(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF7FBFF),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Quizzes',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : _refreshAll,
            icon: const Icon(Icons.refresh, color: Colors.black87),
          ),
        ],
      ),
      body:
          busy
              ? const Center(child: CircularProgressIndicator())
              : (_available.isEmpty && _answered.isEmpty)
              ? _EmptyState(onRetry: _refreshAll, error: _error)
              : RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 16),
                  children: [
                    // Search + Filter Row
                    _SearchAndFilterBar(
                      initialQuery: _query,
                      counts: (
                        all: _available.length + _answered.length,
                        available: _available.length,
                        completed: _answered.length,
                      ),
                      onQueryChanged: (q) => setState(() => _query = q),
                      selected: _filter,
                      onFilterChanged: (f) => setState(() => _filter = f),
                    ),
                    const SizedBox(height: 12),

                    // Results meta
                    Builder(
                      builder: (context) {
                        final filtered = _applySearchAndFilter();
                        return _ResultsBanner(
                          total: filtered.length,
                          showHint: _query.isNotEmpty,
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Grid (filtered view)
                    _ResponsiveGrid(
                      cols: cols,
                      aspect: aspect,
                      available: _available,
                      completed: _answered,
                      hovering: _hovering,
                      query: _query,
                      filter: _filter,
                      onTapAny: _navigateToIntro, // always go to Intro
                    ),
                  ],
                ),
              ),
      bottomNavigationBar: CustomTaskbar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }
}

enum _Filter { all, available, completed }

// ---------- Search & filter UI ----------

class _SearchAndFilterBar extends StatelessWidget {
  final String initialQuery;
  final ({int all, int available, int completed}) counts;
  final ValueChanged<String> onQueryChanged;
  final _Filter selected;
  final ValueChanged<_Filter> onFilterChanged;

  const _SearchAndFilterBar({
    required this.initialQuery,
    required this.counts,
    required this.onQueryChanged,
    required this.selected,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        // Search box
        SizedBox(
          width: 420,
          child: TextField(
            controller: TextEditingController(text: initialQuery),
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search quizzes',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Filters
        _FilterChip(
          label: 'All (${counts.all})',
          selected: selected == _Filter.all,
          onTap: () => onFilterChanged(_Filter.all),
        ),
        _FilterChip(
          label: 'Available (${counts.available})',
          selected: selected == _Filter.available,
          onTap: () => onFilterChanged(_Filter.available),
        ),
        _FilterChip(
          label: 'Answered (${counts.completed})',
          selected: selected == _Filter.completed,
          onTap: () => onFilterChanged(_Filter.completed),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.black87 : Colors.black12),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                  : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _ResultsBanner extends StatelessWidget {
  final int total;
  final bool showHint;

  const _ResultsBanner({required this.total, required this.showHint});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded, size: 18),
          const SizedBox(width: 8),
          Text(
            '$total result${total == 1 ? '' : 's'}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (showHint)
            const Text(
              'Tip: Clear the search to see everything',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Grid & cards ----------

enum _QuizStatus { available, awaiting, returned }

class _ResponsiveGrid extends StatelessWidget {
  final int cols;
  final double aspect;
  final List<Map<String, dynamic>> available;
  final List<Map<String, dynamic>> completed; // awaiting + returned
  final Map<String, bool> hovering;
  final String query;
  final _Filter filter;
  final void Function(String id) onTapAny;

  const _ResponsiveGrid({
    required this.cols,
    required this.aspect,
    required this.available,
    required this.completed,
    required this.hovering,
    required this.query,
    required this.filter,
    required this.onTapAny,
  });

  List<_CardModel> _filtered() {
    // merge and then filter by tab
    List<_CardModel> src = [
      ...available.map(_CardModel.fromMap),
      ...completed.map(_CardModel.fromMap),
    ];

    if (filter == _Filter.available) {
      src = src.where((m) => m.status == _QuizStatus.available).toList();
    } else if (filter == _Filter.completed) {
      src = src.where((m) => m.status != _QuizStatus.available).toList();
    }

    final q = query.trim().toLowerCase();
    if (q.isEmpty) return src;

    return src
        .where(
          (e) =>
              e.id.toLowerCase().contains(q) ||
              e.title.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: Text(
            'No matches.',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.black.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: aspect,
      ),
      itemBuilder: (ctx, i) {
        final m = items[i];
        final isHovered = kIsWeb ? (hovering[m.id] ?? false) : false;

        final locked = m.status != _QuizStatus.available;
        final gradient = LinearGradient(
          colors:
              locked
                  ? [Colors.grey.shade300, Colors.grey.shade200]
                  : [m.color.withOpacity(0.30), m.color.withOpacity(0.45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

        String chipText;
        IconData chipIcon;
        if (m.status == _QuizStatus.available) {
          chipText = 'Tap to start';
          chipIcon = Icons.play_arrow_rounded;
        } else if (m.status == _QuizStatus.awaiting) {
          chipText = 'Awaiting review · Tap to view';
          chipIcon = Icons.hourglass_bottom_rounded;
        } else {
          chipText = 'Returned · Tap to view';
          chipIcon = Icons.visibility_rounded;
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click, // allow click for both states
          onEnter: (_) {
            if (!kIsWeb) return;
            hovering[m.id] = true;
            (ctx as Element).markNeedsBuild();
          },
          onExit: (_) {
            if (!kIsWeb) return;
            hovering[m.id] = false;
            (ctx as Element).markNeedsBuild();
          },
          child: AnimatedScale(
            scale: isHovered && !locked ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                splashColor: m.color.withOpacity(0.25),
                onTap: () => onTapAny(m.id), // Intro decides start vs view
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (locked ? Colors.black26 : m.color)
                                .withOpacity(isHovered ? 0.35 : 0.25),
                            blurRadius: isHovered ? 12 : 8,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color:
                              locked
                                  ? Colors.grey.shade400
                                  : Colors.transparent,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                locked
                                    ? Colors.grey
                                    : m.color.withOpacity(0.95),
                            radius: 28,
                            child: Icon(m.icon, color: Colors.white, size: 28),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            m.title,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87.withOpacity(
                                locked ? 0.65 : 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _StatusChip(text: chipText, icon: chipIcon),
                        ],
                      ),
                    ),

                    // Corner badge for awaiting/returned
                    if (m.status != _QuizStatus.available)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                m.status == _QuizStatus.returned
                                    ? Icons.check_circle_rounded
                                    : Icons.hourglass_bottom_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                // 🔹 Updated labels per your request
                                m.status == _QuizStatus.returned
                                    ? 'Returned'
                                    : 'To be reviewed',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _StatusChip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Models & empty ----------

class _CardModel {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final _QuizStatus status;

  _CardModel({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'icon': icon,
    'color': color,
    'status': status.name,
  };

  static _CardModel fromMap(Map<String, dynamic> m) {
    final s = m['status'];
    final status =
        s is String
            ? (s == 'awaiting'
                ? _QuizStatus.awaiting
                : s == 'returned'
                ? _QuizStatus.returned
                : _QuizStatus.available)
            : _QuizStatus.available;
    return _CardModel(
      id: m['id'] as String,
      title: m['title'] as String,
      icon: m['icon'] as IconData,
      color: m['color'] as Color,
      status: status,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? error;
  const _EmptyState({required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_rounded, size: 48, color: Colors.blueGrey),
            const SizedBox(height: 10),
            const Text(
              'No quiz categories found',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Inter'),
              ),
            ],
            const SizedBox(height: 12),
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
