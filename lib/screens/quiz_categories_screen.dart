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

      // Filter to JSON files
      final jsonFiles =
          files.where((f) => f.toLowerCase().endsWith('.json')).toList();

      if (jsonFiles.isEmpty) {
        _applyFallback();
        return;
      }

      // Fetch each JSON to extract quiz_id, quiz_title, storage_path, and other dynamic data
      final categories = <Map<String, dynamic>>[];
      for (final file in jsonFiles) {
        try {
          // Fetch the JSON content
          final jsonData = await SupabaseService.fetchQuizJsonByPath(file);
          if (jsonData != null && jsonData['quiz_id'] != null) {
            final quizId = jsonData['quiz_id'] as String;
            final quizTitle =
                jsonData['quiz_title'] as String? ?? 'Untitled Quiz';
            final storagePath =
                jsonData['storage_path'] as String? ??
                file; // Use storage_path if available, else fallback to file name
            final quizType = jsonData['type'] as String? ?? 'General';

            // Dynamic icon and color based on type (or use defaults)
            IconData icon;
            Color color;
            switch (quizType.toLowerCase()) {
              case 'career interest':
                icon = Icons.business_center_outlined;
                color = const Color(0xFF4CAF50); // Green for career-related
                break;
              case 'academic':
                icon = Icons.school_outlined;
                color = const Color(0xFF2196F3); // Blue for academic
                break;
              default:
                icon = Icons.quiz_outlined;
                color = const Color(0xFF81D4FA); // Default neutral
            }

            // Check if it's a known strand (fallback to _meta if needed)
            final knownMeta = _meta[quizId];
            if (knownMeta != null) {
              // Use _meta for legacy strands
              categories.add({
                'id': quizId,
                'title': knownMeta.title,
                'icon': knownMeta.icon,
                'color': knownMeta.color,
                'storage_path': storagePath, // Add storage_path
              });
            } else {
              // Use JSON data for dynamic quizzes
              categories.add({
                'id': quizId,
                'title': quizTitle,
                'icon': icon,
                'color': color,
                'storage_path': storagePath, // Add storage_path
              });
            }
          }
        } catch (e) {
          // Skip invalid files
          debugPrint('Failed to load quiz from $file: $e');
        }
      }

      if (categories.isEmpty) {
        _applyFallback();
      } else {
        // Sort for consistent order (e.g., by title or ID)
        categories.sort(
          (a, b) => (a['title'] as String).compareTo(b['title'] as String),
        );
        _categories = categories;
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
            storagePath: cat['storage_path'] as String, // Add from cat map
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

  void _navigateToIntro(String categoryId, String storagePath) {
    // Add storagePath parameter
    print(
      'Navigating to QuizIntroScreen with categoryId: $categoryId, storagePath: $storagePath',
    ); // DEBUG
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder:
            (context, animation, secondaryAnimation) => QuizIntroScreen(
              categoryId: categoryId,
              storagePath: storagePath,
            ), // Pass storagePath
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
    if (w >= 1400) return (w * 0.05, 4, 1.0); // 5% of width for large screens
    if (w >= 1100) return (w * 0.04, 4, 1.0);
    if (w >= 900) return (w * 0.035, 3, 1.05);
    if (w >= 700) return (w * 0.03, 2, 1.1);
    if (w >= 520) return (w * 0.025, 2, 1.15);
    return (w * 0.02, 1, 1.2); // 2% for very small screens
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7FBFF),
        centerTitle: true,
        title: Text(
          'Quizzes',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: screenWidth < 600 ? 18 : 20, // Responsive font
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
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    hPad,
                    12,
                    hPad,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    children: [
                      // Search + Filter Row
                      _SearchAndFilterBar(
                        initialQuery: _query,
                        counts: {
                          'all': _available.length + _answered.length,
                          'available': _available.length,
                          'completed': _answered.length,
                        },
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

                      // Conditional sections: Separate available and answered when "All" is selected
                      if (_filter == _Filter.all) ...[
                        // Available Section
                        if (_available.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Available Quizzes',
                            count: _available.length,
                          ),
                          const SizedBox(height: 8),
                          _ResponsiveGrid(
                            // Removed Flexible
                            cols: cols,
                            aspect: aspect,
                            available: _available,
                            completed: _answered,
                            hovering: _hovering,
                            query: _query,
                            filter: _Filter.available,
                            onTapAny:
                                (id, storagePath) =>
                                    _navigateToIntro(id, storagePath),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Answered Section
                        if (_answered.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Answered Quizzes',
                            count: _answered.length,
                          ),
                          const SizedBox(height: 8),
                          _ResponsiveGrid(
                            // Removed Flexible
                            cols: cols,
                            aspect: aspect,
                            available: const [],
                            completed: _answered,
                            hovering: _hovering,
                            query: _query,
                            filter: _Filter.completed,
                            onTapAny:
                                (id, storagePath) => _navigateToIntro(
                                  id,
                                  storagePath,
                                ), // Fixed: Use lambda for consistency
                          ),
                        ],
                      ] else ...[
                        // Single Grid for "Available" or "Answered" filters
                        _ResponsiveGrid(
                          // Removed Flexible
                          cols: cols,
                          aspect: aspect,
                          available: _available,
                          completed: _answered,
                          hovering: _hovering,
                          query: _query,
                          filter: _filter,
                          onTapAny:
                              (id, storagePath) => _navigateToIntro(
                                id,
                                storagePath,
                              ), // Fixed: Use lambda for consistency
                        ),
                      ],
                    ],
                  ),
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
  final Map<String, int> counts;
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Wrap(
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: screenWidth < 600 ? 8 : 12, // Responsive spacing
      children: [
        // Search box
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth * 0.8, // 80% of screen width, max 400
          ),
          child: SizedBox(
            width: double.infinity, // Allow it to expand within constraints
            child: TextField(
              controller: TextEditingController(text: initialQuery),
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: screenWidth < 600 ? 14 : 16, // Responsive font
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search quizzes',
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03, // 3% of width
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),

        // Filters
        _FilterChip(
          label: 'All (${counts['all'] ?? 0})',
          selected: selected == _Filter.all,
          onTap: () => onFilterChanged(_Filter.all),
        ),
        _FilterChip(
          label: 'Available (${counts['available'] ?? 0})',
          selected: selected == _Filter.available,
          onTap: () => onFilterChanged(_Filter.available),
        ),
        _FilterChip(
          label: 'Answered (${counts['completed'] ?? 0})',
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
    final screenWidth = MediaQuery.of(context).size.width;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03, // 3% of width
          vertical: 8,
        ),
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
            fontSize: screenWidth < 600 ? 12 : 13, // Responsive font
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
    final screenWidth = MediaQuery.of(context).size.width;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.03, // 3% of width
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded, size: 18),
          SizedBox(width: screenWidth * 0.02), // 2% of width
          Text(
            '$total result${total == 1 ? '' : 's'}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: screenWidth < 600 ? 13 : 14, // Responsive font
            ),
          ),
          const Spacer(),
          if (showHint)
            Text(
              'Tip: Clear the search to see everything',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: screenWidth < 600 ? 11 : 12, // Responsive font
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
  final void Function(String id, String storagePath)
  onTapAny; // Update type to accept storagePath

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

    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * 0.42; // ~42% of screen width
    final maxTileWidth = 280.0; // Cap at 280px for large screens

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tileWidth.clamp(
          120,
          maxTileWidth,
        ), // Min 120, max 280
        crossAxisSpacing: screenWidth * 0.02, // 2% of width
        mainAxisSpacing: screenWidth * 0.02, // 2% of width
        childAspectRatio: aspect,
      ),
      itemBuilder: (ctx, i) {
        final m = items[i];
        final isHovered = kIsWeb ? (hovering[m.id] ?? false) : false;
        final tileScreenWidth = MediaQuery.of(ctx).size.width;

        final locked = m.status != _QuizStatus.available;
        final gradient = LinearGradient(
          colors:
              (() {
                if (m.status == _QuizStatus.available) {
                  return [m.color.withOpacity(0.30), m.color.withOpacity(0.45)];
                } else if (m.status == _QuizStatus.awaiting) {
                  return [Colors.amber.shade200, Colors.amber.shade300];
                } else if (m.status == _QuizStatus.returned) {
                  return [Colors.green.shade200, Colors.green.shade300];
                }
                return [Colors.grey.shade300, Colors.grey.shade200];
              })(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

        String chipText;
        IconData chipIcon;
        if (m.status == _QuizStatus.available) {
          chipText = 'Tap to View';
          chipIcon = Icons.play_arrow_rounded;
        } else if (m.status == _QuizStatus.awaiting) {
          chipText = 'Awaiting review · Tap to view';
          chipIcon = Icons.hourglass_bottom_rounded;
        } else {
          chipText = 'Returned · Tap to view';
          chipIcon = Icons.visibility_rounded;
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
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
          child: SizedBox(
            // Add this to constrain AnimatedScale
            width: double.infinity,
            child: AnimatedScale(
              scale: isHovered && !locked ? 1.03 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: ClipRect(
                // Prevents overflow
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    splashColor: m.color.withOpacity(0.25),
                    onTap: () => onTapAny(m.id, m.storagePath),
                    child: Stack(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (() {
                                      if (m.status == _QuizStatus.available) {
                                        return m.color.withOpacity(
                                          isHovered ? 0.35 : 0.25,
                                        );
                                      } else if (m.status ==
                                          _QuizStatus.awaiting) {
                                        return Colors.amber.withOpacity(
                                          isHovered ? 0.35 : 0.25,
                                        );
                                      } else if (m.status ==
                                          _QuizStatus.returned) {
                                        return Colors.green.withOpacity(
                                          isHovered ? 0.35 : 0.25,
                                        );
                                      }
                                      return Colors.black26.withOpacity(
                                        isHovered ? 0.35 : 0.25,
                                      );
                                    })(),
                                blurRadius: isHovered ? 12 : 8,
                                offset: const Offset(0, 6),
                              ),
                            ],
                            border: Border.all(
                              color:
                                  (() {
                                    if (m.status == _QuizStatus.available) {
                                      return Colors.transparent;
                                    } else if (m.status ==
                                        _QuizStatus.awaiting) {
                                      return Colors.amber.shade400;
                                    } else if (m.status ==
                                        _QuizStatus.returned) {
                                      return Colors.green.shade400;
                                    }
                                    return Colors.grey.shade400;
                                  })(),
                            ),
                          ),
                          padding: EdgeInsets.all(
                            tileScreenWidth * 0.03,
                          ), // 3% of tile width
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    (() {
                                      if (m.status == _QuizStatus.available) {
                                        return m.color.withOpacity(0.95);
                                      } else if (m.status ==
                                          _QuizStatus.awaiting) {
                                        return Colors.amber.shade600;
                                      } else if (m.status ==
                                          _QuizStatus.returned) {
                                        return Colors.green.shade600;
                                      }
                                      return Colors.grey;
                                    })(),
                                radius:
                                    tileScreenWidth * 0.06, // 6% of tile width
                                child: Icon(
                                  m.icon,
                                  color: Colors.white,
                                  size:
                                      tileScreenWidth *
                                      0.06, // 6% of tile width
                                ),
                              ),
                              SizedBox(
                                height: tileScreenWidth * 0.02,
                              ), // 2% of tile width
                              SizedBox(
                                height:
                                    tileScreenWidth * 0.12, // 12% of tile width
                                child: Text(
                                  m.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: tileScreenWidth < 600 ? 12 : 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87.withOpacity(
                                      locked ? 0.65 : 1,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: tileScreenWidth * 0.015,
                              ), // 1.5% of tile width
                              _StatusChip(text: chipText, icon: chipIcon),
                            ],
                          ),
                        ),

                        // Corner badge for awaiting/returned
                        if (m.status != _QuizStatus.available)
                          Positioned(
                            top: tileScreenWidth * 0.015, // 1.5% of tile width
                            right:
                                tileScreenWidth * 0.015, // 1.5% of tile width
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal:
                                    tileScreenWidth * 0.01, // 1% of tile width
                                vertical:
                                    tileScreenWidth *
                                    0.005, // 0.5% of tile width
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (() {
                                      if (m.status == _QuizStatus.awaiting) {
                                        return Colors.amber.withOpacity(0.8);
                                      } else if (m.status ==
                                          _QuizStatus.returned) {
                                        return Colors.green.withOpacity(0.8);
                                      }
                                      return Colors.black.withOpacity(0.55);
                                    })(),
                                borderRadius: BorderRadius.circular(
                                  tileScreenWidth * 0.02, // 2% of tile width
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    m.status == _QuizStatus.returned
                                        ? Icons.check_circle_rounded
                                        : Icons.hourglass_bottom_rounded,
                                    size:
                                        tileScreenWidth *
                                        0.025, // 2.5% of tile width
                                    color: Colors.white,
                                  ),
                                  SizedBox(
                                    width: tileScreenWidth * 0.005,
                                  ), // 0.5% of tile width
                                  Text(
                                    m.status == _QuizStatus.returned
                                        ? 'Returned'
                                        : 'To be reviewed',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: tileScreenWidth < 600 ? 9 : 10,
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.03, // 3% of width
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: screenWidth * 0.04,
            color: Colors.black87,
          ), // 4% of width
          SizedBox(width: screenWidth * 0.015), // 1.5% of width
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: screenWidth < 600 ? 12 : 13, // Responsive font
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
  final String storagePath; // Add this field

  _CardModel({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.status,
    required this.storagePath, // Add to constructor
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'icon': icon,
    'color': color,
    'status': status.name,
    'storage_path': storagePath, // Add to map
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
      storagePath: m['storage_path'] as String, // Add from map
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? error;
  const _EmptyState({required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.06), // 6% of width
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_rounded,
              size: screenWidth * 0.12, // 12% of width
              color: Colors.blueGrey,
            ),
            SizedBox(height: screenWidth * 0.025), // 2.5% of width
            Text(
              'No quiz categories found',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: screenWidth < 600 ? 16 : 18, // Responsive font
              ),
            ),
            if (error != null) ...[
              SizedBox(height: screenWidth * 0.015), // 1.5% of width
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: screenWidth < 600 ? 13 : 14, // Responsive font
                ),
              ),
            ],
            SizedBox(height: screenWidth * 0.04), // 4% of width
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.06, // 6% of width
                  vertical: screenWidth * 0.015, // 1.5% of width
                ),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: screenWidth < 600 ? 14 : 16, // Responsive font
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- New Section Header Widget ----------

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({Key? key, required this.title, required this.count})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.03, // 3% of width
        vertical: screenWidth * 0.02, // 2% of width
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: screenWidth < 600 ? 14 : 16, // Responsive font
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: screenWidth < 600 ? 12 : 14, // Responsive font
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
