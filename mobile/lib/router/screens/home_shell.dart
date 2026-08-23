import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/design_system.dart';

/// Nulls = special center action (Ask Ijwi) that pushes a full screen
/// instead of switching tabs.
const _tabs = ['/', '/market', null, '/community', '/profile'];

final isOfflineProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none));
});

class HomeShell extends ConsumerWidget {
  const HomeShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs
        .indexOf(_tabs.firstWhere(
          (t) => t != null && location.startsWith(t),
          orElse: () => '/',
        )!)
        .clamp(0, _tabs.length - 1);
    final tr = ref.watch(trProvider);
    final pending = ref.watch(pendingSyncCountProvider);
    final offline = ref.watch(isOfflineProvider);

    return Scaffold(
      body: Column(children: [
        offline.maybeWhen(
          data: (isDown) => isDown
              ? Material(
                  color: IjwiColors.red,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.wifi_off,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Offline — changes are saved on your phone',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ]),
                  ),
                )
              : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        ),
        pending.maybeWhen(
          data: (n) => n > 0
              ? Material(
                  color: IjwiColors.amber,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(tr('sync_pending').replaceAll('{n}', '$n'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                )
                : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(child: child),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (_tabs[i] == null) {
            context.push('/intelligence');
            return;
          }
          context.go(_tabs[i]!);
        },
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: tr('tab_home')),
          NavigationDestination(
              icon: const Icon(Icons.storefront_outlined),
              selectedIcon: const Icon(Icons.storefront),
              label: tr('tab_market')),
          NavigationDestination(
              icon: const Icon(Icons.auto_awesome_outlined),
              selectedIcon: const Icon(Icons.auto_awesome),
              label: 'Ijwi'),
          NavigationDestination(
              icon: const Icon(Icons.groups_2_outlined),
              selectedIcon: const Icon(Icons.groups_2),
              label: tr('community')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: tr('tab_profile')),
        ],
      ),
    );
  }
}
