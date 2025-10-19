import 'package:flutter/material.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _passwordVisible = false;
  String? _inlineError; // show a banner-like error above the form

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null) return;

    setState(() => _inlineError = null);

    if (!form.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      final response = await SupabaseService.loginUser(email, password);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.user != null) {
        final userId = response.user!.id;

        // Ensure a row exists in users table (first-login bootstrap)
        final profile = await SupabaseService.getMyProfile();
        if (profile == null) {
          await SupabaseService.upsertMyProfile({
            'supabase_id': userId,
            'email': email,
            'first_name': 'Guest',
            'last_name': '',
            'grade_level': null,
            'school': null,
            'profile_picture': null,
          });
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => _inlineError = 'Invalid email or password.');
      }
    } on DisabledAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _inlineError = e.message;
      });
      _showDialog(
        title: 'Account Disabled',
        message:
            '${e.message}\n\nIf you believe this is a mistake, please contact your school or system administrator.',
        icon: Icons.block,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _inlineError = 'Login failed: $e';
      });
    }
  }

  void _showDialog({
    required String title,
    required String message,
    IconData? icon,
  }) {
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: const Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(title)),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Inter'),
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDAE8F5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3EB6FF), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Subtle gradient background to match your brand sky blue
    return Scaffold(
      backgroundColor: const Color(0xFFF2FBFF),
      body: Stack(
        children: [
          // Top accent curve
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE6F6FF), Color(0xFFF2FBFF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo + tagline
                    Column(
                      children: [
                        Image.asset('assets/logo.png', height: 92),
                        const SizedBox(height: 10),
                        const Text(
                          'Plan your path. Achieve your goals.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            color: Color(0xFF3B5568),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Inline error banner
                    if (_inlineError != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8E8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _inlineError!,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: Color(0xFF7F1D1D),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Glassy card
                    Card(
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Login',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 22),

                              // Email
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration(
                                  label: 'Email',
                                  icon: Icons.email_outlined,
                                ),
                                validator: (v) {
                                  final s = v?.trim() ?? '';
                                  if (s.isEmpty) return 'Email is required.';
                                  final ok = RegExp(
                                    r'^[^@]+@[^@]+\.[^@]+$',
                                  ).hasMatch(s);
                                  if (!ok) return 'Enter a valid email.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_passwordVisible,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted:
                                    (_) => _login(), // Enter submits
                                decoration: _decoration(
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  suffix: IconButton(
                                    tooltip:
                                        _passwordVisible
                                            ? 'Hide password'
                                            : 'Show password',
                                    icon: Icon(
                                      _passwordVisible
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed:
                                        () => setState(
                                          () =>
                                              _passwordVisible =
                                                  !_passwordVisible,
                                        ),
                                  ),
                                ),
                                validator: (v) {
                                  final s = v ?? '';
                                  if (s.isEmpty) return 'Password is required.';
                                  if (s.length < 6)
                                    return 'At least 6 characters.';
                                  return null;
                                },
                              ),

                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed:
                                      _isLoading
                                          ? null
                                          : () {
                                            // Hook up a reset flow later if desired
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Password reset is not yet configured.',
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                  icon: const Icon(
                                    Icons.help_outline,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Forgot password?',
                                    style: TextStyle(fontFamily: 'Inter'),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF3EB6FF),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Login button
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3EB6FF),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      _isLoading
                                          ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.8,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text(
                                            'Login',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Divider
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFE6EEF7),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'or',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFF6B7A8C),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFE6EEF7),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Signup link
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Don't have an account?",
                                    style: TextStyle(fontFamily: 'Inter'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _isLoading
                                            ? null
                                            : () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) =>
                                                          const SignupScreen(),
                                                ),
                                              );
                                            },
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF3EB6FF),
                                    ),
                                    child: const Text(
                                      'Sign up',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading overlay (prevents double taps)
          if (_isLoading)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Container(color: Colors.black.withOpacity(0.04)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
