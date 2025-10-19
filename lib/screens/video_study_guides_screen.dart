import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:career_roadmap/widgets/custom_taskbar.dart' as taskbar;
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- THEME (match study_guides_screen) ----
const kPrimaryBlue = Color(0xFF3EB6FF); // brand blue
const kBgSky = Color(0xFFF2FBFF); // soft sky (matches your taskbar bg)
const kCardShadow = Color(0x1A000000); // 10% black
const kTextPrimary = Color(0xFF121212);
const kTextSecondary = Color(0xFF667085);
const kAccentChip = Color(0xFFFFF4CC); // soft pastel chip bg
const kAccentChipBorder = Color(0xFFFFE082);

class VideoStudyGuidesScreen extends StatefulWidget {
  static const routeName = '/video-study-guides';

  const VideoStudyGuidesScreen({Key? key}) : super(key: key);

  @override
  State<VideoStudyGuidesScreen> createState() => _VideoStudyGuidesScreenState();
}

class _VideoStudyGuidesScreenState extends State<VideoStudyGuidesScreen> {
  List<FileObject> _files = [];
  List<FileObject> _filtered = [];
  bool _loading = true;
  String? _errorMessage;

  // UI helpers
  String _query = '';
  bool _grid = false;
  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final list = await SupabaseService.listVideoFiles();

      // keep only common video types
      list.retainWhere((f) {
        final n = f.name.toLowerCase();
        return n.endsWith('.mp4') ||
            n.endsWith('.mov') ||
            n.endsWith('.m4v') ||
            n.endsWith('.webm');
      });

      // A→Z
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _files = list;
        _filtered = _applyFilter(list, _query);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  List<FileObject> _applyFilter(List<FileObject> list, String q) {
    if (q.trim().isEmpty) return list;
    final lq = q.toLowerCase();
    return list.where((f) => f.name.toLowerCase().contains(lq)).toList();
  }

  String _prettyName(String raw) => raw
      .replaceAll(RegExp(r'\.(mp4|mov|m4v|webm)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_\-]+'), ' ');

