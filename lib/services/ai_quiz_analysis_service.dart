import 'dart:convert';
import 'dart:typed_data'; // Add this import for Uint8List
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AIQuizAnalysisService {
  static const String _apiKey =
      'AIzaSyCt3iRdZDs2IKS9X_UEJ9EYV4q1I-jI5gs'; // Replace with your Gemini API key
  static const String _url =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey';

  /// Analyzes user's quiz attempts, identifies low-scoring quizzes (lacks), generates a personalized skill module, and uploads it.
  /// Prioritizes course_code from user's profile in users table.
  /// Returns the module metadata or null on failure.
  static Future<Map<String, dynamic>?> analyzeAndGenerateModule(
    String userId,
  ) async {
    try {
      // Step 1: Fetch user's quiz attempts
      final attempts = await _fetchUserQuizAttempts(userId);
      if (attempts.isEmpty) return null;

      // Step 2: Identify low-scoring quizzes (e.g., score_pct < 70 as "lacks")
      final lowScoreQuizzes =
          attempts
              .where(
                (a) => (((a['score_pct'] as num?)?.toDouble() ?? 0.0) < 70.0),
              )
              .toList(); // Fixed type issue
      if (lowScoreQuizzes.isEmpty) return null; // No lacks found

      // Step 3: Select the most recent low-score quiz for simplicity (or aggregate)
      final targetQuiz =
          lowScoreQuizzes.first; // You can modify to pick based on criteria
      final quizId = targetQuiz['quiz_id'] as String;

      // Step 4: Fetch quiz JSON from storage
      final quizData = await _fetchQuizData(quizId);
      if (quizData == null) return null;

      // Step 5: Fetch user's course_code from users table
      final courseCode = await _fetchUserCourseCode(userId);
      if (courseCode == null) return null; // No course found

      // Step 6: Generate module based on quiz topic/course
      final moduleData = await _generateModuleWithAI(quizData, courseCode);

      // Step 7: Upload to Supabase storage
      final moduleId =
          '${courseCode.toLowerCase()}_review_${DateTime.now().millisecondsSinceEpoch}';
      await _uploadModuleToStorage(courseCode, moduleId, moduleData);

      // Step 8: Save metadata to database
      final metadata = {
        'user_id': userId,
        'quiz_id': quizId,
        'module_id': moduleId,
        'course_code': courseCode,
        'title': moduleData['title'],
        'weaknesses': ['Review of ${quizData['quiz_title']}'], // Simplified
        'storage_path': 'skill-modules/$courseCode/$moduleId.json',
      };
      await Supabase.instance.client
          .from('user_skill_modules')
          .insert(metadata);

      return metadata;
    } catch (e) {
      print('Error in analyzeAndGenerateModule: $e');
      return null;
    }
  }

  // Helper: Fetch user's quiz attempts
  static Future<List<Map<String, dynamic>>> _fetchUserQuizAttempts(
    String userId,
  ) async {
    final response = await Supabase.instance.client
        .from('quiz_attempts')
        .select('*')
        .eq('user_id', userId)
        .order('finished_at', ascending: false); // Most recent first
    return response as List<Map<String, dynamic>>;
  }

  // Helper: Fetch quiz JSON from Supabase storage (quizzes bucket)
  static Future<Map<String, dynamic>?> _fetchQuizData(String quizId) async {
    try {
      final response = await Supabase.instance.client.storage
          .from('quizzes')
          .download('$quizId.json');
      return jsonDecode(utf8.decode(response));
    } catch (e) {
      print('Error fetching quiz data: $e');
      return null;
    }
  }

  // Helper: Fetch user's course_code from users table
  static Future<String?> _fetchUserCourseCode(String userId) async {
    try {
      final user =
          await Supabase.instance.client
              .from('users')
              .select('course_code')
              .eq('supabase_id', userId)
              .single();

      return user['course_code'] as String?;
    } catch (e) {
      print('Error fetching user course_code: $e');
      return null;
    }
  }

  // Helper: Use AI to generate module based on quiz topic/course
  static Future<Map<String, dynamic>> _generateModuleWithAI(
    Map<String, dynamic> quizData,
    String courseCode,
  ) async {
    final title = quizData['quiz_title'] ?? 'Quiz Review';
    final prompt = '''
Generate a skill module JSON for reviewing weaknesses in quiz: "$title" (Course: $courseCode).
Follow this structure:
{
  "schema": "upcourse.skills.module.v1",
  "code": "$courseCode",
  "module_id": "generated_${DateTime.now().millisecondsSinceEpoch}",
  "title": "Review Module for $title",
  "level": 1,
  "estimated_minutes": 30,
  "prerequisites": [],
  "outcomes": ["Review key concepts from $title", "Improve understanding in $courseCode"],
  "lessons": [
    {
      "lesson_id": "L1",
      "title": "Review of $title",
      "content_type": "markdown",
      "content_url": "storage://skills-module/[code]/[module_id]/L1.md",
      "practice": [{"type": "mcq", "question": "Sample question", "options": ["A", "B"], "answer_index": 0}]
    }
  ],
  "total_lessons": 1
}
Also generate Markdown content for each lesson (e.g., "# Review of $title\n\nContent here...").
Return as JSON: {"module": {...}, "lessons": {"L1.md": "markdown content"}}
''';

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
    });
    final response = await http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawText =
          data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '{}';
      final parsed = jsonDecode(
        rawText.replaceAll('```json', '').replaceAll('```', '').trim(),
      );
      return parsed;
    }
    throw Exception('AI generation failed');
  }

  // Helper: Upload module JSON and lesson MDs to Supabase storage
  static Future<void> _uploadModuleToStorage(
    String courseCode,
    String moduleId,
    Map<String, dynamic> moduleData,
  ) async {
    final bucket = Supabase.instance.client.storage.from(
      'skill-modules',
    ); // Your bucket name

    // Upload module JSON
    final moduleJson = jsonEncode(moduleData['module']);
    await bucket.uploadBinary(
      '$courseCode/$moduleId.json',
      Uint8List.fromList(utf8.encode(moduleJson)),
    ); // Fixed: Use uploadBinary for Uint8List

    // Upload lesson MDs
    final lessons = moduleData['lessons'] as Map<String, dynamic>;
    for (final entry in lessons.entries) {
      final fileName = '$courseCode/$moduleId/${entry.key}';
      await bucket.uploadBinary(
        fileName,
        Uint8List.fromList(utf8.encode(entry.value)),
      ); // Fixed: Use uploadBinary for Uint8List
    }
  }
}
