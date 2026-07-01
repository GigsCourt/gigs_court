import 'package:flutter/material.dart';
import '../../config/theme.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: Text('Chat', style: AppTextStyles.headline2)),
    );
  }
}