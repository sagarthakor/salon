import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user});

  final AuthStatus status;
  final AppUser? user;

  AuthState copyWith({AuthStatus? status, AppUser? user}) =>
      AuthState(status: status ?? this.status, user: user ?? this.user);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));

/// Owns the session: token restoration at startup, login/register/logout, and
/// reacting to a 401 from anywhere in the app (wired to [ApiClient.onUnauthorized]
/// once, here, rather than every screen checking for it itself).
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    _ref.read(apiClientProvider).onUnauthorized = () => logout(silent: true);
    _restoreSession();
  }

  final Ref _ref;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);
  SecureStorage get _storage => _ref.read(secureStorageProvider);

  Future<void> _restoreSession() async {
    final token = await _storage.readToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repository.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException {
      await _storage.clearToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _repository.login(email: email, password: password);
    await _storage.saveToken(result.token);
    state = AuthState(status: AuthStatus.authenticated, user: result.user);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final result = await _repository.register(
      name: name,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
    await _storage.saveToken(result.token);
    state = AuthState(status: AuthStatus.authenticated, user: result.user);
  }

  /// Self-service salon-owner registration. Sets [ApiClient.tenantSlug] from
  /// the response so the new owner's very first request in the owner app
  /// already resolves to the tenant just created for them, through the same
  /// `X-Tenant-Slug` mechanism every other tenant-scoped request already
  /// uses (see `ApiClient`) — though the backend's own fallback (a user
  /// with exactly one tenant membership resolves to it even with no header
  /// at all) means this isn't strictly load-bearing for a brand-new owner
  /// today, only ever-correct.
  Future<void> registerOwner({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String salonName,
    String? slug,
  }) async {
    final result = await _repository.registerOwner(
      name: name,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
      salonName: salonName,
      slug: slug,
    );
    await _storage.saveToken(result.token);
    _ref.read(apiClientProvider).tenantSlug = result.tenantSlug;
    state = AuthState(status: AuthStatus.authenticated, user: result.user);
  }

  Future<void> logout({bool silent = false}) async {
    if (!silent) {
      try {
        await _repository.logout();
      } on ApiException {
        // Token may already be invalid/expired server-side — still clear locally.
      }
    }
    await _storage.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref));
