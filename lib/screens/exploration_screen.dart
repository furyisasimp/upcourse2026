// lib/screens/exploration_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home_screen.dart';
import 'quiz_categories_screen.dart';
import 'profile_details_screen.dart';
import '../widgets/custom_taskbar.dart';
import '../services/supabase_service.dart';
import '../models/exploration_models.dart'; // Track / Pathway / SourceLink

// ===== THEME =====
const kPrimaryBlue = Color(0xFF3EB6FF);
const kBgSky = Color(0xFFEAF8FF);
const kTextPrimary = Color(0xFF121212);
const kTextSecondary = Color(0xFF667085);
const kCardShadow = Color(0x1A000000);

// Hex → Color helper
Color _hex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

class ExplorationScreen extends StatefulWidget {
  const ExplorationScreen({Key? key}) : super(key: key);

  @override
  State<ExplorationScreen> createState() => _ExplorationScreenState();
}

class _ExplorationScreenState extends State<ExplorationScreen> {
  final Map<String, GlobalKey> _trackKeys = {}; // built after fetch
  final _scrollController = ScrollController();

  // Small recommender (kept)
  final _interests = <String>{
    'Math/Logic',
    'Science',
    'Programming',
    'Design/UX',
    'Analytics',
    'Robotics',
  };
  final _selected = <String>{'Programming', 'Math/Logic'};

  Future<_VM>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<_VM> _load() async {
    // Pull the user's track code (e.g., TECHPRO / ACADEMIC / STEM)
    final userCode = await SupabaseService.getUserTrackCode();

    Track? userTrack;
    if (userCode != null && userCode.isNotEmpty) {
      userTrack = await SupabaseService.getTrackByCode(userCode);
    }

    final tracks = await SupabaseService.listTracks();

    _trackKeys
      ..clear()
      ..addEntries(tracks.map((t) => MapEntry(t.code, GlobalKey())));

    return _VM(userTrack: userTrack, tracks: tracks);
  }

  // Open URLs safely
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgSky,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(110),
        child: _CurvedHeader(
          title: 'Exploration',
          subtitle: 'Discover Tracks & College Pathways',
          trailingIcon: Icons.explore_rounded,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_VM>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }

            final vm = snap.data!;
            final userTrack = vm.userTrack;
            final tracks = vm.tracks;

