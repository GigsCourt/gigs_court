import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _userSearchController = TextEditingController();
  int _selectedSection = 0;

  final _sections = [
    {'title': 'Overview', 'icon': Icons.dashboard_outlined},
    {'title': 'Reports', 'icon': Icons.flag_outlined},
    {'title': 'Subscriptions', 'icon': Icons.subscriptions_outlined},
    {'title': 'Users', 'icon': Icons.people_outlined},
  ];

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_sections[_selectedSection]['title'] as String, style: AppTextStyles.headline3)),
      body: _buildSection(),
      bottomNavigationBar: Container(
        height: 64.h,
        decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.primary.withValues(alpha: 0.08)))),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
          itemCount: _sections.length,
          itemBuilder: (context, index) {
            final isSelected = _selectedSection == index;
            return GestureDetector(
              onTap: () => setState(() => _selectedSection = index),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                margin: EdgeInsets.symmetric(horizontal: 2.w),
                decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(12.r)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_sections[index]['icon'] as IconData, size: 20.sp, color: isSelected ? AppColors.white : AppColors.grey),
                  SizedBox(height: 2.h),
                  Text(_sections[index]['title'] as String, style: TextStyle(fontSize: 10.sp, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? AppColors.white : AppColors.grey)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection() {
    switch (_selectedSection) {
      case 0: return _buildOverview();
      case 1: return _buildReports();
      case 2: return _buildSubscriptions();
      case 3: return _buildUsers();
      default: return const SizedBox();
    }
  }

  Widget _buildOverview() {
    return FutureBuilder<Map<String, int>>(
      future: _loadOverviewStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {'users': 0, 'subscribers': 0, 'revenue': 0, 'signups': 0, 'chats': 0, 'reports': 0};
        return ListView(padding: EdgeInsets.all(16.w), children: [
          GridView.count(shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 12.w, mainAxisSpacing: 12.h, childAspectRatio: 1.3, physics: const NeverScrollableScrollPhysics(), children: [
            _buildStatCard('Total Users', '${stats['users']}', Icons.people, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserAnalyticsScreen()))),
            _buildStatCard('Subscribers', '${stats['subscribers']}', Icons.verified, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SubscriberAnalyticsScreen()))),
            _buildStatCard('Revenue', 'NGN ${stats['revenue']}', Icons.payments, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _RevenueAnalyticsScreen()))),
            _buildStatCard('New Today', '${stats['signups']}', Icons.person_add, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SignupAnalyticsScreen()))),
            _buildStatCard('Active Chats', '${stats['chats']}', Icons.chat_bubble, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ChatAnalyticsScreen()))),
            _buildStatCard('Reports', '${stats['reports']}', Icons.flag, () => setState(() => _selectedSection = 1)),
          ]),
        ]);
      },
    );
  }

  Future<Map<String, int>> _loadOverviewStats() async {
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').count().get();
      final subsSnap = await FirebaseFirestore.instance.collection('users').where('isSubscribed', isEqualTo: true).count().get();
      final reportsSnap = await FirebaseFirestore.instance.collectionGroup('tickets').where('status', isEqualTo: 'pending').count().get();
      final chatsSnap = await FirebaseFirestore.instance.collection('chats').count().get();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final signupsSnap = await FirebaseFirestore.instance.collection('users').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today)).count().get();
      return {'users': usersSnap.count ?? 0, 'subscribers': subsSnap.count ?? 0, 'revenue': (subsSnap.count ?? 0) * 3500, 'signups': signupsSnap.count ?? 0, 'chats': chatsSnap.count ?? 0, 'reports': reportsSnap.count ?? 0};
    } catch (_) {
      return {'users': 0, 'subscribers': 0, 'revenue': 0, 'signups': 0, 'chats': 0, 'reports': 0};
    }
  }

  Widget _buildStatCard(String label, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: AppColors.primary, size: 24.sp), SizedBox(height: 8.h), Text(value, style: AppTextStyles.headline3), Text(label, style: AppTextStyles.caption)]),
      ),
    );
  }

  Widget _buildReports() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup('tickets').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tickets = snapshot.data!.docs;
        if (tickets.isEmpty) return Center(child: Text('No reports.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)));
        return ListView.builder(padding: EdgeInsets.all(16.w), itemCount: tickets.length, itemBuilder: (context, index) {
          final data = tickets[index].data() as Map<String, dynamic>;
          final ticketId = tickets[index].id;
          final userId = tickets[index].reference.parent.parent!.id;
          return Container(
            margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4.r)), child: Text(data['type'] ?? 'report', style: AppTextStyles.caption.copyWith(color: AppColors.primary))), SizedBox(width: 8.w), Expanded(child: Text(data['subject'] ?? '', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))), _buildStatusBadge(data['status'] ?? 'pending')]),
              if (data['message'] != null && (data['message'] as String).isNotEmpty) ...[SizedBox(height: 6.h), Text(data['message'], style: AppTextStyles.bodySmall)],
              SizedBox(height: 8.h),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('User: ${userId.substring(0, 8)}...', style: AppTextStyles.caption), TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('users').doc(userId).collection('tickets').doc(ticketId).update({'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()}); setState(() {}); }, child: Text('Mark Resolved', style: AppTextStyles.caption.copyWith(color: AppColors.success)))]),
            ]),
          );
        });
      },
    );
  }

  Widget _buildSubscriptions() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('isSubscribed', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final subs = snapshot.data!.docs;
        if (subs.isEmpty) return Center(child: Text('No active subscriptions.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)));
        return ListView.builder(padding: EdgeInsets.all(16.w), itemCount: subs.length, itemBuilder: (context, index) {
          final data = subs[index].data() as Map<String, dynamic>;
          return Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))), child: ListTile(contentPadding: EdgeInsets.zero, title: Text(data['displayName'] ?? data['name'] ?? 'Unknown', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)), subtitle: Text(data['email'] ?? '', style: AppTextStyles.caption), trailing: TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('users').doc(subs[index].id).update({'isSubscribed': false}); }, child: Text('Revoke', style: AppTextStyles.caption.copyWith(color: AppColors.error)))));
        });
      },
    );
  }

  Widget _buildUsers() {
    return Column(children: [
      Padding(padding: EdgeInsets.all(16.w), child: TextField(controller: _userSearchController, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: 'Search by email...', prefixIcon: Icon(Icons.search, size: 20.sp), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none), filled: true, fillColor: AppColors.white), onSubmitted: (_) => setState(() {}))),
      Expanded(
        child: _userSearchController.text.isEmpty
            ? Center(child: Text('Search for a user by email.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))
            : FutureBuilder<QuerySnapshot>(future: FirebaseFirestore.instance.collection('users').where('email', isEqualTo: _userSearchController.text.trim()).get(), builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final users = snapshot.data!.docs;
                if (users.isEmpty) return Center(child: Text('No user found.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)));
                return ListView.builder(padding: EdgeInsets.all(16.w), itemCount: users.length, itemBuilder: (context, index) {
                  final data = users[index].data() as Map<String, dynamic>;
                  return Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))), child: ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Icon(Icons.person)), title: Text(data['displayName'] ?? data['name'] ?? 'Unknown', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)), subtitle: Text('${data['email'] ?? ''}\nLeads: ${data['leadCount'] ?? 0} | Reviews: ${data['reviewCount'] ?? 0} | Subscribed: ${data['isSubscribed'] == true ? 'Yes' : 'No'}', style: AppTextStyles.caption)));
                });
              }),
      ),
    ]);
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'pending' ? Colors.orange : status == 'resolved' ? AppColors.success : AppColors.grey;
    return Container(padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8.r)), child: Text(status, style: AppTextStyles.caption.copyWith(color: color)));
  }
}

