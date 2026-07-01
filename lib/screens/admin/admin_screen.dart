import 'package:flutter/material.dart';
import '../../config/theme.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: Text('Admin', style: AppTextStyles.headline2)),
    );
  }
}