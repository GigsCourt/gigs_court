import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final _overviewKey = GlobalKey();
  bool _isAdmin = false;
  bool _checkingAdmin = true;

  final _sections = [
    {'title': 'Overview', 'icon': Icons.dashboard_outlined},
    {'title': 'Reports', 'icon': Icons.flag_outlined},
    {'title': 'Subscriptions', 'icon': Icons.subscriptions_outlined},
    {'title': 'Users', 'icon': Icons.people_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      if (mounted) setState(() => _checkingAdmin = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_emails')
          .where('email', isEqualTo: user!.email)
          .get();
      if (mounted) {
        setState(() {
          _isAdmin = doc.docs.isNotEmpty;
          _checkingAdmin = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: Text('Access Denied', style: AppTextStyles.headline3)),
        body: Center(
          child: Text(
            'You do not have admin access.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _sections[_selectedSection]['title'] as String,
          style: AppTextStyles.headline3,
        ),
      ),
      body: _buildSection(),
      bottomNavigationBar: Container(
        height: 64.h,
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border(
            top: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
        ),
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
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _sections[index]['icon'] as IconData,
                      size: 20.sp,
                      color: isSelected ? AppColors.white : AppColors.grey,
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _sections[index]['title'] as String,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppColors.white : AppColors.grey,
                      ),
                    ),
                  ],
                ),
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

  // ---- OVERVIEW ----
  Widget _buildOverview() {
    return FutureBuilder<Map<String, dynamic>>(
      key: _overviewKey,
      future: _loadOverviewStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return RefreshIndicator(
            onRefresh: () async { setState(() {}); },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [Center(child: Text('Failed to load overview.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))],
            ),
          );
        }
        final data = snapshot.data ?? {};
        final stats = data['stats'] as Map<String, int>? ?? {};
        final priceNGN = data['priceNGN'] as int? ?? 0;
        final priceUSD = data['priceUSD'] as int? ?? 0;

        return RefreshIndicator(
          onRefresh: () async { setState(() {}); },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(16.w),
            children: [
              GridView.count(
                shrinkWrap: true, crossAxisCount: 2, crossAxisSpacing: 12.w, mainAxisSpacing: 12.h,
                childAspectRatio: 1.3, physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStatCard('Total Users', '${stats['users']}', Icons.people, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserAnalyticsScreen(total: stats['users'] ?? 0)))),
                  _buildStatCard('Subscribers', '${stats['subscribers']}', Icons.verified, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SubscriberAnalyticsScreen(total: stats['subscribers'] ?? 0)))),
                  _buildStatCard('Revenue', 'NGN ${stats['revenue']}', Icons.payments, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _RevenueAnalyticsScreen(price: priceNGN, subscriberCount: stats['subscribers'] ?? 0)))),
                  _buildStatCard('Signups Today', '${stats['signups']}', Icons.person_add, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SignupAnalyticsScreen(total: stats['users'] ?? 0)))),
                  _buildStatCard('Active Chats', '${stats['chats']}', Icons.chat_bubble, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ChatAnalyticsScreen(total: stats['chats'] ?? 0)))),
                  _buildStatCard('Reports', '${stats['reports']}', Icons.flag, () => setState(() => _selectedSection = 1)),
                ],
              ),
              SizedBox(height: 16.h),
              _buildPriceEditor(priceNGN, priceUSD),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadOverviewStats() async {
    try {
      final configDoc = await FirebaseFirestore.instance.collection('app_config').doc('global').get();
      final data = configDoc.data() ?? {};
      final totalUsers = (data['totalUsers'] ?? 0) as int;
      final totalSubscribers = (data['totalSubscribers'] ?? 0) as int;
      final totalChats = (data['totalChats'] ?? 0) as int;
      final priceNGN = (data['subscriptionPriceNGN'] ?? 0) as int;
      final priceUSD = (data['subscriptionPriceUSD'] ?? 0) as int;
      final revenue = totalSubscribers * priceNGN;

      final reportsSnap = await FirebaseFirestore.instance.collection('tickets').where('status', whereIn: ['open', 'pending']).count().get();
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final signupsSnap = await FirebaseFirestore.instance.collection('users').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)).count().get();

      return {
        'price': priceNGN, 'priceNGN': priceNGN, 'priceUSD': priceUSD,
        'stats': {'users': totalUsers, 'subscribers': totalSubscribers, 'chats': totalChats, 'revenue': revenue, 'signups': signupsSnap.count ?? 0, 'reports': reportsSnap.count ?? 0},
      };
    } catch (_) {
      return {'price': 0, 'priceNGN': 0, 'priceUSD': 0, 'stats': {'users': 0, 'subscribers': 0, 'chats': 0, 'revenue': 0, 'signups': 0, 'reports': 0}};
    }
  }

  Widget _buildPriceEditor(int currentPriceNGN, int currentPriceUSD) {
    final ngnController = TextEditingController(text: currentPriceNGN.toString());
    final usdController = TextEditingController(text: currentPriceUSD.toString());
    return Container(
      padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Subscription Price', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)), SizedBox(height: 12.h),
        Text('NGN (Monthly)', style: AppTextStyles.caption.copyWith(color: AppColors.grey)), SizedBox(height: 4.h),
        TextField(controller: ngnController, keyboardType: TextInputType.number, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: 'Price in Naira', prefixText: '₦ ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)), contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h))),
        SizedBox(height: 12.h),
        Text('USD (Monthly)', style: AppTextStyles.caption.copyWith(color: AppColors.grey)), SizedBox(height: 4.h),
        TextField(controller: usdController, keyboardType: TextInputType.number, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: 'Price in USD', prefixText: '\$ ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)), contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h))),
        SizedBox(height: 12.h),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            final pNGN = int.tryParse(ngnController.text.trim()); final pUSD = int.tryParse(usdController.text.trim());
            if (pNGN == null || pNGN < 0 || pUSD == null || pUSD < 0) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter valid prices.'), backgroundColor: AppColors.error)); return; }
            await FirebaseFirestore.instance.collection('app_config').doc('global').set({'subscriptionPriceNGN': pNGN, 'subscriptionPriceUSD': pUSD}, SetOptions(merge: true));
            setState(() {});
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prices updated!'), backgroundColor: AppColors.success));
          },
          child: Text('Save Prices'),
        )),
      ]),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: AppColors.primary, size: 24.sp), SizedBox(height: 8.h), Text(value, style: AppTextStyles.headline3), Text(label, style: AppTextStyles.caption)]),
      ),
    );
  }

  // ---- REPORTS ----
  Widget _buildReports() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tickets').orderBy('createdAt', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return RefreshIndicator(onRefresh: () async {}, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Center(child: Text('Failed to load reports.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
        final tickets = snapshot.data?.docs ?? [];
        if (tickets.isEmpty) return RefreshIndicator(onRefresh: () async {}, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 100.h), Center(child: Text('No reports.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), itemCount: tickets.length,
          itemBuilder: (context, index) {
            final data = tickets[index].data() as Map<String, dynamic>; final ticketId = tickets[index].id;
            final submitterName = data['submitterName'] as String? ?? 'Unknown'; final submitterEmail = data['submitterEmail'] as String? ?? '';
            return Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Container(padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4.r)), child: Text(data['type'] ?? 'support', style: AppTextStyles.caption.copyWith(color: AppColors.primary))), SizedBox(width: 8.w), Expanded(child: Text(data['subject'] ?? '', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))), _buildStatusBadge(data['status'] ?? 'open')]),
                if (data['message'] != null && (data['message'] as String).isNotEmpty) ...[SizedBox(height: 6.h), Text(data['message'], style: AppTextStyles.bodySmall)],
                SizedBox(height: 8.h), Text('From: $submitterName ($submitterEmail)', style: AppTextStyles.caption),
                if (data['status'] != 'resolved') ...[SizedBox(height: 4.h), Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('tickets').doc(ticketId).update({'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()}); }, child: Text('Mark Resolved', style: AppTextStyles.caption.copyWith(color: AppColors.success))))],
              ]),
            );
          },
        );
      },
    );
  }

  // ---- SUBSCRIPTIONS ----
  Widget _buildSubscriptions() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('isSubscribed', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return RefreshIndicator(onRefresh: () async {}, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Center(child: Text('Failed to load subscriptions.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
        final subs = snapshot.data?.docs ?? [];
        if (subs.isEmpty) return RefreshIndicator(onRefresh: () async {}, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 100.h), Center(child: Text('No active subscriptions.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), itemCount: subs.length,
          itemBuilder: (context, index) {
            final data = subs[index].data() as Map<String, dynamic>;
            final expiry = data['subscriptionExpiry'] as Timestamp?;
            final expiryText = expiry != null ? 'Expires: ${_formatDate(expiry.toDate())}' : '';
            return Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
              child: ListTile(
                contentPadding: EdgeInsets.zero, title: Text(data['displayName'] ?? data['name'] ?? 'Unknown', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text('${data['email'] ?? ''}${expiryText.isNotEmpty ? '\n$expiryText' : ''}', style: AppTextStyles.caption),
                trailing: TextButton(onPressed: () => _confirmRevoke(subs[index].id, data['displayName'] ?? data['name'] ?? 'User'), child: Text('Revoke', style: AppTextStyles.caption.copyWith(color: AppColors.error))),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month-1]} ${date.year}';
  }

  Future<void> _confirmRevoke(String userId, String userName) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Revoke Subscription', style: AppTextStyles.bodyLarge), content: Text('Are you sure you want to revoke $userName\'s subscription?', style: AppTextStyles.bodyMedium), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Revoke', style: TextStyle(color: AppColors.error)))]));
    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('users').doc(userId).update({'isSubscribed': false});
    await FirebaseFirestore.instance.collection('app_config').doc('global').set({'totalSubscribers': FieldValue.increment(-1)}, SetOptions(merge: true));
  }

  // ---- USERS ----
  Widget _buildUsers() {
    return Column(children: [
      Padding(padding: EdgeInsets.all(16.w), child: TextField(controller: _userSearchController, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: 'Search by email...', prefixIcon: Icon(Icons.search, size: 20.sp), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none), filled: true, fillColor: AppColors.white), onSubmitted: (_) => setState(() {}))),
      Expanded(
        child: _userSearchController.text.isEmpty
            ? RefreshIndicator(onRefresh: () async {}, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 100.h), Center(child: Text('Search for a user by email.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]))
            : FutureBuilder<QuerySnapshot>(future: FirebaseFirestore.instance.collection('users').where('email', isEqualTo: _userSearchController.text.trim()).get(), builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return RefreshIndicator(onRefresh: () async { setState(() {}); }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Center(child: Text('Search failed.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
                final users = snapshot.data?.docs ?? [];
                if (users.isEmpty) return RefreshIndicator(onRefresh: () async { setState(() {}); }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 100.h), Center(child: Text('No user found.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.grey)))]));
                return RefreshIndicator(onRefresh: () async { setState(() {}); }, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), itemCount: users.length, itemBuilder: (context, index) {
                  final data = users[index].data() as Map<String, dynamic>;
                  return Container(margin: EdgeInsets.only(bottom: 8.h), padding: EdgeInsets.all(14.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))),
                    child: ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundImage: data['photoUrl'] != null && (data['photoUrl'] as String).isNotEmpty ? NetworkImage(data['photoUrl']) : null, child: data['photoUrl'] == null || (data['photoUrl'] as String).isEmpty ? const Icon(Icons.person) : null),
                      title: Text(data['displayName'] ?? data['name'] ?? 'Unknown', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text('${data['email'] ?? ''}\nLeads: ${data['leadCount'] ?? 0} | Reviews: ${data['reviewCount'] ?? 0} | Subscribed: ${data['isSubscribed'] == true ? 'Yes' : 'No'}', style: AppTextStyles.caption)),
                  );
                }));
              }),
      ),
    ]);
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'pending' || status == 'open' ? Colors.orange : status == 'resolved' ? AppColors.success : AppColors.grey;
    return Container(padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8.r)), child: Text(status, style: AppTextStyles.caption.copyWith(color: color)));
  }
}

