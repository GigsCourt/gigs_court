import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/theme.dart';

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
  bool _isFetchingLocation = true;
  bool _isLoadingAddress = false;
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
    setState(() { _isFetchingLocation = true; _locationError = null; });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() { _locationError = 'Location services are disabled. Please enable them.'; _isFetchingLocation = false; });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() { _locationError = 'Location permission is required to set your workspace.'; _isFetchingLocation = false; });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() { _locationError = 'Location permission was permanently denied. Please enable it in settings.'; _isFetchingLocation = false; });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      setState(() { _pinnedLocation = LatLng(position.latitude, position.longitude); _isFetchingLocation = false; _isMapReady = true; });
      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_pinnedLocation, 17));
      }
    } catch (e) {
      setState(() { _locationError = 'Could not get location. Tap to retry.'; _isFetchingLocation = false; });
    }
  }

  Future<void> _onCameraIdle() async {
    if (_mapController != null) {
      final region = await _mapController!.getVisibleRegion();
      _pinnedLocation = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
    }
  }

  Future<void> _fetchAddress() async {
    setState(() => _isLoadingAddress = true);
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('reverseGeocode');
      final result = await callable.call({'lat': _pinnedLocation.latitude, 'lng': _pinnedLocation.longitude});
      final address = result.data['address'] as String;
      if (mounted) {
        setState(() { _address = address; _addressController.text = address; _isLoadingAddress = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAddress = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not fetch address. You can type it manually.')));
      }
    }
  }

  Future<void> _handleSave() async {
    if (_address.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await Supabase.instance.client.rpc('upsert_provider_location', params: {
          'p_user_id': user.uid, 'p_latitude': _pinnedLocation.latitude, 'p_longitude': _pinnedLocation.longitude, 'p_address': _address.trim(),
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isSaving = false);
    context.push('/setup/services');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            if (_isMapReady || !_isFetchingLocation)
              GoogleMap(initialCameraPosition: CameraPosition(target: _pinnedLocation, zoom: 17), onMapCreated: (controller) => _mapController = controller, onCameraIdle: _onCameraIdle, mapType: MapType.hybrid, myLocationEnabled: true, myLocationButtonEnabled: false, zoomControlsEnabled: false)
            else
              Container(color: AppColors.primary.withValues(alpha: 0.1)),

            if (_isFetchingLocation)
              Container(color: AppColors.primary.withValues(alpha: 0.8), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(color: AppColors.white), SizedBox(height: 16.h), Text('Getting your location...', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.white))]))),

            if (_locationError != null)
              Container(color: AppColors.primary.withValues(alpha: 0.9), child: Center(child: Padding(padding: EdgeInsets.all(32.w), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_off, size: 48.sp, color: AppColors.white), SizedBox(height: 16.h), Text(_locationError!, textAlign: TextAlign.center, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.white)), SizedBox(height: 24.h), ElevatedButton(onPressed: _getCurrentLocation, style: ElevatedButton.styleFrom(backgroundColor: AppColors.white, foregroundColor: AppColors.primary), child: const Text('Retry'))])))),

            if (_isMapReady)
              Center(child: Icon(Icons.location_on, size: 40.sp, color: AppColors.primary)),

            Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h), child: Row(children: [
              Container(decoration: BoxDecoration(color: AppColors.white.withValues(alpha: 0.9), shape: BoxShape.circle), child: IconButton(icon: Icon(Icons.arrow_back_ios_new, size: 20.sp), onPressed: () => context.pop())),
              SizedBox(width: 8.w),
              Expanded(child: Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h), decoration: BoxDecoration(color: AppColors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12.r)), child: Text('Drag map to pin your workspace', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)))),
            ])))),

            // Bottom sheet
            if (_isMapReady)
              Positioned(bottom: 0, left: 0, right: 0, child: Container(
                padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
                decoration: BoxDecoration(color: AppColors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: _addressController, onChanged: (value) => _address = value, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: _address.isNotEmpty ? _address : 'Describe your workspace location...', hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)), prefixIcon: Icon(Icons.edit_location_outlined, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.5)))),
                  SizedBox(height: 4.h),
                  Text('Describe your workspace so clients can find you (e.g., "No. 15 Adeola Odeku Street, Victoria Island")', style: AppTextStyles.caption),
                  SizedBox(height: 12.h),
                  SizedBox(width: double.infinity, height: 48.h, child: ElevatedButton(onPressed: (_address.isNotEmpty && !_isSaving) ? _handleSave : null, child: _isSaving ? SizedBox(height: 20.h, width: 20.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2)) : Text('Save Location', style: AppTextStyles.button))),
                  SizedBox(height: 6.h),
                  GestureDetector(onTap: () => context.push('/setup/services'), child: Text('Skip for now', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary))),
                  SizedBox(height: 2.h),
                  Text('You won\'t appear as a provider until you set your workspace.', textAlign: TextAlign.center, style: AppTextStyles.caption),
                ]),
              )),

            // "Use this location" pill (above bottom sheet)
            if (_isMapReady && _address.isEmpty && !_isLoadingAddress)
              Positioned(bottom: 220.h, left: 0, right: 0, child: Center(child: GestureDetector(
                onTap: _fetchAddress,
                child: Container(padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24.r), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8.r, offset: Offset(0, 2.h))]), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.location_on, size: 18.sp, color: AppColors.white), SizedBox(width: 6.w), Text('Use this location?', style: AppTextStyles.bodySmall.copyWith(color: AppColors.white, fontWeight: FontWeight.w600))])),
              ))),

            // Loading address indicator (above bottom sheet)
            if (_isLoadingAddress)
              Positioned(bottom: 220.h, left: 0, right: 0, child: Center(child: Container(padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24.r)), child: Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 16.h, width: 16.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2)), SizedBox(width: 8.w), Text('Getting address...', style: AppTextStyles.bodySmall.copyWith(color: AppColors.white))])))),
          ],
        ),
      ),
    );
  }
}