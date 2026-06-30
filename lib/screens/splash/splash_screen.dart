import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();

    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final status = authProvider.status;

    switch (status) {
      case AuthStatus.unauthenticated:
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
        break;
      case AuthStatus.emailNotVerified:
        final email = authProvider.user?.email ?? '';
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.verifyEmail,
          arguments: email,
        );
        break;
      case AuthStatus.setupIncomplete:
        Navigator.pushReplacementNamed(context, AppRoutes.profilePhoto);
        break;
      case AuthStatus.authenticated:
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        break;
      default:
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'GigsCourt',
                style: AppTextStyles.headline1.copyWith(
                  fontSize: 36.sp,
                  color: AppColors.white,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Your service, Your court',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w300,
                  color: AppColors.white.withValues(alpha: 0.7),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}