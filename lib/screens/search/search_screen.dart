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
import '../../providers/auth_provider.dart' as app_auth;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = false;
  double? _userLat;
  double? _userLng;
  String? _selectedService;
  List<Map<String, dynamic>> _searchResults = [];
  List<ProviderCardData> _providers = [];
  List<Map<String, dynamic>> _trendingServices = [];
  bool _isLoadingTrending = false;
  StreamSubscription? _locationSubscription;
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    _getLocationAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getLocationAndLoad() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _userLat = position.latitude;
      _userLng = position.longitude;
      _loadTrendingServices();

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      ).listen((position) {
        _userLat = position.latitude;
        _userLng = position.longitude;
        if (_selectedService != null) _findProviders();
        _loadTrendingServices();
      });
    } catch (_) {}
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
      if (mounted) {
        setState(() => _isLoadingTrending = false);
      }
    }
  }

  Future<void> _searchServices(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    if (_selectedService != null &&
        query.trim().toLowerCase() == _selectedService!.toLowerCase()) {
      setState(() => _searchResults = []);
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

  void _selectService(Map<String, dynamic> service) {
    setState(() {
      _selectedService = service['name'];
      _searchController.text = service['name'];
      _searchResults = [];
    });
    _findProviders();
  }

  void _clearSelectedService() {
    setState(() {
      _selectedService = null;
      _searchController.clear();
      _providers = [];
      _searchResults = [];
    });
  }

  Future<void> _findProviders() async {
    if (_userLat == null || _userLng == null || _selectedService == null) return;
    setState(() => _isLoading = true);
    final isEarlyAccess = context.read<app_auth.AuthProvider>().isEarlyAccess;

    try {
      final nearbyData = await _supabase.rpc(
        'find_all_providers',
        params: {'p_lat': _userLat, 'p_lng': _userLng},
      );
      final nearbyUsers = List<Map<String, dynamic>>.from(nearbyData);
      if (nearbyUsers.isEmpty) {
        setState(() {
          _providers = [];
          _isLoading = false;
        });
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final userFutures = nearbyUsers
          .map((supa) => FirebaseFirestore.instance
              .collection('users')
              .doc(supa['provider_id'] as String)
              .get())
          .toList();
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
        final reviewCount = userData['reviewCount'] ?? 0;
        final isFree = !isSubscribed && leadCount < 10 && reviewCount < 5;

        providersRaw.add({
          'id': id,
          'name': userData['displayName'] ?? userData['name'] ?? 'Unknown',
          'profileImage': userData['photoUrl'] ?? userData['profileImage'] ?? '',
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

      final serviceMatch = await _supabase
          .from('services')
          .select()
          .eq('name', _selectedService!)
          .maybeSingle();

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

      var filtered = providersRaw;
      if (serviceMatch != null) {
        final matchId = serviceMatch['id'] as String;
        filtered = providersRaw
            .where((p) => (p['serviceIds'] as List<String>).contains(matchId))
            .toList();
      }

      final providers = filtered.map((p) {
        final names = (p['serviceIds'] as List<String>)
            .map((id) => serviceNames[id] ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final workPhotos = List<String>.from(p['workPhotos'] ?? []);
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
          isEarlyAccess: isEarlyAccess,
          isOwnProfile: p['isOwnProfile'],
          latestWorkPhoto: workPhotos.isNotEmpty ? workPhotos.last : null,
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
        _providers = providers;
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

  List<ProviderCardData> get _filteredProviders {
    if (_verifiedOnly) {
      return _providers.where((p) => p.isSubscribed).toList();
    }
    return _providers;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(screenWidth);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
                child: TextField(
                  controller: _searchController,
                  onChanged: _searchServices,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search services...',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20.sp,
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
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
                        onTap: () => _selectService(service),
                      );
                    },
                  ),
                ),
              if (_selectedService == null) ...[
                SizedBox(height: 8.h),
                if (_isLoadingTrending)
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_trendingServices.isNotEmpty)
                  SizedBox(
                    height: 40.h,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 8.h),
                      itemCount: _trendingServices.length,
                      itemBuilder: (context, index) {
                        final service = _trendingServices[index];
                        final name = service['service_name'] as String;
                        final isSelected = _selectedService == name;
                        return Padding(
                          padding: EdgeInsets.only(right: 8.w),
                          child: GestureDetector(
                            onTap: () {
                              if (isSelected) {
                                _clearSelectedService();
                              } else {
                                _selectService({
                                  'name': name,
                                  'category': '',
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
                                borderRadius: BorderRadius.circular(20.r),
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
              ],
              if (_selectedService != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(
                          _selectedService!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        backgroundColor: AppColors.primary,
                        deleteIcon: Icon(
                          Icons.close,
                          size: 16.sp,
                          color: AppColors.white,
                        ),
                        onDeleted: _clearSelectedService,
                      ),
                      const Spacer(),
                      if (_providers.isNotEmpty)
                        Row(
                          children: [
                            Text(
                              'Verified only',
                              style: AppTextStyles.caption,
                            ),
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
                    ],
                  ),
                ),
              Expanded(
                child: _selectedService == null
                    ? Center(
                        child: Text(
                          'Search for a service to find providers near you.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color:
                                AppColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : _isLoading && _providers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredProviders.isEmpty
                            ? Center(
                                child: Text(
                                  _verifiedOnly
                                      ? 'No verified providers found for "$_selectedService".'
                                      : 'No providers found for "$_selectedService".',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              )
                            : GridView.builder(
                                padding: EdgeInsets.all(16.w),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 0.72,
                                  crossAxisSpacing: 12.w,
                                  mainAxisSpacing: 12.h,
                                ),
                                itemCount: _filteredProviders.length,
                                itemBuilder: (context, index) {
                                  final p = _filteredProviders[index];
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
            ],
          ),
        ),
      ),
    );
  }
}