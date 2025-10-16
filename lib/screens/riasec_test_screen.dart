import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'path_review_screen.dart';

class RiasecTestScreen extends StatefulWidget {
  const RiasecTestScreen({super.key});

  @override
  State<RiasecTestScreen> createState() => _RiasecTestScreenState();
}

class _RiasecTestScreenState extends State<RiasecTestScreen> {
  List<Map<String, dynamic>> _items = [];
  List<String> _likert = const [
    'Strongly Disagree',
    'Disagree',
    'Neutral',
    'Agree',
    'Strongly Agree',
  ];
  int _scaleMin = 1, _scaleMax = 5;

  // answers[itemId] = value (1..5)
  final Map<int, int> _answers = {};
  int _index = 0;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseService.loadRiasecItems();
      _items = List<Map<String, dynamic>>.from(data['items'] as List);
      _scaleMin = data['scale_min'] as int;
      _scaleMax = data['scale_max'] as int;
      _likert = List<String>.from(data['likert_labels'] as List);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load RIASEC items: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(int value) {
    final id = (_items[_index]['id'] as num).toInt();
    setState(() => _answers[id] = value);
  }

  void _next() {
    if (_index < _items.length - 1) {
      setState(() => _index++);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
  }

  Future<void> _submit() async {
    if (_answers.length < _items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please answer all items.',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _submitting = true);
    try {
      final scores = SupabaseService.scoreRiasecToPercent(
        items: _items,
        answers: _answers,
        scaleMin: _scaleMin,
        scaleMax: _scaleMax,
      );

      await SupabaseService.insertRiasec(
        userId: uid,
        r: scores['R']!,
        i: scores['I']!,
        a: scores['A']!,
        s: scores['S']!,
        e: scores['E']!,
        c: scores['C']!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'RIASEC submitted!',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );

      // Go to review (compute_learning_path)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PathReviewScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Submit failed: $e',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('RIASEC Test')),
        body: const Center(child: Text('No items found.')),
      );
    }

    final item = _items[_index];
    final id = (item['id'] as num).toInt();
    final selected = _answers[id];

    final progress = (_index + 1) / _items.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RIASEC Test',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: const Color(0xFF007BFF),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Question ${_index + 1} of ${_items.length}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  item['text'] as String,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Likert choices
            Expanded(
              child: ListView.separated(
                itemCount: _likert.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final value = _scaleMin + i; // e.g., 1..5
                  final label = _likert[i];
                  final picked = selected == value;
                  return ListTile(
                    onTap: () => _select(value),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    tileColor: picked ? const Color(0xFFEEF8FF) : null,
                    leading: Radio<int>(
                      value: value,
                      groupValue: selected,
                      onChanged: (v) => _select(v!),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(fontFamily: 'Inter'),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                if (_index > 0)
                  OutlinedButton(
                    onPressed: _prev,
                    child: const Text(
                      'Back',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  ),
                const Spacer(),
                if (_index < _items.length - 1)
                  ElevatedButton(
                    onPressed: selected == null ? null : _next,
                    child: const Text(
                      'Next',
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed:
                        (selected == null || _submitting) ? null : _submit,
                    child:
                        _submitting
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Text(
                              'Submit',
                              style: TextStyle(fontFamily: 'Inter'),
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