  String _formatBytes(dynamic size) {
    if (size == null) return '';
    final s = (size is int) ? size : int.tryParse(size.toString()) ?? 0;
    if (s <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = min(units.length - 1, (log(s) / log(1024)).floor());
    final v = s / pow(1024, i);
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
  }

  String _formatDate(dynamic dt) {
    if (dt == null) return '';
    DateTime? d;
    if (dt is DateTime)
      d = dt;
    else if (dt is String)
      d = DateTime.tryParse(dt);
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onRefresh() => _loadFiles();

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Video Study Guides';
    const pageSubtitle = 'Watch recommended lessons';

    return Scaffold(
      backgroundColor: kBgSky,

      // Clean curved header (no back button overlay)
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(120),
        child: _CurvedHeader(
          title: pageTitle,
          subtitle: pageSubtitle,
          trailing: _HeaderRefreshButton(),
        ),
      ),

      body: Column(
        children: [
          // Search + in-page view toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
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
                      hintText: 'Search videos…',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search, color: kPrimaryBlue),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(color: Colors.blue.shade100),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(28)),
                        borderSide: BorderSide(color: kPrimaryBlue, width: 2),
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

          Expanded(
            child: Builder(
              builder: (_) {
                if (_loading) {
                  return const _CenteredState(
                    icon: Icons.downloading_rounded,
                    label: 'Loading videos…',
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
                    icon: Icons.play_circle_outline_rounded,
                    label: 'No videos yet.\nUpload to get started!',
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

      bottomNavigationBar: taskbar.CustomTaskbar(
        selectedIndex:
            _selectedIndex, // Home=0, Resources=1, Quizzes=2, Profile=3
        onItemTapped: _onItemTapped,
      ),
    );
  }

  // ---- Small UI helpers ----

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

  Widget _videoBadge() {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: kPrimaryBlue,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
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
      itemBuilder: (context, i) {
        final f = _filtered[i];
        final meta = (f.metadata ?? const {}) as Map<String, dynamic>;
        final size = _formatBytes(meta['size']);
        final date = _formatDate(f.updatedAt ?? f.createdAt);

        return InkWell(
          onTap: () => _openPlayer(context, f.name),
          borderRadius: BorderRadius.circular(16),
          child: _cardContainer(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _videoBadge(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _prettyName(f.name),
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
                          if (date.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _metaChip(date),
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
      itemBuilder: (context, i) {
        final f = _filtered[i];
        final meta = (f.metadata ?? const {}) as Map<String, dynamic>;
        final size = _formatBytes(meta['size']);
        final date = _formatDate(f.updatedAt ?? f.createdAt);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPlayer(context, f.name),
          child: _cardContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _videoBadge(),
                const SizedBox(height: 10),
                Text(
                  _prettyName(f.name),
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
                    if (date.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _metaChip(date),
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

  Future<void> _openPlayer(BuildContext context, String key) async {
    // safer: signed URL works for both public/private buckets
    final url = await SupabaseService.getFileUrl(
      bucket: 'study-guide-videos',
      path: key,
      expiresIn: 3600,
    );
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to get video URL')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoPlayerPage(title: _prettyName(key), url: url),
      ),
    );
  }
}

// ---- Curved blue header (kept clean) ----
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

class _HeaderRefreshButton extends StatelessWidget {
  const _HeaderRefreshButton();

  @override
  Widget build(BuildContext context) {
    // use InheritedElement to reach state method
    final state =
        context.findAncestorStateOfType<_VideoStudyGuidesScreenState>();
    return IconButton(
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh, color: Colors.white),
      onPressed: state?._loadFiles,
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

/// Player page with custom controls (play/pause, seek, ±10s, mute, speed, fullscreen).
class _VideoPlayerPage extends StatefulWidget {
  final String title;
  final String url;
  const _VideoPlayerPage({required this.title, required this.url});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _loading = true;
  bool _error = false;
  bool _muted = false;
  double _speed = 1.0;
  bool _controlsVisible = true;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c?.dispose();
    if (_fullscreen) _exitFullscreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause when app goes background
    if (state != AppLifecycleState.resumed) {
      _c?.pause();
    }
  }

  Future<void> _init() async {
    try {
      final c =
          VideoPlayerController.networkUrl(Uri.parse(widget.url))
            ..addListener(() => mounted ? setState(() {}) : null)
            ..setLooping(false);
      await c.initialize();
      await c.setVolume(1.0);
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() => _fullscreen = true);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    setState(() => _fullscreen = false);
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return WillPopScope(
      onWillPop: () async {
        if (_fullscreen) {
          await _exitFullscreen();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: kPrimaryBlue,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            IconButton(
              tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
              icon: Icon(
                _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
              onPressed:
                  () => _fullscreen ? _exitFullscreen() : _enterFullscreen(),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error || _c == null
                ? const Center(
                  child: Text(
                    'Failed to load video',
                    style: TextStyle(color: Colors.red),
                  ),
                )
                : GestureDetector(
                  onTap:
                      () =>
                          setState(() => _controlsVisible = !_controlsVisible),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio:
                              _c!.value.aspectRatio == 0
                                  ? 16 / 9
                                  : _c!.value.aspectRatio,
                          child: VideoPlayer(_c!),
                        ),
                      ),
                      if (_controlsVisible) _buildControls(context),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final v = _c!.value;
    final pos = v.position;
    final dur = v.duration;
    final isPlaying = v.isPlaying;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar
          Row(
            children: [
              Text(_fmt(pos), style: const TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value:
                      pos.inMilliseconds
                          .clamp(0, dur.inMilliseconds)
                          .toDouble(),
                  min: 0,
                  max: max(1, dur.inMilliseconds).toDouble(),
                  onChanged:
                      (v) => _c!.seekTo(Duration(milliseconds: v.toInt())),
                  activeColor: Colors.blueAccent,
                  inactiveColor: Colors.white24,
                ),
              ),
              Text(_fmt(dur), style: const TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 4),
          // Transport & options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Rewind 10s',
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed:
                    () => _c!.seekTo(
                      _c!.value.position - const Duration(seconds: 10),
                    ),
              ),
              IconButton(
                tooltip: isPlaying ? 'Pause' : 'Play',
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: () => isPlaying ? _c!.pause() : _c!.play(),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed:
                    () => _c!.seekTo(
                      _c!.value.position + const Duration(seconds: 10),
                    ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _muted ? 'Unmute' : 'Mute',
                icon: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                ),
                onPressed: () async {
                  _muted = !_muted;
                  await _c!.setVolume(_muted ? 0 : 1);
                  setState(() {});
                },
              ),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: _speed,
                onSelected: (s) async {
                  _speed = s;
                  await _c!.setPlaybackSpeed(s);
                  setState(() {});
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 0.5, child: Text('0.5×')),
                      PopupMenuItem(value: 0.75, child: Text('0.75×')),
                      PopupMenuItem(value: 1.0, child: Text('1.0×')),
                      PopupMenuItem(value: 1.25, child: Text('1.25×')),
                      PopupMenuItem(value: 1.5, child: Text('1.5×')),
                      PopupMenuItem(value: 2.0, child: Text('2.0×')),
                    ],
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${_speed.toStringAsFixed(_speed % 1 == 0 ? 0 : 2)}×',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
