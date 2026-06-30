import 'package:flutter/material.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/verify_email/verify_email_screen.dart';
import '../screens/setup/profile_photo_screen.dart';
import '../screens/setup/location_screen.dart';
import '../screens/setup/services_screen.dart';
import '../screens/home/home_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String verifyEmail = '/verify-email';
  static const String profilePhoto = '/setup/profile-photo';
  static const String location = '/setup/location';
  static const String services = '/setup/services';
  static const String home = '/home';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fadeRoute(settings.name!, const SplashScreen());
      case onboarding:
        return _fadeRoute(settings.name!, const OnboardingScreen());
      case auth:
        return _fadeRoute(settings.name!, const AuthScreen());
      case verifyEmail:
        final email = settings.arguments as String;
        return _fadeRoute(
          settings.name!,
          VerifyEmailScreen(email: email),
        );
      case profilePhoto:
        return _fadeRoute(settings.name!, const ProfilePhotoScreen());
      case location:
        return _fadeRoute(settings.name!, const LocationScreen());
      case services:
        return _fadeRoute(settings.name!, const ServicesScreen());
      case home:
        return _fadeRoute(settings.name!, const HomeScreen());
      default:
        return _fadeRoute(settings.name ?? '/', const _LoadingScreen());
    }
  }

  static PageRouteBuilder _fadeRoute(String routeName, Widget screen) {
    return PageRouteBuilder(
      settings: RouteSettings(name: routeName),
      pageBuilder: (context, animation, secondaryAnimation) => screen,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}