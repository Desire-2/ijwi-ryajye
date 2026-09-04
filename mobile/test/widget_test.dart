// App smoke test.
//
// The app bootstraps a periodic offline-sync timer ~4s after launch, which
// would otherwise leave a pending timer at teardown (and touch sqflite, which
// is unavailable in widget tests). We override the sync engine with a no-op
// subclass, mock SharedPreferences, and advance the clock past the splash and
// bootstrap delays.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ijwi_ryajye/core/network/api_client.dart';
import 'package:ijwi_ryajye/core/storage/local_db.dart';
import 'package:ijwi_ryajye/core/sync/sync_engine.dart';
import 'package:ijwi_ryajye/main.dart';

/// A SyncEngine whose periodic timer never starts, so widget tests can mount
/// the full app without pending timers or sqflite access.
class _NoPeriodicSyncEngine extends SyncEngine {
  _NoPeriodicSyncEngine(super.ref, super.db, super.api);

  @override
  void startPeriodicSync({Duration every = const Duration(minutes: 2)}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // LocalDb without sqflite: construction is lazy and nothing opens a
        // real database during the smoke test.
        localDbProvider.overrideWith((ref) async => LocalDb()),
        syncEngineProvider.overrideWith((ref) async {
          final db = await ref.watch(localDbProvider.future);
          return _NoPeriodicSyncEngine(ref, db, ref.watch(apiClientProvider));
        }),
      ],
      child: const IjwiApp(),
    ));
    await tester.pump(); // first frame
    // Let the splash navigation delay and the deferred sync bootstrap elapse.
    await tester.pump(const Duration(seconds: 6));
  });
}
