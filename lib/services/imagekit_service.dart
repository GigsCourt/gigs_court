import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ImageKitService {
  static Future<Map<String, dynamic>> uploadImage(File imageFile, String fileName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      final idToken = await user.getIdToken();

      final functionUrl =
          'https://us-central1-gigs-court.cloudfunctions.net/getImageKitAuth';

      final tokenResponse = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
      );

      if (tokenResponse.statusCode != 200) {
        return {'success': false, 'error': 'Cloud Function failed: ${tokenResponse.statusCode} ${tokenResponse.body}'};
      }

      final tokenData = jsonDecode(tokenResponse.body);

      final token = tokenData['token'];
      final expire = tokenData['expire'];
      final signature = tokenData['signature'];

      if (token == null || expire == null || signature == null) {
        return {'success': false, 'error': 'Missing token params'};
      }

      final uri = Uri.parse('https://upload.imagekit.io/api/v1/files/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['publicKey'] = AppConfig.imagekitPublicKey
        ..fields['token'] = token
        ..fields['expire'] = expire.toString()
        ..fields['signature'] = signature
        ..fields['fileName'] = fileName
        ..fields['useUniqueFileName'] = 'true'
        ..files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );

      final uploadResponse =
          await http.Response.fromStream(await request.send());

      if (uploadResponse.statusCode == 200) {
        final data = jsonDecode(uploadResponse.body);
        return {'success': true, 'url': data['url']};
      }

      return {'success': false, 'error': 'ImageKit upload failed: ${uploadResponse.statusCode} ${uploadResponse.body}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}