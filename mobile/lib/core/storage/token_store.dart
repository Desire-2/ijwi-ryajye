import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for JWT pair + current user profile using SharedPreferences.
///
/// Replaced flutter_secure_storage to avoid native Keystore crashes on
/// budget Samsung devices (SIGSEGV during JNI init).
class TokenStore {
  static const _accessKey = 'ijwi.access';
  static const _refreshKey = 'ijwi.refresh';
  static const _userKey = 'ijwi.user';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _safe async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String?> readAccess() async {
    try {
      return (await _safe).getString(_accessKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readRefresh() async {
    try {
      return (await _safe).getString(_refreshKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required String access, required String refresh}) async {
    try {
      final prefs = await _safe;
      await prefs.setString(_accessKey, access);
      await prefs.setString(_refreshKey, refresh);
    } catch (_) {}
  }

  Future<void> writeUserJson(String json) async {
    try {
      (await _safe).setString(_userKey, json);
    } catch (_) {}
  }

  Future<String?> readUserJson() async {
    try {
      return (await _safe).getString(_userKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _safe;
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
      await prefs.remove(_userKey);
    } catch (_) {}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
