import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'path_review_screen.dart';

// ====== App palette (file-level so all widgets can use it) ======
const kBg = Color(0xFFEAF8FF); // soft page background
const kPrimary = Color(0xFF007BFF); // primary
const kInk = Color(0xFF0F172A); // near-black text
const kMuted = Color(0xFF6B7280); // secondary text
const kCard = Colors.white; // cards
const kChip = Color(0xFFEEF8FF); // subtle selected fill
const kDivider = Color(0xFFE5E7EB);

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
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
          content: const Text(
            'Failed to load RIASEC items.',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
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
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
          content: const Text(
            'Please answer all items.',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
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
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF16A34A),
          content: Text(
            'RIASEC submitted!',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
          ),
        ),
      );

      // Return to the caller (CareerSetupPanel) and signal success
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
          content: Text(
            'Submit failed. Please try again.',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
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
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kInk),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Back',
          ),
          centerTitle: true,
          title: const Text(
            'Riasec Test',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: kInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: const Center(
          child: Text(
            'No items found.',
            style: TextStyle(fontFamily: 'Inter', color: kMuted),
          ),
        ),
      );
    }

    final item = _items[_index];
    final id = (item['id'] as num).toInt();
    final selected = _answers[id];
    final progress = (_index + 1) / _items.length;

    // Optional badge if domain/scale key exists (R/I/A/S/E/C)
    final domain =
        ((item['domain'] ?? item['scale'] ?? '')).toString().toUpperCase();
    final showBadge = domain.isNotEmpty;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kInk),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Back',
        ),
        centerTitle: true,
        title: const Text(
          'Riasec Test',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: kInk,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // Sticky bottom action bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: kCard,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
            border: const Border(top: BorderSide(color: kDivider)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (_index > 0)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kInk,
                    side: const BorderSide(color: kDivider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _prev,
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted,
                    side: const BorderSide(color: kDivider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: null,
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              if (_index < _items.length - 1)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kPrimary.withOpacity(0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                  onPressed: selected == null ? null : _next,
                  child: const Text(
                    'Next',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kPrimary.withOpacity(0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                  onPressed: (selected == null || _submitting) ? null : _submit,
                  child:
                      _submitting
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            'Submit',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                ),
            ],
          ),
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress with percent
              _RoundedProgress(value: progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Question ${_index + 1} of ${_items.length}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color: kInk,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontFamily: 'Inter', color: kMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Question card (animated between indices)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder:
                    (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                child: _QuestionCard(
                  key: ValueKey(id),
                  text: (item['text'] as String?) ?? '',
                  domain: showBadge ? domain : null,
                ),
              ),
              const SizedBox(height: 12),

              // Likert choices
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _likert.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final value = _scaleMin + i; // 1..5
                    final label = _likert[i];
                    final picked = selected == value;
                    return _ChoiceCard(
                      label: label,
                      value: value,
                      selected: picked,
                      onTap: () => _select(value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== UI pieces =====

class _RoundedProgress extends StatelessWidget {
  const _RoundedProgress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 10,
        backgroundColor: Colors.white,
        color: kPrimary,
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({super.key, required this.text, this.domain});
  final String text;
  final String? domain;

  Color _badgeColor(String code) {
    switch (code) {
      case 'R':
        return const Color(0xFF0EA5E9); // cyan-ish
      case 'I':
        return const Color(0xFF6366F1); // indigo
      case 'A':
        return const Color(0xFFF97316); // orange
      case 'S':
        return const Color(0xFF10B981); // green
      case 'E':
        return const Color(0xFFEC4899); // pink
      case 'C':
        return const Color(0xFFF59E0B); // amber
      default:
        return kPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (domain != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _badgeColor(domain!).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _badgeColor(domain!).withOpacity(0.35),
                  ),
                ),
                child: Text(
                  'Domain: $domain',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    color: _badgeColor(domain!),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                height: 1.35,
                color: kInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kChip : kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kPrimary.withOpacity(0.55) : kDivider,
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                  : const [],
        ),
        child: Row(
          children: [
            // Radio visual
            Container(
              height: 22,
              width: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kPrimary : kDivider,
                  width: 2,
                ),
                color: Colors.white,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 12,
                width: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? kPrimary : Colors.transparent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? kInk : kInk.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
