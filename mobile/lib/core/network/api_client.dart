import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../storage/token_store.dart';

/// Dio client with JWT auth header injection and transparent refresh-token
/// retry on 401 responses.
class ApiClient {
  ApiClient(this._tokens) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final access = await _tokens.readAccess();
        if (access != null && !options.path.contains('/auth/')) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            !(error.requestOptions.extra['__retried__'] == true)) {
          final refreshed = await _tryRefresh();
          if (refreshed != null) {
            final opts = error.requestOptions;
            opts.extra['__retried__'] = true;
            opts.headers['Authorization'] = 'Bearer $refreshed';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } on DioException catch (e) {
              return handler.reject(e);
            }
          }
          await _tokens.clear();
        }
        handler.next(error);
      },
    ));
  }

  final TokenStore _tokens;
  late final Dio _dio;
  Completer<String?>? _refreshLock;

  Dio get dio => _dio;

  Future<String?> _tryRefresh() async {
    if (_refreshLock != null) return _refreshLock!.future;
    _refreshLock = Completer<String?>();
    try {
      final refresh = await _tokens.readRefresh();
      if (refresh == null) {
        _refreshLock!.complete(null);
        return null;
      }
      final response = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
          .post('/auth/refresh',
              options: Options(headers: {'Authorization': 'Bearer $refresh'}));
      final data = response.data as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String? ?? refresh;
      if (access == null) {
        _refreshLock!.complete(null);
        return null;
      }
      await _tokens.write(access: access, refresh: newRefresh);
      _refreshLock!.complete(access);
      return access;
    } catch (_) {
      _refreshLock!.complete(null);
      return null;
    } finally {
      _refreshLock = null;
    }
  }

  Future<Map<String, dynamic>> getJson(String path,
      {Map<String, dynamic>? query}) async {
    final res = await _dio.get(path, queryParameters: query);
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> postJson(String path, Object? body,
      {Map<String, dynamic>? query}) async {
    final res = await _dio.post(path, data: body, queryParameters: query);
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> patchJson(String path, Object? body) async {
    final res = await _dio.patch(path, data: body);
    return (res.data as Map<String, dynamic>);
  }

  Future<void> delete(String path) async {
    await _dio.delete(path);
  }

  /// Normalizes backend error envelopes into a readable message.
  static String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final err = data['error'];
        if (err is Map<String, dynamic>) {
          return err['message'] as String? ?? 'Request failed';
        }
      }
      return error.type == DioExceptionType.connectionError
          ? 'You are offline. Changes will sync later.'
          : 'Network error (${error.response?.statusCode ?? '?'})';
    }
    return 'Unexpected error';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider));
});
