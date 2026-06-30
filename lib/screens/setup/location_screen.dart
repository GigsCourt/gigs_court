import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  GoogleMapController? _mapController;
  LatLng _pinnedLocation = const LatLng(0, 0);
  bool _isMapReady = false;
  String _address = '';
  bool _isLoadingAddress = false;
  bool _isFetchingLocation = true;
  bool _isSaving = false;
  String? _locationError;
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _locationError = null;
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationError = 'Location services are disabled. Please enable them.';
        _isFetchingLocation = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationError = 'Location permission is required to set your workspace.';
          _isFetchingLocation = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationError = 'Location permission was permanently denied. Please enable it in settings.';
        _isFetchingLocation = false;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      setState(() {
        _pinnedLocation = LatLng(position.latitude, position.longitude);
        _isFetchingLocation = false;
        _isMapReady = true;
      });
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_pinnedLocation, 17),
        );
      }
      _fetchAddress(_pinnedLocation);
    } catch (e) {
      setState(() {
        _locationError = 'Could not get location. Tap to retry.';
        _isFetchingLocation = false;
      });
    }
  }

  Future<void> _fetchAddress(LatLng location) async {
    setState(() => _isLoadingAddress = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('reverseGeocode');
      final result = await callable.call({
        'lat': location.latitude,
        'lng': location.longitude,
      });
      final address = result.data['address'] as String;
      if (mounted) {
        setState(() {
          _address = address;
          _addressController.text = address;
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAddress = false;
        });
      }
    }
  }

  Future<void> _onCameraIdle() async {
    if (_mapController != null) {
      final region = await _mapController!.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      _pinnedLocation = center;
      _fetchAddress(center);
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    // Save to Supabase — will be connected when provider data is set up
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pushReplacementNamed(context, AppRoutes.services);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Full screen map
          if (_isMapReady || !_isFetchingLocation)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pinnedLocation,
                zoom: 17,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_isMapReady) {
                  _fetchAddress(_pinnedLocation);
                }
              },
              onCameraIdle: _onCameraIdle,
              mapType: MapType.hybrid,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            )
          else
            Container(color: AppColors.primary.withValues(alpha: 0.1)),

          // Loading / error overlay for location
          if (_isFetchingLocation)
            Container(
              color: AppColors.primary.withValues(alpha: 0.8),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppColors.white),
                    SizedBox(height: 16.h),
                    Text(
                      'Getting your location...',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_locationError != null)
            Container(
              color: AppColors.primary.withValues(alpha: 0.9),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off,
                          size: 48.sp, color: AppColors.white),
                      SizedBox(height: 16.h),
                      Text(
                        _locationError!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      ElevatedButton(
                        onPressed: _getCurrentLocation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.primary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Center pin
          if (_isMapReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on,
                    size: 40.sp,
                    color: AppColors.primary,
                  ),
                  Container(
                    width: 4.w,
                    height: 4.h,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),

          // Top app bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'Drag map to pin your workspace',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom sheet
          if (_isMapReady)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 40.h),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.95),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24.r)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Address input
                    TextField(
                      controller: _addressController,
                      onChanged: (value) => _address = value,
                      style: AppTextStyles.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Fetching address...',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                        prefixIcon: Icon(
                          Icons.location_on_outlined,
                          size: 20.sp,
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                        suffixIcon: _isLoadingAddress
                            ? Padding(
                                padding: EdgeInsets.all(14.w),
                                child: SizedBox(
                                  height: 16.h,
                                  width: 16.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'You can edit the address if it doesn\'t describe your workspace correctly.',
                      style: AppTextStyles.caption,
                    ),
                    SizedBox(height: 16.h),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 56.h,
                      child: ElevatedButton(
                        onPressed:
                            (_address.isNotEmpty && !_isSaving) ? _handleSave : null,
                        child: _isSaving
                            ? SizedBox(
                                height: 22.h,
                                width: 22.w,
                                child: const CircularProgressIndicator(
                                  color: AppColors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Save Location', style: AppTextStyles.button),
                      ),
                    ),
                    SizedBox(height: 8.h),

                    // Skip
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, AppRoutes.services);
                      },
                      child: Text(
                        'Skip for now',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'You won\'t appear as a provider until you set your workspace.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}