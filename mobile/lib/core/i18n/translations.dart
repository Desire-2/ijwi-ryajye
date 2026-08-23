import 'dart:convert';

import 'package:flutter/services.dart' show root;

import '../config.dart';

/// Lightweight runtime-loaded translations (en/rw/fr/sw JSON under
/// assets/lang/). Falls back to the key itself when a translation is missing.
class Translations {
  Translations(this._locale, this._bundle);

  final String _locale;
  final Map<String, String> _bundle;
  Map<String, String>? _fallbackEn;

  static Future<Translations> load(String locale) async {
    final effective =
        AppConfig.supportedLanguages.contains(locale) ? locale : 'en';
    final raw = await rootBundle.loadString('assets/lang/$effective.json');
    return Translations(effective, _parse(raw));
  }

  static Map<String, String> _parse(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  String get locale => _locale;

  Future<void> _ensureFallback() async {
    if (_fallbackEn != null || _locale == 'en') return;
    final raw = await rootBundle.loadString('assets/lang/en.json');
    _fallbackEn = _parse(raw);
  }

  String t(String key) => _bundle[key] ?? key;
}
