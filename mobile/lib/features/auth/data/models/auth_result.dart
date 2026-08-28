import 'user.dart';

/// Mirrors the `{user, token}` payload returned by `POST /auth/login` and
/// `POST /auth/register`.
class AuthResult {
  const AuthResult({required this.user, required this.token});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    token: json['token'] as String,
  );

  final AppUser user;
  final String token;
}