// ==================== ANALYTICS ====================

class _UserAnalyticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('User Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Users'));
}
class _SubscriberAnalyticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Subscriber Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Subscribers', isSubscribed: true));
}
class _RevenueAnalyticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Revenue Analytics', style: AppTextStyles.headline3)), body: FutureBuilder<QuerySnapshot>(future: FirebaseFirestore.instance.collection('users').where('isSubscribed', isEqualTo: true).get(), builder: (context, snapshot) {
      final count = snapshot.data?.docs.length ?? 0;
      return ListView(padding: EdgeInsets.all(20.w), children: [_buildSummaryCard('Total Subscribers', '$count', Icons.people), SizedBox(height: 12.h), _buildSummaryCard('Monthly Revenue (est.)', 'NGN ${count * 3500}', Icons.payments), SizedBox(height: 12.h), _buildSummaryCard('Annual Revenue (est.)', 'NGN ${count * 3500 * 12}', Icons.trending_up)]);
    }));
  }
}
class _SignupAnalyticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Signup Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Signups'));
}
class _ChatAnalyticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Chat Analytics', style: AppTextStyles.headline3)), body: FutureBuilder<QuerySnapshot>(future: FirebaseFirestore.instance.collection('chats').get(), builder: (context, snapshot) {
      final count = snapshot.data?.docs.length ?? 0;
      return ListView(padding: EdgeInsets.all(20.w), children: [_buildSummaryCard('Total Chats', '$count', Icons.chat_bubble)]);
    }));
  }
}

