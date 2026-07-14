import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart' as app_auth;  

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String value) {
    // Remove non-digits
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return digits.substring(0, 11);
    return digits;
  }

  bool get _isValid => _phoneController.text.replaceAll(RegExp(r'\D'), '').length == 11;

  Future<void> _handleSave() async {
    if (!_isValid) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'phoneNumber': _phoneController.text.replaceAll(RegExp(r'\D'), ''),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isSaving = false);
    context.read<app_auth.AuthProvider>().setSetupComplete();
    context.go('/home');
  }

  void _handleSkip() {
    context.read<app_auth.AuthProvider>().setSetupComplete();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 20.h),
                Text(
                  "What's your phone number?",
                  style: AppTextStyles.headline2,
                ),
                SizedBox(height: 8.h),
                Text(
                  'Clients will be able to contact you directly. You can skip this and add it later.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary.withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: 32.h),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        '+234',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: AppTextStyles.bodyMedium,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '801 234 5678',
                          hintStyle: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_phoneController.text.isNotEmpty && !_isValid)
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Text(
                      'Please enter a valid 11-digit phone number.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                SizedBox(height: 32.h),
                SizedBox(
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: (_isValid && !_isSaving) ? _handleSave : null,
                    child: _isSaving
                        ? SizedBox(
                            height: 20.h,
                            width: 20.w,
                            child: const CircularProgressIndicator(
                              color: AppColors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text('Save & Continue', style: AppTextStyles.button),
                  ),
                ),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: _handleSkip,
                  child: Text(
                    'Skip for now',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'You can add or change your phone number later in your profile settings.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}