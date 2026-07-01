import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme.dart';

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(borderRadius.r),
      ),
    );
  }
}

class ProviderCardSkeleton extends StatelessWidget {
  final bool isHorizontal;

  const ProviderCardSkeleton({super.key, this.isHorizontal = false});

  @override
  Widget build(BuildContext context) {
    if (isHorizontal) {
      return Container(
        width: 280.w,
        margin: EdgeInsets.only(right: 12.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          children: [
            Container(
              width: 110.w,
              height: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(16.r)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SkeletonLoader(width: 100.w, height: 14.h),
                    SizedBox(height: 8.h),
                    SkeletonLoader(width: 80.w, height: 10.h),
                    SizedBox(height: 8.h),
                    SkeletonLoader(width: 120.w, height: 10.h),
                    SizedBox(height: 8.h),
                    SkeletonLoader(width: 60.w, height: 10.h),
                    SizedBox(height: 8.h),
                    SkeletonLoader(width: 70.w, height: 10.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120.h,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 80.w, height: 12.h),
                SizedBox(height: 6.h),
                SkeletonLoader(width: 60.w, height: 10.h),
                SizedBox(height: 6.h),
                SkeletonLoader(width: 100.w, height: 10.h),
                SizedBox(height: 6.h),
                SkeletonLoader(width: 50.w, height: 10.h),
                SizedBox(height: 6.h),
                SkeletonLoader(width: 70.w, height: 10.h),
              ],
            ),
          ),
        ],
      ),
    );
  }
}