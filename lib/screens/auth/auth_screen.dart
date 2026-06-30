import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();

  bool _isSignIn = true;

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();
  final _forgotPasswordEmailController = TextEditingController();

  bool _isLoading = false;
  bool _obscureSignInPassword = true;
  bool _obscureSignUpPassword = true;
  bool _obscureSignUpConfirmPassword = true;
  bool _isForgotPassword = false;

  String? _errorMessage;

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    _forgotPasswordEmailController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  String? _validateEmail(String value) {
    if (value.trim().isEmpty) return 'Please enter your email address';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email address';
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) return 'Please enter your password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirmPassword(String value) {
    if (value.isEmpty) return 'Please confirm your password';
    if (value != _signUpPasswordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _handleSignIn() async {
    _clearError();

    final emailError = _validateEmail(_signInEmailController.text);
    final passwordError = _validatePassword(_signInPasswordController.text);

    if (emailError != null || passwordError != null) {
      setState(() => _errorMessage = emailError ?? passwordError);
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.signIn(
      _signInEmailController.text.trim(),
      _signInPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      final authProvider = context.read<AuthProvider>();
      await authProvider.refreshUser();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      final status = authProvider.status;
      if (status == AuthStatus.emailNotVerified) {
        context.go('/verify-email', extra: _signInEmailController.text.trim());
      } else {
        context.go('/setup/photo');
      }
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  Future<void> _handleSignUp() async {
    _clearError();

    if (_signUpNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }

    final emailError = _validateEmail(_signUpEmailController.text);
    final passwordError = _validatePassword(_signUpPasswordController.text);
    final confirmError = _validateConfirmPassword(_signUpConfirmPasswordController.text);

    if (emailError != null || passwordError != null || confirmError != null) {
      setState(() => _errorMessage = emailError ?? passwordError ?? confirmError);
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.signUp(
      _signUpEmailController.text.trim(),
      _signUpPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      context.go('/verify-email', extra: _signUpEmailController.text.trim());
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  Future<void> _handleForgotPassword() async {
    _clearError();

    final emailError = _validateEmail(_forgotPasswordEmailController.text);
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.forgotPassword(
      _forgotPasswordEmailController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() {
        _errorMessage = null;
        _isForgotPassword = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent. Please check your inbox.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  void _toggleAuthMode() {
    setState(() {
      _isSignIn = !_isSignIn;
      _errorMessage = null;
      _isForgotPassword = false;
    });
    _clearControllers();
  }

  void _clearControllers() {
    _signInEmailController.clear();
    _signInPasswordController.clear();
    _signUpNameController.clear();
    _signUpEmailController.clear();
    _signUpPasswordController.clear();
    _signUpConfirmPasswordController.clear();
    _forgotPasswordEmailController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: _isForgotPassword
                  ? _buildForgotPasswordForm()
                  : _isSignIn
                      ? _buildSignInForm()
                      : _buildSignUpForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 40.h),
        Text('Welcome back', textAlign: TextAlign.center, style: AppTextStyles.headline1),
        SizedBox(height: 8.h),
        Text('Sign in to continue', textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
        SizedBox(height: 40.h),

        if (_errorMessage != null) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(child: Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
            ]),
          ),
          SizedBox(height: 16.h),
        ],

        Text('Email', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signInEmailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Enter your email',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.email_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
        ),
        SizedBox(height: 16.h),

        Text('Password', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signInPasswordController,
          obscureText: _obscureSignInPassword,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.lock_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
            suffixIcon: IconButton(
              icon: Icon(_obscureSignInPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
              onPressed: () => setState(() => _obscureSignInPassword = !_obscureSignInPassword),
            ),
          ),
        ),
        SizedBox(height: 8.h),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() { _isForgotPassword = true; _errorMessage = null; }),
            child: Text('Forgot Password?', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7))),
          ),
        ),
        SizedBox(height: 16.h),

        SizedBox(
          height: 56.h,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSignIn,
            child: _isLoading
                ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                : Text('Sign In', style: AppTextStyles.button),
          ),
        ),
        SizedBox(height: 24.h),

        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text("Don't have an account? ", style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
          GestureDetector(onTap: _toggleAuthMode, child: Text('Sign Up', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
        ]),
        SizedBox(height: 40.h),
      ],
    );
  }

  Widget _buildSignUpForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 40.h),
        Text('Create Account', textAlign: TextAlign.center, style: AppTextStyles.headline1),
        SizedBox(height: 8.h),
        Text('Sign up to get started', textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
        SizedBox(height: 40.h),

        if (_errorMessage != null) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(child: Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
            ]),
          ),
          SizedBox(height: 16.h),
        ],

        Text('Full Name', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signUpNameController,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Enter your full name',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.person_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
        ),
        SizedBox(height: 16.h),

        Text('Email', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signUpEmailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Enter your email',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.email_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
        ),
        SizedBox(height: 16.h),

        Text('Password', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signUpPasswordController,
          obscureText: _obscureSignUpPassword,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Min. 8 characters',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.lock_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
            suffixIcon: IconButton(
              icon: Icon(_obscureSignUpPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
              onPressed: () => setState(() => _obscureSignUpPassword = !_obscureSignUpPassword),
            ),
          ),
        ),
        SizedBox(height: 16.h),

        Text('Confirm Password', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _signUpConfirmPasswordController,
          obscureText: _obscureSignUpConfirmPassword,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.lock_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
            suffixIcon: IconButton(
              icon: Icon(_obscureSignUpConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
              onPressed: () => setState(() => _obscureSignUpConfirmPassword = !_obscureSignUpConfirmPassword),
            ),
          ),
        ),
        SizedBox(height: 24.h),

        SizedBox(
          height: 56.h,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSignUp,
            child: _isLoading
                ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                : Text('Sign Up', style: AppTextStyles.button),
          ),
        ),
        SizedBox(height: 24.h),

        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Already have an account? ', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
          GestureDetector(onTap: _toggleAuthMode, child: Text('Sign In', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
        ]),
        SizedBox(height: 40.h),
      ],
    );
  }

  Widget _buildForgotPasswordForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 40.h),
        Text('Forgot Password', textAlign: TextAlign.center, style: AppTextStyles.headline1),
        SizedBox(height: 8.h),
        Text('Enter your email and we\'ll send you a reset link', textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
        SizedBox(height: 40.h),

        if (_errorMessage != null) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(child: Text(_errorMessage!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
            ]),
          ),
          SizedBox(height: 16.h),
        ],

        Text('Email', style: AppTextStyles.label),
        SizedBox(height: 8.h),
        TextField(
          controller: _forgotPasswordEmailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _clearError(),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Enter your email',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.email_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
        ),
        SizedBox(height: 24.h),

        SizedBox(
          height: 56.h,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleForgotPassword,
            child: _isLoading
                ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                : Text('Send Reset Link', style: AppTextStyles.button),
          ),
        ),
        SizedBox(height: 16.h),

        TextButton(
          onPressed: () => setState(() { _isForgotPassword = false; _errorMessage = null; }),
          child: Text('Back to Sign In', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
        ),
        SizedBox(height: 40.h),
      ],
    );
  }
}