enum _TimePeriod { days, weeks, months, years }

class _AnalyticsView extends StatefulWidget {
  final String collection, dateField, title;
  final bool isSubscribed;
  const _AnalyticsView({required this.collection, required this.dateField, required this.title, this.isSubscribed = false});
  @override
  State<_AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<_AnalyticsView> {
  _TimePeriod _period = _TimePeriod.days;
  Map<String, int> _data = {};
  bool _isLoading = true;
  int _total = 0;
  final _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    DateTime startDate;
    switch (_period) { case _TimePeriod.days: startDate = now.subtract(const Duration(days: 7)); break; case _TimePeriod.weeks: startDate = now.subtract(const Duration(days: 28)); break; case _TimePeriod.months: startDate = now.subtract(const Duration(days: 365)); break; case _TimePeriod.years: startDate = DateTime(2020); break; }
    try {
      Query query = FirebaseFirestore.instance.collection(widget.collection).where(widget.dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      if (widget.isSubscribed) query = query.where('isSubscribed', isEqualTo: true);
      final snapshot = await query.get();
      final grouped = <String, int>{};
      for (final doc in snapshot.docs) {
        final ts = (doc.data() as Map<String, dynamic>)[widget.dateField] as Timestamp?;
        if (ts == null) continue;
        final d = ts.toDate();
        String key;
        switch (_period) { case _TimePeriod.days: key = '${d.day}/${d.month}'; break; case _TimePeriod.weeks: key = 'Week ${((d.day - 1) ~/ 7) + 1}'; break; case _TimePeriod.months: key = _months[d.month - 1]; break; case _TimePeriod.years: key = '${d.year}'; break; }
        grouped[key] = (grouped[key] ?? 0) + 1;
      }
      setState(() { _data = grouped; _total = snapshot.docs.length; _isLoading = false; });
    } catch (_) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.all(16.w), children: [
      Text(widget.title, style: AppTextStyles.headline2), SizedBox(height: 4.h), Text('Total: $_total', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)), SizedBox(height: 16.h),
      Row(children: _TimePeriod.values.map((p) {
        final sel = _period == p;
        return Expanded(child: GestureDetector(onTap: () { _period = p; _loadData(); }, child: Container(padding: EdgeInsets.symmetric(vertical: 8.h), margin: EdgeInsets.symmetric(horizontal: 2.w), decoration: BoxDecoration(color: sel ? AppColors.primary : AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8.r)), child: Text(p.name.toUpperCase(), textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(color: sel ? AppColors.white : AppColors.primary, fontWeight: FontWeight.w600)))));
      }).toList()),
      SizedBox(height: 16.h),
      if (_isLoading) const Center(child: CircularProgressIndicator()) else ..._data.entries.map((e) => Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(12.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r)), child: Row(children: [Expanded(child: Text(e.key, style: AppTextStyles.bodyMedium)), Text('${e.value}', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))]))),
    ]);
  }
}

Widget _buildSummaryCard(String title, String value, IconData icon) {
  return Container(padding: EdgeInsets.all(16.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))), child: Row(children: [Icon(icon, color: AppColors.primary, size: 32.sp), SizedBox(width: 12.w), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey)), Text(value, style: AppTextStyles.headline3)])]));
}