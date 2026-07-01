import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/verify_email/verify_email_screen.dart';
import '../screens/setup/profile_photo_screen.dart';
import '../screens/setup/location_screen.dart';
import '../screens/setup/services_screen.dart';
import '../screens/shell/main_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) {
        final email = state.extra as String;
        return VerifyEmailScreen(email: email);
      },
    ),
    GoRoute(
      path: '/setup/photo',
      builder: (context, state) => const ProfilePhotoScreen(),
    ),
    GoRoute(
      path: '/setup/location',
      builder: (context, state) => const LocationScreen(),
    ),
    GoRoute(
      path: '/setup/services',
      builder: (context, state) => const ServicesScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const MainShell(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const _PlaceholderScreen(title: 'Notifications'),
    ),
    GoRoute(
      path: '/provider/:id',
      builder: (context, state) => const _PlaceholderScreen(title: 'Provider Profile'),
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title - Coming Soon')),
    );
  }
}