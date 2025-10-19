// lib/screens/profile_details_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'package:career_roadmap/widgets/custom_taskbar.dart' as taskbar;
import 'package:career_roadmap/screens/login_screen.dart'; // for logout redirect

// ===== THEME (aligned with your app) =====
const kPrimaryBlue = Color(0xFF3EB6FF); // brand blue
const kCyan = Color(0xFF00E0FF); // cyan accent for gradient
const kBgSky = Color(0xFFF2FBFF); // soft sky like your taskbar bg
const kTextPrimary = Color(0xFF121212);
const kTextSecondary = Color(0xFF667085);
const kCardShadow = Color(0x1A000000); // 10% black
const kChipBg = Color(0xFFEFF6FF);
const kChipText = Color(0xFF2563EB);

class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  ProfileDetailsScreenState createState() => ProfileDetailsScreenState();
}

class ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  int _selectedIndex = 3; // Profile active
  bool _isLoading = false;
  Map<String, dynamic>? _profileData;
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  Future<void> _fetchUserProfile() async {
    setState(() => _isLoading = true);
    final profile = await SupabaseService.getMyProfile();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _profileData = profile;
    });

    if (profile == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to load profile',
            style: TextStyle(fontFamily: 'Inter'),
          ),
        ),
      );
    }
  }

  Future<void> _pickProfilePicture() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _profileImage = File(picked.path));
      final bytes = await File(picked.path).readAsBytes();

      final url = await SupabaseService.uploadAvatar(
        fileName: 'profile_${SupabaseService.authUserId}.jpg',
        bytes: bytes,
      );

      await SupabaseService.upsertMyProfile({'profile_picture': url});
      if (mounted) _fetchUserProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text(
              'Log out',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            content: const Text(
              'Are you sure you want to log out?',
              style: TextStyle(fontFamily: 'Inter'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontFamily: 'Inter'),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Log out',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white),
                ),
              ),
            ],
          ),
    );
    if (ok == true) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgSky,

      // Curved blue header like your Resources/Home
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(110),
        child: _CurvedHeader(
          title: 'Profile',
          subtitle: 'Your account details',
        ),
      ),

      // Your custom bottom nav with Profile active
      bottomNavigationBar: taskbar.CustomTaskbar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped, // navigation handled inside the widget
      ),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child:
                    _isLoading
                        ? const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: kPrimaryBlue,
                            ),
                          ),
                        )
                        : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          child:
                              _profileData == null
                                  ? const _EmptyState()
                                  : _buildProfileView(constraints.maxWidth),
                        ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileView(double width) {
    // ⚠️ Make these Strings so the extension works
    final String firstName = (_profileData?['first_name'] ?? '').toString();
    final String middleName = (_profileData?['middle_name'] ?? '').toString();
    final String lastName = (_profileData?['last_name'] ?? '').toString();
    final String gradeLevel =
        (_profileData?['grade_level'] ?? '').toString().trim();
    final String email = (SupabaseService.authEmail ?? 'N/A').toString();

    // NEW: Section
    final String section = (_profileData?['section'] ?? '').toString().trim();

    // NEW: Track & Course (from normalized service fields)
    final String track =
        (_profileData?['track_label'] ??
                _profileData?['track_id'] ??
                _profileData?['strand'] ??
                '')
            .toString()
            .trim();

    final String course =
        (_profileData?['course_label'] ??
                _profileData?['course'] ??
                (_profileData?['courses']?['name']) ??
                '')
            .toString()
            .trim();

    final String fullName = [
      firstName,
      if (middleName.isNotEmpty) middleName,
      lastName,
    ].where((e) => e.trim().isNotEmpty).join(' ');

    final String profilePicUrl =
        (_profileData?['profile_picture'] ?? '').toString();

    final bool isNarrow = width < 380; // tiny phones breakpoint
    final double avatarRadius = isNarrow ? 32 : 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Profile header card =====
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPrimaryBlue, kCyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: kCardShadow,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child:
              isNarrow
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Avatar(
                        radius: avatarRadius,
                        imageFile: _profileImage,
                        networkUrl: profilePicUrl,
                        onEdit: _pickProfilePicture,
                      ),
                      const SizedBox(height: 12),
                      _NameAndRole(
                        name: fullName.isEmpty ? 'Student' : fullName,
                        role:
                            gradeLevel.isNotEmpty
                                ? 'Grade $gradeLevel Student'
                                : 'Student',
                        centered: true,
                      ),
                      const SizedBox(height: 12),
                      _ChipsRow(
                        gradeLevel: gradeLevel,
                        track: track,
                        course: course,
                        section: section,
                      ),
                    ],
                  )
                  : Row(
                    children: [
                      _Avatar(
                        radius: avatarRadius,
                        imageFile: _profileImage,
                        networkUrl: profilePicUrl,
                        onEdit: _pickProfilePicture,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _NameAndRole(
                              name: fullName.isEmpty ? 'Student' : fullName,
                              role:
                                  gradeLevel.isNotEmpty
                                      ? 'Grade $gradeLevel Student'
                                      : 'Student',
                            ),
                            const SizedBox(height: 12),
                            _ChipsRow(
                              gradeLevel: gradeLevel,
                              track: track,
                              course: course,
                              section: section,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
        ),

        const SizedBox(height: 20),

        // ===== Student Information =====
        _buildSection(
          title: 'Student Information',
          icon: Icons.badge_rounded,
          children: [
            _infoRow('First Name', firstName.ifEmpty('—')),
            _infoRow('Middle Name', middleName.ifEmpty('—')),
            _infoRow('Last Name', lastName.ifEmpty('—')),
            _infoRow('Full Name', fullName.ifEmpty('—')),
            _infoRow(
              'Grade Level',
              gradeLevel.isNotEmpty ? 'Grade $gradeLevel' : '—',
            ),
            _infoRow('Section', section.ifEmpty('—')),
            _infoRow('Email', email.ifEmpty('—')),

            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),

            // Track & Course lines
            _infoRow('Track', track.ifEmpty('—')),
            _infoRow('Course', course.ifEmpty('—')),
          ],
        ),

        const SizedBox(height: 12),

        // ===== Account Actions =====
        _buildSection(
          title: 'Account Settings',
          icon: Icons.settings_rounded,
          children: [
            _actionRow(
              icon: Icons.camera_alt_rounded,
              label: 'Change Profile Photo',
              onTap: _pickProfilePicture,
            ),
            _divider(),
            _actionRow(
              icon: Icons.refresh_rounded,
              label: 'Refresh Profile',
              onTap: _fetchUserProfile,
            ),
            _divider(),
            // logout at the bottom
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _confirmLogout,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Log out',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.black38,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ===== UI Pieces =====

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: kTextPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: kTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: kChipBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: kPrimaryBlue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade200);

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: kChipBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: kPrimaryBlue, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: kTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

// ===== Components =====

class _CurvedHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _CurvedHeader({required this.title, required this.subtitle});

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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, // "Profile"
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
            Container(
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.person_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final double radius;
  final File? imageFile;
  final String? networkUrl;
  final VoidCallback onEdit;

  const _Avatar({
    required this.radius,
    required this.imageFile,
    required this.networkUrl,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider imageProvider;
    if (imageFile != null) {
      imageProvider = FileImage(imageFile!);
    } else if (networkUrl != null && networkUrl!.isNotEmpty) {
      imageProvider = NetworkImage(networkUrl!);
    } else {
      imageProvider = const AssetImage('assets/user_placeholder.png');
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(radius: radius, backgroundImage: imageProvider),
        Positioned(
          bottom: -2,
          right: -2,
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kCardShadow,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.edit, size: 16, color: kPrimaryBlue),
            ),
          ),
        ),
      ],
    );
  }
}

class _NameAndRole extends StatelessWidget {
  final String name;
  final String role;
  final bool centered;

  const _NameAndRole({
    required this.name,
    required this.role,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final String gradeLevel;

  // show track & course chips if present
  final String? track;
  final String? course;

  // section chip
  final String? section;

  const _ChipsRow({
    required this.gradeLevel,
    this.track,
    this.course,
    this.section,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (gradeLevel.isNotEmpty) _chip('Grade $gradeLevel'),
      if ((section ?? '').trim().isNotEmpty)
        _chip('Section: ${section!.trim()}'),
      if ((track ?? '').trim().isNotEmpty) _chip('Track: ${track!.trim()}'),
      if ((course ?? '').trim().isNotEmpty) _chip(course!.trim()),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kChipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(
        text,
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: kChipText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline_rounded, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'No profile data found.',
            style: TextStyle(fontFamily: 'Inter', color: kTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ===== Small string helper =====
extension _StrX on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
