import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme.dart';

class ProviderCardData {
  final String id;
  final String name;
  final String profileImage;
  final List<String> services;
  final double rating;
  final int reviewCount;
  final double distanceKm;
  final bool isSubscribed;
  final bool isFree;
  final bool isOnline;
  final String? lastSeen;
  final bool isEarlyAccess;
  final bool isOwnProfile;

  ProviderCardData({
    required this.id,
    required this.name,
    required this.profileImage,
    required this.services,
    required this.rating,
    required this.reviewCount,
    required this.distanceKm,
    required this.isSubscribed,
    required this.isFree,
    this.isOnline = false,
    this.lastSeen,
    this.isEarlyAccess = true,
    this.isOwnProfile = false,
  });

  bool get isLocked => !isEarlyAccess && !isFree && !isSubscribed;
  bool get isTappable => isEarlyAccess || isFree || isSubscribed || isOwnProfile;
  bool get showOnlineStatus => isEarlyAccess || isSubscribed;
  bool get showVerifiedBadge => isEarlyAccess || isSubscribed;
}

class ProviderCard extends StatelessWidget {
  final ProviderCardData provider;
  final bool isHorizontal;
  final VoidCallback? onTap;

  const ProviderCard({
    super.key,
    required this.provider,
    this.isHorizontal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (provider.isTappable) {
          onTap?.call();
        } else {
          _showLockedDialog(context);
        }
      },
      child: isHorizontal ? _buildHorizontalCard() : _buildPortraitCard(context),
    );
  }

  void _showLockedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Not Available', style: AppTextStyles.bodyLarge),
        content: Text(
          'This provider is currently not accepting new clients.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard() {
    return Container(
      width: 280.w,
      margin: EdgeInsets.only(right: 12.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Row(
        children: [
          // Photo (40%)
          ClipRRect(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(16.r)),
            child: Container(
              width: 110.w,
              height: double.infinity,
              color: AppColors.primary.withValues(alpha: 0.06),
              child: provider.profileImage.isNotEmpty
                  ? Image.network(provider.profileImage, fit: BoxFit.cover)
                  : Icon(Icons.person, size: 36.sp, color: AppColors.primary.withValues(alpha: 0.3)),
            ),
          ),
          // Details (60%)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Line 1: Name + Verified badge
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.name,
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (provider.showVerifiedBadge) ...[
                        SizedBox(width: 4.w),
                        Icon(Icons.verified, size: 16.sp, color: AppColors.success),
                      ],
                      if (provider.isOwnProfile) ...[
                        SizedBox(width: 4.w),
                        Text('(You)', style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                  SizedBox(height: 4.h),
                  // Line 2: Online status
                  if (provider.showOnlineStatus)
                    Row(
                      children: [
                        Container(
                          width: 7.w,
                          height: 7.h,
                          decoration: BoxDecoration(
                            color: provider.isOnline ? AppColors.success : AppColors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          provider.isOnline ? 'Online now' : 'Last seen ${provider.lastSeen ?? "recently"}',
                          style: AppTextStyles.caption.copyWith(
                            color: provider.isOnline ? AppColors.success : AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: 4.h),
                  // Line 3: Services
                  Text(
                    provider.services.take(2).join(', '),
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  // Line 4: Rating
                  Row(
                    children: [
                      Icon(Icons.star, size: 14.sp, color: Colors.amber),
                      SizedBox(width: 2.w),
                      Text(
                        '${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  // Line 5: Distance
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 14.sp, color: AppColors.primary.withValues(alpha: 0.5)),
                      SizedBox(width: 2.w),
                      Text(
                        '${provider.distanceKm.toStringAsFixed(1)} km away',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 380;
    final nameSize = isSmall ? 12.0 : 13.0;
    final detailSize = isSmall ? 10.0 : 11.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo with lock overlay
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                child: Container(
                  height: 120.h,
                  width: double.infinity,
                  color: AppColors.primary.withValues(alpha: 0.06),
                  child: provider.profileImage.isNotEmpty
                      ? Image.network(provider.profileImage, fit: BoxFit.cover)
                      : Icon(Icons.person, size: 36.sp, color: AppColors.primary.withValues(alpha: 0.3)),
                ),
              ),
              if (provider.isLocked)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: Center(
                      child: Icon(Icons.lock_outline, color: AppColors.white, size: 32.sp),
                    ),
                  ),
                ),
            ],
          ),
          // Details
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + Badge
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        provider.name,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: nameSize.sp,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (provider.showVerifiedBadge) ...[
                      SizedBox(width: 4.w),
                      Icon(Icons.verified, size: 14.sp, color: AppColors.success),
                    ],
                    if (provider.isOwnProfile) ...[
                      SizedBox(width: 2.w),
                      Text('(You)', style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp)),
                    ],
                  ],
                ),
                SizedBox(height: 3.h),
                // Online
                if (provider.showOnlineStatus)
                  Row(
                    children: [
                      Container(
                        width: 6.w,
                        height: 6.h,
                        decoration: BoxDecoration(
                          color: provider.isOnline ? AppColors.success : AppColors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 3.w),
                      Text(
                        provider.isOnline ? 'Online' : provider.lastSeen ?? '',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: detailSize.sp,
                          color: provider.isOnline ? AppColors.success : AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: 3.h),
                // Services
                Text(
                  provider.services.take(2).join(', '),
                  style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 3.h),
                // Rating
                Row(
                  children: [
                    Icon(Icons.star, size: 12.sp, color: Colors.amber),
                    SizedBox(width: 2.w),
                    Text(
                      '${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})',
                      style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp),
                    ),
                  ],
                ),
                SizedBox(height: 3.h),
                // Distance
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 12.sp, color: AppColors.primary.withValues(alpha: 0.5)),
                    SizedBox(width: 2.w),
                    Text(
                      '${provider.distanceKm.toStringAsFixed(1)} km',
                      style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}