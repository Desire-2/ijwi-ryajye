import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/i18n_provider.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/design_system.dart';
import 'router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
    debugPrint(details.stack.toString());
  };
  runZonedGuarded(() {
    runApp(const ProviderScope(child: IjwiApp()));
  }, (error, stack) {
    debugPrint('[ZoneError] $error');
    debugPrint(stack.toString());
  });
}

class IjwiApp extends ConsumerStatefulWidget {
  const IjwiApp({super.key});

  @override
  ConsumerState<IjwiApp> createState() => _IjwiAppState();
}

class _IjwiAppState extends ConsumerState<IjwiApp> {
  @override
  void initState() {
    super.initState();
    _bootstrapSync();
  }

  Future<void> _bootstrapSync() async {
    // Delay sync engine init so it doesn't compete with splash rendering
    // on low-RAM devices.
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    try {
      final engine = await ref.read(syncEngineProvider.future);
      engine.startPeriodicSync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final i18n = ref.watch(i18nProvider);

    return MaterialApp.router(
      title: 'Ijwi Ryajye',
      debugShowCheckedModeBanner: false,
      theme: buildIjwiTheme(),
      routerConfig: router,
      builder: (context, child) {
        // Surface translation load errors as a blank splash instead of crash.
        if (i18n.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
