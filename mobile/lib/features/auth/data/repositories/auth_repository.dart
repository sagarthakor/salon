import '../../../../core/network/api_client.dart';
import '../models/auth_result.dart';
import '../models/user.dart';

/// Talks to `POST /auth/login`, `POST /auth/register`, `GET /auth/me`, and
/// `POST /auth/logout` — the exact Phase 1 endpoints, no invented routes.
/// UI code goes through [AuthController]/providers, never this class
/// directly.
class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<AuthResult> login({required String email, required String password}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResult.fromJson(data);
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );
    return AuthResult.fromJson(data);
  }

  Future<AppUser> me() async {
    final data = await _client.get<Map<String, dynamic>>('/auth/me');
    return AppUser.fromJson(data);
  }

  Future<void> logout() => _client.post<dynamic>('/auth/logout');
}
