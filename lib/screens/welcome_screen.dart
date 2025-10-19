import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter; // for subtle glass blur
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _brandBlue = Color(0xFF3EB6FF);
  static const _bgTop = Color(0xFFE6F6FF);
  static const _bgBottom = Color(0xFFF2FBFF);

  InputBorder get _outline => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFDAE8F5)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBottom,
      body: Stack(
        children: [
          // Brand gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_bgTop, _bgBottom],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Decorative soft circles
          Positioned(
            top: -60,
            left: -40,
            child: _Halo(color: _brandBlue.withOpacity(.15), size: 220),
          ),
          Positioned(
            bottom: -80,
            right: -30,
            child: _Halo(color: _brandBlue.withOpacity(.12), size: 260),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 6),

                        // Header
                        Column(
                          children: [
                            Hero(
                              tag: 'app_logo',
                              child: Image.asset('assets/logo.png', height: 92),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'UpCourse • Career Roadmap',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B5568),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Plan your path. Achieve your goals.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: Color(0xFF5D6B7A),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Hero card (glassy) with illustration + chips
                        _Glassy(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                            child: Column(
                              children: [
                                // --- Illustration (no cropping; keep head visible) ---
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    color: Colors.white,
                                    padding: const EdgeInsets.all(8),
                                    child: SizedBox(
                                      height: 220, // adjust 200–260 as desired
                                      width: double.infinity,
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        alignment: Alignment.topCenter,
                                        child: Image.asset(
                                          'assets/illustration1.png',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Feature chips row
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: const [
                                    _FeatureChip(
                                      icon: Icons.explore_outlined,
                                      label: 'Discover tracks',
                                    ),
                                    _FeatureChip(
                                      icon: Icons.school_outlined,
                                      label: 'In-demand courses',
                                    ),
                                    _FeatureChip(
                                      icon: Icons.quiz_outlined,
                                      label: 'Quizzes',
                                    ),
                                    _FeatureChip(
                                      icon: Icons.analytics_outlined,
                                      label: 'Personalized path',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Actions
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                label: const Text(
                                  'Sign up',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SignupScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _brandBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.login_rounded),
                                label: const Text(
                                  'I already have an account',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: _brandBlue,
                                    width: 1.4,
                                  ),
                                  foregroundColor: _brandBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Subtle terms text
                            const Text(
                              'By continuing, you agree to our Terms & Privacy Policy.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: Color(0xFF7A8A98),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Small UI atoms ----------

class _Glassy extends StatelessWidget {
  final Widget child;
  const _Glassy({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE9F2FA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF3B5568)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3B5568),
            ),
          ),
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  final Color color;
  final double size;
  const _Halo({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 60, spreadRadius: 20)],
      ),
    );
  }
}
