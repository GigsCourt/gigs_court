import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;
  bool _isNigeria = false;

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _isNigeria = locale.countryCode == 'NG';
  }

  String get _currency => _isNigeria ? 'NGN' : 'USD';
  String get _currencySymbol => _isNigeria ? '₦' : '\$';

  List<Map<String, dynamic>> get _tiers => [
    {'months': 1, 'price': _isNigeria ? 3500 : 10, 'label': '1 Month'},
    {'months': 6, 'price': _isNigeria ? 20000 : 50, 'label': '6 Months', 'savings': _isNigeria ? 'Save ₦1,000' : 'Save \$10'},
    {'months': 12, 'price': _isNigeria ? 35700 : 102, 'label': '12 Months', 'savings': '15% off'},
  ];

  int _selectedTier = 0;

  Future<void> _subscribe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final idToken = await user.getIdToken();
      final tier = _tiers[_selectedTier];

      final response = await http.post(
        Uri.parse('https://us-central1-gigs-court.cloudfunctions.net/initializePayment'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
        body: jsonEncode({
          'email': user.email,
          'amount': tier['price'],
          'currency': _currency,
          'months': tier['months'],
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
              builder: (_) => _PaystackWebView(url: authUrl, reference: reference),
            ),
          );
          if (result == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subscription activated!'), backgroundColor: AppColors.success));
            context.pop();
          }
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment initialization failed.'), backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('GigsCourt Premium', style: AppTextStyles.headline3)),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(children: [
            Icon(Icons.verified, size: 56.sp, color: Color(0xFF2196F3)),
            SizedBox(height: 12.h),
            Text('Unlock Premium', style: AppTextStyles.headline1),
            SizedBox(height: 8.h),
            Text('Get unlimited visibility and more clients', textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
            SizedBox(height: 24.h),

            // Tier cards
            ...List.generate(_tiers.length, (i) {
              final tier = _tiers[i];
              final isSelected = _selectedTier == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedTier = i),
                child: Container(
                  margin: EdgeInsets.only(bottom: 12.h),
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.04) : AppColors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.15), width: isSelected ? 2 : 1),
                  ),
                  child: Row(children: [
                    Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 22.sp, color: isSelected ? AppColors.primary : AppColors.grey),
                    SizedBox(width: 12.w),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tier['label'], style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                      if (tier['savings'] != null) Text(tier['savings'], style: AppTextStyles.caption.copyWith(color: AppColors.success)),
                    ])),
                    Text('$_currencySymbol${tier['price']}', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            }),

            SizedBox(height: 16.h),

            // Benefits
            ...['Unlimited client leads', 'Verified badge on your profile', 'Priority ranking in search', 'Appear in Featured section', 'Online status visible to clients'].map((b) => Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Row(children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 18.sp),
                SizedBox(width: 8.w),
                Text(b, style: AppTextStyles.bodySmall),
              ]),
            )),

            if (!_isNigeria)
              Padding(
                padding: EdgeInsets.only(top: 12.h),
                child: Row(children: [
                  Icon(Icons.credit_card, size: 18.sp, color: AppColors.primary.withValues(alpha: 0.6)),
                  SizedBox(width: 8.w),
                  Text('Pay securely with your card', style: AppTextStyles.caption.copyWith(color: AppColors.primary.withValues(alpha: 0.6))),
                ]),
              ),

            const Spacer(),

            SizedBox(width: double.infinity, height: 52.h,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _subscribe,
                child: _isLoading
                    ? SizedBox(height: 22.h, width: 22.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                    : Text('Subscribe Now', style: AppTextStyles.button),
              ),
            ),
            SizedBox(height: 12.h),
            Text('One-time payment. Does not auto-renew.', style: AppTextStyles.caption),
            SizedBox(height: 16.h),
          ]),
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
          if (url.contains('paystack.com') && url.contains('success')) _verifyAndClose();
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
        Uri.parse('https://us-central1-gigs-court.cloudfunctions.net/verifyPayment'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
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
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}