import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';

class SavedProvidersScreen extends StatefulWidget {
  const SavedProvidersScreen({super.key});

  @override
  State<SavedProvidersScreen> createState() => _SavedProvidersScreenState();
}

class _SavedProvidersScreenState extends State<SavedProvidersScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _savedProviders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _isLoading = false); return; }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final savedIds = List<String>.from(userDoc.data()?['savedProviders'] ?? []);

      if (savedIds.isEmpty) { setState(() => _isLoading = false); return; }

      // Get current location for distance
      double? userLat, userLng;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)),
        );
        userLat = position.latitude;
        userLng = position.longitude;
      } catch (_) {}

      final providers = <Map<String, dynamic>>[];
      for (final id in savedIds) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
        if (!doc.exists) continue;
        final data = doc.data()!;

        double? distanceKm;
        if (userLat != null && userLng != null) {
          try {
            final result = await _supabase.rpc('find_all_providers', params: {'p_lat': userLat, 'p_lng': userLng});
            final list = List<Map<String, dynamic>>.from(result);
            final match = list.where((p) => p['provider_id'] == id).firstOrNull;
            if (match != null) {
              distanceKm = (match['distance_meters'] as num) / 1000.0;
            }
          } catch (_) {}
        }

        providers.add({
          'id': id,
          'name': data['displayName'] ?? data['name'] ?? 'Unknown',
          'photoUrl': data['profileImage'] ?? data['photoUrl'],
          'isSubscribed': data['isSubscribed'] == true,
          'distanceKm': distanceKm,
        });
      }

      setState(() { _savedProviders = providers; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSaved(String providerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'savedProviders': FieldValue.arrayRemove([providerId]),
    });
    setState(() => _savedProviders.removeWhere((p) => p['id'] == providerId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Saved Providers', style: AppTextStyles.headline3)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedProviders.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.bookmark_outline, size: 64.sp, color: AppColors.primary.withValues(alpha: 0.3)),
                    SizedBox(height: 16.h),
                    Text('No saved providers yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))),
                  ]),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: _savedProviders.length,
                  itemBuilder: (context, index) {
                    final p = _savedProviders[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 8.h),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(24.r),
                          child: SizedBox(width: 44.w, height: 44.w,
                            child: p['photoUrl'] != null && p['photoUrl'].toString().isNotEmpty
                                ? CachedNetworkImage(imageUrl: p['photoUrl'], fit: BoxFit.cover)
                                : Container(color: AppColors.primary.withValues(alpha: 0.06), child: Icon(Icons.person, size: 22.sp, color: AppColors.primary.withValues(alpha: 0.3))),
                          ),
                        ),
                        title: Row(children: [
                          Flexible(child: Text(p['name'], style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                          if (p['isSubscribed'] == true) ...[SizedBox(width: 4.w), Icon(Icons.verified, size: 16.sp, color: Color(0xFF2196F3))],
                        ]),
                        subtitle: p['distanceKm'] != null
                            ? Row(children: [
                                Icon(Icons.location_on_outlined, size: 14.sp, color: AppColors.primary.withValues(alpha: 0.5)),
                                SizedBox(width: 2.w),
                                Text('${(p['distanceKm'] as double).toStringAsFixed(1)} km away', style: AppTextStyles.caption),
                              ])
                            : null,
                        trailing: IconButton(
                          icon: Icon(Icons.bookmark, size: 20.sp, color: AppColors.primary),
                          onPressed: () => _removeSaved(p['id']),
                        ),
                        onTap: () => context.push('/provider/${p['id']}'),
                      ),
                    );
                  },
                ),
    );
  }
}