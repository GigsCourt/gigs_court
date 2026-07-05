import 'package:cloud_firestore/cloud_firestore.dart';

class DisplayNameService {
  static Future<String> getDisplayName(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) {
        return doc.data()?['displayName'] ?? 
               doc.data()?['name'] ?? 
               'Someone';
      }
    } catch (_) {}
    return 'Someone';
  }
}