            final ordered = <Track>[
              if (userTrack != null) userTrack,
              ...tracks.where(
                (t) => userTrack == null || t.code != userTrack.code,
              ),
            ];

            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    userTrack != null
                        ? 'Recommended for You'
                        : 'Recommended Tracks',
                    userTrack != null
                        ? 'Based on your profile: ${userTrack.name}'
                        : 'Based on your interests',
                  ),

                  // Dynamic cards (e.g., Academic, TVL-ICT, TVL-HE, Arts & Design, Sports)
                  ...ordered.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _shsTrackCard(
                        key: _trackKeys[t.code],
                        title: t.name,
                        match:
                            (userTrack != null && t.code == userTrack.code)
                                ? 'Your track'
                                : 'Explore',
                        description: t.summary,
                        points: t.points,
                        gradient: LinearGradient(
                          colors: [_hex(t.gradientStart), _hex(t.gradientEnd)],
                        ),
                        badgeColor: _hex(t.badgeColor),
                        icon: _iconForTrack(t.code),
                        onTap:
                            () => _showTrackSheet(
                              context,
                              trackCode: t.code, // code to fetch pathways
                              track: t.name,
                              summary: t.summary,
                              sampleCurriculum: t.sampleCurriculum,
                              entryRoles: t.entryRoles,
                              skills: t.skills,
                              sources:
                                  t.sources
                                      .map((x) => _Source(x.name, x.url))
                                      .toList(),
                            ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // College Pathways (inline) – show for user's track if available
                  _sectionTitle(
                    'College Pathways',
                    userTrack != null
                        ? 'For ${userTrack.name}'
                        : 'Tap a track to view',
                  ),
                  if (userTrack != null)
                    FutureBuilder<List<PathwayMatch>>(
                      future: SupabaseService.listPathwaysForStrand(
                        userTrack.code,
                      ),
                      builder: (context, s) {
                        if (s.connectionState != ConnectionState.done) {
                          return _coursesContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          );
                        }
                        if (s.hasError) {
                          return _coursesContainer(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Failed to load pathways: ${s.error}',
                                style: const TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }
                        final rows = s.data ?? const [];
                        if (rows.isEmpty) {
                          return _coursesContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No pathways found yet for this track.',
                                style: TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }
                        return _coursesContainer(
                          child: Column(
                            children: rows.map(_pathwayTile).toList(),
                          ),
                        );
                      },
                    )
                  else
                    _coursesContainer(
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          "Pathways appear after you choose or are matched to a track. "
                          "Tap any track card above to see its pathways.",
                          style: TextStyle(fontFamily: 'Inter'),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                  _sectionTitle(
                    'Labor Market & Salary Links',
                    'Check latest official stats',
                  ),
                  _marketInsights(
                    onDole: () => _openUrl('https://ble.dole.gov.ph/'),
                    onPsa:
                        () => _openUrl(
                          'https://psa.gov.ph/statistics/survey/labor-and-employment',
                        ),
                    onPhilJobNet: () => _openUrl('https://philjobnet.gov.ph/'),
                  ),

                  const SizedBox(height: 20),
                  _sectionTitle(
                    'AI Career Counselor (Lite)',
                    'Pick interests to get track suggestions',
                  ),
                  _aiCounselorCard(
                    interests: _interests,
                    selected: _selected,
                    onToggle:
                        (s) => setState(() {
                          _selected.contains(s)
                              ? _selected.remove(s)
                              : _selected.add(s);
                        }),
                    onRecommend: () {
                      final rec = _recommend(_selected);
                      _showRecommendationDialog(rec);
                    },
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: CustomTaskbar(
        selectedIndex: 1,
        onItemTapped: (index) {
          if (index == 1) return;
          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
              break;
            case 2:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const QuizCategoriesScreen()),
              );
              break;
            case 3:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()),
              );
              break;
          }
        },
      ),
    );
  }

  // Icons per track (adjust to your codes)
  IconData _iconForTrack(String code) {
    switch (code.toUpperCase()) {
      case 'ACAD':
      case 'ACADTRACK':
        return Icons.menu_book_rounded; // Academic
      case 'TVL-ICT':
      case 'TECHPRO':
      case 'TVL':
        return Icons.memory_rounded; // TVL/ICT
      case 'TVL-HE':
        return Icons.restaurant_rounded; // Home Economics
      case 'ARTS':
      case 'ARTS&DESIGN':
      case 'ARTS-DESIGN':
        return Icons.brush_rounded; // Arts & Design
      case 'SPORTS':
        return Icons.sports_soccer_rounded; // Sports
      default:
        return Icons.school_rounded;
    }
  }

  // --- Simple heuristic recommender (now returns track codes)
  List<String> _recommend(Set<String> picks) {
    int acadScore = 0, tvlIctScore = 0;
    for (final p in picks) {
      switch (p) {
        case 'Programming':
        case 'Design/UX':
        case 'Analytics':
          tvlIctScore += 2;
          break;
        case 'Math/Logic':
        case 'Science':
        case 'Robotics':
          acadScore += 2;
          break;
      }
    }
    if (acadScore == tvlIctScore) return ['ACAD', 'TVL-ICT']; // neutral nudge
    return (tvlIctScore > acadScore) ? ['TVL-ICT'] : ['ACAD'];
  }

  void _scrollToTrack(String code) {
    final key = _trackKeys[code];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      alignment: 0.1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ====== PATHWAYS UI ======
  static Widget _coursesContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }

  static Widget _riasecBadge(String code) {
    final txt = code.isEmpty ? '-' : code.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(
        txt,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          color: Color(0xFF2563EB),
          fontSize: 12,
        ),
      ),
    );
  }

  // New compact renderer for Pathway + label
  static Widget _pathwayTile(PathwayMatch pm) {
    final p = pm.pathway;
    final hasOutcomes = p.outcomes.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: kPrimaryBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (pm.matchLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    pm.matchLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          if (p.subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              p.subtitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: kTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (hasOutcomes) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.outcomes.take(4).map((o) => _skillChip(o)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ===== UI helpers (kept) =====
  Widget _sectionTitle(String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: kTextSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _shsTrackCard({
    required Key? key,
    required String title,
    required String match,
    required String description,
    required List<String> points,
    required LinearGradient gradient,
    required Color badgeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: badgeColor.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: badgeColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    match,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontFamily: 'Inter')),
            const SizedBox(height: 8),
            ...points.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketInsights({
    required VoidCallback onDole,
    required VoidCallback onPsa,
    required VoidCallback onPhilJobNet,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.insights_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Official sources for latest trends',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _trendBar(label: 'Digital jobs demand', value: 0.82),
          const SizedBox(height: 6),
          _trendBar(label: 'Entry-level opportunities', value: 0.64),
          const SizedBox(height: 6),
          _trendBar(label: 'STEM pathway relevance', value: 0.76),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _linkChip('DOLE LMI', Icons.trending_up, onDole),
              _linkChip('PSA Labor Stats', Icons.bar_chart, onPsa),
              _linkChip('PhilJobNet', Icons.work_outline, onPhilJobNet),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _trendBar({required String label, required double value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: kTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 10,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryBlue),
          ),
        ),
      ],
    );
  }

  static Widget _linkChip(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blue.shade100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: kPrimaryBlue),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCounselorCard({
    required Set<String> interests,
    required Set<String> selected,
    required void Function(String) onToggle,
    required VoidCallback onRecommend,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.chat_bubble_outline_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pick 2–4 interests and get track suggestions',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                interests.map((s) {
                  final active = selected.contains(s);
                  return InkWell(
                    onTap: () => onToggle(s),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: active ? kPrimaryBlue : Colors.white,
                        border: Border.all(
                          color: active ? kPrimaryBlue : Colors.blue.shade100,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : kTextPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.recommend_rounded),
              onPressed: onRecommend,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: const Text('Get Recommendations'),
            ),
          ),
        ],
      ),
    );
  }

  void _showRecommendationDialog(List<String> trackCodes) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Suggested Tracks'),
            content: Text(
              trackCodes.join(' • '),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              for (final code in trackCodes)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _scrollToTrack(code);
                  },
                  child: Text('Go to $code'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  void _showTrackSheet(
    BuildContext context, {
    required String trackCode,
    required String track,
    required String summary,
    required List<String> sampleCurriculum,
    required List<String> entryRoles,
    required List<String> skills,
    required List<_Source> sources,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.45,
            maxChildSize: 0.9,
            builder:
                (_, controller) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.school_rounded, color: kPrimaryBlue),
                          const SizedBox(width: 8),
                          Text(
                            '$track Track',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        summary,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          color: kTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _pillHeader('Sample curriculum'),
                      ...sampleCurriculum.map(_bullet),
                      const SizedBox(height: 10),

                      _pillHeader('Entry-level roles'),
                      ...entryRoles.map(_bullet),
                      const SizedBox(height: 10),

                      _pillHeader('Key skills you’ll build'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: skills.map(_skillChip).toList(),
                      ),
                      const SizedBox(height: 16),

                      _pillHeader('College Pathways for $track'),
                      const SizedBox(height: 8),
                      FutureBuilder<List<PathwayMatch>>(
                        future: SupabaseService.listPathwaysForStrand(
                          trackCode,
                        ),
                        builder: (context, s) {
                          if (s.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (s.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Failed to load pathways: ${s.error}',
                                style: const TextStyle(fontFamily: 'Inter'),
                              ),
                            );
                          }
                          final rows = s.data ?? const [];
                          if (rows.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No pathways found yet.',
                                style: TextStyle(fontFamily: 'Inter'),
                              ),
                            );
                          }
                          return Column(
                            children: rows.map(_pathwayTile).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      _pillHeader('Sources'),
                      ...sources.map(
                        (s) => ListTile(
                          leading: const Icon(Icons.link, color: kPrimaryBlue),
                          title: Text(
                            s.name,
                            style: const TextStyle(fontFamily: 'Inter'),
                          ),
                          subtitle: Text(
                            s.url,
                            style: const TextStyle(
                              fontSize: 12,
                              color: kTextSecondary,
                            ),
                          ),
                          onTap: () => _openUrl(s.url),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  static Widget _pillHeader(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.blue.shade100),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.circle, size: 6, color: kTextSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontFamily: 'Inter')),
          ),
        ],
      ),
    );
  }

  static Widget _skillChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          color: Color(0xFF2563EB),
        ),
      ),
    );
  }
}

// ===== Header =====
class _CurvedHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData trailingIcon;

  const _CurvedHeader({
    required this.title,
    required this.subtitle,
    required this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kPrimaryBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(trailingIcon, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// Small data holder for sources (UI)
class _Source {
  final String name;
  final String url;
  const _Source(this.name, this.url);
}

// Local lightweight ViewModel
class _VM {
  final Track? userTrack;
  final List<Track> tracks;
  _VM({required this.userTrack, required this.tracks});
}
