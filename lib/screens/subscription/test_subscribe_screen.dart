import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../../../config/theme.dart';

class TestSubscribeScreen extends StatefulWidget {
  const TestSubscribeScreen({super.key});

  @override
  State<TestSubscribeScreen> createState() => _TestSubscribeScreenState();
}

class _TestSubscribeScreenState extends State<TestSubscribeScreen> {
  bool _isLoading = false;

  Future<void> _subscribe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/initializePayment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'email': user.email,
          'amount': 3500,
          'currency': 'NGN',
          'months': 1,
          'userId': user.uid,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final authUrl = data['authorization_url'] as String;
        final reference = data['reference'] as String;

        if (mounted) {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _PaystackWebView(
                url: authUrl,
                reference: reference,
              ),
            ),
          );
          if (result == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Subscription activated!'),
                backgroundColor: AppColors.success,
              ),
            );
            context.pop();
          }
        }
      } else {
        final body = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(body['error'] ?? 'Payment initialization failed.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Subscribe (Test)', style: AppTextStyles.headline3)),
      body: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified, size: 56.sp, color: Color(0xFF2196F3)),
            SizedBox(height: 16.h),
            Text('GigsCourt Premium', style: AppTextStyles.headline1),
            SizedBox(height: 8.h),
            Text('1 Month Subscription', style: AppTextStyles.bodyLarge),
            SizedBox(height: 4.h),
            Text('₦3,500', style: AppTextStyles.headline1.copyWith(
              color: AppColors.primary,
              fontSize: 40.sp,
            )),
            SizedBox(height: 24.h),
            ...['Unlimited client leads', 'Verified badge', 'Priority ranking', 'Featured section', 'Online status visible'].map((b) => Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 18.sp),
                  SizedBox(width: 8.w),
                  Text(b, style: AppTextStyles.bodySmall),
                ],
              ),
            )),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              height: 52.h,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _subscribe,
                child: _isLoading
                    ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                    : Text('Pay ₦3,500', style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;
  const _PaystackWebView({required this.url, required this.reference});

  @override
  State<_PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<_PaystackWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (url) {
          setState(() => _isLoading = false);
          if (url.contains('paystack.com') && url.contains('success')) {
            _verifyAndClose();
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _verifyAndClose() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/verifyPayment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'reference': widget.reference}),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Payment', style: AppTextStyles.headline3)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}