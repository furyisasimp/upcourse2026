import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:career_roadmap/services/supabase_service.dart';
import 'results_screen.dart';

class Question {
  final String text;
  final List<String> options;
  Question({required this.text, required this.options});

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      text: json['text'],
      options: List<String>.from(json['options']),
    );
  }
}

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({Key? key}) : super(key: key);

  @override
  _QuestionnaireScreenState createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  List<Question> _questions = [];
  final Map<int, String> _answers = {};
  bool _isSaving = false;
  bool _isLoading = true;

  static List<Question>? _cachedQuestions;

  @override
  void initState() {
    super.initState();
    _loadQuestionsFromJson();
  }

  Future<void> _loadQuestionsFromJson() async {
    if (_cachedQuestions != null) {
      setState(() {
        _questions = _cachedQuestions!;
        _isLoading = false;
      });
      return;
    }

    try {
      final url = await SupabaseService.getFileUrl(
        bucket: "ncae-preassessment-data",
        path: "questionnaire.json",
        expiresIn: 60 * 60 * 24,
      );

      if (url == null) throw Exception("Questionnaire file not found");

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _cachedQuestions = data.map((q) => Question.fromJson(q)).toList();

        setState(() {
          _questions = _cachedQuestions!;
          _isLoading = false;
        });
      } else {
        throw Exception("Failed to load questionnaire");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load questionnaire: $e")),
      );
    }
  }

  Future<void> _submitAnswers() async {
    if (_isSaving) return;

    if (_answers.length < _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please answer all questions before submitting."),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1) Raw responses -> questionnaire_responses
      await SupabaseService.saveQuestionnaireResponses(
        _answers.map((k, v) => MapEntry(k, int.parse(v))),
      );

      // 2) Compute processed results -> questionnaire_results
      final latestResponse = await SupabaseService.getLatestResponse();
      final questionnaire = await SupabaseService.loadQuestionnaire();

      if (latestResponse != null) {
        final answers = Map<String, dynamic>.from(
          latestResponse['answers'] ?? {},
        );
        final results = SupabaseService.processResults(answers, questionnaire);

        await SupabaseService.saveProcessedResults(results);

        // ✅ 3) Copy latest questionnaire_results into ncae_results
        await SupabaseService.upsertNcaeFromQuestionnaire();

        // ✅ 4) If both RIASEC + NCAE exist, finalize path
        await SupabaseService.finalizeIfReady();

        if (!mounted) return;

        // Keep your ResultsScreen flow (panel will refresh when you pop back)
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ResultsScreen(results: results)),
        );
      }

      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Assessment completed!")));

      // ✅ 5) Pop back to Home so CareerSetupPanel's .then(...) can refresh
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save questionnaire: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2FBFF),
      body: SafeArea(
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Pre-Assessment Questionnaire for NCAE",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _questions.length,
                          itemBuilder: (context, idx) {
                            return _buildQuestionCard(idx, _questions[idx]);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child:
                            _isSaving
                                ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                                : ElevatedButton(
                                  onPressed: _submitAnswers,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3EB6FF),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    "Submit",
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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

  Widget _buildQuestionCard(int idx, Question q) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Q${idx + 1}. ${q.text}",
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...q.options.asMap().entries.map((entry) {
              final optIndex = entry.key;
              final opt = entry.value;
              return RadioListTile<String>(
                title: Text(
                  opt,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                ),
                value: optIndex.toString(),
                groupValue: _answers[idx],
                onChanged: (val) {
                  setState(() => _answers[idx] = val!);
                },
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
