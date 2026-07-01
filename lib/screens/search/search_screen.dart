import 'package:flutter/material.dart';
import '../../config/theme.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: Text('Search', style: AppTextStyles.headline2)),
    );
  }
}