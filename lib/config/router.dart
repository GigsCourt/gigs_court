import 'package:go_router/go_router.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/verify_email/verify_email_screen.dart';
import '../screens/setup/profile_photo_screen.dart';
import '../screens/setup/location_screen.dart';
import '../screens/setup/services_screen.dart';
import '../screens/shell/main_shell.dart';
import '../screens/profile/provider_profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/chat/chat_conversation_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/help_support_screen.dart';
import '../screens/reviews/reviews_screen.dart';
import '../screens/saved/saved_providers_screen.dart';
import '../screens/subscription/subscription_screen.dart';
import '../screens/subscription/test_subscribe_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/verify-email', builder: (context, state) {
      final email = state.extra as String;
      return VerifyEmailScreen(email: email);
    }),
    GoRoute(path: '/setup/photo', builder: (context, state) => const ProfilePhotoScreen()),
    GoRoute(path: '/setup/location', builder: (context, state) => const LocationScreen()),
    GoRoute(path: '/setup/services', builder: (context, state) => const ServicesScreen()),
    GoRoute(path: '/home', builder: (context, state) => const MainShell()),
    GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
    GoRoute(path: '/provider/:id', builder: (context, state) {
      final id = state.pathParameters['id']!;
      final extra = state.extra as Map<String, dynamic>?;
      return ProviderProfileScreen(
        providerId: id,
        initialDistanceKm: extra?['distanceKm'] as double?,
        initialIsOnline: extra?['isOnline'] as bool?,
        initialLastSeen: extra?['lastSeen'] as String?,
      );
    }),
    GoRoute(path: '/chat/:chatId', builder: (context, state) {
      final chatId = state.pathParameters['chatId']!;
      final extra = state.extra as Map<String, dynamic>;
      return ChatConversationScreen(chatId: chatId, otherUserId: extra['otherUserId'] as String, otherUserName: extra['otherUserName'] as String);
    }),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/help-support', builder: (context, state) => const HelpSupportScreen()),
    GoRoute(path: '/edit-profile', builder: (context, state) => const EditProfileScreen()),
    GoRoute(path: '/reviews/:userId', builder: (context, state) {
      final userId = state.pathParameters['userId']!;
      return ReviewsScreen(providerId: userId);
    }),
    GoRoute(path: '/saved-providers', builder: (context, state) => const SavedProvidersScreen()),
    GoRoute(path: '/subscription', builder: (context, state) => const SubscriptionScreen()),
    GoRoute(path: '/test-subscribe', builder: (context, state) => const TestSubscribeScreen()),
  ],
);