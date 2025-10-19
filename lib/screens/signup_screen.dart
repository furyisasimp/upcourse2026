import 'package:flutter/material.dart';
import 'package:career_roadmap/services/supabase_service.dart';
import 'profile_builder_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  SignupScreenState createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  String? _inlineError;

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null) return;

    setState(() => _inlineError = null);

    if (!form.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      // Use service wrapper (creates users row with sane defaults)
      final response = await SupabaseService.registerUser(email, password);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.user != null) {
        final userId = response.user!.id;

        // Safety: ensure profile row exists (registerUser already upserts; this is harmless)
        await SupabaseService.upsertMyProfile({
          'supabase_id': userId,
          'email': email,
          'first_name': 'Guest',
          'last_name': '',
          'grade_level': null,
          'school': null,
          'profile_picture': null,
        });

        _showDialog(
          title: 'Registration Successful',
          message:
              'Welcome to UpCourse! We created your account. You can now complete your profile.',
          icon: Icons.check_circle_outline,
        );

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileBuilderScreen(userId: userId),
          ),
        );
      } else {
        setState(() => _inlineError = 'Signup failed. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _inlineError = 'Failed to register: $e';
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
                  Icon(icon, color: const Color(0xFF16A34A)),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF2FBFF),
      body: Stack(
        children: [
          // Brand gradient like LoginScreen
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
                    // Logo + subtitle
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

                    // Inline error banner (consistent with Login)
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Create Account',
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
                                textInputAction: TextInputAction.next,
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
                              const SizedBox(height: 14),

                              // Confirm Password
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: !_confirmPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted:
                                    (_) => _register(), // Enter submits
                                decoration: _decoration(
                                  label: 'Confirm Password',
                                  icon: Icons.lock_outline,
                                  suffix: IconButton(
                                    tooltip:
                                        _confirmPasswordVisible
                                            ? 'Hide password'
                                            : 'Show password',
                                    icon: Icon(
                                      _confirmPasswordVisible
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed:
                                        () => setState(
                                          () =>
                                              _confirmPasswordVisible =
                                                  !_confirmPasswordVisible,
                                        ),
                                  ),
                                ),
                                validator: (v) {
                                  final s = v ?? '';
                                  if (s.isEmpty)
                                    return 'Please confirm your password.';
                                  if (s != _passwordController.text) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 18),

                              // Sign Up button
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _register,
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
                                            'Sign Up',
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

                              // Login link (consistent styling)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Already have an account?',
                                    style: TextStyle(fontFamily: 'Inter'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _isLoading
                                            ? null
                                            : () {
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) =>
                                                          const LoginScreen(),
                                                ),
                                              );
                                            },
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF3EB6FF),
                                    ),
                                    child: const Text(
                                      'Log in',
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

          // Light overlay while loading (prevents accidental double taps)
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
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
