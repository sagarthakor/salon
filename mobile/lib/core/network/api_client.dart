import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'api_exception.dart';

/// Invoked whenever the backend rejects a request with 401 (expired/invalid
/// token), so the app can clear the session and return to login. Set by the
/// auth layer at startup — the client itself has no notion of "being logged
/// in," it just reports the failure.
typedef UnauthorizedCallback = void Function();

/// Centralized HTTP client: base URL, timeouts, auth header injection,
/// dev-only logging, and response-envelope unwrapping all live here so no
/// other part of the app touches Dio directly. Every method returns the
/// backend's `data` payload and throws [ApiException] on failure — callers
/// never see a raw [DioException] or the `{success, message, data}` wrapper.
class ApiClient {
  ApiClient({required SecureStorage secureStorage, Dio? dio})
    // ignore: prefer_initializing_formals
    : _secureStorage = secureStorage,
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (tenantSlug != null) {
            options.headers['X-Tenant-Slug'] = tenantSlug;
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );

    // Never logs headers (avoids ever printing the bearer token) and
    // redacts known-sensitive body fields (password, gateway signatures) —
    // see _RedactingLogInterceptor. Compiled out of behavior entirely in
    // release builds regardless of the ENABLE_NETWORK_LOGGING define, so a
    // misconfigured build can't leak request/response bodies.
    if (AppConfig.enableNetworkLogging && kDebugMode) {
      this.dio.interceptors.add(_RedactingLogInterceptor());
    }
  }

  final Dio dio;
  final SecureStorage _secureStorage;

  UnauthorizedCallback? onUnauthorized;

  /// Optional `X-Tenant-Slug` sent with every request once a customer has
  /// selected which salon they're acting on behalf of. Most Phase 6/7
  /// customer routes resolve the tenant from the resource itself (branch id,
  /// booking id) and ignore this header, but it's harmless to send and keeps
  /// the client consistent with the owner/staff API convention.
  String? tenantSlug;

  Future<T> get<T>(String path, {Map<String, dynamic>? queryParameters}) =>
      _unwrap<T>(dio.get(path, queryParameters: queryParameters));

  Future<T> post<T>(String path, {dynamic data, Map<String, dynamic>? headers}) =>
      _unwrap<T>(dio.post(path, data: data, options: headers != null ? Options(headers: headers) : null));

  Future<T> put<T>(String path, {dynamic data}) => _unwrap<T>(dio.put(path, data: data));

  Future<T> patch<T>(String path, {dynamic data}) => _unwrap<T>(dio.patch(path, data: data));

  Future<T> delete<T>(String path) => _unwrap<T>(dio.delete(path));

  /// Multipart upload (image + form fields), e.g. staff photo or a service
  /// image. Values may be plain scalars or [MultipartFile] instances. Laravel
  /// cannot parse a multipart body on PUT/PATCH (a PHP limitation, not
  /// specific to this backend), so an update is sent as `POST` with Laravel's
  /// standard `_method` override field rather than inventing a different
  /// upload endpoint — pass `httpMethodOverride: 'PUT'` for updates.
  Future<T> postMultipart<T>(String path, Map<String, dynamic> fields, {String? httpMethodOverride}) {
    final formData = FormData.fromMap({
      ...fields,
      '_method': ?httpMethodOverride,
    });
    return _unwrap<T>(dio.post(path, data: formData));
  }

  Future<T> _unwrap<T>(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      final body = response.data;
      if (body is Map<String, dynamic>) {
        return body['data'] as T;
      }
      return body as T;
    } on DioException catch (error) {
      throw ApiExceptionMapper.fromDioException(error);
    }
  }
}

/// Debug-only request/response logging that never prints headers (so the
/// bearer token is never logged) and redacts known-sensitive body fields —
/// a password on `/auth/login`/`/auth/register`, or a payment gateway
/// signature on a checkout-verify call — rather than dumping the raw body
/// verbatim. Only ever installed behind `kDebugMode` (see [ApiClient]), so
/// this never runs in a release build regardless of configuration.
class _RedactingLogInterceptor extends Interceptor {
  static const _sensitiveKeyFragments = ['password', 'signature', 'token', 'secret'];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('--> ${options.method} ${options.uri}');
    if (options.data != null) {
      debugPrint('Body: ${_redact(options.data)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint('<-- ${response.statusCode} ${response.requestOptions.uri}');
    debugPrint('Body: ${_redact(response.data)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('<-- ERROR ${err.requestOptions.uri}: ${err.message}');
    handler.next(err);
  }

  dynamic _redact(dynamic data) {
    if (data is Map) {
      return data.map((key, value) {
        final isSensitive = _sensitiveKeyFragments.any((fragment) => key.toString().toLowerCase().contains(fragment));
        return MapEntry(key, isSensitive ? '***REDACTED***' : _redact(value));
      });
    }
    if (data is List) {
      return data.map(_redact).toList();
    }
    return data;
  }
}
