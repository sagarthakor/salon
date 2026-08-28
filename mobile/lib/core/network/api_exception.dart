import 'package:dio/dio.dart';

/// Broad category of failure, used by the UI to decide how to react
/// (e.g. show a retry button for [network]/[timeout], redirect to login for
/// [unauthorized], render field errors for [validation]).
enum ApiErrorType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  rateLimited,
  server,
  /// HTTP 402 — the tenant's subscription is not in an access-allowed state
  /// (Phase 10). Screens should surface the backend's message and point the
  /// owner at the Subscription screen rather than treating this as a
  /// generic error; see OWNER_APP_ARCHITECTURE.md / SAAS_BILLING_ARCHITECTURE.md.
  paymentRequired,
  unknown,
}

/// A normalized failure thrown by [ApiClient] for every network/API error.
/// UI code should never need to inspect a raw [DioException] or the backend's
/// `{success, message, errors}` envelope directly.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.type,
    this.statusCode,
    this.fieldErrors,
  });

  final String message;
  final ApiErrorType type;
  final int? statusCode;

  /// Laravel Form Request validation errors, keyed by field name (e.g.
  /// `items.0.service_id`), each a list of human-readable messages.
  final Map<String, List<String>>? fieldErrors;

  String? firstErrorFor(String field) => fieldErrors?[field]?.first;

  @override
  String toString() => message;
}

class ApiExceptionMapper {
  const ApiExceptionMapper._();

  static ApiException fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          message: 'The request timed out. Please try again.',
          type: ApiErrorType.timeout,
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          message: 'No internet connection. Please check your connection and try again.',
          type: ApiErrorType.network,
        );
      case DioExceptionType.cancel:
        return const ApiException(
          message: 'The request was cancelled.',
          type: ApiErrorType.unknown,
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'Could not establish a secure connection.',
          type: ApiErrorType.unknown,
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
      default:
        return _fromResponse(error);
    }
  }

  static ApiException _fromResponse(DioException error) {
    final response = error.response;
    if (response == null) {
      return const ApiException(
        message: 'No internet connection. Please check your connection and try again.',
        type: ApiErrorType.network,
      );
    }

    final statusCode = response.statusCode ?? 0;
    String message = 'Something went wrong. Please try again.';
    Map<String, List<String>>? fieldErrors;

    final body = response.data;
    if (body is Map) {
      final backendMessage = body['message'];
      if (backendMessage is String && backendMessage.isNotEmpty) {
        message = backendMessage;
      }
      final errors = body['errors'];
      if (errors is Map) {
        fieldErrors = errors.map(
          (key, value) => MapEntry(
            key.toString(),
            value is List ? value.map((v) => v.toString()).toList() : [value.toString()],
          ),
        );
      }
    }

    final type = switch (statusCode) {
      401 => ApiErrorType.unauthorized,
      403 => ApiErrorType.forbidden,
      402 => ApiErrorType.paymentRequired,
      404 => ApiErrorType.notFound,
      409 => ApiErrorType.conflict,
      422 => ApiErrorType.validation,
      429 => ApiErrorType.rateLimited,
      _ when statusCode >= 500 => ApiErrorType.server,
      _ => ApiErrorType.unknown,
    };

    if (type == ApiErrorType.server) {
      message = 'The server ran into a problem. Please try again shortly.';
    }
    if (type == ApiErrorType.network) {
      message = 'No internet connection. Please check your connection and try again.';
    }

    return ApiException(
      message: message,
      type: type,
      statusCode: statusCode,
      fieldErrors: fieldErrors,
    );
  }
}
