// lib/widgets/career_setup_panel.dart
import 'package:flutter/material.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/screens/riasec_test_screen.dart';
import 'package:career_roadmap/screens/questionnaire_screen.dart';

class CareerSetupPanel extends StatefulWidget {
  /// Called when both RIASEC & NCAE are complete, or right after finalize succeeds.
  final VoidCallback? onCompleted;

  const CareerSetupPanel({Key? key, this.onCompleted}) : super(key: key);

  @override
  State<CareerSetupPanel> createState() => _CareerSetupPanelState();
}

class _CareerSetupPanelState extends State<CareerSetupPanel> {
  bool _loading = true; // page spinner
  bool _finalizing = false; // submit button spinner
  bool _riasecDone = false;
  bool _ncaeDone = false;
  Map<String, dynamic>? _preview; // optional strand/course preview
  String? _error;

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _refreshFlags();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _notifyCompleted() {
    final cb = widget.onCompleted;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
  }

  // ---------- data ----------
  Future<void> _refreshFlags() async {
    _safeSetState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = SupabaseService.authUserId;
      if (uid == null) {
        _safeSetState(() {
          _riasecDone = false;
          _ncaeDone = false;
          _preview = null;
          _loading = false;
        });
        return;
      }

      // Check flags (guard after each await)
      final hasRiasec = await SupabaseService.userHasRiasecResult(uid);
      if (!mounted) return;
      final hasNcae = await SupabaseService.userHasNcaeResult(uid);
      if (!mounted) return;

      Map<String, dynamic>? preview;
      if (hasRiasec && hasNcae) {
        try {
          preview = await SupabaseService.previewLearningPath();
        } catch (_) {
          preview = null; // preview is optional
        }
        if (!mounted) return;
      }

      _safeSetState(() {
        _riasecDone = hasRiasec;
        _ncaeDone = hasNcae;
        _preview = preview;
        _loading = false;
      });

      if (hasRiasec && hasNcae) _notifyCompleted();
    } catch (e) {
      _safeSetState(() {
        _error = 'Failed to load status: $e';
        _loading = false;
      });
    }
  }

  // Called by buttons after a flow completes successfully
  void _markRiasecDone() => _safeSetState(() => _riasecDone = true);
  void _markNcaeDone() => _safeSetState(() => _ncaeDone = true);

  // Finalize (writes user_learning_path via RPC) – guarded and with spinner
  Future<void> _finalize() async {
    if (_finalizing) return;
    _safeSetState(() {
      _finalizing = true;
      _error = null;
    });

    try {
      await SupabaseService.finalizeLearningPath();
      if (!mounted) return;
      _notifyCompleted();
    } catch (e) {
      _safeSetState(() => _error = 'Failed to finalize: $e');
    } finally {
      _safeSetState(() => _finalizing = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _decor(),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final bothDone = _riasecDone && _ncaeDone;

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
              if (!mounted) return;
              if (finished == true) {
                _markRiasecDone();
                await _refreshFlags();
              } else {
                await _refreshFlags(); // still refresh in case data changed
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
              if (!mounted) return;
              if (finished == true) {
                _markNcaeDone();
                await _refreshFlags();
              } else {
                await _refreshFlags();
              }
            },
          ),

          const SizedBox(height: 12),

          if (bothDone) ...[
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
                onPressed: _finalizing ? null : _finalize,
                icon:
                    _finalizing
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.check_circle_outline),
                label: Text(
                  _finalizing ? 'Saving…' : 'Finalize / Save Path',
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ] else
            const Text(
              'Complete both tests to find out your recommended Track and Course.',
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
      margin: const EdgeInsets.only(bottom: 8),
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
