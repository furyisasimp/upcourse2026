// lib/widgets/career_setup_panel.dart
import 'package:flutter/material.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/screens/riasec_test_screen.dart';
import 'package:career_roadmap/screens/questionnaire_screen.dart';

class CareerSetupPanel extends StatefulWidget {
  /// Called when the panel’s work is complete (both RIASEC & NCAE done),
  /// or immediately after “Finalize / Save Path” succeeds.
  final VoidCallback? onCompleted;

  const CareerSetupPanel({Key? key, this.onCompleted}) : super(key: key);

  @override
  State<CareerSetupPanel> createState() => _CareerSetupPanelState();
}

class _CareerSetupPanelState extends State<CareerSetupPanel> {
  bool _loading = true;
  bool _riasecDone = false;
  bool _ncaeDone = false;
  Map<String, dynamic>? _preview; // strand/course preview if you show it
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshFlags();
  }

  Future<void> _refreshFlags() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = SupabaseService.authUserId;
      if (uid == null) {
        setState(() {
          _riasecDone = false;
          _ncaeDone = false;
          _loading = false;
        });
        return;
      }

      // Check if user has RIASEC result
      final hasRiasec = await SupabaseService.userHasRiasecResult(uid);
      // Check if user has NCAE result (either structured ncae_results or questionnaire_results)
      final hasNcae = await SupabaseService.userHasNcaeResult(uid);

      setState(() {
        _riasecDone = hasRiasec;
        _ncaeDone = hasNcae;
        _loading = false;
      });

      if (_riasecDone && _ncaeDone) {
        // Optional: load preview when both are present
        try {
          _preview = await SupabaseService.previewLearningPath();
        } catch (_) {
          /* ignore preview errors */
        }
        _notifyCompleted(); // tell HomeScreen so it can hide the panel
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load status: $e';
        _loading = false;
      });
    }
  }

  void _notifyCompleted() {
    // Fire after the current frame to avoid setState-order issues
    if (widget.onCompleted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCompleted!.call();
      });
    }
  }

  // Call this right after you save a RIASEC result from inside this panel
  Future<void> _markRiasecDone() async {
    setState(() => _riasecDone = true);
    if (_riasecDone && _ncaeDone) _notifyCompleted();
  }

  // Call this right after you save an NCAE result from inside this panel
  Future<void> _markNcaeDone() async {
    setState(() => _ncaeDone = true);
    if (_riasecDone && _ncaeDone) _notifyCompleted();
  }

  // When user presses "Finalize / Save Path"
  Future<void> _finalize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.finalizeLearningPath();
      // After finalize, also notify parent to hide the panel
      _notifyCompleted();
    } catch (e) {
      setState(() => _error = 'Failed to finalize: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _decor(),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _decor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Career Setup',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),

          _statusRow(
            'RIASEC Test',
            _riasecDone,
            onTapTake: () async {
              final finished = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const RiasecTestScreen()),
              );
              if (finished == true) {
                await _markRiasecDone();
                await _refreshFlags();
              }
            },
          ),

          _statusRow(
            'NCAE Pre-Assessment',
            _ncaeDone,
            onTapTake: () async {
              final finished = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const QuestionnaireScreen()),
              );
              if (finished == true) {
                await _markNcaeDone();
                await _refreshFlags();
              }
            },
          ),

          const SizedBox(height: 12),

          if (_riasecDone && _ncaeDone) ...[
            // Optional small preview text
            if (_preview != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Suggested: ${_preview!['strand_name'] ?? _preview!['strand_id']}'
                  ' • ${_preview!['course_name'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _finalize,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finalize / Save Path'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ] else
            const Text(
              'Complete both tests to generate your recommended SHS strand and course.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _decor() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );

  Widget _statusRow(
    String label,
    bool done, {
    required VoidCallback onTapTake,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: done ? const Color(0xFFB6F2D3) : const Color(0xFFE6EDF5),
        ),
        color: done ? const Color(0xFFE8FFF4) : const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? const Color(0xFF1FA971) : const Color(0xFF90A4AE),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!done)
            TextButton(onPressed: onTapTake, child: const Text('Take')),
        ],
      ),
    );
  }
}