// ==================== ANALYTICS ====================

class _UserAnalyticsScreen extends StatelessWidget {
  final int total;
  const _UserAnalyticsScreen({required this.total});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('User Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Users', total: total));
}
class _SubscriberAnalyticsScreen extends StatelessWidget {
  final int total;
  const _SubscriberAnalyticsScreen({required this.total});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Subscriber Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Subscribers', total: total, isSubscribed: true));
}
class _RevenueAnalyticsScreen extends StatelessWidget {
  final int price;
  final int subscriberCount;
  const _RevenueAnalyticsScreen({required this.price, required this.subscriberCount});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Revenue Analytics', style: AppTextStyles.headline3)), body: _RevenueAnalyticsBody(price: price, subscriberCount: subscriberCount));
}
class _SignupAnalyticsScreen extends StatelessWidget {
  final int total;
  const _SignupAnalyticsScreen({required this.total});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Signup Analytics', style: AppTextStyles.headline3)), body: _AnalyticsView(collection: 'users', dateField: 'createdAt', title: 'Signups', total: total));
}
class _ChatAnalyticsScreen extends StatelessWidget {
  final int total;
  const _ChatAnalyticsScreen({required this.total});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: Text('Chat Analytics', style: AppTextStyles.headline3)), body: _ChatAnalyticsBody(total: total));
}

