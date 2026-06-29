import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../config/theme.dart';
import '../../config/app_config.dart';

class ProfilePhotoScreen extends StatefulWidget {
  const ProfilePhotoScreen({super.key});

  @override
  State<ProfilePhotoScreen> createState() => _ProfilePhotoScreenState();
}

class _ProfilePhotoScreenState extends State<ProfilePhotoScreen> {
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  double _uploadProgress = 0;
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
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // Step 1: Get auth params from Cloud Function
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('getImageKitAuth');
      final authResult = await callable.call();
      final token = authResult.data['token'];
      final expire = authResult.data['expire'];
      final signature = authResult.data['signature'];

      // Step 2: Prepare file data
      Uint8List fileBytes;
      String fileName;

      if (_selectedImageBytes != null) {
        fileBytes = _selectedImageBytes!;
        fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        fileBytes = await _selectedImageFile!.readAsBytes();
        fileName = _selectedImageFile!.path.split('/').last;
      }

      // Step 3: Upload to ImageKit
      final dio = Dio();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        'publicKey': AppConfig.imagekitPublicKey,
        'token': token,
        'expire': expire.toString(),
        'signature': signature,
        'fileName': fileName,
      });

      final response = await dio.post(
        'https://upload.imagekit.io/api/v1/files/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            setState(() {
              _uploadProgress = sent / total;
            });
          }
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        // Store imageUrl: response.data['url']
        // Navigate to next setup screen — will be connected when built
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _errorMessage = 'Failed to upload photo. Please try again.';
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

              // Upload progress
              if (_isUploading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    minHeight: 6.h,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Uploading... ${(_uploadProgress * 100).toInt()}%',
                  style: AppTextStyles.caption,
                ),
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
                    children: [
                      Icon(Icons.error_outline,
                          color: AppColors.error, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
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