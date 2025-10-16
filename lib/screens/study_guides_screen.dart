// lib/screens/study_guides_screen.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ⬇️ bring in your taskbar
import '../widgets/custom_taskbar.dart';

// ---- THEME (aligned with your app) ----
const kPrimaryBlue = Color(0xFF3EB6FF); // brand blue
const kBgSky = Color(0xFFF2FBFF); // soft sky (matches your taskbar bg)
const kCardShadow = Color(0x1A000000); // 10% black
const kTextPrimary = Color(0xFF121212);
const kTextSecondary = Color(0xFF667085);
const kAccentChip = Color(0xFFFFF4CC); // soft pastel chip bg
const kAccentChipBorder = Color(0xFFFFE082);

class StudyGuidesScreen extends StatefulWidget {
  const StudyGuidesScreen({Key? key}) : super(key: key);

  @override
  State<StudyGuidesScreen> createState() => _StudyGuidesScreenState();
}

class _StudyGuidesScreenState extends State<StudyGuidesScreen> {
  final _client = http.Client();

  List<FileObject> _files = [];
  List<FileObject> _filtered = [];
  bool _loading = true;
  String? _errorMessage;

  // UI helpers
  String _query = '';
  bool _grid = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final files = await Supabase.instance.client.storage
          .from('my-study-guides')
          .list(path: ''); // root

