import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart' as app_auth;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _isEarlyAccess = true;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = context.read<app_auth.AuthProvider>().isEarlyAccess;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists && mounted) {
      setState(() => _pushNotifications = doc.data()?['pushNotifications'] ?? true);
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    setState(() => _pushNotifications = value);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'pushNotifications': value});
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset email sent.'), backgroundColor: AppColors.success));
    }
  }

  Future<void> _logOut() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'isOnline': false, 'lastSeen': FieldValue.serverTimestamp()});
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/onboarding');
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete Account', style: AppTextStyles.bodyLarge), content: Text('Your account will be permanently deleted. This action cannot be undone. All your data including messages, reviews, and profile will be removed.', style: AppTextStyles.bodyMedium), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (confirm != true) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final notifs = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in notifs.docs) { batch.delete(doc.reference); }
      final chats = await FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: user.uid).get();
      for (final chat in chats.docs) {
        final messages = await chat.reference.collection('messages').get();
        for (final msg in messages.docs) { batch.delete(msg.reference); }
        batch.delete(chat.reference);
      }
      final reviewsGiven = await FirebaseFirestore.instance.collection('reviews').where('clientId', isEqualTo: user.uid).get();
      for (final doc in reviewsGiven.docs) { batch.delete(doc.reference); }
      final reviewsReceived = await FirebaseFirestore.instance.collection('reviews').where('providerId', isEqualTo: user.uid).get();
      for (final doc in reviewsReceived.docs) { batch.delete(doc.reference); }
      batch.delete(FirebaseFirestore.instance.collection('users').doc(user.uid));
      await batch.commit();

      // Check if user was subscribed to decrement counter
      final userData = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final wasSubscribed = userData.data()?['isSubscribed'] == true;

      final configUpdate = <String, dynamic>{
        'totalUsers': FieldValue.increment(-1),
      };
      if (wasSubscribed) {
        configUpdate['totalSubscribers'] = FieldValue.increment(-1);
      }
      await FirebaseFirestore.instance.collection('app_config').doc('global').set(configUpdate, SetOptions(merge: true));
      
      await user.delete();
      if (mounted) context.go('/onboarding');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete account. Please try again.'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _helpAndSupport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tickets').add({
      'type': 'support',
      'submittedBy': user.uid,
      'subject': 'Help & Support',
      'message': 'User requested support.',
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Support ticket created. We will get back to you.'), backgroundColor: AppColors.success));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Settings', style: AppTextStyles.headline3)), body: ListView(padding: EdgeInsets.all(16.w), children: [
      _buildSection('Account'),
      _buildTile(Icons.email_outlined, 'Email', subtitle: user?.email ?? ''),
      _buildTile(Icons.lock_outline, 'Change Password', onTap: _changePassword),
      SizedBox(height: 20.h),
      _buildSection('Notifications'),
      _buildSwitchTile('Push Notifications', _pushNotifications, _togglePushNotifications),
      SizedBox(height: 20.h),
      _buildSection('About'),
      _buildTile(Icons.description_outlined, 'Privacy Policy', onTap: () => _showLegal('Privacy Policy', _privacyPolicy)),
      _buildTile(Icons.article_outlined, 'Terms of Service', onTap: () => _showLegal('Terms of Service', _termsOfService)),
      if (_isEarlyAccess) _buildTile(Icons.info_outline, 'About Early Access', onTap: () => _showLegal('Early Access', _earlyAccessInfo)),
      _buildTile(Icons.info_outline, 'App Version', subtitle: '1.0.0'),
      SizedBox(height: 20.h),
      _buildSection('Support'),
      _buildTile(Icons.support_outlined, 'Help & Support', onTap: _helpAndSupport),
      SizedBox(height: 20.h),
      _buildTile(Icons.logout, 'Log Out', onTap: _logOut),
      SizedBox(height: 8.h),
      _buildTile(Icons.delete_outline, 'Delete Account', color: AppColors.error, onTap: _deleteAccount),
      SizedBox(height: 40.h),
    ]));
  }

  void _showLegal(String title, String content) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text(title, style: AppTextStyles.headline3)), body: SingleChildScrollView(padding: EdgeInsets.all(20.w), child: Text(content, style: AppTextStyles.bodyMedium.copyWith(height: 1.6))))));
  }

  Widget _buildSection(String title) => Padding(padding: EdgeInsets.only(bottom: 8.h), child: Text(title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey, fontWeight: FontWeight.w600)));
  Widget _buildTile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Color? color}) => ListTile(contentPadding: EdgeInsets.symmetric(horizontal: 4.w), leading: Icon(icon, size: 22.sp, color: color ?? AppColors.primary), title: Text(title, style: AppTextStyles.bodyMedium.copyWith(color: color ?? AppColors.primary)), subtitle: subtitle != null ? Text(subtitle, style: AppTextStyles.caption) : null, trailing: onTap != null ? Icon(Icons.chevron_right, size: 20.sp, color: AppColors.grey) : null, onTap: onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)));
  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) => SwitchListTile(contentPadding: EdgeInsets.symmetric(horizontal: 4.w), title: Text(title, style: AppTextStyles.bodyMedium), value: value, onChanged: onChanged, activeTrackColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)));

  static const String _privacyPolicy = '''Privacy Policy\n\nLast updated: June 2026\n\nGigsCourt ("we," "our," or "us") is committed to protecting your privacy.\n\nInformation We Collect\n- Account information: email address, display name, profile photo\n- Location data: workspace address for provider discovery\n- Usage data: app interactions, features used\n- Communication data: messages sent through the app\n\nHow We Use Your Information\n- To provide and improve our services\n- To connect clients with nearby service providers\n- To send notifications about messages, reviews, and account updates\n- To ensure platform safety and prevent fraud\n\nData Sharing\n- Your profile information is visible to other users as described in the app\n- We do not sell your personal data to third parties\n\nData Security\nWe implement appropriate security measures to protect your data.\n\nContact Us\nFor privacy-related inquiries, contact us at support@gigscourt.com''';
  static const String _termsOfService = '''Terms of Service\n\nLast updated: June 2026\n\nBy using GigsCourt, you agree to these terms.\n\n1. Account Registration\nYou must provide accurate information when creating an account.\n\n2. Provider Subscriptions\nProviders may be required to subscribe for continued visibility after reaching certain thresholds.\n\n3. User Conduct\nYou agree not to post false or misleading information, harass other users, or use the platform for illegal activities.\n\n4. Limitation of Liability\nGigsCourt is a discovery platform. We are not responsible for the quality of services provided by users.\n\n5. Termination\nWe may suspend or terminate accounts that violate these terms.\n\nContact: support@gigscourt.com''';
  static const String _earlyAccessInfo = '''About Early Access\n\nGigsCourt is currently in Early Access. During this period, all features are free for all users.\n\nWhat This Means\n- Full visibility for all providers at no cost\n- Unlimited client leads\n- All features unlocked\n\nWhat Happens Later\nWhen the platform reaches sufficient activity, a subscription model will be introduced.\n\nPricing will be announced before subscriptions go live. Thank you for being an early supporter of GigsCourt!''';
}
