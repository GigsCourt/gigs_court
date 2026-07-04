import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _onlineListeners = {};

  @override
  void dispose() {
    _searchController.dispose();
    for (final listener in _onlineListeners.values) {
      listener.cancel();
    }
    _onlineListeners.clear();
    super.dispose();
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }

  Future<void> _fetchUsers(List<String> userIds) async {
    final uncached = userIds.where((id) => !_userCache.containsKey(id)).toList();
    if (uncached.isEmpty) return;
    final futures = uncached.map((id) => FirebaseFirestore.instance.collection('users').doc(id).get());
    final docs = await Future.wait(futures);
    bool hasNew = false;
    for (int i = 0; i < uncached.length; i++) {
      if (docs[i].exists) {
        _userCache[uncached[i]] = docs[i].data()!;
        _startOnlineListener(uncached[i]);
        hasNew = true;
      }
    }
    if (hasNew && mounted) {
      setState(() {});
    }
  }

  void _startOnlineListener(String userId) {
    if (_onlineListeners.containsKey(userId)) return;
    _onlineListeners[userId] = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data();
      if (data != null) {
        final currentData = _userCache[userId];
        if (currentData != null &&
            (currentData['isOnline'] != data['isOnline'] ||
             currentData['lastSeen'] != data['lastSeen'])) {
          setState(() {
            _userCache[userId] = data;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(backgroundColor: AppColors.background, body: Center(child: Text('Please log in', style: AppTextStyles.bodyMedium)));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Messages', style: AppTextStyles.headline3)),
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: TextField(controller: _searchController, onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()), style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: 'Search conversations...', hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)), prefixIcon: Icon(Icons.search, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.5)))),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: _currentUser.uid).orderBy('lastMessageAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var chats = snapshot.data!.docs;
              if (chats.isEmpty) {
                return Center(child: Text('No messages yet.\nFind a provider and start chatting.', textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))));
              }

              final otherUserIds = <String>{};
              for (final chat in chats) {
                final data = chat.data() as Map<String, dynamic>;
                final participants = List<String>.from(data['participants'] ?? []);
                final otherId = participants.firstWhere((id) => id != _currentUser.uid, orElse: () => '');
                if (otherId.isNotEmpty) otherUserIds.add(otherId);
              }

              _fetchUsers(otherUserIds.toList());

              return ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  final data = chat.data() as Map<String, dynamic>;
                  final participants = List<String>.from(data['participants'] ?? []);
                  final otherUserId = participants.firstWhere((id) => id != _currentUser.uid, orElse: () => '');
                  final userData = _userCache[otherUserId];
                  final name = userData?['displayName'] ?? userData?['name'] ?? 'Unknown';
                  final photoUrl = userData?['profileImage'] ?? userData?['photoUrl'];
                  final isOnline = userData?['isOnline'] ?? false;

                  final lastMessage = data['lastMessage'] ?? '';
                  final lastMessageType = data['lastMessageType'] ?? 'text';
                  final lastMessageAt = data['lastMessageAt'] as Timestamp?;
                  final isTyping = data['typing_$otherUserId'] == true;
                  final unreadMap = data['unreadCount'] as Map<String, dynamic>?;
                  final unreadCount = unreadMap?[_currentUser.uid] ?? 0;

                  if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery)) {
                    return const SizedBox.shrink();
                  }

                  final preview = lastMessageType == 'image' ? '📷 Photo' : lastMessageType == 'voice' ? '🎤 Voice note' : lastMessage.toString();

                  return ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                    leading: Stack(children: [
                      ClipRRect(borderRadius: BorderRadius.circular(24.r), child: SizedBox(width: 48.w, height: 48.w, child: photoUrl != null && photoUrl.toString().isNotEmpty ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover) : Container(color: AppColors.primary.withValues(alpha: 0.06), child: Icon(Icons.person, color: AppColors.primary.withValues(alpha: 0.3))))),
                      Positioned(bottom: 0, right: 0, child: Container(width: 14.w, height: 14.w, decoration: BoxDecoration(color: isOnline ? AppColors.success : AppColors.grey, shape: BoxShape.circle, border: Border.all(color: AppColors.background, width: 2)))),
                    ]),
                    title: Text(name, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(isTyping ? 'typing...' : preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: isTyping ? AppColors.primary : AppColors.grey, fontWeight: isTyping ? FontWeight.w600 : FontWeight.w400)),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(_formatTime(lastMessageAt), style: AppTextStyles.caption.copyWith(fontSize: 10.sp)),
                      if (unreadCount > 0) ...[SizedBox(height: 4.h), Container(padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12.r)), child: Text('$unreadCount', style: TextStyle(color: AppColors.white, fontSize: 11.sp, fontWeight: FontWeight.w600)))],
                    ]),
                    onTap: () => context.push('/chat/${chat.id}', extra: {'otherUserId': otherUserId, 'otherUserName': name}),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}