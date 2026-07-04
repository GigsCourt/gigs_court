import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _subjectController.text.trim().isNotEmpty &&
      _messageController.text.trim().isNotEmpty &&
      !_isSubmitting;

  Future<void> _submitTicket() async {
    if (!_canSubmit) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance.collection('tickets').add({
        'type': 'support',
        'submittedBy': user.uid,
        'submitterEmail': user.email ?? '',
        'submitterName': user.displayName ?? '',
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
        'status': 'open',
        'adminResponse': null,
        'createdAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });
      if (mounted) context.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit ticket. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('Help & Support', style: AppTextStyles.headline3)),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Have an issue or question? Let us know and we\'ll get back to you.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6)),
              ),
              SizedBox(height: 24.h),
              Text('Subject', style: AppTextStyles.label),
              SizedBox(height: 8.h),
              TextField(
                controller: _subjectController,
                style: AppTextStyles.bodyMedium,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Brief description of your issue',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
              ),
              SizedBox(height: 16.h),
              Text('Message', style: AppTextStyles.label),
              SizedBox(height: 8.h),
              TextField(
                controller: _messageController,
                style: AppTextStyles.bodyMedium,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Describe your issue in detail...',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                height: 48.h,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submitTicket : null,
                  child: _isSubmitting
                      ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                      : Text('Submit Ticket', style: AppTextStyles.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}