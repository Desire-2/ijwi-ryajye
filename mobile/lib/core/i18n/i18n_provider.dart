import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'translations.dart';

/// Holds the active [Translations] bundle; switch language at runtime via
/// [changeLocale] which reloads the JSON asset.
class I18nController extends StateNotifier<AsyncValue<Translations>> {
  I18nController() : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    final t = await Translations.load('rw');
    state = AsyncValue.data(t);
  }

  Future<void> changeLocale(String locale) async {
    state = const AsyncValue.loading();
    try {
      final t = await Translations.load(locale);
      state = AsyncValue.data(t);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final i18nProvider =
    StateNotifierProvider<I18nController, AsyncValue<Translations>>(
        (ref) => I18nController());

/// Usage: `ref.watch(trProvider)("tab_market")`
final trProvider = Provider<String Function(String key)>((ref) {
  final asyncT = ref.watch(i18nProvider);
  return asyncT.maybeWhen(
    data: (t) => t.t,
    orElse: () => (key) => key,
  );
});
