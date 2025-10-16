// lib/screens/path_review_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';

class PathReviewScreen extends StatefulWidget {
  const PathReviewScreen({super.key});
  @override
  State<PathReviewScreen> createState() => _PathReviewScreenState();
}

class _PathReviewScreenState extends State<PathReviewScreen> {
  Map<String, dynamic>? suggestion;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final s = await SupabaseService.previewLearningPath();
      setState(() => suggestion = s);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => saving = true);
    try {
      await SupabaseService.finalizeLearningPath();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Path saved! Content will now match your Strand/Course.',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    } finally {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Review Your Path',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : s == null
              ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'We need your RIASEC and NCAE results first.',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Enter both, then come back to Review.',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  ],
                ),
              )
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Suggested SHS Strand', s['strand_id']),
                    _row(
                      'Suggested Course',
                      s['course_name'] ?? '(choose later)',
                    ),
                    _row('Top RIASEC', s['top_riasec']),
                    const SizedBox(height: 10),
                    Text(
                      s['rationale'] ?? '',
                      style: const TextStyle(fontFamily: 'Inter'),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving ? null : _confirm,
                        child:
                            saving
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Text(
                                  'Confirm & Save',
                                  style: TextStyle(fontFamily: 'Inter'),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _row(String k, String? v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 180,
          child: Text(
            k,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(v ?? '-', style: const TextStyle(fontFamily: 'Inter')),
        ),
      ],
    ),
  );
}
