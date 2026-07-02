import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart' as app_auth;

class ProviderProfileScreen extends StatefulWidget {
  final String providerId;
  const ProviderProfileScreen({super.key, required this.providerId});
  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _services = [];
  List<String> _workPhotos = [];
  bool _isLoading = true;
  bool _isSaved = false;
  double? _distanceKm;
  bool _isDistanceLoading = false;
  String _providerAddress = '';
  bool _isEarlyAccess = true;

  @override
  void initState() {
    super.initState();
    _isEarlyAccess = context.read<app_auth.AuthProvider>().isEarlyAccess;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.providerId).get();
      if (!userDoc.exists) { setState(() => _isLoading = false); return; }
      final userData = userDoc.data()!;
      final serviceIds = List<int>.from(userData['services'] ?? []);
      List<Map<String, dynamic>> services = [];
      if (serviceIds.isNotEmpty) {
        try {
          final namesData = await _supabase.rpc('get_service_names', params: {'p_service_ids': serviceIds});
          services = List<Map<String, dynamic>>.from(namesData);
        } catch (_) {}
      }
      bool isSaved = false;
      if (_currentUser != null) {
        final savedDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).get();
        if (savedDoc.exists) {
          final savedProviders = List<String>.from(savedDoc.data()?['savedProviders'] ?? []);
          isSaved = savedProviders.contains(widget.providerId);
        }
      }
      setState(() { _userData = userData; _services = services; _workPhotos = List<String>.from(userData['workPhotos'] ?? []); _isSaved = isSaved; _isLoading = false; });
      _loadDistance();
    } catch (e) { setState(() => _isLoading = false); }
  }

  Future<void> _loadDistance() async {
    setState(() => _isDistanceLoading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _isDistanceLoading = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)));
      final result = await _supabase.rpc('find_all_providers', params: {'p_lat': position.latitude, 'p_lng': position.longitude});
      final providers = List<Map<String, dynamic>>.from(result);
      final match = providers.where((p) => p['provider_id'] == widget.providerId).firstOrNull;
      if (match != null) {
        setState(() { _distanceKm = (match['distance_meters'] as num) / 1000.0; });
      }
      final locationData = await _supabase.from('provider_locations').select('address').eq('provider_id', widget.providerId).maybeSingle();
      if (locationData != null && mounted) {
        setState(() { _providerAddress = locationData['address'] ?? ''; });
      }
    } catch (_) {}
    setState(() => _isDistanceLoading = false);
  }

  Future<void> _toggleSave() async {
    if (_currentUser == null) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);
    setState(() => _isSaved = !_isSaved);
    try {
      if (_isSaved) await userRef.update({'savedProviders': FieldValue.arrayUnion([widget.providerId])});
      else await userRef.update({'savedProviders': FieldValue.arrayRemove([widget.providerId])});
    } catch (_) { setState(() => _isSaved = !_isSaved); }
  }

  Future<void> _startChat() async {
    if (_currentUser == null) return;
    final existingChat = await FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: _currentUser.uid).get();
    String? existingChatId;
    for (final doc in existingChat.docs) {
      final participants = List<String>.from(doc.data()['participants'] ?? []);
      if (participants.contains(widget.providerId)) { existingChatId = doc.id; break; }
    }
    if (existingChatId != null) {
      if (mounted) context.push('/chat/$existingChatId', extra: {'otherUserId': widget.providerId, 'otherUserName': _userData?['displayName'] ?? _userData?['name'] ?? 'Unknown'});
      return;
    }
    if (!mounted) return;
    final shouldProceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Important', style: AppTextStyles.bodyLarge), content: Text('Don\'t pay any provider you haven\'t seen or trust.', style: AppTextStyles.bodyMedium), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('I Understand', style: TextStyle(color: AppColors.primary)))]));
    if (shouldProceed != true || !mounted) return;
    final chatRef = await FirebaseFirestore.instance.collection('chats').add({'participants': [_currentUser.uid, widget.providerId], 'lastMessage': '', 'lastMessageAt': FieldValue.serverTimestamp(), 'unreadCount': <String, int>{}});

    // Increment total chats counter (only for new chats, not existing)
    await FirebaseFirestore.instance.collection('app_config').doc('global').set({
      'totalChats': FieldValue.increment(1),
    }, SetOptions(merge: true));

    if (!_isEarlyAccess) {
      final existingLeads = await FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: widget.providerId).get();
      final uniqueClients = <String>{};
      for (final doc in existingLeads.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        uniqueClients.addAll(participants.where((id) => id != widget.providerId));
      }
      await FirebaseFirestore.instance.collection('users').doc(widget.providerId).update({'leadCount': uniqueClients.length});
      _sendLeadNotification(widget.providerId, uniqueClients.length);
    }

    if (!mounted) return;
    context.push('/chat/${chatRef.id}', extra: {'otherUserId': widget.providerId, 'otherUserName': _userData?['displayName'] ?? _userData?['name'] ?? 'Unknown'});
  }

  Future<void> _rateProvider() async {
    int rating = 0;
    final commentController = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(title: Text('Rate & Review', style: AppTextStyles.bodyLarge), content: Column(mainAxisSize: MainAxisSize.min, children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(icon: Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36.sp), onPressed: () => setDialogState(() => rating = i + 1)))), SizedBox(height: 12.h), TextField(controller: commentController, maxLines: 3, decoration: InputDecoration(hintText: 'Share your experience (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r))))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () { if (rating > 0) Navigator.pop(ctx, true); }, child: Text('Submit', style: TextStyle(color: AppColors.primary)))])));
    if (result != true || rating == 0 || _currentUser == null) return;
    final existingReview = await FirebaseFirestore.instance.collection('reviews').where('providerId', isEqualTo: widget.providerId).where('clientId', isEqualTo: _currentUser.uid).get();
    if (existingReview.docs.isNotEmpty) {
      await existingReview.docs.first.reference.update({'rating': rating, 'comment': commentController.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await FirebaseFirestore.instance.collection('reviews').add({'providerId': widget.providerId, 'clientId': _currentUser.uid, 'clientName': _currentUser.displayName ?? 'Client', 'rating': rating, 'comment': commentController.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
    }
    final allReviews = await FirebaseFirestore.instance.collection('reviews').where('providerId', isEqualTo: widget.providerId).get();
    double totalRating = 0;
    for (final doc in allReviews.docs) { totalRating += (doc.data()['rating'] as num).toDouble(); }
    final avgRating = allReviews.docs.isEmpty ? 0.0 : totalRating / allReviews.docs.length;
    await FirebaseFirestore.instance.collection('users').doc(widget.providerId).update({'rating': avgRating, 'reviewCount': allReviews.docs.length, 'lastReviewedAt': FieldValue.serverTimestamp()});
    if (!_isEarlyAccess) _sendReviewNotification(widget.providerId, allReviews.docs.length);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review submitted. Thank you!'), backgroundColor: AppColors.success));
  }

  Future<void> _reportProvider() async {
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text('Report Provider', style: AppTextStyles.bodyLarge), content: Text('Why are you reporting this provider?', style: AppTextStyles.bodyMedium), actions: [TextButton(onPressed: () => Navigator.pop(ctx, 'Inappropriate content'), child: const Text('Inappropriate')), TextButton(onPressed: () => Navigator.pop(ctx, 'Fake profile'), child: const Text('Fake Profile')), TextButton(onPressed: () => Navigator.pop(ctx, 'Other'), child: const Text('Other'))]));
    if (reason != null && _currentUser != null) {
      await FirebaseFirestore.instance.collection('users').doc(widget.providerId).collection('tickets').add({'type': 'report', 'submittedBy': _currentUser.uid, 'targetUserId': widget.providerId, 'subject': reason, 'message': '', 'status': 'pending', 'createdAt': FieldValue.serverTimestamp(), 'resolvedAt': null});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report submitted. Thank you.'), backgroundColor: AppColors.success));
    }
  }

  Future<void> _sendLeadNotification(String providerId, int leadCount) async {
    final milestones = {1: 'First Lead! 🎉', 5: '5 Leads Used', 8: 'Almost There', 10: 'Limit Reached'};
    final bodies = {1: 'Someone just contacted you. You have 9 free leads remaining.', 5: 'You\'re halfway through your free leads. 5 remaining.', 8: 'You\'ve used 8 of 10 free leads. 2 remaining before you need to subscribe.', 10: 'You\'ve used all 10 free leads. Subscribe to GigsCourt Premium to continue receiving clients.'};
    if (milestones.containsKey(leadCount)) {
      await FirebaseFirestore.instance.collection('users').doc(providerId).collection('notifications').add({'type': leadCount >= 10 ? 'lead_limit' : 'lead_milestone', 'title': milestones[leadCount]!, 'body': bodies[leadCount]!, 'read': false, 'data': {}, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _sendReviewNotification(String providerId, int reviewCount) async {
    final milestones = {1: 'First Review! ⭐', 3: '3 Reviews Received', 5: 'Review Milestone Reached'};
    final bodies = {1: 'A client left you a review. You now have 1 of 5 reviews needed for free tier.', 3: 'You\'re over halfway. 2 more reviews before you need to subscribe.', 5: 'You\'ve received 5 reviews. Subscribe to GigsCourt Premium to keep your profile visible.'};
    if (milestones.containsKey(reviewCount)) {
      await FirebaseFirestore.instance.collection('users').doc(providerId).collection('notifications').add({'type': reviewCount >= 5 ? 'review_limit' : 'review_milestone', 'title': milestones[reviewCount]!, 'body': bodies[reviewCount]!, 'read': false, 'data': {}, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  void _viewPhoto(int index) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: IconThemeData(color: Colors.white)), body: PageView.builder(controller: PageController(initialPage: index), itemCount: _workPhotos.length, itemBuilder: (_, i) => Center(child: Image.network(_workPhotos[i], fit: BoxFit.contain))))));
  }

  String _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Offline';
    final date = (lastSeen as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_userData == null) return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(), body: Center(child: Text('Provider not found.', style: AppTextStyles.bodyMedium)));
    final name = _userData!['displayName'] ?? _userData!['name'] ?? 'Unknown';
    final photoUrl = _userData!['profileImage'] ?? _userData!['photoUrl'];
    final bio = _userData!['bio'] ?? '';
    final isSubscribed = _userData!['isSubscribed'] == true;
    final showBadge = _isEarlyAccess || isSubscribed;
    final isOnline = _userData!['isOnline'] ?? false;
    final lastSeen = _userData!['lastSeen'];
    final rating = (_userData!['rating'] ?? _userData!['averageRating'] ?? 0.0).toDouble();
    final reviewCount = _userData!['reviewCount'] ?? 0;
    final isOwnProfile = _currentUser?.uid == widget.providerId;
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text(name, style: AppTextStyles.headline3), actions: [if (!isOwnProfile) IconButton(icon: Icon(Icons.flag_outlined, size: 20.sp), tooltip: 'Report', onPressed: _reportProvider)]), body: SingleChildScrollView(padding: EdgeInsets.all(20.w), child: Column(children: [
      Center(child: ClipRRect(borderRadius: BorderRadius.circular(80.r), child: SizedBox(width: 140.w, height: 140.w, child: photoUrl != null && photoUrl.toString().isNotEmpty ? Image.network(photoUrl, fit: BoxFit.cover) : Container(color: AppColors.primary.withValues(alpha: 0.06), child: Icon(Icons.person, size: 60.sp, color: AppColors.primary.withValues(alpha: 0.3)))))),
      SizedBox(height: 16.h),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: Text(name, style: AppTextStyles.headline2, overflow: TextOverflow.ellipsis)), if (showBadge) ...[SizedBox(width: 6.w), Icon(Icons.verified, size: 20.sp, color: Color(0xFF2196F3))]]),
      SizedBox(height: 4.h),
      if (showBadge) Row(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: isOnline ? AppColors.success : AppColors.grey, shape: BoxShape.circle)), SizedBox(width: 4.w), Text(isOnline ? 'Online now' : _formatLastSeen(lastSeen), style: AppTextStyles.bodySmall.copyWith(color: isOnline ? AppColors.success : AppColors.grey))]),
      SizedBox(height: 16.h),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_buildStat(rating.toStringAsFixed(1), 'Rating'), _buildDivider(), GestureDetector(onTap: () => context.push('/reviews/${widget.providerId}'), child: _buildStat('$reviewCount', 'Reviews'))]),
      SizedBox(height: 20.h),
      if (bio.isNotEmpty) ...[Text(bio, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)), SizedBox(height: 16.h)],
      if (_services.isNotEmpty) ...[Text('Services', style: AppTextStyles.bodyLarge), SizedBox(height: 8.h), Wrap(alignment: WrapAlignment.center, spacing: 8.w, runSpacing: 8.h, children: _services.map((s) => Chip(label: Text(s['name'] ?? '', style: AppTextStyles.bodySmall), backgroundColor: AppColors.primary.withValues(alpha: 0.08), side: BorderSide.none)).toList()), SizedBox(height: 16.h)],
      if (_providerAddress.isNotEmpty) ...[Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_on_outlined, size: 16.sp, color: AppColors.primary.withValues(alpha: 0.5)), SizedBox(width: 4.w), Flexible(child: Text(_providerAddress, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7)), textAlign: TextAlign.center))]), SizedBox(height: 8.h)],
      if (_isDistanceLoading) Text('Calculating distance...', style: AppTextStyles.caption) else if (_distanceKm != null) Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.straighten, size: 16.sp, color: AppColors.primary.withValues(alpha: 0.5)), SizedBox(width: 4.w), Text('${_distanceKm!.toStringAsFixed(1)} km away', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7)))]),
      SizedBox(height: 20.h),
      if (!isOwnProfile) ...[Row(children: [Expanded(child: SizedBox(height: 48.h, child: ElevatedButton(onPressed: _startChat, child: Text('Chat', style: AppTextStyles.button)))), SizedBox(width: 8.w), Expanded(child: SizedBox(height: 48.h, child: OutlinedButton(onPressed: _toggleSave, style: OutlinedButton.styleFrom(side: BorderSide(color: _isSaved ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3)), backgroundColor: _isSaved ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))), child: Text(_isSaved ? 'Saved' : 'Save', style: AppTextStyles.button.copyWith(color: AppColors.primary)))))]), SizedBox(height: 8.h), SizedBox(width: double.infinity, height: 48.h, child: OutlinedButton(onPressed: _rateProvider, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.amber), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.star, color: Colors.amber, size: 18.sp), SizedBox(width: 6.w), Text('Rate Provider', style: AppTextStyles.button.copyWith(color: Colors.amber))]))), SizedBox(height: 24.h)],
      if (_workPhotos.isNotEmpty) ...[Text('Work Photos', style: AppTextStyles.bodyLarge), SizedBox(height: 8.h), GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4.w, mainAxisSpacing: 4.h), itemCount: _workPhotos.length, itemBuilder: (context, index) => GestureDetector(onTap: () => _viewPhoto(index), child: ClipRRect(borderRadius: BorderRadius.circular(8.r), child: Image.network(_workPhotos[index], fit: BoxFit.cover))))],
    ])));
  }

  Widget _buildStat(String value, String label) => Column(children: [Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)), Text(label, style: AppTextStyles.caption)]);
  Widget _buildDivider() => Container(height: 24.h, width: 1.w, color: AppColors.primary.withValues(alpha: 0.15), margin: EdgeInsets.symmetric(horizontal: 16.w));
}