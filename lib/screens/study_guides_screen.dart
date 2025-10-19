// lib/screens/study_guides_screen.dart
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // for PPT open + external

import '../widgets/custom_taskbar.dart';

// ---- THEME ----
const kPrimaryBlue = Color(0xFF3EB6FF);
const kBgSky = Color(0xFFF2FBFF);
const kCardShadow = Color(0x1A000000);
const kTextPrimary = Color(0xFF121212);
const kTextSecondary = Color(0xFF667085);
const kAccentChip = Color(0xFFFFF4CC);
const kAccentChipBorder = Color(0xFFFFE082);

enum TypeFilter { all, pdf, image, ppt }

class StudyGuidesScreen extends StatefulWidget {
  const StudyGuidesScreen({Key? key}) : super(key: key);

  @override
  State<StudyGuidesScreen> createState() => _StudyGuidesScreenState();
}

class _StudyGuidesScreenState extends State<StudyGuidesScreen> {
  final _client = http.Client();

  List<GuideItem> _all = [];
  List<GuideItem> _filtered = [];
  bool _loading = true;
  String? _errorMessage;

  // UI helpers
  String _query = '';
  bool _grid = false;
  TypeFilter _filter = TypeFilter.all;

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
      final items = await SupabaseService.listStudyGuides();
      setState(() {
        _all = items;
        _filtered = _applyFilter(_all, _query, _filter);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint("❌ Error fetching study guides: $e\n$st");
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  List<GuideItem> _applyFilter(
    List<GuideItem> list,
    String q,
    TypeFilter filter,
  ) {
    Iterable<GuideItem> it = list;
    switch (filter) {
      case TypeFilter.pdf:
        it = it.where((g) => g.type == GuideType.pdf);
        break;
      case TypeFilter.image:
        it = it.where((g) => g.type == GuideType.image);
        break;
      case TypeFilter.ppt:
        it = it.where((g) => g.type == GuideType.ppt);
        break;
      case TypeFilter.all:
        break;
    }
    if (q.trim().isNotEmpty) {
      final ql = q.toLowerCase();
      it = it.where((g) => g.name.toLowerCase().contains(ql));
    }
    return it.toList();
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

    if (await file.exists()) return file.path;

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

      if (mounted) Navigator.of(context).pop();
      return file.path;
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<void> _openItem(GuideItem item) async {
    final url = await SupabaseService.getFileUrl(
      bucket: 'resources',
      path: item.path,
      expiresIn: 3600,
    );
    if (url == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to get file URL')));
      return;
    }

    if (item.type == GuideType.pdf) {
      try {
        final localPath = await _downloadToCache(url: url, key: item.path);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(path: localPath, title: item.name),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open PDF: $e')));
      }
      return;
    }

    if (item.type == GuideType.image) {
      showDialog(
        context: context,
        builder:
            (_) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
      );
      return;
    }

    // PPT/PPTX – open externally (browser / app chooser)
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  String _prettyName(String raw) => raw
      .replaceAll(
        RegExp(r'\.(pdf|pptx?|png|jpe?g|gif|webp)$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[_\-]+'), ' ');

  String _formatBytes(int? s) {
    if (s == null || s <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = (log(s) / log(1024)).floor();
    final value = s / pow(1024, i);
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[min(i, units.length - 1)]}';
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onRefresh() => _loadFiles();

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Study Guides';
    const pageSubtitle = 'Browse study materials';

    return Scaffold(
      backgroundColor: kBgSky,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: _CurvedHeader(
          title: pageTitle,
          subtitle: pageSubtitle,
          trailing: const SizedBox.shrink(),
        ),
      ),
      body: Column(
        children: [
          // Search + toggles + type filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged:
                        (v) => setState(() {
                          _query = v;
                          _filtered = _applyFilter(_all, _query, _filter);
                        }),
                    decoration: InputDecoration(
                      hintText: 'Search by name…',
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

          // Type filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                _typeChip('All', TypeFilter.all),
                _typeChip('PDFs', TypeFilter.pdf),
                _typeChip('Images', TypeFilter.image),
                _typeChip('PPT', TypeFilter.ppt),
              ],
            ),
          ),

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
                if (_all.isEmpty) {
                  return const _CenteredState(
                    icon: Icons.menu_book_rounded,
                    label: 'Nothing here yet. Upload to /resources.',
                  );
                }

                // When "All" → show grouped sections. Otherwise → single list/grid.
                if (_filter == TypeFilter.all) {
                  final imgs =
                      _filtered
                          .where((g) => g.type == GuideType.image)
                          .toList();
                  final pdfs =
                      _filtered.where((g) => g.type == GuideType.pdf).toList();
                  final ppts =
                      _filtered.where((g) => g.type == GuideType.ppt).toList();

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: kPrimaryBlue,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        if (imgs.isNotEmpty) _section('Images', imgs),
                        if (pdfs.isNotEmpty) _section('PDFs', pdfs),
                        if (ppts.isNotEmpty) _section('PPT', ppts),
                        if (imgs.isEmpty && pdfs.isEmpty && ppts.isEmpty)
                          const _CenteredState(
                            icon: Icons.search_off_rounded,
                            label: 'No matches for your search.',
                          ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: kPrimaryBlue,
                  child: _grid ? _buildGrid(_filtered) : _buildList(_filtered),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomTaskbar(
        selectedIndex: 1,
        onItemTapped: _noop,
      ),
    );
  }

  // ---- UI helpers ----

  static void _noop(int _) {}

  Widget _typeChip(String label, TypeFilter value) {
    final active = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        setState(() {
          _filter = value;
          _filtered = _applyFilter(_all, _query, _filter);
        });
      },
      selectedColor: kPrimaryBlue,
      labelStyle: TextStyle(color: active ? Colors.white : kTextSecondary),
      backgroundColor: Colors.white,
      shape: StadiumBorder(side: BorderSide(color: Colors.blue.shade100)),
    );
  }

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

  Widget _badge(GuideType t) {
    final icon = switch (t) {
      GuideType.pdf => Icons.picture_as_pdf,
      GuideType.image => Icons.photo,
      GuideType.ppt => Icons.slideshow,
    };
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: kPrimaryBlue,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white),
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

  // ---- Sectioned rendering for "All" ----
  Widget _section(String title, List<GuideItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '$title • ${items.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: kTextPrimary,
              fontSize: 16,
            ),
          ),
        ),
        _grid ? _buildGrid(items) : _buildList(items),
        const SizedBox(height: 10),
      ],
    );
  }

  // ---- List/Grid (single collection) ----
  Widget _buildList(List<GuideItem> items) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final g = items[index];
        final size = _formatBytes(g.size);
        final updated = _formatDate(g.updated);

        return InkWell(
          onTap: () => _openItem(g),
          borderRadius: BorderRadius.circular(16),
          child: _cardContainer(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _badge(g.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _prettyName(g.name),
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

  Widget _buildGrid(List<GuideItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3 / 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final g = items[index];
        final size = _formatBytes(g.size);
        final updated = _formatDate(g.updated);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openItem(g),
          child: _cardContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _badge(g.type),
                const SizedBox(height: 10),
                Text(
                  _prettyName(g.name),
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

// ---- Curved header, states, and PDF viewer (unchanged except title) ----
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF view error: $error')));
        },
        onPageError: (page, error) {
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