class _RevenueAnalyticsBody extends StatelessWidget {
  final int price;
  final int subscriberCount;
  const _RevenueAnalyticsBody({required this.price, required this.subscriberCount});
  @override
  Widget build(BuildContext context) {
    final revenue = subscriberCount * price;
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), children: [
        _buildInfoCard('Total Subscribers', '$subscriberCount', Icons.people),
        SizedBox(height: 8.h),
        _buildInfoCard('Subscription Price', 'NGN $price', Icons.sell),
        SizedBox(height: 8.h),
        _buildInfoCard('Monthly Revenue', 'NGN $revenue', Icons.payments),
        SizedBox(height: 8.h),
        _buildInfoCard('Annual Revenue (est.)', 'NGN ${revenue * 12}', Icons.trending_up),
      ]),
    );
  }
}

class _ChatAnalyticsBody extends StatefulWidget {
  final int total;
  const _ChatAnalyticsBody({required this.total});
  @override
  State<_ChatAnalyticsBody> createState() => _ChatAnalyticsBodyState();
}
class _ChatAnalyticsBodyState extends State<_ChatAnalyticsBody> {
  Map<String, int> _data = {};
  bool _isLoading = true;
  int _periodTotal = 0;
  _TimePeriod _period = _TimePeriod.days;
  final _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now(); DateTime startDate;
    switch (_period) { case _TimePeriod.days: startDate = now.subtract(const Duration(days: 7)); break; case _TimePeriod.weeks: startDate = now.subtract(const Duration(days: 28)); break; case _TimePeriod.months: startDate = now.subtract(const Duration(days: 365)); break; case _TimePeriod.years: startDate = DateTime(2020); break; }
    try {
      final snapshot = await FirebaseFirestore.instance.collection('chats').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate)).get();
      final grouped = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data(); final ts = data['createdAt'] as Timestamp? ?? data['lastMessageAt'] as Timestamp?;
        if (ts == null) continue;
        final d = ts.toDate(); String key;
        switch (_period) { case _TimePeriod.days: key = '${d.day}/${d.month}'; break; case _TimePeriod.weeks: key = 'Week ${((d.day-1)~/7)+1}'; break; case _TimePeriod.months: key = _months[d.month-1]; break; case _TimePeriod.years: key = '${d.year}'; break; }
        grouped[key] = (grouped[key] ?? 0) + 1;
      }
      setState(() { _data = grouped; _periodTotal = snapshot.docs.length; _isLoading = false; });
    } catch (_) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _loadData, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), children: [
      Text('Chat Analytics', style: AppTextStyles.headline2), SizedBox(height: 4.h),
      _buildInfoCard('Total Chats', '${widget.total}', Icons.chat_bubble),
      SizedBox(height: 12.h),
      Text('History', style: AppTextStyles.bodyLarge), SizedBox(height: 8.h),
      _buildPeriodSelector(),
      SizedBox(height: 12.h),
      if (_isLoading) const Center(child: CircularProgressIndicator()) else ..._data.entries.map((e) => _buildBar(e.key, e.value, _periodTotal)),
    ]));
  }

  Widget _buildPeriodSelector() {
    return Row(children: _TimePeriod.values.map((p) { final sel = _period == p; return Expanded(child: GestureDetector(onTap: () { _period = p; _loadData(); }, child: Container(padding: EdgeInsets.symmetric(vertical: 8.h), margin: EdgeInsets.symmetric(horizontal: 2.w), decoration: BoxDecoration(color: sel ? AppColors.primary : AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8.r)), child: Text(p.name.toUpperCase(), textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(color: sel ? AppColors.white : AppColors.primary, fontWeight: FontWeight.w600))))); }).toList());
  }

  Widget _buildBar(String label, int value, int max) {
    final fraction = max > 0 ? value / max : 0.0;
    return Padding(padding: EdgeInsets.only(bottom: 6.h), child: Row(children: [
      SizedBox(width: 60.w, child: Text(label, style: AppTextStyles.caption)),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4.r), child: LinearProgressIndicator(value: fraction, minHeight: 20.h, backgroundColor: AppColors.primary.withValues(alpha: 0.08), color: AppColors.primary))),
      SizedBox(width: 8.w), Text('$value', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
    ]));
  }
}

