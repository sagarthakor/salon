import 'user.dart';

/// Mirrors the `{user, token, tenant_slug}` payload returned by
/// `POST /auth/register-owner` — a deliberately separate shape from
/// [AuthResult] (used by login/plain register) since only this flow ever
/// returns a `tenant_slug`: the newly-created tenant the caller just became
/// the owner of.
class OwnerRegistrationResult {
  const OwnerRegistrationResult({required this.user, required this.token, required this.tenantSlug});

  factory OwnerRegistrationResult.fromJson(Map<String, dynamic> json) => OwnerRegistrationResult(
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    token: json['token'] as String,
    tenantSlug: json['tenant_slug'] as String,
  );

  final AppUser user;
  final String token;
  final String tenantSlug;
}
