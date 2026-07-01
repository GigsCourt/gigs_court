import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://ucwffnukedmowwxedqzv.supabase.co',
    publishableKey: 'sb_publishable_mNwlLP9omXRkPNIQzaVKRg_yFUsW6xZ',
  );

  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10),
    minimumFetchInterval: const Duration(hours: 1),
  ));
  await remoteConfig.setDefaults({'subscriptions_enforced': false});
  await remoteConfig.fetchAndActivate();

  await _initFCM();

  runApp(const GigsCourtApp());
}

Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  if (token != null) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    }
    messaging.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': newToken,
        }, SetOptions(merge: true));
      }
    });
  }

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationTap(message.data);
  });

  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationTap(initialMessage.data);
  }
}

void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'];
  switch (type) {
    case 'message':
      appRouter.go('/home');
      break;
    case 'subscription_expired':
    case 'subscription_expiring':
      appRouter.go('/subscription');
      break;
    default:
      appRouter.go('/home');
  }
}

class GigsCourtApp extends StatefulWidget {
  const GigsCourtApp({super.key});

  @override
  State<GigsCourtApp> createState() => _GigsCourtAppState();
}

class _GigsCourtAppState extends State<GigsCourtApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } else if (state == AppLifecycleState.paused) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => app_auth.AuthProvider(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return MaterialApp.router(
            title: 'GigsCourt',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}