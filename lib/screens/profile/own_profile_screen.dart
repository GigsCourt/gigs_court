import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/imagekit_service.dart';
import '../../providers/auth_provider.dart' as app_auth;

class OwnProfileScreen extends StatefulWidget {
  const OwnProfileScreen({super.key});
  @override
  State<OwnProfileScreen> createState() => _OwnProfileScreenState();
}

class _OwnProfileScreenState extends State<OwnProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _profileListener;

  @override
  void initState() {
    super.initState();
    _startProfileListener();
  }

  @override
  void dispose() {
    _profileListener?.cancel();
    super.dispose();
  }

  void _startProfileListener() {
    if (_currentUser == null) return;
    _profileListener?.cancel();
    _profileListener = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser.uid)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final userData = doc.data()!;
      final serviceIds = List<String>.from(userData['services'] ?? []);
      List<Map<String, dynamic>> services = [];
      if (serviceIds.isNotEmpty) {
        try {
          final namesData = await _supabase.rpc(
            'get_service_names',
            params: {'p_service_ids': serviceIds},
          );
          services = List<Map<String, dynamic>>.from(namesData);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _userData = userData;
          _services = services;
          _workPhotos = List<String>.from(userData['workPhotos'] ?? []);
          _isLoading = false;
        });
      }
      try {
        final locationData = await _supabase
            .from('provider_locations')
            .select('address')
            .eq('provider_id', _currentUser!.uid)
            .maybeSingle();
        if (locationData != null && mounted) {
          setState(() {
            _userData?['workspaceAddress'] = locationData['address'] ?? '';
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _addWorkPhotos() async {
    final remaining = 15 - _workPhotos.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum 15 photos reached.')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    final selected = picked.take(remaining).toList();
    final newPhotos = List<String>.from(_workPhotos);
    for (int i = 0; i < selected.length; i++) {
      final result = await ImageKitService.uploadImage(
        File(selected[i].path),
        'work_${DateTime.now().millisecondsSinceEpoch}_$i',
      );
      if (result['success'] == true) newPhotos.add(result['url'] as String);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'workPhotos': newPhotos});
    }
  }

  Future<void> _deleteWorkPhoto(int index) async {
    final newPhotos = List<String>.from(_workPhotos);
    newPhotos.removeAt(index);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'workPhotos': newPhotos});
    }
  }

  void _showPhotoOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.fullscreen, size: 20.sp),
              title: Text('View Full Screen', style: AppTextStyles.bodyMedium),
              onTap: () {
                Navigator.pop(ctx);
                _viewPhoto(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  size: 20.sp, color: AppColors.error),
              title: Text('Delete Photo',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteWorkPhoto(index);
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  void _viewPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          body: PageView.builder(
            controller: PageController(initialPage: index),
            itemCount: _workPhotos.length,
            itemBuilder: (_, i) => Center(
              child: Image.network(_workPhotos[i], fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  String _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Offline';
    final date = (lastSeen as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isEarlyAccess = context.watch<app_auth.AuthProvider>().isEarlyAccess;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    final name = _userData?['displayName'] ?? _userData?['name'] ?? 'Unknown';
    final photoUrl = _userData?['profileImage'] ?? _userData?['photoUrl'];
    final bio = _userData?['bio'] ?? '';
    final address = _userData?['workspaceAddress'] ?? '';
    final isSubscribed = _userData?['isSubscribed'] == true;
    final subscriptionExpiry = _userData?['subscriptionExpiry'] as Timestamp?;
    final showBadge = isEarlyAccess || isSubscribed;
    final isOnline = _userData?['isOnline'] ?? false;
    final lastSeen = _userData?['lastSeen'];
    final rating = (_userData?['rating'] ?? _userData?['averageRating'] ?? 0.0)
        .toDouble();
    final reviewCount = _userData?['reviewCount'] ?? 0;
    final savedCount = (_userData?['savedProviders'] as List?)?.length ?? 0;
    final leadCount = _userData?['leadCount'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Profile', style: AppTextStyles.headline3),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 22.sp),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(80.r),
                child: SizedBox(
                  width: 140.w,
                  height: 140.w,
                  child: photoUrl != null && photoUrl.toString().isNotEmpty
                      ? Image.network(photoUrl, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          child: Icon(Icons.person,
                              size: 60.sp,
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                ),
              ),
            ),
            SizedBox(height: 10.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: AppTextStyles.headline2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showBadge) ...[
                  SizedBox(width: 6.w),
                  Icon(Icons.verified, size: 20.sp, color: Color(0xFF2196F3)),
                ],
              ],
            ),
            SizedBox(height: 2.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.success : AppColors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 4.w),
                Text(
                  isOnline ? 'Online now' : _formatLastSeen(lastSeen),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isOnline ? AppColors.success : AppColors.grey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStat(rating.toStringAsFixed(1), 'Rating'),
                _buildDivider(),
                GestureDetector(
                  onTap: () => context.push('/reviews/${user?.uid ?? ''}'),
                  child: _buildStat('$reviewCount', 'Reviews'),
                ),
                _buildDivider(),
                GestureDetector(
                  onTap: () => context.push('/saved-providers'),
                  child: _buildStat('$savedCount', 'Saved'),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (bio.isNotEmpty) ...[
              Text(
                bio,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
              ),
              SizedBox(height: 10.h),
            ],
            if (_services.isNotEmpty) ...[
              Text('Services', style: AppTextStyles.bodyLarge),
              SizedBox(height: 6.h),
              Text(
                _services.map((s) => s['name'] ?? '').join(', '),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(height: 10.h),
            ],
            if (address.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16.sp,
                      color: AppColors.primary.withValues(alpha: 0.5)),
                  SizedBox(width: 4.w),
                  Flexible(
                    child: Text(
                      address,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
            ],
            _buildStatusBar(
              isEarlyAccess: isEarlyAccess,
              isSubscribed: isSubscribed,
              subscriptionExpiry: subscriptionExpiry,
              leadCount: leadCount,
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: OutlinedButton(
                onPressed: () => context.push('/edit-profile'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
                child: Text('Edit Profile',
                    style: AppTextStyles.button
                        .copyWith(color: AppColors.primary)),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Work Photos', style: AppTextStyles.bodyLarge),
                if (_workPhotos.length < 15)
                  TextButton(
                    onPressed: _addWorkPhotos,
                    child: Text('Add Photos',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            if (_workPhotos.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4.w,
                  mainAxisSpacing: 4.h,
                ),
                itemCount: _workPhotos.length,
                itemBuilder: (context, index) => GestureDetector(
                  onLongPress: () => _showPhotoOptions(index),
                  onTap: () => _viewPhoto(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: Image.network(_workPhotos[index],
                        fit: BoxFit.cover),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label) => Column(
        children: [
          Text(value,
              style: AppTextStyles.bodyLarge
                  .copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: AppTextStyles.caption),
        ],
      );

  Widget _buildDivider() => Container(
        height: 24.h,
        width: 1.w,
        color: AppColors.primary.withValues(alpha: 0.15),
        margin: EdgeInsets.symmetric(horizontal: 16.w),
      );

  Widget _buildStatusBar({
    required bool isEarlyAccess,
    required bool isSubscribed,
    required Timestamp? subscriptionExpiry,
    required int leadCount,
  }) {
    if (isEarlyAccess) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, color: AppColors.success, size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Early Access — All features unlocked',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    bool activeSubscription = false;
    if (isSubscribed && subscriptionExpiry != null) {
      final expiryDate = subscriptionExpiry.toDate();
      if (DateTime.now().isBefore(expiryDate)) {
        activeSubscription = true;
      }
    }

    if (activeSubscription) {
      final expiryDate = subscriptionExpiry!.toDate();
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, color: AppColors.success, size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Premium — Active until ${_formatDate(expiryDate)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (leadCount < 10) {
      final remaining = 10 - leadCount;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$remaining/10 leads remaining',
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: leadCount / 10,
                      minHeight: 4.h,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.1),
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            SizedBox(
              height: 36.h,
              child: ElevatedButton(
                onPressed: () => context.push('/subscription'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                ),
                child: Text('Subscribe',
                    style: AppTextStyles.button
                        .copyWith(fontSize: 12.sp)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: ElevatedButton(
              onPressed: () => context.push('/subscription'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Text('Subscribe Now', style: AppTextStyles.button),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Subscribe to continue receiving clients',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}