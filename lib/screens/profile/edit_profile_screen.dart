import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../services/imagekit_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  Map<String, dynamic>? _userData;
  List<String> _selectedServiceIds = [];
  List<String> _selectedServiceNames = [];
  String? _address;
  bool _isLoading = true;
  bool _isSaving = false;
  File? _newPhotoFile;

  @override
  void initState() { super.initState(); _loadProfile(); }

  @override
  void dispose() { _nameController.dispose(); _bioController.dispose(); super.dispose(); }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) { setState(() => _isLoading = false); return; }
      final userData = userDoc.data()!;
      _nameController.text = userData['displayName'] ?? userData['name'] ?? '';
      _bioController.text = userData['bio'] ?? '';

      final serviceIds = List<String>.from(userData['services'] ?? []);
      if (serviceIds.isNotEmpty) {
        try {
          final namesData = await _supabase.rpc('get_service_names', params: {'p_service_ids': serviceIds});
          final services = List<Map<String, dynamic>>.from(namesData);
          _selectedServiceIds = services.map((s) => s['id'].toString()).toList();
          _selectedServiceNames = services.map((s) => s['name'].toString()).toList();
        } catch (_) {}
      }
      String? address;
      try {
        final locData = await _supabase.from('provider_locations').select('address').eq('provider_id', user.uid).maybeSingle();
        address = locData?['address'] as String?;
      } catch (_) {}
      setState(() { _userData = userData; _address = address; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024, maxHeight: 1024);
    if (picked != null) setState(() => _newPhotoFile = File(picked.path));
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      String? photoUrl = _userData?['profileImage'] ?? _userData?['photoUrl'];
      if (_newPhotoFile != null) {
        final result = await ImageKitService.uploadImage(_newPhotoFile!, 'profile_${DateTime.now().millisecondsSinceEpoch}');
        if (result['success'] == true) photoUrl = result['url'] as String;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'displayName': _nameController.text.trim(),
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'profileImage': photoUrl,
        'services': _selectedServiceIds.toList(),
      });

      if (_selectedServiceIds.isNotEmpty) {
        for (final id in _selectedServiceIds) {
          try { await _supabase.rpc('add_user_service', params: {'p_user_id': user.uid, 'p_service_id': id}); } catch (_) {}
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated!'), backgroundColor: AppColors.success));
        context.pop();
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save. Please try again.'), backgroundColor: AppColors.error));
    }
  }

  void _removeService(int index) {
    setState(() { _selectedServiceIds.removeAt(index); _selectedServiceNames.removeAt(index); });
  }

  Future<void> _addServices() async {
    final result = await context.push<List<Map<String, dynamic>>>('/setup/services');
    if (result != null && mounted) {
      setState(() {
        for (final s in result) {
          final id = s['id'].toString(); final name = s['name'].toString();
          if (!_selectedServiceIds.contains(id)) { _selectedServiceIds.add(id); _selectedServiceNames.add(name); }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final photoUrl = _newPhotoFile != null ? null : (_userData?['profileImage'] ?? _userData?['photoUrl']);

    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Edit Profile', style: AppTextStyles.headline3)), body: GestureDetector(onTap: () => FocusScope.of(context).unfocus(), child: SingleChildScrollView(padding: EdgeInsets.all(20.w), child: Column(children: [
      GestureDetector(onTap: _pickPhoto, child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(80.r), child: SizedBox(width: 120.w, height: 120.w, child: _newPhotoFile != null ? Image.file(_newPhotoFile!, fit: BoxFit.cover) : photoUrl != null && photoUrl.toString().isNotEmpty ? Image.network(photoUrl, fit: BoxFit.cover) : Container(color: AppColors.primary.withValues(alpha: 0.06), child: Icon(Icons.person, size: 50.sp, color: AppColors.primary.withValues(alpha: 0.3))))),
        Positioned(bottom: 0, right: 0, child: Container(padding: EdgeInsets.all(6.w), decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: Icon(Icons.camera_alt, size: 16.sp, color: AppColors.white))),
      ])),
      SizedBox(height: 24.h),
      Text('Name', style: AppTextStyles.label), SizedBox(height: 8.h), TextField(controller: _nameController, style: AppTextStyles.bodyMedium),
      SizedBox(height: 16.h),
      Text('Bio', style: AppTextStyles.label), SizedBox(height: 8.h), TextField(controller: _bioController, maxLines: 3, maxLength: 300, style: AppTextStyles.bodyMedium),
      SizedBox(height: 16.h),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Services', style: AppTextStyles.label), TextButton(onPressed: _addServices, child: Text('Edit', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)))]),
      if (_selectedServiceNames.isNotEmpty) Wrap(spacing: 8.w, runSpacing: 8.h, children: List.generate(_selectedServiceNames.length, (i) => Chip(label: Text(_selectedServiceNames[i], style: AppTextStyles.bodySmall), backgroundColor: AppColors.primary.withValues(alpha: 0.08), side: BorderSide.none, onDeleted: () => _removeService(i)))),
      SizedBox(height: 16.h),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Address', style: AppTextStyles.label), TextButton(onPressed: () => context.push('/setup/location'), child: Text('Edit', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)))]),
      if (_address != null && _address!.isNotEmpty) Row(children: [Icon(Icons.location_on_outlined, size: 16.sp, color: AppColors.primary.withValues(alpha: 0.5)), SizedBox(width: 4.w), Flexible(child: Text(_address!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7))))]),
      SizedBox(height: 32.h),
      SizedBox(width: double.infinity, height: 48.h, child: ElevatedButton(onPressed: _isSaving ? null : _save, child: _isSaving ? SizedBox(height: 20.h, width: 20.w, child: const CircularProgressIndicator(color: AppColors.white, strokeWidth: 2)) : Text('Save Changes', style: AppTextStyles.button))),
      SizedBox(height: 40.h),
    ]))));
  }
}