import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:career_roadmap/services/module_service.dart';
import 'package:career_roadmap/services/supabase_service.dart';

class AdaptiveLessonScreen extends StatefulWidget {
  final String moduleId;
  final String title;

  const AdaptiveLessonScreen({
    required this.moduleId,
    required this.title,
    Key? key,
  }) : super(key: key);

  @override
  _AdaptiveLessonScreenState createState() => _AdaptiveLessonScreenState();
}

class _AdaptiveLessonScreenState extends State<AdaptiveLessonScreen> {
  Map<String, dynamic>? _moduleData;
  bool _isLoading = true;
  int _currentLessonIndex = 0;
  Map<int, String> _preloadedContent = {}; // Preload markdown for each lesson
  Map<int, int?> _userAnswers = {}; // Track selected MCQ answers
  Map<int, bool?> _answerFeedback =
      {}; // Track feedback (true=correct, false=incorrect)

  @override
  void initState() {
    super.initState();
    _loadModule();
  }

  Future<void> _loadModule() async {
    setState(() => _isLoading = true);
    final data = await ModuleService.loadModuleByStrand(
      moduleId: widget.moduleId,
    );
    if (data != null) {
      await _preloadContent(data);
    }
    setState(() {
      _moduleData = data;
      _isLoading = false;
    });
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Module not available. Please try again.'),
        ),
      );
    }
  }

  Future<void> _preloadContent(Map<String, dynamic> moduleData) async {
    final lessons = moduleData['lessons'] as List<dynamic>? ?? [];
    for (int i = 0; i < lessons.length; i++) {
      final lesson = lessons[i] as Map<String, dynamic>;
      final contentUrl = lesson['content_url'] as String?;
      if (contentUrl != null) {
        final fullUrl = contentUrl.replaceFirst(
          'storage://skills-module/',
          'https://aybgkbtwkavtluzemlst.supabase.co/storage/v1/object/public/skill-modules/', // Update with your real URL!
        );
        debugPrint('Attempting to fetch MD from: $fullUrl'); // Add this
        try {
          final response = await http
              .get(Uri.parse(fullUrl))
              .timeout(const Duration(seconds: 10));
          debugPrint(
            'MD fetch response status: ${response.statusCode}',
          ); // Add this
          if (response.statusCode == 200) {
            _preloadedContent[i] = response.body;
          } else {
            debugPrint(
              'MD fetch failed with body: ${response.body}',
            ); // Add this
            _preloadedContent[i] =
                'Content not available (status ${response.statusCode}).';
          }
        } catch (e) {
          debugPrint('MD fetch error: $e'); // Add this
          _preloadedContent[i] = 'Error loading content: $e';
        }
      }
    }
  }

  void _nextLesson() {
    final lessons = _moduleData?['lessons'] as List<dynamic>? ?? [];
    if (_currentLessonIndex < lessons.length - 1) {
      setState(() => _currentLessonIndex++);
      _updateProgress();
    } else {
      _completeModule();
    }
  }

  void _previousLesson() {
    if (_currentLessonIndex > 0) {
      setState(() => _currentLessonIndex--);
    }
  }

  void _updateProgress() {
    final lessons = _moduleData?['lessons'] as List<dynamic>? ?? [];
    SupabaseService.updateSkillProgress(
      widget.moduleId,
      _currentLessonIndex + 1, // 1-based index
      lessons.length,
    );
  }

  void _completeModule() {
    final lessons = _moduleData?['lessons'] as List<dynamic>? ?? [];
    SupabaseService.updateSkillProgress(
      widget.moduleId,
      lessons.length,
      lessons.length,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Module completed!')));
    Navigator.pop(context);
  }

  void _checkAnswer(int questionIndex, Map<String, dynamic> q) {
    final selected = _userAnswers[questionIndex];
    if (selected != null) {
      final isCorrect = selected == q['answer_index'];
      setState(() => _answerFeedback[questionIndex] = isCorrect);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCorrect ? 'Correct!' : 'Incorrect. Try again.'),
          backgroundColor: isCorrect ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Widget _buildLesson() {
    final lessons = _moduleData?['lessons'] as List<dynamic>? ?? [];
    if (_currentLessonIndex >= lessons.length)
      return const Text('No more lessons.');

    final lesson = lessons[_currentLessonIndex] as Map<String, dynamic>;
    final practice = lesson['practice'] as List<dynamic>? ?? [];
    final totalLessons = lessons.length;

    // _buildLesson method
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lesson Progress
          Text(
            'Lesson ${_currentLessonIndex + 1} of $totalLessons',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            lesson['title'],
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Preloaded Markdown Content
          Markdown(
            data: _preloadedContent[_currentLessonIndex]!,
            shrinkWrap: true, // <-- Add this to fix unbounded height
          ),
          const SizedBox(height: 16),

          // MCQs
          for (int i = 0; i < practice.length; i++) _buildMCQ(practice[i], i),
          const SizedBox(height: 16),

          // Navigation Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: _currentLessonIndex > 0 ? _previousLesson : null,
                child: const Text('Previous'),
              ),
              ElevatedButton(
                onPressed: _nextLesson,
                child: Text(
                  _currentLessonIndex == totalLessons - 1 ? 'Complete' : 'Next',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMCQ(Map<String, dynamic> q, int questionIndex) {
    final options = q['options'] as List<dynamic>;
    final selected = _userAnswers[questionIndex];
    final feedback = _answerFeedback[questionIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q['question'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < options.length; i++)
          RadioListTile<int>(
            title: Text(options[i]),
            value: i,
            groupValue: selected,
            activeColor:
                feedback == true
                    ? Colors.green
                    : (feedback == false ? Colors.red : null),
            onChanged:
                (value) => setState(() => _userAnswers[questionIndex] = value),
          ),
        if (selected != null)
          ElevatedButton(
            onPressed: () => _checkAnswer(questionIndex, q),
            child: const Text('Check Answer'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF3EB6FF),
        actions: [
          if (_moduleData != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${_currentLessonIndex + 1}/${(_moduleData!['lessons'] as List).length}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _moduleData != null
              ? _buildLesson()
              : const Center(child: Text('Failed to load module.')),
    );
  }
}
