import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Added: For loading the .env file securely
import 'dart:io'; // Added: For debugging the current directory

import 'routes/route_tracker.dart';
import 'screens/welcome_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_builder_screen.dart';
import 'screens/video_study_guides_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (client-side uses the anon key only)
  await Supabase.initialize(
    url: 'https://aybgkbtwkavtluzemlst.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF5YmdrYnR3a2F2dGx1emVtbHN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ5MDk0MjUsImV4cCI6MjA3MDQ4NTQyNX0.E1u5XzF173BQmPZ6U4aNdWz2Rk04TPA6X25Ffu9w8MM',
  );

  print(
    'Current directory: ${Directory.current.path}',
  ); // Added: Debug to see where Flutter is looking for .env
  // await dotenv.load(
  //   fileName: 'lib/.env',
  // ); // Changed: Load from lib/ folder (move .env there if needed)

  runApp(const CareerRoadmapApp());
}

class CareerRoadmapApp extends StatelessWidget {
  const CareerRoadmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      navigatorObservers: [RouteTracker.instance], // back-stack tracking
      routes: {
        '/': (context) => const WelcomeScreen(),
        '/signup': (context) => const SignupScreen(),
        '/login': (context) => const LoginScreen(),
        '/profileBuilder': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>?;
          final userId = args?['userId'] ?? '';
          return ProfileBuilderScreen(userId: userId);
        },
        '/video-study': (context) => const VideoStudyGuidesScreen(),
      },
    );
  }
}