      // Keep only PDFs and sort A→Z by name
      files.retainWhere((f) => f.name.toLowerCase().endsWith('.pdf'));
      files.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _files = files;
        _filtered = _applyFilter(_files, _query);
        _loading = false;
      });

      debugPrint("✅ Files fetched: ${files.map((f) => f.name).toList()}");
    } catch (e, st) {
      debugPrint("❌ Error fetching files: $e\n$st");
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  List<FileObject> _applyFilter(List<FileObject> list, String q) {
    if (q.trim().isEmpty) return list;
    final ql = q.toLowerCase();
    return list.where((f) => f.name.toLowerCase().contains(ql)).toList();
  }

  Future<String> _downloadToCache({
    required String url,
    required String key,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/study_guides');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final safeName = key.replaceAll('/', '_');
    final file = File('${cacheDir.path}/$safeName');

    // already cached
    if (await file.exists()) return file.path;

    // Simple indeterminate progress dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const AlertDialog(
            title: Text('Downloading…'),
            content: Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(color: kPrimaryBlue),
            ),
          ),
    );

    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await _client.send(req);
      if (res.statusCode != 200) {
        throw 'HTTP ${res.statusCode}';
      }

      final sink = file.openWrite();
      await res.stream.pipe(sink);
      await sink.close();

      if (mounted) Navigator.of(context).pop(); // close dialog
      return file.path;
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // ensure dialog closes on error
      }
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<void> _openPdf(FileObject file) async {
    try {
      final key = file.name; // if you add subfolders later, prefix here
      final pdfUrl = await SupabaseService.getFileUrl(
        bucket: 'my-study-guides',
        path: key,
        expiresIn: 3600,
      );
      if (pdfUrl == null) throw 'Failed to get file URL';

      final localPath = await _downloadToCache(url: pdfUrl, key: key);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(path: localPath, title: file.name),
        ),
      );
    } catch (e, st) {
      debugPrint("❌ Failed to open PDF: $e\n$st");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open PDF: $e')));
    }
  }

  String _prettyName(String raw) {
    final noExt = raw.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return noExt.replaceAll(RegExp(r'[_\-]+'), ' ');
  }

  String _formatBytes(dynamic size) {
    if (size == null) return '';
    final s = (size is int) ? size : int.tryParse(size.toString()) ?? 0;
    if (s <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = (log(s) / log(1024)).floor();
    final value = s / pow(1024, i);
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[min(i, units.length - 1)]}';
  }

  // Accepts either DateTime? or String? (ISO) — avoids the type error
  String _formatDate(dynamic dt) {
    if (dt == null) return '';
    DateTime? d;
    if (dt is DateTime) {
      d = dt;
    } else if (dt is String) {
      d = DateTime.tryParse(dt);
    }
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onRefresh() => _loadFiles();

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Study Guides';
    const pageSubtitle = 'Browse recommended materials';

    return Scaffold(
      backgroundColor: kBgSky,
      // Header styled like your Home top banner (rounded bottom)
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: _CurvedHeader(
          title: pageTitle,
          subtitle: pageSubtitle,
          trailing: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.info_outline, color: Colors.white),
            tooltip: 'About',
          ),
        ),
      ),
      body: Column(
        children: [
          // Search + toggle row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged:
                        (v) => setState(() {
                          _query = v;
                          _filtered = _applyFilter(_files, _query);
                        }),
                    decoration: InputDecoration(
                      hintText: 'Search study guides…',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search, color: kPrimaryBlue),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(color: Colors.blue.shade100),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(
                          color: kPrimaryBlue,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _viewToggle(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Content states
          Expanded(
            child: Builder(
              builder: (_) {
                if (_loading) {
                  return const _CenteredState(
                    icon: Icons.downloading_rounded,
                    label: 'Loading study guides…',
                  );
                }

                if (_errorMessage != null) {
                  return _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadFiles,
                  );
                }

                if (_files.isEmpty) {
                  return const _CenteredState(
                    icon: Icons.menu_book_rounded,
                    label: 'No study guides yet.\nUpload a PDF to get started!',
                  );
                }

                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: kPrimaryBlue,
                  child: _grid ? _buildGrid() : _buildList(),
                );
              },
            ),
          ),
        ],
      ),

      // ⬇️ Your custom bottom nav with Resources active
      bottomNavigationBar: const CustomTaskbar(
        selectedIndex: 1, // Home=0, Resources=1, Quizzes=2, Profile=3
        onItemTapped: _noop, // navigation handled inside CustomTaskbar
      ),
    );
  }

  // ---- Small UI helpers ----

  static void _noop(int _) {}

  Widget _viewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
        border: Border.all(color: Colors.blue.shade50),
      ),
      child: Row(
        children: [
          _toggleBtn(
            active: !_grid,
            icon: Icons.view_list_rounded,
            label: 'List',
            onTap: () => setState(() => _grid = false),
          ),
          _toggleBtn(
            active: _grid,
            icon: Icons.grid_view_rounded,
            label: 'Grid',
            onTap: () => setState(() => _grid = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : kTextSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : kTextSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfBadge() {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: kPrimaryBlue,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.picture_as_pdf, color: Colors.white),
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kAccentChip,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAccentChipBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: kTextSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _cardContainer({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: child,
    );
  }

  // ---- List/Grid ----

  Widget _buildList() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _filtered.length,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final file = _filtered[index];
        final meta = (file.metadata ?? const {}) as Map<String, dynamic>;
        final size = _formatBytes(meta['size']);
        final updated = _formatDate(file.updatedAt ?? file.createdAt);

        return InkWell(
          onTap: () => _openPdf(file),
          borderRadius: BorderRadius.circular(16),
          child: _cardContainer(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _pdfBadge(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _prettyName(file.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (size.isNotEmpty) _metaChip(size),
                          if (updated.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _metaChip(updated),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.black38),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3 / 2,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final file = _filtered[index];
        final meta = (file.metadata ?? const {}) as Map<String, dynamic>;
        final size = _formatBytes(meta['size']);
        final updated = _formatDate(file.updatedAt ?? file.createdAt);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPdf(file),
          child: _cardContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pdfBadge(),
                const SizedBox(height: 10),
                Text(
                  _prettyName(file.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    if (size.isNotEmpty) _metaChip(size),
                    if (updated.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _metaChip(updated),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Curved blue header like your Home screen ----
class _CurvedHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _CurvedHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kPrimaryBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 18),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, // "Study Guides"
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ---- Friendly states ----
class _CenteredState extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CenteredState({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              'Error: $message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'Try again',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  final String path;
  final String title;

  const PdfViewerScreen({Key? key, required this.path, required this.title})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgSky,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: _CurvedHeader(
          title: title.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
          subtitle: 'PDF viewer',
          trailing: const SizedBox.shrink(),
        ),
      ),
      body: PDFView(
        filePath: path,
        enableSwipe: true,
        autoSpacing: true,
        pageFling: true,
        onError: (error) {
          debugPrint("❌ PDF view error: $error");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF view error: $error')));
        },
        onPageError: (page, error) {
          debugPrint("❌ Error on page $page: $error");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error on page $page: $error')),
          );
        },
      ),
      bottomNavigationBar: const CustomTaskbar(
        selectedIndex: 1,
        onItemTapped: _StudyGuidesScreenState._noop,
      ),
    );
  }
}
