import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('GigsCourt', style: AppTextStyles.headline3),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, size: 22.sp),
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              await authProvider.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64.sp,
              color: AppColors.success,
            ),
            SizedBox(height: 16.h),
            Text(
              'You\'re all set!',
              style: AppTextStyles.headline2,
            ),
            SizedBox(height: 8.h),
            Text(
              'Welcome to GigsCourt',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}