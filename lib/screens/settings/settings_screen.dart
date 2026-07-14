import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import 'help_support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDeleting = false;

    // ---- Change Password ----
  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Password', style: AppTextStyles.bodyLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'ll send a password reset link to:',
              style: AppTextStyles.bodyMedium,
            ),
            SizedBox(height: 8.h),
            Text(
              user!.email!,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text('Send Reset Link', style: AppTextStyles.button.copyWith(color: AppColors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent. Check your inbox.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ---- Log Out ----
  Future<void> _logOut() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'isOnline': false, 'lastSeen': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
    await context.read<app_auth.AuthProvider>().signOut();
    if (mounted) context.go('/onboarding');
  }

  // ---- Delete Account ----
  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Account', style: AppTextStyles.bodyLarge),
        content: Text('Your account will be permanently deleted. This action cannot be undone. All your data including messages, reviews, and profile will be removed.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Read wasSubscribed BEFORE deleting the user doc
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final wasSubscribed = userDoc.data()?['isSubscribed'] == true;
      final supabase = Supabase.instance.client;

      // Delete Supabase data
      try {
        await supabase.from('provider_locations').delete().eq('provider_id', user.uid);
      } catch (_) {}

      // Delete all data in chunks (batch limit: 500 operations)
      await _batchDeleteUserData(user.uid);

      // Delete the user document itself
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();

      // Update counters
      final configUpdate = <String, dynamic>{'totalUsers': FieldValue.increment(-1)};
      if (wasSubscribed) {
        configUpdate['totalSubscribers'] = FieldValue.increment(-1);
      }
      await FirebaseFirestore.instance.collection('app_config').doc('global').set(configUpdate, SetOptions(merge: true));

      // Delete Firebase Auth user
      await user.delete();

      if (mounted) {
        setState(() => _isDeleting = false);
        context.go('/onboarding');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete account. Please try again.'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _batchDeleteUserData(String uid) async {
    final batchSize = 400; // Safe margin under 500
    final firestore = FirebaseFirestore.instance;

    // Delete notifications
    var notifsQuery = firestore.collection('users').doc(uid).collection('notifications').limit(batchSize);
    var snapshot = await notifsQuery.get();
    while (snapshot.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs) { batch.delete(doc.reference); }
      await batch.commit();
      snapshot = await notifsQuery.startAfterDocument(snapshot.docs.last).get();
    }

    // Delete tickets
    var ticketsQuery = firestore.collection('users').doc(uid).collection('tickets').limit(batchSize);
    snapshot = await ticketsQuery.get();
    while (snapshot.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs) { batch.delete(doc.reference); }
      await batch.commit();
      snapshot = await ticketsQuery.startAfterDocument(snapshot.docs.last).get();
    }

    // Soft-delete chats: mark user as deleted in participants
    var chatsQuery = firestore.collection('chats').where('participants', arrayContains: uid).limit(batchSize);
    snapshot = await chatsQuery.get();
    while (snapshot.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? []);
        if (participants.length == 2) {
          // Two-person chat: mark all messages from this user as deleted
          var msgsQuery = doc.reference.collection('messages').where('senderId', isEqualTo: uid).limit(batchSize);
          var msgsSnapshot = await msgsQuery.get();
          while (msgsSnapshot.docs.isNotEmpty) {
            final msgBatch = firestore.batch();
            for (final msg in msgsSnapshot.docs) {
              msgBatch.update(msg.reference, {'senderDeleted': true, 'text': 'This message was deleted', 'imageUrl': null, 'voiceUrl': null});
            }
            await msgBatch.commit();
            if (msgsSnapshot.docs.length >= batchSize) {
              msgsSnapshot = await msgsQuery.startAfterDocument(msgsSnapshot.docs.last).get();
            } else {
              break;
            }
          }
        }
        batch.update(doc.reference, {'deleted_$uid': true});
      }
      await batch.commit();
      snapshot = await chatsQuery.startAfterDocument(snapshot.docs.last).get();
    }

    // Delete reviews given by this user
    var reviewsGivenQuery = firestore.collection('reviews').where('clientId', isEqualTo: uid).limit(batchSize);
    snapshot = await reviewsGivenQuery.get();
    while (snapshot.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs) { batch.delete(doc.reference); }
      await batch.commit();
      snapshot = await reviewsGivenQuery.startAfterDocument(snapshot.docs.last).get();
    }

    // Delete reviews received by this user (they were the provider)
    var reviewsReceivedQuery = firestore.collection('reviews').where('providerId', isEqualTo: uid).limit(batchSize);
    snapshot = await reviewsReceivedQuery.get();
    while (snapshot.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs) { batch.delete(doc.reference); }
      await batch.commit();
      snapshot = await reviewsReceivedQuery.startAfterDocument(snapshot.docs.last).get();
    }
  }

  // ---- Help & Support ----
  Future<void> _helpAndSupport() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Support ticket submitted. We will get back to you.'), backgroundColor: AppColors.success));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEarlyAccess = context.watch<app_auth.AuthProvider>().isEarlyAccess;
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Settings', style: AppTextStyles.headline3)),
      body: Stack(
        children: [
          ListView(padding: EdgeInsets.all(16.w), children: [
            _buildSection('Account'),
            _buildTile(Icons.email_outlined, 'Email', subtitle: user?.email ?? ''),
            _buildTile(Icons.lock_outline, 'Change Password', onTap: _isDeleting ? null : _changePassword),
            SizedBox(height: 20.h),
            _buildSection('About'),
            _buildTile(Icons.description_outlined, 'Privacy Policy', onTap: () => _showLegal('Privacy Policy', _privacyPolicy)),
            _buildTile(Icons.article_outlined, 'Terms of Service', onTap: () => _showLegal('Terms of Service', _termsOfService)),
            if (isEarlyAccess) _buildTile(Icons.info_outline, 'About Early Access', onTap: () => _showLegal('Early Access', _earlyAccessInfo)),
            _buildTile(Icons.info_outline, 'App Version', subtitle: '1.0.0'),
            SizedBox(height: 20.h),
            _buildSection('Support'),
            _buildTile(Icons.support_outlined, 'Help & Support', onTap: _isDeleting ? null : _helpAndSupport),
            SizedBox(height: 20.h),
            _buildTile(Icons.logout, 'Log Out', onTap: _isDeleting ? null : _logOut),
            SizedBox(height: 8.h),
            _buildTile(Icons.delete_outline, 'Delete Account', color: AppColors.error, onTap: _isDeleting ? null : _deleteAccount),
            SizedBox(height: 40.h),
          ]),
          if (_isDeleting)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _showLegal(String title, String content) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text(title, style: AppTextStyles.headline3)), body: SingleChildScrollView(padding: EdgeInsets.all(20.w), child: Text(content, style: AppTextStyles.bodyMedium.copyWith(height: 1.6))))));
  }

  Widget _buildSection(String title) => Padding(padding: EdgeInsets.only(bottom: 8.h), child: Text(title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey, fontWeight: FontWeight.w600)));
  Widget _buildTile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Color? color}) => ListTile(contentPadding: EdgeInsets.symmetric(horizontal: 4.w), leading: Icon(icon, size: 22.sp, color: color ?? AppColors.primary), title: Text(title, style: AppTextStyles.bodyMedium.copyWith(color: color ?? AppColors.primary)), subtitle: subtitle != null ? Text(subtitle, style: AppTextStyles.caption) : null, trailing: onTap != null ? Icon(Icons.chevron_right, size: 20.sp, color: AppColors.grey) : null, onTap: onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)));

  static const String _privacyPolicy = '''Privacy Policy\n\nLast updated: June 2026\n\nGigsCourt ("we," "our," or "us") is committed to protecting your privacy.\n\nInformation We Collect\n- Account information: email address, display name, profile photo\n- Location data: workspace address for provider discovery\n- Usage data: app interactions, features used\n- Communication data: messages sent through the app\n\nHow We Use Your Information\n- To provide and improve our services\n- To connect clients with nearby service providers\n- To send notifications about messages, reviews, and account updates\n- To ensure platform safety and prevent fraud\n\nData Sharing\n- Your profile information is visible to other users as described in the app\n- We do not sell your personal data to third parties\n\nData Security\nWe implement appropriate security measures to protect your data.\n\nContact Us\nFor privacy-related inquiries, contact us at support@gigscourt.com''';
  static const String _termsOfService = '''Terms of Service\n\nLast updated: June 2026\n\nBy using GigsCourt, you agree to these terms.\n\n1. Account Registration\nYou must provide accurate information when creating an account.\n\n2. Provider Subscriptions\nProviders may be required to subscribe for continued visibility after reaching certain thresholds.\n\n3. User Conduct\nYou agree not to post false or misleading information, harass other users, or use the platform for illegal activities.\n\n4. Limitation of Liability\nGigsCourt is a discovery platform. We are not responsible for the quality of services provided by users.\n\n5. Termination\nWe may suspend or terminate accounts that violate these terms.\n\nContact: support@gigscourt.com''';
  static const String _earlyAccessInfo = '''About Early Access\n\nGigsCourt is currently in Early Access. During this period, all features are free for all users.\n\nWhat This Means\n- Full visibility for all providers at no cost\n- Unlimited client leads\n- All features unlocked\n\nWhat Happens Later\nWhen the platform reaches sufficient activity, a subscription model will be introduced.\n\nPricing will be announced before subscriptions go live. Thank you for being an early supporter of GigsCourt!''';
}