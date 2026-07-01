import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'review': return Icons.star_outline;
      case 'lead_milestone':
      case 'review_milestone':
        return Icons.trending_up;
      case 'lead_limit':
      case 'review_limit':
        return Icons.warning_amber_rounded;
      case 'missed_connection': return Icons.person_off_outlined;
      case 'subscription_expiring':
      case 'subscription_expired':
        return Icons.card_giftcard_outlined;
      case 'early_access_ending': return Icons.info_outline;
      default: return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'message': return AppColors.primary;
      case 'review': return Colors.amber;
      case 'lead_milestone':
      case 'review_milestone':
        return AppColors.success;
      case 'lead_limit':
      case 'review_limit':
        return AppColors.error;
      case 'missed_connection': return Colors.orange;
      case 'subscription_expiring':
      case 'subscription_expired':
        return Colors.purple;
      case 'early_access_ending': return AppColors.primary;
      default: return AppColors.grey;
    }
  }

  void _handleTap(BuildContext context, Map<String, dynamic> notif) {
    final type = notif['type'] as String? ?? '';
    final data = notif['data'] as Map<String, dynamic>? ?? {};

    // Mark as read
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && notif['id'] != null) {
      FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('notifications').doc(notif['id'])
          .update({'read': true});
    }

    switch (type) {
      case 'message':
        final chatId = data['chatId'] as String?;
        final otherUserId = data['otherUserId'] as String?;
        final otherUserName = data['otherUserName'] as String?;
        if (chatId != null && otherUserId != null) {
          context.push('/chat/$chatId', extra: {'otherUserId': otherUserId, 'otherUserName': otherUserName ?? 'User'});
        }
        break;
      case 'review':
      case 'review_milestone':
      case 'lead_milestone':
      case 'lead_limit':
      case 'review_limit':
        context.push('/home');
        break;
      case 'missed_connection':
      case 'subscription_expiring':
      case 'subscription_expired':
        context.push('/subscription');
        break;
      case 'early_access_ending':
      default:
        break;
    }
  }

  String _formatTime(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Notifications', style: AppTextStyles.headline3),
      ),
      body: user == null
          ? Center(child: Text('Please log in', style: AppTextStyles.bodyMedium))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(user.uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final notifications = snapshot.data!.docs;
                if (notifications.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.notifications_none, size: 64.sp, color: AppColors.primary.withValues(alpha: 0.3)),
                      SizedBox(height: 16.h),
                      Text('No notifications yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))),
                    ]),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 72.w),
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] as String? ?? '';
                    final title = data['title'] as String? ?? '';
                    final body = data['body'] as String? ?? '';
                    final read = data['read'] as bool? ?? false;
                    final createdAt = data['createdAt'] as Timestamp?;

                    return ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                      leading: Container(
                        width: 44.w, height: 44.w,
                        decoration: BoxDecoration(
                          color: _colorForType(type).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconForType(type), size: 20.sp, color: _colorForType(type)),
                      ),
                      title: Text(title, style: AppTextStyles.bodySmall.copyWith(fontWeight: read ? FontWeight.w400 : FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(height: 2.h),
                        Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                        SizedBox(height: 4.h),
                        Text(createdAt != null ? _formatTime(createdAt) : '', style: AppTextStyles.caption.copyWith(fontSize: 10.sp)),
                      ]),
                      tileColor: read ? Colors.transparent : AppColors.primary.withValues(alpha: 0.02),
                      onTap: () => _handleTap(context, {...data, 'id': doc.id}),
                    );
                  },
                );
              },
            ),
    );
  }
}