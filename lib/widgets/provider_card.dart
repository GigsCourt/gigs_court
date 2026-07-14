import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';

class ProviderCardData {
  final String id;
  final String name;
  final String profileImage;
  final String? latestWorkPhoto;
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
    this.latestWorkPhoto,
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

  bool get showOnlineStatus => isEarlyAccess || isSubscribed;
  bool get showVerifiedBadge => isEarlyAccess || isSubscribed;
  bool get isAcceptingClients => isEarlyAccess || isSubscribed || isFree;

  ProviderCardData copyWith({
    String? id,
    String? name,
    String? profileImage,
    String? latestWorkPhoto,
    List<String>? services,
    double? rating,
    int? reviewCount,
    double? distanceKm,
    bool? isSubscribed,
    bool? isFree,
    bool? isOnline,
    String? lastSeen,
    bool? isEarlyAccess,
    bool? isOwnProfile,
  }) {
    return ProviderCardData(
      id: id ?? this.id,
      name: name ?? this.name,
      profileImage: profileImage ?? this.profileImage,
      latestWorkPhoto: latestWorkPhoto ?? this.latestWorkPhoto,
      services: services ?? this.services,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      distanceKm: distanceKm ?? this.distanceKm,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isFree: isFree ?? this.isFree,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isEarlyAccess: isEarlyAccess ?? this.isEarlyAccess,
      isOwnProfile: isOwnProfile ?? this.isOwnProfile,
    );
  }
}

class ProviderCard extends StatelessWidget {
  final ProviderCardData provider;
  final bool isHorizontal;
  final VoidCallback? onTap;
  static const Color _verifiedBlue = Color(0xFF2196F3);

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
        onTap?.call();
        if (!provider.isEarlyAccess && !provider.isSubscribed && !provider.isOwnProfile) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(provider.id)
              .collection('notifications')
              .add({
            'type': 'missed_connection',
            'title': 'Profile Viewed',
            'body': provider.isAcceptingClients
                ? 'A potential client viewed your profile but your chat, directions, and work photos are hidden until you subscribe.'
                : 'A client tried to book you but your profile is listed as Fully Booked. Subscribe to start accepting clients again.',
            'read': false,
            'data': {'providerId': provider.id},
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      },
      child: isHorizontal ? _buildHorizontalCard() : _buildPortraitCard(context),
    );
  }

  Widget _buildPhotoSection({double? height}) {
    final hasWorkPhoto = provider.latestWorkPhoto != null && provider.latestWorkPhoto!.isNotEmpty;
    final showWorkPhotos = provider.isEarlyAccess || provider.isSubscribed;
    return ClipRRect(
      borderRadius: isHorizontal
          ? BorderRadius.horizontal(left: Radius.circular(16.r))
          : BorderRadius.vertical(top: Radius.circular(16.r)),
      child: Container(
        height: height,
        width: isHorizontal ? 110.w : double.infinity,
        color: AppColors.primary.withValues(alpha: 0.06),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasWorkPhoto && showWorkPhotos)
              Image.network(provider.latestWorkPhoto!, fit: BoxFit.cover)
            else if (provider.profileImage.isNotEmpty)
              Image.network(provider.profileImage, fit: BoxFit.cover)
            else
              Icon(Icons.person, size: 36.sp, color: AppColors.primary.withValues(alpha: 0.3)),
            if (hasWorkPhoto && showWorkPhotos)
              Positioned(
                top: 8.h,
                left: 8.w,
                child: Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4.r)],
                    image: provider.profileImage.isNotEmpty
                        ? DecorationImage(image: NetworkImage(provider.profileImage), fit: BoxFit.cover)
                        : null,
                  ),
                  child: provider.profileImage.isEmpty
                      ? Icon(Icons.person, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.5))
                      : null,
                ),
              ),
          ],
        ),
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
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 12.r, offset: Offset(0, 4.h))],
      ),
      child: Row(
        children: [
          _buildPhotoSection(height: double.infinity),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Flexible(child: Text(provider.name, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    if (provider.showVerifiedBadge) ...[SizedBox(width: 4.w), Icon(Icons.verified, size: 16.sp, color: _verifiedBlue)],
                    if (provider.isOwnProfile) ...[SizedBox(width: 4.w), Text('(You)', style: AppTextStyles.caption)],
                  ]),
                  SizedBox(height: 4.h),
                  _buildStatusChip(),
                  SizedBox(height: 4.h),
                  if (provider.showOnlineStatus)
                    Row(children: [
                      Container(width: 7.w, height: 7.h, decoration: BoxDecoration(color: provider.isOnline ? AppColors.success : AppColors.grey, shape: BoxShape.circle)),
                      SizedBox(width: 4.w),
                      Text(provider.isOnline ? 'Online now' : 'Last seen ${provider.lastSeen ?? "recently"}', style: AppTextStyles.caption.copyWith(color: provider.isOnline ? AppColors.success : AppColors.grey)),
                    ]),
                  SizedBox(height: 4.h),
                  Text(provider.services.take(2).join(', '), style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  SizedBox(height: 4.h),
                  Row(children: [Icon(Icons.star, size: 14.sp, color: Colors.amber), SizedBox(width: 2.w), Text('${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})', style: AppTextStyles.caption)]),
                  SizedBox(height: 4.h),
                  Row(children: [Icon(Icons.location_on_outlined, size: 14.sp, color: AppColors.primary.withValues(alpha: 0.5)), SizedBox(width: 2.w), Text('${provider.distanceKm.toStringAsFixed(1)} km away', style: AppTextStyles.caption)]),
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
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 12.r, offset: Offset(0, 4.h))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPhotoSection(height: 120.h),
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(provider.name, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, fontSize: nameSize.sp), overflow: TextOverflow.ellipsis)),
                  if (provider.showVerifiedBadge) ...[SizedBox(width: 4.w), Icon(Icons.verified, size: 14.sp, color: _verifiedBlue)],
                  if (provider.isOwnProfile) ...[SizedBox(width: 2.w), Text('(You)', style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp))],
                ]),
                SizedBox(height: 3.h),
                _buildStatusChip(),
                SizedBox(height: 3.h),
                if (provider.showOnlineStatus)
                  Row(children: [
                    Container(width: 6.w, height: 6.h, decoration: BoxDecoration(color: provider.isOnline ? AppColors.success : AppColors.grey, shape: BoxShape.circle)),
                    SizedBox(width: 3.w),
                    Text(provider.isOnline ? 'Online' : provider.lastSeen ?? '', style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp, color: provider.isOnline ? AppColors.success : AppColors.grey)),
                  ]),
                SizedBox(height: 3.h),
                Text(provider.services.take(2).join(', '), style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp), maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: 3.h),
                Row(children: [Icon(Icons.star, size: 12.sp, color: Colors.amber), SizedBox(width: 2.w), Text('${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})', style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp))]),
                SizedBox(height: 3.h),
                Row(children: [Icon(Icons.location_on_outlined, size: 12.sp, color: AppColors.primary.withValues(alpha: 0.5)), SizedBox(width: 2.w), Text('${provider.distanceKm.toStringAsFixed(1)} km', style: AppTextStyles.caption.copyWith(fontSize: detailSize.sp))]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    if (provider.isOwnProfile) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: provider.isAcceptingClients
            ? AppColors.success.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        provider.isAcceptingClients ? 'Accepting clients' : 'Fully booked',
        style: AppTextStyles.caption.copyWith(
          fontSize: 9.sp,
          color: provider.isAcceptingClients ? AppColors.success : Colors.orange,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}