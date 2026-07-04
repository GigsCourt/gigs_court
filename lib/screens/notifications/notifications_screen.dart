import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isMarkingAll = false;

  IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'review':
        return Icons.star_outline;
      case 'lead_milestone':
      case 'review_milestone':
        return Icons.trending_up;
      case 'lead_limit':
      case 'review_limit':
        return Icons.warning_amber_rounded;
      case 'missed_connection':
        return Icons.person_off_outlined;
      case 'subscription_expiring':
      case 'subscription_expired':
        return Icons.card_giftcard_outlined;
      case 'early_access_ending':
        return Icons.info_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'message':
        return AppColors.primary;
      case 'review':
        return Colors.amber;
      case 'lead_milestone':
      case 'review_milestone':
        return AppColors.success;
      case 'lead_limit':
      case 'review_limit':
        return AppColors.error;
      case 'missed_connection':
        return Colors.orange;
      case 'subscription_expiring':
      case 'subscription_expired':
        return Colors.purple;
      case 'early_access_ending':
        return AppColors.primary;
      default:
        return AppColors.grey;
    }
  }

  Future<void> _markAsRead(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(docId)
          .update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _markAllAsRead(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isMarkingAll = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['read'] != true) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
    }
    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All notifications marked as read.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark all as read.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _isMarkingAll = false);
  }

  Future<void> _deleteNotification(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(docId)
          .delete();
    } catch (_) {}
  }

  void _handleTap(BuildContext context, Map<String, dynamic> notif) {
    final type = notif['type'] as String? ?? '';
    final data = notif['data'] as Map<String, dynamic>? ?? {};
    final docId = notif['_docId'] as String?;

    // Mark as read
    if (docId != null) {
      _markAsRead(docId);
    }

    switch (type) {
      case 'message':
        final chatId = data['chatId'] as String?;
        final otherUserId = data['otherUserId'] as String?;
        final otherUserName = data['otherUserName'] as String?;
        if (chatId != null && otherUserId != null) {
          context.push('/chat/$chatId', extra: {
            'otherUserId': otherUserId,
            'otherUserName': otherUserName ?? 'User',
          });
        }
        break;
      case 'review':
      case 'review_milestone':
      case 'lead_milestone':
      case 'lead_limit':
      case 'review_limit':
        final providerId = data['providerId'] as String?;
        if (providerId != null) {
          context.push('/provider/$providerId');
        } else {
          context.push('/home');
        }
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

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getDateGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This Week';
    return 'Older';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Notifications', style: AppTextStyles.headline3),
        actions: [
          if (user != null)
            _isMarkingAll
                ? Padding(
                    padding: EdgeInsets.all(16.w),
                    child: SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: () async {
                      final snapshot = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('notifications')
                          .where('read', isEqualTo: false)
                          .get();
                      if (snapshot.docs.isNotEmpty) {
                        _markAllAsRead(snapshot.docs);
                      }
                    },
                    child: Text(
                      'Read all',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
        ],
      ),
      body: user == null
          ? Center(
              child: Text('Please log in', style: AppTextStyles.bodyMedium))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: 100.h),
                        Center(
                          child: Text(
                            'Failed to load notifications.',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.grey),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final notifications = snapshot.data?.docs ?? [];
                if (notifications.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: 80.h),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 64.sp,
                                color: AppColors.primary
                                    .withValues(alpha: 0.3),
                              ),
                              SizedBox(height: 16.h),
                              Text(
                                'No notifications yet',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                'When you receive messages, reviews,\nor updates, they\'ll appear here.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Group by date
                final grouped = <String, List<QueryDocumentSnapshot>>{};
                for (final doc in notifications) {
                  final data = doc.data() as Map<String, dynamic>;
                  final ts = data['createdAt'] as Timestamp?;
                  final date = ts?.toDate() ?? DateTime.now();
                  final group = _getDateGroup(date);
                  grouped.putIfAbsent(group, () => []).add(doc);
                }

                final groupOrder = ['Today', 'Yesterday', 'This Week', 'Older'];
                final keys = grouped.keys.toList()
                  ..sort((a, b) => groupOrder.indexOf(a).compareTo(groupOrder.indexOf(b)));

                final items = <Widget>[];
                for (final key in keys) {
                  items.add(
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      child: Text(
                        key,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                  for (final doc in grouped[key]!) {
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] as String? ?? '';
                    final title = data['title'] as String? ?? '';
                    final body = data['body'] as String? ?? '';
                    final read = data['read'] as bool? ?? false;
                    final createdAt = data['createdAt'] as Timestamp?;

                    items.add(
                      Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.only(right: 20.w),
                          color: AppColors.error,
                          child: Icon(Icons.delete_outline,
                              color: AppColors.white, size: 20.sp),
                        ),
                        onDismissed: (_) => _deleteNotification(doc.id),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 4.h),
                          leading: Container(
                            width: 44.w,
                            height: 44.w,
                            decoration: BoxDecoration(
                              color: _colorForType(type)
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_iconForType(type),
                                size: 20.sp, color: _colorForType(type)),
                          ),
                          title: Text(
                            title,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontWeight:
                                  read ? FontWeight.w400 : FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 2.h),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                _formatTime(createdAt),
                                style: AppTextStyles.caption
                                    .copyWith(fontSize: 10.sp),
                              ),
                            ],
                          ),
                          tileColor: read
                              ? Colors.transparent
                              : AppColors.primary.withValues(alpha: 0.02),
                          onTap: () => _handleTap(
                            context,
                            {...data, '_docId': doc.id},
                          ),
                        ),
                      ),
                    );
                  }
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    // StreamBuilder auto-refreshes, but this gives visual feedback
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: items,
                  ),
                );
              },
            ),
    );
  }
}
