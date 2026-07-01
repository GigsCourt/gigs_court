import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../../config/theme.dart';
import '../../services/cache_service.dart';
import '../../widgets/provider_card.dart';
import '../../widgets/skeleton_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final _remoteConfig = FirebaseRemoteConfig.instance;
  final _scrollController = ScrollController();

  List<ProviderCardData> _featuredProviders = [];
  List<ProviderCardData> _allProviders = [];
  bool _isLoading = true;
  bool _isEarlyAccess = true;
  bool _showScrollToTop = false;
  double? _userLat;
  double? _userLng;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = !_remoteConfig.getBool('subscriptions_enforced');
    _scrollController.addListener(_onScroll);
    _getLocationAndLoad();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      setState(() => _showScrollToTop = _scrollController.offset > 400);
    }
  }

  Future<void> _getLocationAndLoad() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _isLoading = false);
        return;
      }

      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        _userLat = lastPosition.latitude;
        _userLng = lastPosition.longitude;
        await _loadProviders();
      }

      try {
        final freshPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 5));

        if (_userLat == null ||
            (freshPosition.latitude - _userLat!).abs() > 0.001 ||
            (freshPosition.longitude - _userLng!).abs() > 0.001) {
          _userLat = freshPosition.latitude;
          _userLng = freshPosition.longitude;
          await _loadProviders();
        }
      } catch (_) {
        if (_userLat == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      ).listen((position) {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _loadProviders();
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProviders() async {
    if (_userLat == null || _userLng == null) return;

    try {
      final nearbyData = await _supabase.rpc('find_all_providers', params: {
        'p_lat': _userLat,
        'p_lng': _userLng,
      });

      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);
      if (nearbyUsers.isEmpty) {
        setState(() {
          _featuredProviders = [];
          _allProviders = [];
          _isLoading = false;
        });
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      final userFutures = nearbyUsers.map((supa) {
        return FirebaseFirestore.instance.collection('users').doc(supa['provider_id'] as String).get();
      }).toList();

      final userDocs = await Future.wait(userFutures);
      final allServiceIds = <int>{};
      final providersRaw = <Map<String, dynamic>>[];

      for (int i = 0; i < nearbyUsers.length; i++) {
        final supa = nearbyUsers[i];
        final userDoc = userDocs[i];
        if (!userDoc.exists) continue;

        final id = supa['provider_id'] as String;
        final userData = userDoc.data()!;
        final serviceIds = List<int>.from(userData['services'] ?? []);
        allServiceIds.addAll(serviceIds);

        final isSubscribed = userData['isSubscribed'] == true;
        final leadCount = userData['leadCount'] ?? 0;
        final reviewCount = userData['reviewCount'] ?? 0;
        final isFree = !isSubscribed && leadCount < 10 && reviewCount < 5;

        providersRaw.add({
          'id': id,
          'name': userData['displayName'] ?? userData['name'] ?? 'Unknown',
          'profileImage': userData['photoUrl'] ?? userData['profileImage'] ?? '',
          'serviceIds': serviceIds,
          'isSubscribed': _isEarlyAccess || isSubscribed,
          'isFree': _isEarlyAccess || isFree,
          'isOnline': _isEarlyAccess ? (userData['isOnline'] ?? false) : (isSubscribed && (userData['isOnline'] ?? false)),
          'lastSeen': _formatLastSeen(userData['lastSeen']),
          'rating': (userData['averageRating'] ?? userData['rating'] ?? 0.0).toDouble(),
          'reviewCount': userData['reviewCount'] ?? 0,
          'distanceKm': (supa['distance_meters'] as num) / 1000.0,
          'isOwnProfile': id == currentUserId,
        });
      }

      // Fetch service names
      Map<int, String> serviceNames = CacheService.get<Map<int, String>>('service_names') ?? {};
      final uncachedIds = allServiceIds.where((id) => !serviceNames.containsKey(id)).toList();
      if (uncachedIds.isNotEmpty) {
        final namesData = await _supabase.rpc('get_service_names', params: {'service_ids': uncachedIds});
        for (final row in List<Map<String, dynamic>>.from(namesData)) {
          serviceNames[row['id'] as int] = row['name'] as String;
        }
        CacheService.set('service_names', serviceNames, ttl: const Duration(hours: 24));
      }

      // Build final list
      final providers = providersRaw.map((p) {
        final names = (p['serviceIds'] as List<int>).map((id) => serviceNames[id] ?? '').where((n) => n.isNotEmpty).toList();
        return ProviderCardData(
          id: p['id'],
          name: p['name'],
          profileImage: p['profileImage'],
          services: names,
          rating: p['rating'],
          reviewCount: p['reviewCount'],
          distanceKm: p['distanceKm'],
          isSubscribed: p['isSubscribed'],
          isFree: p['isFree'],
          isOnline: p['isOnline'],
          lastSeen: p['lastSeen'],
          isEarlyAccess: _isEarlyAccess,
          isOwnProfile: p['isOwnProfile'],
        );
      }).toList();

      // Sort: Distance → Subscribed → Rating → Review count
      providers.sort((a, b) {
        final distCompare = a.distanceKm.compareTo(b.distanceKm);
        if (distCompare != 0) return distCompare;
        if (a.isSubscribed && !b.isSubscribed) return -1;
        if (!a.isSubscribed && b.isSubscribed) return 1;
        if (a.rating < 3.0 && b.rating >= 3.0) return 1;
        if (a.rating >= 3.0 && b.rating < 3.0) return -1;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.reviewCount.compareTo(a.reviewCount);
      });

      setState(() {
        _featuredProviders = providers.where((p) => p.isSubscribed && !p.isOwnProfile).toList();
        _allProviders = providers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String? _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return null;
    final date = (lastSeen as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth < 600) return 2;
    if (screenWidth < 900) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(screenWidth);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('GigsCourt', style: AppTextStyles.headline3),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, size: 22.sp),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading && _allProviders.isEmpty
              ? _buildSkeletonGrid(crossAxisCount)
              : RefreshIndicator(
                  onRefresh: _loadProviders,
                  child: ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16.w),
                    children: [
                      if (_featuredProviders.isNotEmpty) ...[
                        Text('Featured Providers', style: AppTextStyles.bodyLarge),
                        SizedBox(height: 12.h),
                        SizedBox(
                          height: 160.h,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _featuredProviders.length,
                            itemBuilder: (context, index) {
                              final p = _featuredProviders[index];
                              return ProviderCard(
                                provider: p,
                                isHorizontal: true,
                                onTap: () => context.push('/provider/${p.id}'),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],
                      Text('All Providers', style: AppTextStyles.bodyLarge),
                      SizedBox(height: 12.h),
                      if (_allProviders.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(32.h),
                          child: Center(
                            child: Text(
                              'No providers found nearby.',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5)),
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 12.w,
                            mainAxisSpacing: 12.h,
                          ),
                          itemCount: _allProviders.length,
                          itemBuilder: (context, index) {
                            final p = _allProviders[index];
                            return ProviderCard(
                              provider: p,
                              onTap: () => context.push('/provider/${p.id}'),
                            );
                          },
                        ),
                    ],
                  ),
                ),
          if (_showScrollToTop)
            Positioned(
              bottom: 20.h,
              right: 20.w,
              child: FloatingActionButton.small(
                onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                backgroundColor: AppColors.primary,
                child: Icon(Icons.keyboard_arrow_up, color: AppColors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid(int crossAxisCount) {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        const SkeletonLoader(width: 120, height: 18),
        SizedBox(height: 12.h),
        SizedBox(
          height: 160.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            itemBuilder: (_, _) => const ProviderCardSkeleton(isHorizontal: true),
          ),
        ),
        SizedBox(height: 24.h),
        const SkeletonLoader(width: 100, height: 18),
        SizedBox(height: 12.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12.w,
            mainAxisSpacing: 12.h,
          ),
          itemCount: 6,
          itemBuilder: (_, _) => const ProviderCardSkeleton(),
        ),
      ],
    );
  }
}