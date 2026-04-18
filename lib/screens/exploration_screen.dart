// lib/screens/exploration_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart'; // For rendering bar charts

import 'home_screen.dart';
import 'quiz_categories_screen.dart';
import 'profile_details_screen.dart';
import '../widgets/custom_taskbar.dart';
import '../services/supabase_service.dart';
import '../models/exploration_models.dart'; // Track / Pathway / SourceLink
import '../services/labor_insights_service.dart'; // Add this to use the labor insights service
import '../services/ai_career_counselor_service.dart';

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

  // ✅ ADD THIS VARIABLE HERE (at class level)
  String? userCourse;

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
    // Pull the user's course code (e.g., BSIT, BEEd, BSHM)
    final userCourse = await SupabaseService.getUserCourseCode();
    final userCourseName = LaborInsightsService.getCourseName(
      userCourse ?? 'General',
    );

    final tracks = await SupabaseService.listTracks();

    _trackKeys
      ..clear()
      ..addEntries(tracks.map((t) => MapEntry(t.code, GlobalKey())));

    return _VM(
      userCourse: userCourse,
      userCourseName: userCourseName,
      tracks: tracks,
    );
  }

  // New method to fetch match data without Future.wait()
  Future<List<dynamic>> _fetchMatchData() async {
    try {
      final riasecResults = await SupabaseService.getUserRIASECResults();
      final ncaeResults = await SupabaseService.getUserNCAEResults();
      return [riasecResults, ncaeResults];
    } catch (e) {
      print('❌ Error fetching match data: $e');
      rethrow;
    }
  }

  // Open URL in browser
  Future<void> _openUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }

    // Proof Card Widget
    Widget _proofCard({
      required String title,
      required String value,
      required String subtitle,
      required IconData icon,
      required Color color,
      required String source,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: kTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: kTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Source: $source',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: kTextSecondary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    // Proof Cards Container
    Widget _proofCardsContainer({required Widget child}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: child,
      );
    }

    // Source Chip Widget
    Widget _sourceChip(String text, String url, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.blue.shade100),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 14, color: kPrimaryBlue),
              const SizedBox(width: 4),
              Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryBlue,
                ),
              ),
            ],
          ),
        ),
      );
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
            final userCourse = vm.userCourse;
            final userCourseName = vm.userCourseName;
            final tracks = vm.tracks;

            // ✅ NO setState() HERE - userCourse is already set in initState()

            final ordered = <Track>[...tracks];

            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    'Recommended Tracks',
                    'Based on your interests',
                  ),

                  // Dynamic cards (e.g., Academic, TVL-ICT, TVL-HE, Arts & Design, Sports)
                  ...ordered.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _shsTrackCard(
                        key: _trackKeys[t.code],
                        title: t.name,
                        match:
                            (userCourse != null && t.code == userCourse)
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

                  // Match Explanation Section (Feature 1 - Improved UI)
                  if (userCourse != null) ...[
                    const SizedBox(height: 20),
                    FutureBuilder<List<dynamic>>(
                      future: _fetchMatchData(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox.shrink();
                        }

                        if (snapshot.hasError) {
                          print('❌ Error: ${snapshot.error}');
                          return const SizedBox.shrink();
                        }

                        if (!snapshot.hasData) {
                          return const SizedBox.shrink();
                        }

                        final data = snapshot.data!;

                        // Use as dynamic and check type manually
                        final riasecResults = data[0] as dynamic;
                        final ncaeResults = data[1] as dynamic;

                        // Check if they are Maps
                        if (riasecResults is! Map<String, dynamic> ||
                            ncaeResults is! Map<String, dynamic>) {
                          print('⚠️ Results are not Maps');
                          return const SizedBox.shrink();
                        }

                        if (riasecResults.isEmpty || ncaeResults.isEmpty) {
                          print('⚠️ Results are empty');
                          return const SizedBox.shrink();
                        }

                        print('📊 RIASEC Results: $riasecResults');
                        print('📊 NCAE Results: $ncaeResults');

                        final explanation =
                            LaborInsightsService.generateMatchExplanation(
                              courseCode: userCourse!,
                              riasecResults: riasecResults,
                              ncaeResults: ncaeResults,
                            );

                        print('📝 Explanation: $explanation');

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                Colors.blue.shade50.withOpacity(0.5),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.blue.shade100,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade100.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with Icon
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      color: kPrimaryBlue,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Why This Course Was Matched to You',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: kPrimaryBlue,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Explanation Text (with rich formatting)
                              Text(
                                explanation,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: kTextSecondary,
                                  height: 1.6,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Footer with AI badge
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 16,
                                      color: Colors.green.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'AI-Powered Match • Based on your RIASEC & NCAE results',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  // ✅ INSERT YOUR NEW CODE HERE (After Match Explanation)
                  // Top 3 Course Selection Section (Redirection Feature)
                  if (userCourse != null) ...[
                    const SizedBox(height: 20),
                    _sectionTitle(
                      'Your Top 3 Course Options',
                      'Choose the best fit for you',
                    ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: LaborInsightsService.getTop3Courses(
                        userId: SupabaseService.authUserId ?? '',
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return _coursesContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return _coursesContainer(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Failed to load courses: ${snapshot.error}',
                                style: const TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }

                        final courses = snapshot.data ?? const [];
                        if (courses.isEmpty) {
                          return _coursesContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No courses found. Please complete your assessments.',
                                style: TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }

                        return _coursesContainer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show top 3 courses
                              ...List.generate(courses.length, (index) {
                                final course = courses[index];
                                final isSelected =
                                    course['courseCode'] == userCourse;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: RadioListTile<String>(
                                    title: Text(
                                      '${index + 1}. ${course['courseName']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Match Score: ${(course['fitScore'] * 100).toStringAsFixed(1)}% • ${course['trackName']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    value: course['courseCode'],
                                    groupValue: userCourse,
                                    onChanged: (value) {
                                      if (value != null) {
                                        _showRedirectionDialog(course, value);
                                      }
                                    },
                                    selected: isSelected,
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                              // Redirection button
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (courses.isNotEmpty) {
                                    _showRedirectionDialog(
                                      courses[0],
                                      userCourse,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Choose a Different Course'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade500,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  // Feature 2: Course Proof & Insights (AI-Enhanced Version)
                  if (userCourse != null) ...[
                    const SizedBox(height: 20),
                    _sectionTitle(
                      'Course Proof & Insights',
                      'Evidence-based data with AI verification',
                    ),
                    FutureBuilder<Map<String, dynamic>>(
                      future: LaborInsightsService.getCourseProofData(
                        course: userCourse!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return _proofCardsContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return _proofCardsContainer(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Unable to load proof data: ${snapshot.error}',
                                style: const TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return _proofCardsContainer(
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No proof data available for this course.',
                                style: TextStyle(fontFamily: 'Inter'),
                              ),
                            ),
                          );
                        }

                        final proofData = snapshot.data!;
                        final aiVerification =
                            proofData['aiVerification']
                                as Map<String, dynamic>?;
                        final aiInsights =
                            proofData['aiInsights'] as Map<String, dynamic>?;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // AI Verification Badge
                            if (aiVerification != null &&
                                aiVerification['verified'] == true) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.verified_rounded,
                                      color: Colors.green.shade600,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AI Verified Data',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Confidence: ${(aiVerification['confidenceScore'] as double? ?? 0.0) * 100}% | ${aiVerification['verificationMethod']}',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 10,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Proof Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _proofCard(
                                    title: 'Job Demand',
                                    value: proofData['jobDemand'] ?? 'N/A',
                                    subtitle: 'Available positions',
                                    icon: Icons.work_outline_rounded,
                                    color: Colors.green.shade500,
                                    source:
                                        proofData['sources']?['jobDemand'] ??
                                        'DOLE',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _proofCard(
                                    title: 'Avg. Salary',
                                    value: proofData['avgSalary'] ?? 'N/A',
                                    subtitle: 'Monthly (PHP)',
                                    icon: Icons.attach_money_rounded,
                                    color: Colors.blue.shade500,
                                    source:
                                        proofData['sources']?['avgSalary'] ??
                                        'DOLE',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _proofCard(
                                    title: 'Employment Rate',
                                    value: proofData['employmentRate'] ?? 'N/A',
                                    subtitle: 'Graduates employed',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: Colors.orange.shade500,
                                    source:
                                        proofData['sources']?['employmentRate'] ??
                                        'PSA',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _proofCard(
                                    title: 'Industry Growth',
                                    value: proofData['industryGrowth'] ?? 'N/A',
                                    subtitle: 'Annual growth',
                                    icon: Icons.trending_up_rounded,
                                    color: Colors.purple.shade500,
                                    source:
                                        proofData['sources']?['industryGrowth'] ??
                                        'DOLE',
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // AI Insights Section
                            if (aiInsights != null) ...[
                              _sectionTitle(
                                'AI-Generated Insights',
                                'Personalized analysis based on your course',
                              ),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.shade100,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade50.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.smart_toy_rounded,
                                          color: kPrimaryBlue,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'AI Analysis Summary',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: kPrimaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      aiInsights['summary'] ??
                                          'No insights available.',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        color: kTextSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Key Findings:',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: kTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...((aiInsights['keyFindings']
                                                as List<dynamic>?)
                                            ?.map(
                                              (finding) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 4,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle,
                                                      size: 14,
                                                      color:
                                                          Colors.green.shade600,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        finding,
                                                        style: const TextStyle(
                                                          fontFamily: 'Inter',
                                                          fontSize: 12,
                                                          color: kTextSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ) ??
                                        []),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Recommendations:',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: kTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...((aiInsights['recommendations']
                                                as List<dynamic>?)
                                            ?.map(
                                              (rec) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 4,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .lightbulb_outline_rounded,
                                                      size: 14,
                                                      color:
                                                          Colors
                                                              .orange
                                                              .shade600,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        rec,
                                                        style: const TextStyle(
                                                          fontFamily: 'Inter',
                                                          fontSize: 12,
                                                          color: kTextSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ) ??
                                        []),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Source citations
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: kTextSecondary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Data Sources:',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: kTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _sourceChip(
                                        'DOLE',
                                        'https://ble.dole.gov.ph/',
                                        () => _openUrl(
                                          'https://ble.dole.gov.ph/',
                                        ),
                                      ),
                                      _sourceChip(
                                        'PSA',
                                        'https://psa.gov.ph/',
                                        () => _openUrl('https://psa.gov.ph/'),
                                      ),
                                      _sourceChip(
                                        'PhilJobNet',
                                        'https://philjobnet.gov.ph/',
                                        () => _openUrl(
                                          'https://philjobnet.gov.ph/',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Last Updated: ${proofData['lastUpdated'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      color: kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (userCourse != null)
                    FutureBuilder<List<PathwayMatch>>(
                      future: SupabaseService.listPathwaysForStrand(userCourse),
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
                  // Labor Market & Salary Links - Now with course-specific insights
                  FutureBuilder<Map<String, dynamic>>(
                    future: LaborInsightsService.getLaborInsights(
                      course: vm.userCourse ?? 'General',
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _marketInsights(
                          insights:
                              'Loading credible insights from official PSA and DOLE data...',
                          generalChartData: {},
                          courseChartData: {},
                          courseName: vm.userCourseName ?? 'General',
                          onDole: () => _openUrl('https://ble.dole.gov.ph/'),
                          onPsa:
                              () => _openUrl(
                                'https://psa.gov.ph/statistics/survey/labor-and-employment',
                              ),
                          onPhilJobNet:
                              () => _openUrl('https://philjobnet.gov.ph/'),
                        );
                      } else if (snapshot.hasError) {
                        return _marketInsights(
                          insights:
                              'Credible data unavailable. Insights are based only on official sources—please check the links below for the latest information.',
                          generalChartData: {},
                          courseChartData: {},
                          courseName: vm.userCourseName ?? 'General',
                          onDole: () => _openUrl('https://ble.dole.gov.ph/'),
                          onPsa:
                              () => _openUrl(
                                'https://psa.gov.ph/statistics/survey/labor-and-employment',
                              ),
                          onPhilJobNet:
                              () => _openUrl('https://philjobnet.gov.ph/'),
                        );
                      } else {
                        final data =
                            snapshot.data ??
                            {
                              'summary': 'No data available.',
                              'generalChart': {},
                              'courseChart': {},
                            };
                        return _marketInsights(
                          insights: data['summary'] ?? 'No data available.',
                          generalChartData: data['generalChart'] ?? {},
                          courseChartData: data['courseChart'] ?? {},
                          courseName: vm.userCourseName ?? 'General',
                          onDole: () => _openUrl('https://ble.dole.gov.ph/'),
                          onPsa:
                              () => _openUrl(
                                'https://psa.gov.ph/statistics/survey/labor-and-employment',
                              ),
                          onPhilJobNet:
                              () => _openUrl('https://philjobnet.gov.ph/'),
                        );
                      }
                    },
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
                    onRecommend: () async {
                      final rec =
                          await AICareerCounselorService.recommendTracks(
                            _selected,
                          );
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

  // Show redirection dialog
  void _showRedirectionDialog(
    Map<String, dynamic> course,
    String? selectedCourse,
  ) {
    // Get current user ID using your existing getter
    final currentUserId = SupabaseService.authUserId;

    if (currentUserId == null || currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to change your course')),
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Course Selection'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You selected: ${course['courseName']} (${course['courseCode']})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text('Why are you choosing this course?'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reason',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'interest',
                      child: const Text('Personal Interest'),
                    ),
                    DropdownMenuItem(
                      value: 'career',
                      child: const Text('Career Goals'),
                    ),
                    DropdownMenuItem(
                      value: 'family',
                      child: const Text('Family Preference'),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: const Text('Other'),
                    ),
                  ],
                  onChanged: (value) {},
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final reason = 'Personal Interest'; // Get from dropdown
                  final success = await LaborInsightsService.saveCourseChoice(
                    userId: currentUserId,
                    courseCode: course['courseCode'],
                    reason: reason,
                  );

                  if (success) {
                    Navigator.pop(context);
                    setState(() {
                      userCourse = course['courseCode'];
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Course updated successfully!'),
                      ),
                    );
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
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
    required String insights,
    required Map<String, dynamic> generalChartData,
    required Map<String, dynamic> courseChartData,
    required String courseName,
    required VoidCallback onDole,
    required VoidCallback onPsa,
    required VoidCallback onPhilJobNet,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: Colors.green.shade600,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI-Powered Labor Insights (Official Data Only)',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insights,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // General Job Market Chart
          if (generalChartData.isNotEmpty) ...[
            Text(
              'General Job Market Growth (%)',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(generalChartData.length, (index) {
                    final key = generalChartData.keys.elementAt(index);
                    final value =
                        (generalChartData[key] as num?)?.toDouble() ?? 0.0;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: value,
                          color:
                              value > 0
                                  ? Colors.green.shade500
                                  : Colors.red.shade500,
                          width: 14,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget:
                            (value, meta) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                generalChartData.keys.elementAt(value.toInt()),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        getTitlesWidget:
                            (value, meta) => Text(
                              '${value.toInt()}%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
                    getDrawingHorizontalLine:
                        (value) => FlLine(
                          color: Colors.grey.shade300,
                          strokeWidth: 0.3,
                        ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.black87,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final key = generalChartData.keys.elementAt(
                          group.x.toInt(),
                        );
                        final value = rod.toY;
                        return BarTooltipItem(
                          '$key: ${value.toStringAsFixed(1)}%',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  maxY:
                      generalChartData.values
                          .map((v) => (v as num).toDouble().abs())
                          .fold<double>(0.0, (a, b) => a > b ? a : b) +
                      2.0,
                  minY:
                      -generalChartData.values
                          .map((v) => (v as num).toDouble().abs())
                          .fold<double>(0.0, (a, b) => a > b ? a : b) -
                      2.0,
                ),
                swapAnimationDuration: const Duration(milliseconds: 600),
                swapAnimationCurve: Curves.easeOut,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Course-Specific Job Chart
          if (courseChartData.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.school_rounded, color: kPrimaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Jobs for $courseName',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kPrimaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: BarChart(
                      BarChartData(
                        barGroups: List.generate(courseChartData.length, (
                          index,
                        ) {
                          final key = courseChartData.keys.elementAt(index);
                          final value =
                              (courseChartData[key] as num?)?.toDouble() ?? 0.0;
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: value,
                                color:
                                    value > 0
                                        ? Colors.blue.shade500
                                        : Colors.red.shade500,
                                width: 14,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ],
                          );
                        }),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget:
                                  (value, meta) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      courseChartData.keys.elementAt(
                                        value.toInt(),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 35,
                              getTitlesWidget:
                                  (value, meta) => Text(
                                    '${value.toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black54,
                                    ),
                                  ),
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 2,
                          getDrawingHorizontalLine:
                              (value) => FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 0.3,
                              ),
                        ),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: Colors.black87,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final key = courseChartData.keys.elementAt(
                                group.x.toInt(),
                              );
                              final value = rod.toY;
                              return BarTooltipItem(
                                '$key: ${value.toStringAsFixed(1)}%',
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ),
                        maxY:
                            courseChartData.values
                                .map((v) => (v as num).toDouble().abs())
                                .fold<double>(0.0, (a, b) => a > b ? a : b) +
                            2.0,
                        minY:
                            -courseChartData.values
                                .map((v) => (v as num).toDouble().abs())
                                .fold<double>(0.0, (a, b) => a > b ? a : b) -
                            2.0,
                      ),
                      swapAnimationDuration: const Duration(milliseconds: 600),
                      swapAnimationCurve: Curves.easeOut,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
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

  void _showRecommendationDialog(String recommendation) {
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with icon and title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPrimaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline_rounded,
                          color: kPrimaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AI Career Recommendations',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Scrollable content
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        recommendation,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: kTextSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Styled button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Got it!',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  // Proof Card Widget (with source citation)
  Widget _proofCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String source,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: kTextSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: kTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Source: $source',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: kTextSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // Proof Cards Container
  Widget _proofCardsContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }

  // Source Chip Widget (with 3 parameters)
  Widget _sourceChip(String text, String url, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blue.shade100),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 14, color: kPrimaryBlue),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: kPrimaryBlue,
              ),
            ),
          ],
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
  final String? userCourse;
  final String? userCourseName;
  final List<Track> tracks;
  _VM({this.userCourse, this.userCourseName, required this.tracks});
}
