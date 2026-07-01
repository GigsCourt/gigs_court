import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile/own_profile_screen.dart';
import '../admin/admin_screen.dart';
import '../../config/theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _isAdmin = false;
  int _unreadChats = 0;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _listenToUnread();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('admin_emails')
        .where('email', isEqualTo: user!.email)
        .get();

    if (mounted) {
      setState(() => _isAdmin = doc.docs.isNotEmpty);
    }
  }

  void _listenToUnread() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) {
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        count += (data['unreadCount'] ?? 0) as int;
      }
      if (mounted) setState(() => _unreadChats = count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = [
      NavigationDestination(icon: Icon(Icons.home_outlined, size: 22.sp), selectedIcon: Icon(Icons.home, size: 22.sp), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.search_outlined, size: 22.sp), selectedIcon: Icon(Icons.search, size: 22.sp), label: 'Search'),
      NavigationDestination(
        icon: _buildChatIcon(Icons.chat_bubble_outline),
        selectedIcon: _buildChatIcon(Icons.chat_bubble),
        label: 'Chat',
      ),
      NavigationDestination(
        icon: _buildProfileIcon(),
        selectedIcon: _buildProfileIcon(),
        label: 'Profile',
      ),
      if (_isAdmin)
        NavigationDestination(icon: Icon(Icons.shield_outlined, size: 22.sp), selectedIcon: Icon(Icons.shield, size: 22.sp), label: 'Admin'),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          const SearchScreen(),
          const ChatListScreen(),
          const OwnProfileScreen(),
          if (_isAdmin) const AdminScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: destinations,
      ),
    );
  }

  Widget _buildChatIcon(IconData icon) {
    if (_unreadChats > 0) {
      return Badge(
        label: Text(_unreadChats > 99 ? '99+' : '$_unreadChats', style: TextStyle(fontSize: 10.sp, color: AppColors.white)),
        backgroundColor: AppColors.error,
        child: Icon(icon, size: 22.sp),
      );
    }
    return Icon(icon, size: 22.sp);
  }

  Widget _buildProfileIcon() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final photoUrl = data?['profileImage'] ?? data?['photoUrl'];
        if (photoUrl != null && photoUrl.toString().isNotEmpty) {
          return ClipOval(
            child: Image.network(photoUrl, width: 24.sp, height: 24.sp, fit: BoxFit.cover),
          );
        }
        return Icon(Icons.person_outline, size: 22.sp);
      },
    );
  }
}