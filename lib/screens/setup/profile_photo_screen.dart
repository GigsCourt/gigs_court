import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/imagekit_service.dart';

class ProfilePhotoScreen extends StatefulWidget {
  const ProfilePhotoScreen({super.key});

  @override
  State<ProfilePhotoScreen> createState() => _ProfilePhotoScreenState();
}

class _ProfilePhotoScreenState extends State<ProfilePhotoScreen> {
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  bool get _hasImage => _selectedImageFile != null || _selectedImageBytes != null;

  Future<void> _pickImage() async {
    _clearError();
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageFile = null;
        });
      } else {
        setState(() {
          _selectedImageFile = File(pickedFile.path);
          _selectedImageBytes = null;
        });
      }
    }
  }

  Future<void> _handleContinue() async {
    if (!_hasImage) return;

    _clearError();
    setState(() => _isUploading = true);

    final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await ImageKitService.uploadImage(_selectedImageFile!, fileName);

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, AppRoutes.location);
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Upload failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            children: [
              SizedBox(height: 20.h),
              Text(
                'Add Your Profile Photo',
                textAlign: TextAlign.center,
                style: AppTextStyles.headline2,
              ),
              SizedBox(height: 12.h),
              Text(
                'Upload a clear photo of yourself. This helps\nproviders and clients recognize you.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 40.h),

              // Photo preview
              GestureDetector(
                onTap: _isUploading ? null : _pickImage,
                child: Container(
                  height: 180.h,
                  width: 180.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hasImage
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: _hasImage
                      ? ClipOval(
                          child: _selectedImageBytes != null
                              ? Image.memory(
                                  _selectedImageBytes!,
                                  fit: BoxFit.cover,
                                )
                              : Image.file(
                                  _selectedImageFile!,
                                  fit: BoxFit.cover,
                                ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 40.sp,
                              color: AppColors.primary.withValues(alpha: 0.4),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Tap to upload',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                ),
              ),
              SizedBox(height: 32.h),

              // Uploading
              if (_isUploading) ...[
                const CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 8.h),
                Text('Uploading...', style: AppTextStyles.caption),
                SizedBox(height: 16.h),
              ],

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          color: AppColors.error, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _errorMessage!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (!_isUploading && _errorMessage == null) ...[
                Text(
                  _hasImage
                      ? 'Tap the photo to change it'
                      : 'A clear headshot works best',
                  style: AppTextStyles.caption,
                ),
              ],

              const Spacer(),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: ElevatedButton(
                  onPressed: (_hasImage && !_isUploading)
                      ? _handleContinue
                      : null,
                  child: _isUploading
                      ? SizedBox(
                          height: 22.h,
                          width: 22.w,
                          child: const CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text('Continue', style: AppTextStyles.button),
                ),
              ),
              SizedBox(height: 40.h),
            ],
          ),
        ),
      ),
    );
  }
}