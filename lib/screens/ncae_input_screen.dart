// lib/screens/ncae_input_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class NcaeInputScreen extends StatefulWidget {
  const NcaeInputScreen({super.key});
  @override
  State<NcaeInputScreen> createState() => _NcaeInputScreenState();
}

class _NcaeInputScreenState extends State<NcaeInputScreen> {
  final math = TextEditingController(),
      sci = TextEditingController(),
      eng = TextEditingController(),
      bus = TextEditingController(),
      tvl = TextEditingController(),
      hum = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    math.dispose();
    sci.dispose();
    eng.dispose();
    bus.dispose();
    tvl.dispose();
    hum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int? toInt(TextEditingController t) => int.tryParse(t.text.trim());
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final vals = [math, sci, eng, bus, tvl, hum].map(toInt).toList();
    if (vals.any((v) => v == null || v! < 0 || v! > 100)) {
      _snack('Please enter 0–100 for all NCAE fields.');
      return;
    }
    setState(() => saving = true);
    try {
      await SupabaseService.insertNcae(
        userId: uid,
        math: vals[0]!,
        sci: vals[1]!,
        eng: vals[2]!,
        business: vals[3]!,
        techvoc: vals[4]!,
        humanities: vals[5]!,
      );
      _snack('NCAE saved.');
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Inter'))),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NCAE Percentiles',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _num('Math', math),
          _num('Science', sci),
          _num('English', eng),
          _num('Business', bus),
          _num('Tech-Voc', tvl),
          _num('Humanities', hum),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: saving ? null : _save,
            child:
                saving
                    ? const CircularProgressIndicator()
                    : const Text('Save', style: TextStyle(fontFamily: 'Inter')),
          ),
        ],
      ),
    );
  }

  Widget _num(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
