import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/chat_screen.dart';
import '../../features/chat/conversations_screen.dart';
import '../../features/community/community_screen.dart';
import '../../features/intelligence/intelligence_hub.dart';
import '../../features/market/market_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/sell/create_listing_screen.dart';
import '../../features/sell/my_listings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/trade/listing_detail_screen.dart';
import '../../features/trade/offers_screen.dart';
import '../../features/trade/orders_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../auth/auth_controller.dart';
import 'screens/home_shell.dart';
import 'screens/home_tab.dart';
import 'screens/login_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/register_screen.dart';

/// The router is built once; auth changes re-evaluate redirects through
/// [refreshListenable] instead of recreating the router (which would reset
/// navigation state on every login/logout).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    refreshListenable: refresh,
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (loc == '/splash') return null; // splash always shows first

      // Hold every route on the splash while the session is still restoring,
      // so we never flash onboarding/login for already-signed-in users.
      if (auth.isLoading) return '/splash';

      final loggingIn = loc.startsWith('/auth');
      final onboarding = loc == '/onboarding';

      // Not logged in and never onboarded → show onboarding once.
      if (!loggingIn && auth.valueOrNull == null) {
        return onboarding ? null : '/onboarding';
      }
      // Logged in users never see auth screens again.
      if (auth.valueOrNull != null && (loggingIn || onboarding)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeTab()),
          GoRoute(path: '/market', builder: (_, __) => const MarketScreen()),
          GoRoute(
              path: '/chats', builder: (_, __) => const ConversationsScreen()),
          GoRoute(
              path: '/community',
              builder: (_, __) => const CommunityScreen()),
          GoRoute(
              path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
          path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/auth/register',
          builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/auth/verify',
          builder: (context, state) {
            final phone = state.uri.queryParameters['phone'] ?? '';
            return OtpScreen(phone: phone);
          }),
      GoRoute(
          path: '/listing/:id',
          builder: (context, state) =>
              ListingDetailScreen(listingId: state.pathParameters['id']!)),
      GoRoute(path: '/offers', builder: (_, __) => const OffersScreen()),
      GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen()),
      GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/sell', builder: (_, __) => const MyListingsScreen()),
      GoRoute(
          path: '/sell/new',
          builder: (_, __) => const CreateListingScreen()),
      GoRoute(
          path: '/intelligence',
          builder: (context, state) => IntelligenceHubScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ??
                      0)),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      GoRoute(
          path: '/chat/:id',
          builder: (context, state) =>
              ChatScreen(conversationId: state.pathParameters['id']!)),
    ],
  );
  return router;
});
