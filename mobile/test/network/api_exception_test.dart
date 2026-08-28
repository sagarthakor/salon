import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/core/network/api_exception.dart';

RequestOptions _options() => RequestOptions(path: '/test');

void main() {
  group('ApiExceptionMapper.fromDioException', () {
    test('maps a connection timeout to ApiErrorType.timeout', () {
      final error = DioException(requestOptions: _options(), type: DioExceptionType.connectionTimeout);
      final result = ApiExceptionMapper.fromDioException(error);
      expect(result.type, ApiErrorType.timeout);
    });

    test('maps a connection error (no internet) to ApiErrorType.network', () {
      final error = DioException(requestOptions: _options(), type: DioExceptionType.connectionError);
      final result = ApiExceptionMapper.fromDioException(error);
      expect(result.type, ApiErrorType.network);
      expect(result.message, contains('No internet connection'));
    });

    test('maps a 401 response to ApiErrorType.unauthorized', () {
      final error = _responseError(401, {'success': false, 'message': 'Unauthenticated.', 'errors': {}});
      expect(ApiExceptionMapper.fromDioException(error).type, ApiErrorType.unauthorized);
    });

    test('maps a 409 response to ApiErrorType.conflict and preserves the backend message', () {
      final error = _responseError(409, {
        'success': false,
        'message': 'That slot is no longer available.',
        'errors': {'booking': ['That slot is no longer available.']},
      });
      final result = ApiExceptionMapper.fromDioException(error);
      expect(result.type, ApiErrorType.conflict);
      expect(result.message, 'That slot is no longer available.');
    });

    test('maps a 422 response to ApiErrorType.validation and parses field errors', () {
      final error = _responseError(422, {
        'success': false,
        'message': 'The submitted data is invalid.',
        'errors': {
          'email': ['The email field is required.'],
          'password': ['The password must be at least 12 characters.'],
        },
      });
      final result = ApiExceptionMapper.fromDioException(error);
      expect(result.type, ApiErrorType.validation);
      expect(result.firstErrorFor('email'), 'The email field is required.');
      expect(result.firstErrorFor('password'), 'The password must be at least 12 characters.');
      expect(result.firstErrorFor('missing'), isNull);
    });

    test('maps a 5xx response to ApiErrorType.server with a generic message', () {
      final error = _responseError(500, {'success': false, 'message': 'boom', 'errors': {}});
      final result = ApiExceptionMapper.fromDioException(error);
      expect(result.type, ApiErrorType.server);
      expect(result.message, isNot('boom'));
    });

    test('maps a 429 response to ApiErrorType.rateLimited', () {
      final error = _responseError(429, {'success': false, 'message': 'Too many requests.', 'errors': {}});
      expect(ApiExceptionMapper.fromDioException(error).type, ApiErrorType.rateLimited);
    });
  });
}

DioException _responseError(int statusCode, Map<String, dynamic> body) {
  final options = _options();
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: statusCode, data: body),
  );
}
