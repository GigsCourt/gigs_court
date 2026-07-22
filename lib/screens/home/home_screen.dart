import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/cache_service.dart';
import '../../widgets/provider_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../providers/auth_provider.dart' as app_auth;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  // Provider data
  List<ProviderCardData> _featuredProviders = [];
  List<ProviderCardData> _allProviders = [];
  bool _isLoading = true;
  bool _showScrollToTop = false;

  // Location
  double? _userLat;
  double? _userLng;
  bool _locationInitialized = false;
  StreamSubscription? _locationSubscription;
  StreamSubscription<QuerySnapshot>? _onlineStatusListener;

  // Search
  String? _selectedService;
  String? _selectedServiceId;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _trendingServices = [];
  bool _isLoadingTrending = false;
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
        _clearSearch();
      }
    });
    _getLocationAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _locationSubscription?.cancel();
    _onlineStatusListener?.cancel();
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
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLoading = false);
        return;
      }

      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        _userLat = lastPosition.latitude;
        _userLng = lastPosition.longitude;
        await _loadProviders();
        _loadTrendingServices();
      }

      try {
        final freshPosition = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 5));
        if (_userLat == null ||
            (freshPosition.latitude - _userLat!).abs() > 0.001 ||
            (freshPosition.longitude - _userLng!).abs() > 0.001) {
          _userLat = freshPosition.latitude;
          _userLng = freshPosition.longitude;
          await _loadProviders();
          _loadTrendingServices();
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
        // Skip the first automatic position update
        if (!_locationInitialized) {
          _locationInitialized = true;
          return;
        }
        _userLat = position.latitude;
        _userLng = position.longitude;
        _loadProviders();
        _loadTrendingServices();
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTrendingServices() async {
    if (_userLat == null || _userLng == null) return;
    setState(() => _isLoadingTrending = true);
    try {
      final data = await _supabase.rpc(
        'get_trending_services',
        params: {'p_lat': _userLat, 'p_lng': _userLng, 'p_limit': 15},
      );
      if (mounted) {
        setState(() {
          _trendingServices = List<Map<String, dynamic>>.from(data);
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _searchServices(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      if (_selectedService != null) {
        _clearSearch();
      }
      return;
    }
    try {
      final data = await _supabase
          .from('services')
          .select()
          .eq('status', 'approved')
          .ilike('name', '%$query%')
          .order('name')
          .limit(10);
      if (mounted) {
        setState(() =>
            _searchResults = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {}
  }

  void _selectServiceFromSearch(Map<String, dynamic> service) {
    _searchController.text = service['name'] as String;
    setState(() {
      _selectedService = service['name'] as String;
      _selectedServiceId = service['id'].toString();
      _searchResults = [];
    });
    _searchFocusNode.unfocus();
    _loadProviders();
  }

  void _selectServiceFromTrending(Map<String, dynamic> service) {
    _searchController.text = service['name'] as String;
    setState(() {
      _selectedService = service['name'] as String;
      _selectedServiceId = service['id'].toString();
      _searchResults = [];
    });
    _loadProviders();
  }

  void _clearSearch() {
    setState(() {
      _selectedService = null;
      _selectedServiceId = null;
      _searchController.clear();
      _searchResults = [];
    });
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    if (_userLat == null || _userLng == null) return;
    final isEarlyAccess = context.read<app_auth.AuthProvider>().isEarlyAccess;
    try {
      final nearbyData = await _supabase.rpc(
        'find_all_providers',
        params: {'p_lat': _userLat, 'p_lng': _userLng},
      );
      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);
      if (nearbyUsers.isEmpty) {
        setState(() {
          _featuredProviders = [];
          _allProviders = [];
          _isLoading = false;
        });
        _cancelOnlineStatusListener();
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final userFutures = nearbyUsers.map((supa) {
        return FirebaseFirestore.instance
            .collection('users')
            .doc(supa['provider_id'] as String)
            .get();
      }).toList();
      final userDocs = await Future.wait(userFutures);
      final allServiceIds = <String>{};
      final providersRaw = <Map<String, dynamic>>[];

      for (int i = 0; i < nearbyUsers.length; i++) {
        final supa = nearbyUsers[i];
        final userDoc = userDocs[i];
        if (!userDoc.exists) continue;
        final id = supa['provider_id'] as String;
        final userData = userDoc.data()!;
        final serviceIds = List<String>.from(userData['services'] ?? []);
        allServiceIds.addAll(serviceIds);

        final isSubscribed = userData['isSubscribed'] == true;
        final leadCount = userData['leadCount'] ?? 0;
        final isFree = !isSubscribed && leadCount < 10;

        providersRaw.add({
          'id': id,
          'name': userData['displayName'] ?? userData['name'] ?? 'Unknown',
          'profileImage':
              userData['photoUrl'] ?? userData['profileImage'] ?? '',
          'serviceIds': serviceIds,
          'isSubscribed': isEarlyAccess || isSubscribed,
          'isFree': isEarlyAccess || isFree,
          'isOnline': isEarlyAccess
              ? (userData['isOnline'] ?? false)
              : (isSubscribed && (userData['isOnline'] ?? false)),
          'lastSeen': _formatLastSeen(userData['lastSeen']),
          'rating': (userData['averageRating'] ?? userData['rating'] ?? 0.0)
              .toDouble(),
          'reviewCount': userData['reviewCount'] ?? 0,
          'distanceKm': (supa['distance_meters'] as num) / 1000.0,
          'isOwnProfile': id == currentUserId,
          'workPhotos': List<String>.from(userData['workPhotos'] ?? []),
        });
      }

      if (_selectedServiceId != null) {
        providersRaw.removeWhere(
            (p) => !(p['serviceIds'] as List<String>).contains(_selectedServiceId));
      }

      Map<String, String> serviceNames =
          CacheService.get<Map<String, String>>('service_names') ?? {};
      final uncachedIds =
          allServiceIds.where((id) => !serviceNames.containsKey(id)).toList();
      if (uncachedIds.isNotEmpty) {
        final namesData = await _supabase.rpc(
          'get_service_names',
          params: {'p_service_ids': uncachedIds},
        );
        for (final row in List<Map<String, dynamic>>.from(namesData)) {
          serviceNames[row['id'] as String] = row['name'] as String;
        }
        CacheService.set('service_names', serviceNames,
            ttl: const Duration(hours: 24));
      }

      final providers = providersRaw.map((p) {
        final names = (p['serviceIds'] as List<String>)
            .map((id) => serviceNames[id] ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final workPhotos = List<String>.from(p['workPhotos'] ?? []);
        return ProviderCardData(
          id: p['id'],
          name: p['name'],
          profileImage: p['profileImage'],
          latestWorkPhoto: workPhotos.isNotEmpty ? workPhotos.last : null,
          services: names,
          rating: p['rating'],
          reviewCount: p['reviewCount'],
          distanceKm: p['distanceKm'],
          isSubscribed: p['isSubscribed'],
          isFree: p['isFree'],
          isOnline: p['isOnline'],
          lastSeen: p['lastSeen'],
          isEarlyAccess: isEarlyAccess,
          isOwnProfile: p['isOwnProfile'],
        );
      }).toList();

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
        _featuredProviders =
            providers.where((p) => p.isSubscribed).toList();
        _allProviders = providers;
        _isLoading = false;
      });

      _startOnlineStatusListener();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _cancelOnlineStatusListener() {
    _onlineStatusListener?.cancel();
    _onlineStatusListener = null;
  }

  void _startOnlineStatusListener() {
    _cancelOnlineStatusListener();

    final providerIds = _allProviders.map((p) => p.id).toList();
    if (providerIds.isEmpty) return;

    final batchIds =
        providerIds.length <= 30 ? providerIds : providerIds.sublist(0, 30);

    _onlineStatusListener = FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: batchIds)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      bool hasChanges = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        final isOnline = data['isOnline'] ?? false;
        final lastSeen = _formatLastSeen(data['lastSeen']);

        for (int i = 0; i < _featuredProviders.length; i++) {
          if (_featuredProviders[i].id == docId) {
            if (_featuredProviders[i].isOnline != isOnline ||
                _featuredProviders[i].lastSeen != lastSeen) {
              _featuredProviders[i] = _featuredProviders[i].copyWith(
                isOnline: isOnline,
                lastSeen: lastSeen,
              );
              hasChanges = true;
            }
            break;
          }
        }

        for (int i = 0; i < _allProviders.length; i++) {
          if (_allProviders[i].id == docId) {
            if (_allProviders[i].isOnline != isOnline ||
                _allProviders[i].lastSeen != lastSeen) {
              _allProviders[i] = _allProviders[i].copyWith(
                isOnline: isOnline,
                lastSeen: lastSeen,
              );
              hasChanges = true;
            }
            break;
          }
        }
      }

      if (hasChanges && mounted) {
        setState(() {});
      }
    });
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

  List<ProviderCardData> get _displayedProviders {
    if (_verifiedOnly) {
      return _allProviders.where((p) => p.isSubscribed).toList();
    }
    return _allProviders;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(screenWidth);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _searchServices,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search services...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8.h),
              suffixIcon: _selectedService != null
                  ? IconButton(
                      icon: Icon(Icons.close, size: 18.sp,
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      onPressed: _clearSearch,
                    )
                  : Icon(Icons.search, size: 20.sp,
                      color: AppColors.primary.withValues(alpha: 0.5)),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, size: 22.sp),
              onPressed: () => context.push('/notifications'),
            ),
          ],
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await _loadProviders();
                _loadTrendingServices();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Search hint text (only when no search active and no service selected)
                  if (_selectedService == null && _searchResults.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
                      child: Text(
                        'Search for a service e.g. Barber, Plumber, Web Developer',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          fontSize: 10.sp,
                        ),
                      ),
                    ),

                  // Search results dropdown
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            blurRadius: 8.r,
                          ),
                        ],
                      ),
                      constraints: BoxConstraints(maxHeight: 200.h),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final service = _searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(service['name'],
                                style: AppTextStyles.bodyMedium),
                            subtitle: Text(service['category'],
                                style: AppTextStyles.caption),
                            onTap: () => _selectServiceFromSearch(service),
                          );
                        },
                      ),
                    ),

                  // Trending pills + Verified toggle row
                  if (_selectedService == null && _searchResults.isEmpty)
                    _buildTrendingRow(),

                  // Verified toggle when searching
                  if (_selectedService != null && _searchResults.isEmpty)
                    _buildVerifiedToggleRow(),

                  // Main content
                  if (_isLoading && _allProviders.isEmpty)
                    _buildSkeletonGrid(crossAxisCount)
                  else ...[
                    if (_featuredProviders.isNotEmpty &&
                        _selectedService == null) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                        child: Text('Featured Providers',
                            style: AppTextStyles.bodyLarge),
                      ),
                      SizedBox(height: 12.h),
                      SizedBox(
                        height: 160.h,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          itemCount: _featuredProviders.length,
                          itemBuilder: (context, index) {
                            final p = _featuredProviders[index];
                            return ProviderCard(
                              provider: p,
                              isHorizontal: true,
                              onTap: () => context.push(
                                '/provider/${p.id}',
                                extra: {
                                  'distanceKm': p.distanceKm,
                                  'isOnline': p.isOnline,
                                  'lastSeen': p.lastSeen,
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w,
                          (_featuredProviders.isEmpty || _selectedService != null) ? 12.h : 16.h,
                          16.w, 0),
                      child: Row(
                        children: [
                          Text(
                            _selectedService != null
                                ? 'Results'
                                : 'All Providers',
                            style: AppTextStyles.bodyLarge,
                          ),
                          const Spacer(),
                          if (_selectedService == null && _verifiedOnly)
                            Text('Verified only',
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary)),
                        ],
                      ),
                    ),
                    SizedBox(height: 12.h),
                    if (_displayedProviders.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(32.h),
                        child: Center(
                          child: Text(
                            _selectedService != null
                                ? 'No providers found.'
                                : 'No providers found nearby.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color:
                                  AppColors.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 12.w,
                            mainAxisSpacing: 12.h,
                          ),
                          itemCount: _displayedProviders.length,
                          itemBuilder: (context, index) {
                            final p = _displayedProviders[index];
                            return ProviderCard(
                              provider: p,
                              onTap: () => context.push(
                                '/provider/${p.id}',
                                extra: {
                                  'distanceKm': p.distanceKm,
                                  'isOnline': p.isOnline,
                                  'lastSeen': p.lastSeen,
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 40.h),
                  ],
                ],
              ),
            ),
            if (_showScrollToTop)
              Positioned(
                bottom: 20.h,
                right: 20.w,
                child: FloatingActionButton.small(
                  onPressed: () => _scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut),
                  backgroundColor: AppColors.primary,
                  child:
                      Icon(Icons.keyboard_arrow_up, color: AppColors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingRow() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: _isLoadingTrending
                ? Padding(
                    padding: EdgeInsets.all(16.w),
                    child: const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _trendingServices.isEmpty
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 36.h,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              EdgeInsets.symmetric(horizontal: 16.w),
                          itemCount: _trendingServices.length,
                          itemBuilder: (context, index) {
                            final service = _trendingServices[index];
                            final name =
                                service['service_name'] as String;
                            final isSelected =
                                _selectedService == name;
                            return Padding(
                              padding: EdgeInsets.only(right: 8.w),
                              child: GestureDetector(
                                onTap: () {
                                  if (isSelected) {
                                    _clearSearch();
                                  } else {
                                    _selectServiceFromTrending({
                                      'name': name,
                                      'id': service['service_id'],
                                    });
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 14.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.primary
                                            .withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(20.r),
                                  ),
                                  child: Text(
                                    name,
                                    style:
                                        AppTextStyles.bodySmall.copyWith(
                                      color: isSelected
                                          ? AppColors.white
                                          : AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          if (_trendingServices.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Verified', style: AppTextStyles.caption),
                  SizedBox(width: 4.w),
                  SizedBox(
                    height: 32.h,
                    child: Switch(
                      value: _verifiedOnly,
                      onChanged: (value) {
                        setState(() => _verifiedOnly = value);
                      },
                      activeColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerifiedToggleRow() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Verified only', style: AppTextStyles.caption),
          SizedBox(width: 4.w),
          SizedBox(
            height: 32.h,
            child: Switch(
              value: _verifiedOnly,
              onChanged: (value) {
                setState(() => _verifiedOnly = value);
              },
              activeColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid(int crossAxisCount) {
    return Column(
      children: [
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: const SkeletonLoader(width: 120, height: 18),
        ),
        SizedBox(height: 12.h),
        SizedBox(
          height: 160.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            itemBuilder: (_, _) =>
                const ProviderCardSkeleton(isHorizontal: true),
          ),
        ),
        SizedBox(height: 24.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: const SkeletonLoader(width: 100, height: 18),
        ),
        SizedBox(height: 12.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
            ),
            itemCount: 6,
            itemBuilder: (_, _) => const ProviderCardSkeleton(),
          ),
        ),
      ],
    );
  }
}