import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;

  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService();

  bool _isResending = false;
  bool _isChecking = false;
  String? _errorMessage;

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleResendEmail() async {
    _clearError();
    setState(() => _isResending = true);

    final result = await _authService.resendVerificationEmail();

    if (!mounted) return;

    setState(() => _isResending = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email resent. Please check your inbox.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() {
        _errorMessage = result.error;
      });
    }
  }

  Future<void> _handleCheckVerified() async {
    _clearError();
    setState(() => _isChecking = true);

    bool verified = false;
    for (int i = 0; i < 3; i++) {
      final result = await _authService.checkEmailVerified();
      if (result.success) {
        verified = true;
        break;
      }
      if (i < 2) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (!mounted) return;

    setState(() => _isChecking = false);

    if (verified) {
      Navigator.pushReplacementNamed(context, AppRoutes.profilePhoto);
    } else {
      setState(() {
        _errorMessage = 'Email not verified yet. Please check your inbox.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            children: [
              SizedBox(height: 32.h),

              // Email icon
              Container(
                height: 80.h,
                width: 80.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.email_outlined,
                  size: 36.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 24.h),

              // Headline
              Text(
                'Verify Your Email',
                textAlign: TextAlign.center,
                style: AppTextStyles.headline2,
              ),
              SizedBox(height: 12.h),

              // Body
              Text(
                'We sent a verification link to',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Please check your inbox and tap the link to verify.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 40.h),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.error, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
              ],

              // I've Verified button
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _handleCheckVerified,
                  child: _isChecking
                      ? SizedBox(
                          height: 22.h,
                          width: 22.w,
                          child: const CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text("I've Verified, Continue", style: AppTextStyles.button),
                ),
              ),
              SizedBox(height: 12.h),

              // Resend email
              TextButton(
                onPressed: _isResending ? null : _handleResendEmail,
                child: _isResending
                    ? SizedBox(
                        height: 18.h,
                        width: 18.w,
                        child: const CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Resend Email',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const Spacer(),

              // Wrong email hint
              Padding(
                padding: EdgeInsets.only(bottom: 40.h),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Wrong email? Go back and update it.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}