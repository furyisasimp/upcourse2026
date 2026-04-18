// lib/screens/skills_screen.dart
import 'package:flutter/material.dart';
import 'package:career_roadmap/widgets/custom_taskbar.dart';
import 'home_screen.dart';
import 'resources_screen.dart';
import 'quiz_categories_screen.dart';
import 'profile_details_screen.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/routes/route_tracker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:career_roadmap/services/module_service.dart'; // Added import

// Import adaptive screens
import 'adaptive_lesson_screen.dart';
import 'adaptive_quiz_screen.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({Key? key}) : super(key: key);

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  // ✅ Bucket names
  static const String _modulesBucket = 'skill-modules';
  static const String _quizzesBucket = 'quizzes';

  bool _isLoading = true;
  String? _strandOrCourse; // e.g., GAS, STEM, ABM, BSENTREP, etc.

  // Progress rows from DB
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _quizzes = [];

  // moduleId/quizId -> resolved storage path (for download / folder-aware open)
  final Map<String, String> _moduleStoragePath = {};
  final Map<String, String> _quizStoragePath = {};

  // tiny diagnostics
  int _diagModuleFiles = 0;
  int _diagQuizFiles = 0;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  // ---------- Helpers ----------

  // Keep original case; just replace spaces with underscores.
  String _toFileName(String id) => id.trim().replaceAll(' ', '_');

  // Path utilities
  String _stripJson(String name) =>
      name.endsWith('.json') ? name.substring(0, name.length - 5) : name;

  // Generate case variants for folder names (e.g., GAS, gas, Gas)
  List<String> _pathVariants(String? code) {
    if (code == null || code.trim().isEmpty) return const [''];
    final c = code.trim();
    return {c, c.toUpperCase(), c.toLowerCase()}.toList();
  }

  // List basenames in a bucket/path
  Future<List<String>> _storageListNames({
    required String bucket,
    required String path,
  }) async {
    try {
      final items = await Supabase.instance.client.storage
          .from(bucket)
          .list(path: path);
      final names = items.map((e) => e.name).toList();
      debugPrint('[storage.list] bucket=$bucket path="$path" -> $names');
      return names;
    } catch (e) {
      debugPrint('[storage.list] ERROR bucket=$bucket path="$path": $e');
      return <String>[];
    }
  }

  // Discover all top-level folders (no hard-coded list)
  Future<List<String>> _topLevelFolders(String bucket) async {
    try {
      final entries = await Supabase.instance.client.storage
          .from(bucket)
          .list(path: '');
      final dirs = <String>[];
      for (final e in entries) {
        if (!e.name.contains('.')) {
          try {
            final probe = await Supabase.instance.client.storage
                .from(bucket)
                .list(path: e.name);
            if (probe.isNotEmpty) dirs.add(e.name);
          } catch (_) {
            // ignore and continue
          }
        }
      }
      return dirs;
    } catch (_) {
      return const [];
    }
  }

  // ---------- DEBUG: list storage contents quickly ----------
  Future<void> _debugStorageList() async {
    try {
      final s = Supabase.instance.client.storage;

      // Root of adaptive-quizzes
      final root = await s.from(_quizzesBucket).list(path: '');
      debugPrint('$_quizzesBucket root: ${root.map((e) => e.name).toList()}');

      // If user has a strand/course code, list that folder
      final code = (_strandOrCourse ?? '').trim();
      if (code.isNotEmpty) {
        final sub = await s.from(_quizzesBucket).list(path: code);
        debugPrint('$_quizzesBucket/$code: ${sub.map((e) => e.name).toList()}');
      }

      // Bonus: iterate all top-level folders and print their contents
      for (final e in root) {
        final name = e.name;
        if (!name.contains('.')) {
          final kids = await s.from(_quizzesBucket).list(path: name);
          debugPrint(
            '$_quizzesBucket/$name: ${kids.map((k) => k.name).toList()}',
          );
        }
      }

      // Also dump modules root to ensure visibility
      final modRoot = await s.from(_modulesBucket).list(path: '');
      debugPrint(
        '$_modulesBucket root: ${modRoot.map((e) => e.name).toList()}',
      );
      if (code.isNotEmpty) {
        final modSub = await s.from(_modulesBucket).list(path: code);
        debugPrint(
          '$_modulesBucket/$code: ${modSub.map((e) => e.name).toList()}',
        );
      }
    } catch (e) {
      debugPrint('DEBUG storage list error: $e');
    }
  }

  // Resolve a module/quiz id to its real storage path (supports nested module folder)
  Future<String?> _resolveStoragePath({
    required String bucket,
    required String id,
    required bool isModule,
  }) async {
    final fileExact = '${_toFileName(id)}.json';
    final fileLower = fileExact.toLowerCase();

    // 1) Try user's strand/course folder variants
    for (final folder in _pathVariants(_strandOrCourse)) {
      if (folder.isEmpty) continue;

      // direct json inside folder
      final names = await _storageListNames(bucket: bucket, path: folder);
      if (names.contains(fileExact)) return '$folder/$fileExact';
      if (names.contains(fileLower)) return '$folder/$fileLower';

      // nested: <folder>/<id>/module.json (modules only)
      if (isModule) {
        final subNames = await _storageListNames(
          bucket: bucket,
          path: '$folder/${_toFileName(id)}',
        );
        if (subNames.contains('module.json')) {
          return '$folder/${_toFileName(id)}/module.json';
        }
      }
    }

    // 2) Try root
    final rootFiles = await _storageListNames(bucket: bucket, path: '');
    if (rootFiles.contains(fileExact)) return fileExact;
    if (rootFiles.contains(fileLower)) return fileLower;

    // 3) Try every top-level folder (strand or course)
    for (final folder in await _topLevelFolders(bucket)) {
      final names = await _storageListNames(bucket: bucket, path: folder);
      if (names.contains(fileExact)) return '$folder/$fileExact';
      if (names.contains(fileLower)) return '$folder/$fileLower';

      if (isModule) {
        final subNames = await _storageListNames(
          bucket: bucket,
          path: '$folder/${_toFileName(id)}',
        );
        if (subNames.contains('module.json')) {
          return '$folder/${_toFileName(id)}/module.json';
        }
      }
    }

    debugPrint(
      '[resolve] NOT FOUND: bucket=$bucket id=$id (looked for $fileExact / $fileLower and nested module.json)',
    );
    return null;
  }

  // Turn DB quiz_id into the **effective** id we should open (keeps folder if mapped)
  String _effectiveQuizId(String rawId) {
    final path = _quizStoragePath[rawId]; // e.g. GAS/reading_quiz_01.json
    if (path == null || path.isEmpty) return rawId; // fallback to basename id
    return path.endsWith('.json') ? path.substring(0, path.length - 5) : path;
  }

  /// Seed modules and quizzes by scanning user's folder, all top-level folders, and root.
  /// We ALWAYS seed using **basenames** (no folder) so later resolution can attach
  /// the correct folder path per user.
  Future<void> _seedFromStorageIfMissing({
    required List<Map<String, dynamic>> currentSkills,
    required bool seedQuizzesIfEmpty,
  }) async {
    // MODULES: Always check and add missing course-specific modules
    final moduleIds = await ModuleService.fetchModulesForUserCourse();
    setState(() => _diagModuleFiles = moduleIds.length);
    debugPrint('[seed] course-specific module IDs: $moduleIds');

    for (final m in moduleIds) {
      final existing = currentSkills.any((s) => s['module_id'] == m);
      if (!existing) {
        // Load module JSON to get total_lessons
        final moduleData = await ModuleService.loadModuleByStrand(moduleId: m);
        final totalLessons = moduleData?['total_lessons'] ?? 20;
        await SupabaseService.updateSkillProgress(m, 0, totalLessons);
        debugPrint('[seed] inserted missing module: $m');
      }
    }

    // QUIZZES: user variants + discovered top-level + root
    final quizFolders = <String>{
      ..._pathVariants(_strandOrCourse).where((s) => s.isNotEmpty),
      ...await _topLevelFolders(_quizzesBucket),
      '',
    };

    final quizNames = <String>{};
    for (final folder in quizFolders) {
      final names = await _storageListNames(
        bucket: _quizzesBucket,
        path: folder,
      );
      quizNames.addAll(
        names.where((n) => n.endsWith('.json') && !n.endsWith('_tos.json')),
      );
    }

    // Convert to IDs: basename without .json
    final quizIds = quizNames.map(_stripJson).toSet();

    setState(() => _diagQuizFiles = quizIds.length);
    debugPrint('[seed] discovered quiz IDs (basenames): $quizIds');

    if (seedQuizzesIfEmpty && quizIds.isNotEmpty) {
      int i = 0;
      for (final q in quizIds.take(3)) {
        await SupabaseService.updateQuizProgress(
          q,
          status: i == 0 ? 'in_progress' : 'locked',
        );
        i++;
      }
    }
  }

  Future<void> _loadProgress() async {
    setState(() => _isLoading = true);

    // 1) Get user's course
    _strandOrCourse = await SupabaseService.getUserStrandOrCourseCode();
    debugPrint('[user] course: $_strandOrCourse');

    // 2) Fetch all skills
    final allSkills = await SupabaseService.getSkillProgress();
    debugPrint('[db] all skills: $allSkills');

    // 3) Filter skills
    final filteredSkills = <Map<String, dynamic>>[];
    for (final s in allSkills) {
      final moduleId = s['module_id'] as String?;
      if (moduleId == null || _strandOrCourse == null) continue;
      debugPrint(
        '[filter check] moduleId: $moduleId, course: $_strandOrCourse',
      );
      if (await _isModuleForCourse(moduleId, _strandOrCourse!)) {
        debugPrint('[filter] added $moduleId via storage check');
        filteredSkills.add(s);
      } else if (moduleId.startsWith('${_strandOrCourse}_')) {
        debugPrint('[filter] added $moduleId via prefix check');
        filteredSkills.add(s);
      }
    }
    debugPrint('[filtered] skills for $_strandOrCourse: $filteredSkills');

    // 4) Seed missing modules
    await _seedFromStorageIfMissing(
      currentSkills: filteredSkills,
      seedQuizzesIfEmpty: false, // Focus on modules first
    );

    // 5) Refresh skills
    final updatedSkills = await SupabaseService.getSkillProgress();
    final finalFilteredSkills = <Map<String, dynamic>>[];
    for (final s in updatedSkills) {
      final moduleId = s['module_id'] as String?;
      if (moduleId == null || _strandOrCourse == null) continue;
      if (await _isModuleForCourse(moduleId, _strandOrCourse!) ||
          moduleId.startsWith('${_strandOrCourse}_')) {
        finalFilteredSkills.add(s);
      }
    }

    // 6) Fetch quizzes (simplified)
    final quizzes = await SupabaseService.getQuizProgress();
    final quizzes2 =
        quizzes.isEmpty ? await SupabaseService.getQuizProgress() : quizzes;

    // 7) Resolve paths
    _moduleStoragePath.clear();
    for (final s in finalFilteredSkills) {
      final id = (s['module_id'] ?? '').toString();
      final p = await _resolveStoragePath(
        bucket: _modulesBucket,
        id: id,
        isModule: true,
      );
      if (p != null) _moduleStoragePath[id] = p;
    }

    _quizStoragePath.clear();
    for (final q in quizzes2) {
      final id = (q['quiz_id'] ?? '').toString();
      final p = await _resolveStoragePath(
        bucket: _quizzesBucket,
        id: id,
        isModule: false,
      );
      if (p != null) _quizStoragePath[id] = p;
    }

    setState(() {
      _skills = finalFilteredSkills;
      _quizzes = quizzes2;
      _isLoading = false;
    });

    debugPrint('[final] skills: $_skills');
    debugPrint('[final] quizzes: $_quizzes');
  }

  // Add this helper method to the class (outside _loadProgress)
  Future<bool> _isModuleForCourse(String moduleId, String course) async {
    final path = '$course/${moduleId}.json';
    debugPrint('[storage check] trying path: $path');
    try {
      await Supabase.instance.client.storage
          .from(_modulesBucket)
          .download(path);
      debugPrint('[storage check] success for $path');
      return true;
    } catch (e) {
      debugPrint('[storage check] failed for $path: $e');
      return false;
    }
  }

  Future<void> _forceScanAndReload() async {
    setState(() => _isLoading = true);
    // On manual sync: always try to seed quizzes; only seed modules if currently empty.
    await _seedFromStorageIfMissing(
      currentSkills: _skills,
      seedQuizzesIfEmpty: true,
    );
    await _loadProgress();
  }

  Future<bool> _handleBack(BuildContext context) async {
    final nav = Navigator.of(context);

    if (nav.canPop()) {
      nav.pop();
      return false;
    }

    try {
      final last = RouteTracker.instance.lastRouteName;
      if (last != null && last.isNotEmpty) {
        nav.pushReplacementNamed(last);
        return false;
      }
    } catch (_) {}

    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => const ResourcesScreen()),
    );
    return false;
  }

  // ---------- UI ----------

  Widget _buildSkillCard({
    required String title,
    required String level,
    required int lessonsCompleted,
    required int lessonsTotal,
    bool isPrimary = false,
  }) {
    final progress = lessonsTotal > 0 ? lessonsCompleted / lessonsTotal : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFFEFF6FF) : Colors.white,
        border: Border.all(
          color: isPrimary ? const Color(0xFF3B82F6) : Colors.grey.shade300,
          width: isPrimary ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + Level
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isPrimary
                          ? const Color(0xFF3B82F6)
                          : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  level,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isPrimary ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Lessons
          Text(
            '$lessonsCompleted / $lessonsTotal lessons completed',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
          const SizedBox(height: 4),

          // Progress Bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            color: Colors.black,
            minHeight: 8,
          ),
          const SizedBox(height: 12),

          // Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdaptiveLessonScreen(
                              moduleId: title,
                              title: title.replaceAll('_', ' ').toUpperCase(),
                            ),
                      ),
                    ).then((_) => _loadProgress());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    "Continue Learning",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () async {
                  final storagePath =
                      _moduleStoragePath[title] ?? '${_toFileName(title)}.json';
                  final url = await SupabaseService.getFileUrl(
                    bucket: _modulesBucket,
                    path: storagePath,
                  );
                  if (!mounted) return;
                  if (url != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Download started: $url",
                          style: const TextStyle(fontFamily: 'Inter'),
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black12),
                ),
                child: const Text(
                  "Download",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quizCard(Map<String, dynamic> quiz) {
    final status = quiz['status'] ?? 'locked';
    final score = quiz['score'];
    final isCompleted = status == 'completed';
    final isLocked = status == 'locked';

    String subtitle;
    if (isCompleted) {
      subtitle = "Completed • Score: ${score ?? '--'}%";
    } else if (status == 'in_progress') {
      subtitle = "In Progress";
    } else {
      subtitle = "Locked • Complete previous quiz";
    }

    return Opacity(
      opacity: isLocked ? 0.4 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color:
              isCompleted
                  ? const Color(0xFFDFFFE0)
                  : isLocked
                  ? Colors.grey.shade100
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle
                  : isLocked
                  ? Icons.lock
                  : Icons.play_arrow,
              color: isCompleted ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (quiz['quiz_id'] as String)
                        .replaceAll('_', ' ')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLocked) // <-- Use collection-if here
              ElevatedButton(
                onPressed: () {
                  final effectiveId = _effectiveQuizId(quiz['quiz_id']);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => AdaptiveQuizScreen(
                            quizId: effectiveId,
                            title:
                                (quiz['quiz_id'] as String)
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                          ),
                    ),
                  ).then((_) => _loadProgress());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  isCompleted ? "View" : "Start",
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quizEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No adaptive quizzes yet",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.blueGrey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Tap Sync to scan the '$_quizzesBucket' bucket and seed your first quizzes (searches all folders).",
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _forceScanAndReload,
                icon: const Icon(Icons.sync),
                label: const Text("Sync from Storage"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "Found (modules: $_diagModuleFiles, quizzes: $_diagQuizFiles)",
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBack(context),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FBFF),
        appBar: AppBar(
          title: const Text(
            'Skill Development',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF3EB6FF),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: BackButton(onPressed: () => _handleBack(context)),
          actions: [
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync from Storage',
              onPressed: _forceScanAndReload,
            ),
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug list storage',
              onPressed: _debugStorageList,
            ),
          ],
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                  onRefresh: _loadProgress,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Skill Development Modules",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Learning Modules${_strandOrCourse != null ? ' • ${_strandOrCourse!}' : ''}",
                          style: const TextStyle(fontFamily: 'Inter'),
                        ),
                        const SizedBox(height: 16),

                        // Dynamic Skill Cards
                        for (var i = 0; i < _skills.length; i++)
                          _buildSkillCard(
                            title: _skills[i]['module_id'],
                            level: "Level ${(i + 1)}",
                            lessonsCompleted:
                                _skills[i]['lessons_completed'] ?? 0,
                            lessonsTotal: _skills[i]['lessons_total'] ?? 0,
                            isPrimary: i == 0,
                          ),

                        const SizedBox(height: 30),
                        const Text(
                          "Quizzes",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        // Dynamic Quizzes or empty state
                        if (_quizzes.isEmpty) _quizEmptyState(),
                        for (final quiz in _quizzes) _quizCard(quiz),
                      ],
                    ),
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
                  MaterialPageRoute(
                    builder: (_) => const QuizCategoriesScreen(),
                  ),
                );
                break;
              case 3:
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileDetailsScreen(),
                  ),
                );
                break;
            }
          },
        ),
      ),
    );
  }
}
