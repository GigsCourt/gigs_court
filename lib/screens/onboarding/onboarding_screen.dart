import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      illustration: const _SearchIllustration(),
      headline: 'Find Trusted Service\nProviders',
      body:
          'Browse over 100 verified services near you.\nFrom barbers to web developers, find\nexactly who you need.',
    ),
    _OnboardingPage(
      illustration: const _ChatIllustration(),
      headline: 'Chat & Connect',
      body:
          'Message providers directly. Share images,\nsend voice notes, and build trust\nbefore you hire.',
    ),
    _OnboardingPage(
      illustration: const _CommunityIllustration(),
      headline: 'Your Service,\nYour Court',
      body:
          'One account does it all. Hire providers\nor offer your own services to clients\nnear you.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNextPressed() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: () {
                      context.go('/auth');
                    },
                    child: Text(
                      'Skip',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),

                // PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return _pages[index];
                    },
                  ),
                ),

                // Page indicator
                Padding(
                  padding: EdgeInsets.only(bottom: 24.h),
                  child: SmoothPageIndicator(
                    controller: _pageController,
                    count: _pages.length,
                    effect: WormEffect(
                      dotHeight: 8.h,
                      dotWidth: 8.w,
                      activeDotColor: AppColors.primary,
                      dotColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                ),

                // Next / Get Started button
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 40.h),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56.h,
                    child: ElevatedButton(
                      onPressed: _onNextPressed,
                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- Onboarding Page Model ----

class _OnboardingPage extends StatelessWidget {
  final Widget illustration;
  final String headline;
  final String body;

  const _OnboardingPage({
    required this.illustration,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          illustration,
          SizedBox(height: 56.h),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: AppTextStyles.headline1.copyWith(
              fontSize: 26.sp,
              height: 1.3,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primary.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Color helpers ----
Color _darkColor(double alpha) =>
    AppColors.primary.withValues(alpha: alpha);

// ---- Illustration 1: Search / Find ----

class _SearchIllustration extends StatelessWidget {
  const _SearchIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220.h,
      width: 220.w,
      decoration: BoxDecoration(
        color: _darkColor(0.04),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 42.sp,
            color: _darkColor(0.15),
          ),
          Positioned(
            top: 65.h,
            right: 55.w,
            child: Container(
              height: 70.h,
              width: 70.w,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Icon(
                Icons.search,
                size: 36.sp,
                color: AppColors.white,
              ),
            ),
          ),
          Positioned(
            bottom: 55.h,
            left: 50.w,
            child: Container(
              height: 50.h,
              width: 50.w,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14.r),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.1),
                    blurRadius: 12.r,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.person_outline,
                size: 24.sp,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Illustration 2: Chat ----

class _ChatIllustration extends StatelessWidget {
  const _ChatIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220.h,
      width: 220.w,
      decoration: BoxDecoration(
        color: _darkColor(0.04),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background chat bubble
          Positioned(
            top: 50.h,
            left: 40.w,
            child: Container(
              height: 60.h,
              width: 100.w,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                  bottomRight: Radius.circular(20.r),
                  bottomLeft: Radius.circular(4.r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.06),
                    blurRadius: 10.r,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 28.sp,
                  color: _darkColor(0.3),
                ),
              ),
            ),
          ),
          // Voice note bubble
          Positioned(
            top: 90.h,
            right: 35.w,
            child: Container(
              height: 44.h,
              width: 90.w,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                  bottomLeft: Radius.circular(20.r),
                  bottomRight: Radius.circular(4.r),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mic,
                    size: 18.sp,
                    color: AppColors.white.withValues(alpha: 0.7),
                  ),
                  SizedBox(width: 8.w),
                  Container(
                    height: 4.h,
                    width: 30.w,
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Main chat icon
          Positioned(
            bottom: 50.h,
            child: Container(
              height: 64.h,
              width: 64.w,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(22.r),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.25),
                    blurRadius: 16.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 30.sp,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Illustration 3: Community / Connection ----

class _CommunityIllustration extends StatelessWidget {
  const _CommunityIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220.h,
      width: 220.w,
      decoration: BoxDecoration(
        color: _darkColor(0.04),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Person 1 (left)
          Positioned(
            left: 30.w,
            top: 60.h,
            child: Container(
              height: 80.h,
              width: 80.w,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(24.r),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.08),
                    blurRadius: 12.r,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.person_outline,
                size: 38.sp,
                color: AppColors.primary,
              ),
            ),
          ),
          // Person 2 (right)
          Positioned(
            right: 30.w,
            top: 90.h,
            child: Container(
              height: 70.h,
              width: 70.w,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.08),
                    blurRadius: 12.r,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.person_outline,
                size: 32.sp,
                color: AppColors.primary,
              ),
            ),
          ),
          // Center connection icon
          Positioned(
            bottom: 40.h,
            child: Container(
              height: 64.h,
              width: 64.w,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(22.r),
                boxShadow: [
                  BoxShadow(
                    color: _darkColor(0.25),
                    blurRadius: 16.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.handshake_outlined,
                size: 30.sp,
                color: AppColors.white,
              ),
            ),
          ),
          // Connecting line between people
          Positioned(
            top: 95.h,
            left: 70.w,
            child: Container(
              height: 2.h,
              width: 80.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _darkColor(0.0),
                    _darkColor(0.15),
                    _darkColor(0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}