enum _TimePeriod { days, weeks, months, years }

class _AnalyticsView extends StatefulWidget {
  final String collection, dateField, title;
  final int total;
  final bool isSubscribed;
  const _AnalyticsView({required this.collection, required this.dateField, required this.title, required this.total, this.isSubscribed = false});
  @override
  State<_AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<_AnalyticsView> {
  _TimePeriod _period = _TimePeriod.days;
  Map<String, int> _data = {};
  bool _isLoading = true;
  int _periodTotal = 0;
  final _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now(); DateTime startDate;
    switch (_period) { case _TimePeriod.days: startDate = now.subtract(const Duration(days: 7)); break; case _TimePeriod.weeks: startDate = now.subtract(const Duration(days: 28)); break; case _TimePeriod.months: startDate = now.subtract(const Duration(days: 365)); break; case _TimePeriod.years: startDate = DateTime(2020); break; }
    try {
      Query query = FirebaseFirestore.instance.collection(widget.collection).where(widget.dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(startDate)).limit(500);
      if (widget.isSubscribed) query = query.where('isSubscribed', isEqualTo: true);
      final snapshot = await query.get();
      final grouped = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>; final ts = data[widget.dateField] as Timestamp?;
        if (ts == null) continue; final d = ts.toDate(); String key;
        switch (_period) { case _TimePeriod.days: key = '${d.day}/${d.month}'; break; case _TimePeriod.weeks: key = 'Week ${((d.day-1)~/7)+1}'; break; case _TimePeriod.months: key = _months[d.month-1]; break; case _TimePeriod.years: key = '${d.year}'; break; }
        grouped[key] = (grouped[key] ?? 0) + 1;
      }
      setState(() { _data = grouped; _periodTotal = snapshot.docs.length; _isLoading = false; });
    } catch (_) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _loadData, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(16.w), children: [
      Text(widget.title, style: AppTextStyles.headline2), SizedBox(height: 4.h),
      _buildInfoCard('Total', '${widget.total}', Icons.people),
      SizedBox(height: 4.h),
      _buildInfoCard('This Period', '$_periodTotal', Icons.trending_up),
      SizedBox(height: 12.h),
      Text('History', style: AppTextStyles.bodyLarge), SizedBox(height: 8.h),
      Row(children: _TimePeriod.values.map((p) { final sel = _period == p; return Expanded(child: GestureDetector(onTap: () { _period = p; _loadData(); }, child: Container(padding: EdgeInsets.symmetric(vertical: 8.h), margin: EdgeInsets.symmetric(horizontal: 2.w), decoration: BoxDecoration(color: sel ? AppColors.primary : AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8.r)), child: Text(p.name.toUpperCase(), textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(color: sel ? AppColors.white : AppColors.primary, fontWeight: FontWeight.w600))))); }).toList()),
      SizedBox(height: 12.h),
      if (_isLoading) const Center(child: CircularProgressIndicator()) else ..._data.entries.map((e) => _buildBar(e.key, e.value, _periodTotal)),
    ]));
  }

  Widget _buildBar(String label, int value, int max) {
    final fraction = max > 0 ? value / max : 0.0;
    return Padding(padding: EdgeInsets.only(bottom: 6.h), child: Row(children: [
      SizedBox(width: 60.w, child: Text(label, style: AppTextStyles.caption)),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4.r), child: LinearProgressIndicator(value: fraction, minHeight: 20.h, backgroundColor: AppColors.primary.withValues(alpha: 0.08), color: AppColors.primary))),
      SizedBox(width: 8.w), Text('$value', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
    ]));
  }
}

Widget _buildInfoCard(String title, String value, IconData icon) {
  return Container(padding: EdgeInsets.all(12.w), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.primary.withValues(alpha: 0.08))), child: Row(children: [Icon(icon, color: AppColors.primary, size: 28.sp), SizedBox(width: 12.w), Text(title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.grey)), const Spacer(), Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))]));
}