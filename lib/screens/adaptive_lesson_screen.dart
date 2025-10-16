import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/screens/skills_screen.dart';

class AdaptiveLessonScreen extends StatefulWidget {
  final String moduleId;
  final String title;

  const AdaptiveLessonScreen({
    super.key,
    required this.moduleId,
    required this.title,
  });

  @override
  State<AdaptiveLessonScreen> createState() => _AdaptiveLessonScreenState();
}

class _AdaptiveLessonScreenState extends State<AdaptiveLessonScreen> {
  List<Map<String, dynamic>> lessons = [];
  int currentIndex = 0;
  bool isLoading = true;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    final data = await SupabaseService.loadSkillModule(widget.moduleId);
    if (!mounted) return;

    if (data.isEmpty) {
      setState(() {
        isLoading = false;
        _inlineError = 'No lessons found for ${widget.moduleId}.';
      });
      return;
    }

    setState(() {
      lessons = data;
      isLoading = false;
    });

    // Hydrate markdown bodies from storage:// URLs if needed
    await _hydrateAllMissingContent();

    // Continue where the user left off
    final progress = await SupabaseService.getSkillProgress();
    final module = progress.firstWhere(
      (p) => p['module_id'] == widget.moduleId,
      orElse: () => {},
    );

    if (!mounted) return;
    if (module.isNotEmpty) {
      setState(() {
        currentIndex = (module['lessons_completed'] as int?) ?? 0;
        if (currentIndex >= lessons.length) currentIndex = 0;
      });
    }
  }

  /// Parse storage://<bucket>/<path> → (bucket, path), normalizing bucket name.
  (String, String)? _parseStorageUrl(String? url) {
    if (url == null) return null;
    final u = url.trim();
    if (!u.startsWith('storage://')) return null;
    final rest = u.substring('storage://'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    var bucket = rest.substring(0, slash);
    final path = rest.substring(slash + 1);
    if (bucket == 'skills-module') bucket = 'skill-modules'; // legacy typo
    return (bucket, path);
  }

  /// Download text content and attach to lesson['content_md'] if missing.
  Future<void> _hydrateAllMissingContent() async {
    final client = Supabase.instance.client;
    String? firstError;

    for (int i = 0; i < lessons.length; i++) {
      final m = lessons[i];
      final hasMd = (m['content_md'] ?? '').toString().trim().isNotEmpty;
      final url = (m['content_url'] ?? '').toString().trim();
      if (hasMd || url.isEmpty) continue;

      final parsed = _parseStorageUrl(url);
      if (parsed == null) {
        firstError ??= 'Invalid content_url: $url';
        continue;
      }

      final (bucket, path) = parsed;

      try {
        final bytes = await client.storage.from(bucket).download(path);
        final text = utf8.decode(bytes);
        if (!mounted) return;
        setState(() {
          lessons[i] = {...m, 'content_md': text};
        });
      } catch (e) {
        firstError ??= 'Failed to fetch $bucket/$path: $e';
      }
    }

    if (firstError != null && mounted) {
      setState(() {
        _inlineError = firstError;
      });
    }
  }

  Future<void> _updateProgress() async {
    await SupabaseService.updateSkillProgress(
      widget.moduleId,
      currentIndex,
      lessons.length,
    );
  }

  void _nextLesson() async {
    if (currentIndex < lessons.length - 1) {
      setState(() => currentIndex++);
      await _updateProgress();
    } else {
      // finished module
      await SupabaseService.updateSkillProgress(
        widget.moduleId,
        lessons.length,
        lessons.length,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SkillsScreen()),
      );
    }
  }

  void _prevLesson() async {
    if (currentIndex > 0) {
      setState(() => currentIndex--);
      await _updateProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (lessons.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            "No lessons found for this module.",
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    }

    final lesson = lessons[currentIndex];
    final String title = (lesson['title'] ?? '').toString().trim();
    final String md = (lesson['content_md'] ?? '').toString().trim();
    final String summary = (lesson['content_summary'] ?? '').toString().trim();
    final int practiceCount =
        lesson['practice'] is List ? (lesson['practice'] as List).length : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF3EB6FF),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: (currentIndex + 1) / lessons.length,
              backgroundColor: Colors.grey.shade300,
              color: Colors.black,
            ),
            const SizedBox(height: 16),
            Text(
              "Lesson ${currentIndex + 1} of ${lessons.length}",
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            if (_inlineError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _inlineError!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Prefer Markdown body; fallback to summary; otherwise info text.
                    if (md.isNotEmpty)
                      MarkdownBody(
                        data: md,
                        styleSheet: MarkdownStyleSheet.fromTheme(
                          Theme.of(context),
                        ).copyWith(
                          p: const TextStyle(fontFamily: 'Inter', fontSize: 16),
                          h1: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                          ),
                          h2: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (summary.isNotEmpty)
                      Text(
                        summary,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else
                      Builder(
                        builder: (context) {
                          final url = (lesson['content_url'] ?? '').toString();
                          return Text(
                            url.isNotEmpty
                                ? 'No inline content. Attached: $url'
                                : 'No content provided for this lesson.',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          );
                        },
                      ),

                    if (practiceCount > 0) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Practice items: $practiceCount',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (currentIndex > 0)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _prevLesson,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text(
                        "Previous",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                if (currentIndex > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _nextLesson,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      currentIndex == lessons.length - 1
                          ? "Finish"
                          : "Next Lesson",
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
