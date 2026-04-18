import 'dart:ui'; // For Matrix4
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:career_roadmap/screens/home_screen.dart';
import 'package:career_roadmap/screens/questionnaire_intro_screen.dart';
import 'package:career_roadmap/screens/video_study_guides_screen.dart';
import 'package:career_roadmap/screens/exploration_screen.dart';
import 'package:career_roadmap/screens/skills_screen.dart';
import 'package:career_roadmap/screens/profile_details_screen.dart';
import 'package:career_roadmap/screens/study_guides_screen.dart';
import 'package:career_roadmap/widgets/custom_taskbar.dart' as taskbar;

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({Key? key}) : super(key: key);

  @override
  ResourcesScreenState createState() => ResourcesScreenState();
}

class ResourcesScreenState extends State<ResourcesScreen> {
  int _selectedIndex = 1;

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);

    Widget? target;
    switch (index) {
      case 0:
        target = const HomeScreen();
        break;
      case 1:
        return;
      case 2:
        target = const QuestionnaireIntroScreen();
        break;
      case 3:
        target = const ProfileDetailsScreen();
        break;
    }

    if (target != null) {
      Navigator.of(context).pushReplacement(_buildPageRoute(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2FBFF),
      appBar: AppBar(
        automaticallyImplyLeading: false, // 🚫 disables back button
        backgroundColor: const Color(0xFFF2FBFF),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Resources',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ResourceCard(
              icon: Icons.assignment,
              title: 'Pre-Assessment',
              subtitle: 'Test your NCAE readiness',
              colors: const [Color(0xFF81D4FA), Color(0xFF29B6F6)],
              onTap: () {
                Navigator.of(
                  context,
                ).push(_buildPageRoute(const QuestionnaireIntroScreen()));
              },
            ),
            const SizedBox(height: 12),
            _ResourceCard(
              icon: Icons.book,
              title: 'Study Guides',
              subtitle: 'Browse recommended materials',
              colors: const [Color(0xFFCE93D8), Color(0xFFAB47BC)],
              onTap: () {
                Navigator.of(
                  context,
                ).push(_buildPageRoute(const StudyGuidesScreen()));
              },
            ),
            const SizedBox(height: 12),
            _ResourceCard(
              icon: Icons.video_library,
              title: 'Video Tutorials',
              subtitle: 'Watch explanatory videos',
              colors: const [Color(0xFFFFF59D), Color(0xFFFFEE58)],
              onTap: () {
                Navigator.of(
                  context,
                ).push(_buildPageRoute(const VideoStudyGuidesScreen()));
              },
            ),
            const SizedBox(height: 12),
            _ResourceCard(
              icon: Icons.explore,
              title: 'Exploration',
              subtitle: 'Discover Pathways',
              colors: const [Color(0xFFA5D6A7), Color(0xFF66BB6A)],
              onTap: () {
                Navigator.of(
                  context,
                ).push(_buildPageRoute(const ExplorationScreen()));
              },
            ),
            const SizedBox(height: 12),
            _ResourceCard(
              icon: Icons.star,
              title: 'Skills',
              subtitle: 'Build & track skills',
              colors: const [Color(0xFFFFAB91), Color(0xFFFF7043)],
              onTap: () {
                Navigator.of(
                  context,
                ).push(_buildPageRoute(const SkillsScreen()));
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: taskbar.CustomTaskbar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Route _buildPageRoute(Widget screen) {
    return PageRouteBuilder(
      pageBuilder: (c, a, sa) => screen,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (c, animation, sa, child) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation);
        final fade = Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    );
  }
}

class _ResourceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  const _ResourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<_ResourceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c1 = widget.colors.first;
    final c2 = widget.colors.last;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      transform:
          (_hover && kIsWeb)
              ? (Matrix4.identity()..scale(1.03))
              : Matrix4.identity(),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: c2.withOpacity(_hover ? 0.5 : 0.3),
            blurRadius: _hover ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(12),
            child: Icon(widget.icon, size: 28, color: c2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70),
        ],
      ),
    );

    if (kIsWeb) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: card,
      );
    }

    return GestureDetector(onTap: widget.onTap, child: card);
  }
}
