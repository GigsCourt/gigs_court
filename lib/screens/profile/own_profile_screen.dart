import 'package:flutter/material.dart';
import '../../config/theme.dart';

class OwnProfileScreen extends StatelessWidget {
  const OwnProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: Text('Profile', style: AppTextStyles.headline2)),
    );
  }
}