import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';

class ReviewsScreen extends StatelessWidget {
  final String providerId;

  const ReviewsScreen({super.key, required this.providerId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Reviews', style: AppTextStyles.headline3)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reviews')
            .where('providerId', isEqualTo: providerId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allReviews = snapshot.data!.docs;
          if (allReviews.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.star_outline, size: 64.sp, color: AppColors.primary.withValues(alpha: 0.3)),
                SizedBox(height: 16.h),
                Text('No reviews yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))),
              ]),
            );
          }

          double totalRating = 0;
          for (final doc in allReviews) {
            totalRating += (doc['rating'] as num).toDouble();
          }
          final avgRating = totalRating / allReviews.length;

          final seenClients = <String>{};
          final latestReviews = <QueryDocumentSnapshot>[];
          for (final doc in allReviews) {
            final clientId = doc['clientId'] as String;
            if (!seenClients.contains(clientId)) {
              seenClients.add(clientId);
              latestReviews.add(doc);
            }
          }

          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.star, color: Colors.amber, size: 28.sp),
                  SizedBox(width: 8.w),
                  Text(avgRating.toStringAsFixed(1), style: AppTextStyles.headline2),
                  SizedBox(width: 8.w),
                  Text('(${allReviews.length} reviews)', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)),
                ]),
              ),
              SizedBox(height: 16.h),
              ...latestReviews.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final clientName = data['clientName'] ?? 'Client';
                final rating = (data['rating'] as num).toDouble();
                final comment = data['comment'] ?? '';
                final createdAt = data['createdAt'] as Timestamp?;
                final clientId = data['clientId'] as String;

                return Container(
                  margin: EdgeInsets.only(bottom: 12.h),
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 36.w, height: 36.w,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
                        child: Icon(Icons.person, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(child: Text(clientName, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
                      Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, size: 16.sp, color: Colors.amber))),
                    ]),
                    if (comment.isNotEmpty) ...[SizedBox(height: 8.h), Text(comment, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7)))],
                    SizedBox(height: 8.h),
                    Row(children: [
                      Text(_formatDate(createdAt), style: AppTextStyles.caption),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _ClientReviewsScreen(providerId: providerId, clientId: clientId, clientName: clientName),
                        )),
                        child: Text('See all reviews', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ]),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _ClientReviewsScreen extends StatelessWidget {
  final String providerId;
  final String clientId;
  final String clientName;

  const _ClientReviewsScreen({required this.providerId, required this.clientId, required this.clientName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text("$clientName's Reviews", style: AppTextStyles.headline3)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reviews')
            .where('providerId', isEqualTo: providerId)
            .where('clientId', isEqualTo: clientId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final reviews = snapshot.data!.docs;
          if (reviews.isEmpty) return Center(child: Text('No reviews', style: AppTextStyles.bodyMedium));

          return ListView.builder(
            padding: EdgeInsets.all(16.w),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final data = reviews[index].data() as Map<String, dynamic>;
              final rating = (data['rating'] as num).toDouble();
              final comment = data['comment'] ?? '';
              final createdAt = data['createdAt'] as Timestamp?;

              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, size: 16.sp, color: Colors.amber))),
                  if (comment.isNotEmpty) ...[SizedBox(height: 8.h), Text(comment, style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary.withValues(alpha: 0.7)))],
                  SizedBox(height: 8.h),
                  Text(_formatDate(createdAt), style: AppTextStyles.caption),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }
}