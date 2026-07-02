import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
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
  bool _isEarlyAccess = false;
  bool _hasConnectionIssue = false;

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

    _loadConfigAndNavigate();
  }

  Future<void> _loadConfigAndNavigate() async {
    // Fetch early access config
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('global')
          .get();
      if (configDoc.exists) {
        _isEarlyAccess = configDoc.data()?['earlyAccessEnabled'] ?? true;
      }
    } catch (_) {
      _isEarlyAccess = true;
    }

    if (!mounted) return;

    // Store early access in provider
    final authProvider = context.read<AuthProvider>();
    authProvider.setEarlyAccess(_isEarlyAccess);

    // Wait for auth status to be known (max 8 seconds)
    final startTime = DateTime.now();

    while (authProvider.status == AuthStatus.unknown) {
      if (DateTime.now().difference(startTime).inSeconds > 8) {
        if (mounted) setState(() => _hasConnectionIssue = true);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;

    _navigate(authProvider);
  }

  void _navigate(AuthProvider authProvider) {
    final status = authProvider.status;

    switch (status) {
      case AuthStatus.unauthenticated:
        context.go('/onboarding');
        break;
      case AuthStatus.emailNotVerified:
        final email = authProvider.user?.email ?? '';
        context.go('/verify-email', extra: email);
        break;
      case AuthStatus.setupIncomplete:
        context.go('/setup/photo');
        break;
      case AuthStatus.authenticated:
        context.go('/home');
        break;
      default:
        context.go('/onboarding');
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
              if (_hasConnectionIssue) ...[
                SizedBox(height: 40.h),
                Text(
                  'Connection issue.\nPlease check your internet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white.withValues(alpha: 0.8),
                  ),
                ),
                SizedBox(height: 20.h),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasConnectionIssue = false;
                    });
                    _loadConfigAndNavigate();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomSheet: _isEarlyAccess
          ? Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12.h),
              color: AppColors.success.withValues(alpha: 0.9),
              child: Text(
                'Early Access — Free for everyone',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }
}