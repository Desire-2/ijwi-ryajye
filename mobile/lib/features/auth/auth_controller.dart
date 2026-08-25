import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_store.dart';

class AppUser {
  AppUser({
    required this.id,
    required this.phone,
    required this.fullName,
    this.primaryRole = 'FARMER',
    this.username,
  });

  final String id;
  final String phone;
  final String fullName;
  final String primaryRole;
  final String? username;

  bool get isFarmer => primaryRole == 'FARMER';
  bool get isBuyer => primaryRole == 'BUYER';
  bool get isLogistics => primaryRole == 'LOGISTICS';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        phone: j['phone'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        primaryRole: j['primary_role'] as String? ?? 'FARMER',
        username: j['username'] as String?,
      );
}

class AuthController extends StateNotifier<AsyncValue<AppUser?>> {
  AuthController(this._tokens, this._api) : super(const AsyncValue.loading()) {
    _restore();
  }

  final TokenStore _tokens;
  final ApiClient _api;

  Future<void> _restore() async {
    final access = await _tokens.readAccess();
    if (access == null) {
      state = const AsyncValue.data(null);
      return;
    }
    final cached = await _tokens.readUserJson();
    if (cached != null) {
      state = AsyncValue.data(
          AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(cached))));
      return;
    }
    try {
      final me = await _api.getJson('/users/me');
      final user = AppUser.fromJson(me['user'] as Map<String, dynamic>);
      state = AsyncValue.data(user);
      await _cacheUser(user);
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _cacheUser(AppUser user) =>
      _tokens.writeUserJson(jsonEncode({
        'id': user.id,
        'phone': user.phone,
        'full_name': user.fullName,
        'primary_role': user.primaryRole,
        if (user.username != null) 'username': user.username,
      }));

  /// Role chosen during onboarding; consumed as the default in RegisterScreen.
  String preferredRole = 'FARMER';

  Future<void> setPreferredRole(String role) async {
    preferredRole = role;
  }

  /// Step 1: register then verify OTP.
  Future<String?> register({
    required String phone,
    required String fullName,
    required String password,
    String role = 'FARMER',
    }) async {
    await _api.postJson('/auth/register', {
      'phone': phone,
      'full_name': fullName,
      'password': password,
      'role': role,
    });
    return null; // OTP sent; UI moves to verification
  }

  Future<AppUser> verifyOtp({required String phone, required String code}) async {
    final res = await _api.postJson(
        '/auth/verify_otp', {'phone': phone, 'code': code});
    final verified = res['verified'] == true;
    if (!verified) throw Exception('Invalid code');
    final tokens =
        (res['tokens'] as Map<String, dynamic>);
    await _tokens.write(
      access: tokens['access_token'] as String,
      refresh: tokens['refresh_token'] as String,
    );
    final user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    state = AsyncValue.data(user);
    await _cacheUser(user);
    return user;
  }

  Future<AppUser> login({required String phone, required String password}) async {
    final res = await _api.postJson('/auth/login', {
      'phone': phone,
      'password': password,
    });
    await _tokens.write(
      access: res['access_token'] as String,
      refresh: res['refresh_token'] as String,
    );
    final user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    state = AsyncValue.data(user);
    await _cacheUser(user);
    return user;
  }

  Future<void> logout() async {
    try {
      await _api.postJson('/auth/logout', {});
    } catch (_) {}
    await _tokens.clear();
    state = const AsyncValue.data(null);
  }
}

final authProvider = StateNotifierProvider<AuthController, AsyncValue<AppUser?>>(
    (ref) => AuthController(ref.watch(tokenStoreProvider),
        ref.watch(apiClientProvider)));
