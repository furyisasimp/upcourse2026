// lib/screens/second_profile_intro_screen.dart
import 'package:flutter/material.dart';
import 'riasec_test_screen.dart';
import 'ncae_input_screen.dart';
import 'path_review_screen.dart';

class SecondProfileIntroScreen extends StatelessWidget {
  const SecondProfileIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Career Path Setup',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: const Color(0xFF007BFF),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We’ll tailor Study Guides, Quizzes, and Videos to your path.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 16),
            ),
            const SizedBox(height: 12),
            _StepTile(
              num: 1,
              title: 'RIASEC',
              desc: 'Enter your RIASEC scores (0–100).',
            ),
            _StepTile(
              num: 2,
              title: 'NCAE',
              desc: 'Enter your NCAE percentiles (0–100).',
            ),
            _StepTile(
              num: 3,
              title: 'Review',
              desc: 'Preview & confirm SHS Strand + Course.',
            ),

            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RiasecTestScreen(),
                          ),
                        ),
                    child: const Text(
                      'Start: RIASEC',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NcaeInputScreen(),
                          ),
                        ),
                    child: const Text(
                      'Go to NCAE',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PathReviewScreen(),
                      ),
                    ),
                child: const Text(
                  'Review Result',
                  style: TextStyle(fontFamily: 'Inter'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int num;
  final String title;
  final String desc;
  const _StepTile({
    required this.num,
    required this.title,
    required this.desc,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF3EB6FF),
        child: Text(
          '$num',
          style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(desc, style: const TextStyle(fontFamily: 'Inter')),
    );
  }
}
