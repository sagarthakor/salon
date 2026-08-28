import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.hasSalonProfile});

  final AuthStatus status;
  final AppUser? user;

  /// Whether the current owner's tenant has completed Salon setup. `null`
  /// for every role other than owner, and for an owner restored from an
  /// existing session (unknown until the dashboard/router actually checks —
  /// see the setup-prompt banner on the Owner Dashboard) — never assume
  /// `null` means "no salon". Only `registerOwner()` sets this deterministically
  /// (`false`, since a just-created tenant can never have a salon yet); this
  /// is a routing hint only, never used for authorization — the backend
  /// remains authoritative (`requireSalon()` on every dependent endpoint).
  final bool? hasSalonProfile;

  AuthState copyWith({AuthStatus? status, AppUser? user, bool? hasSalonProfile}) => AuthState(
    status: status ?? this.status,
    user: user ?? this.user,
    hasSalonProfile: hasSalonProfile ?? this.hasSalonProfile,
  );
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
    state = AuthState(status: AuthStatus.authenticated, user: result.user, hasSalonProfile: false);
  }

  /// Called once the owner's Salon has just been created (see
  /// `SalonProfileScreen`'s create-mode). Routing-only, mirroring
  /// `registerOwner()`'s deterministic `false` — never re-fetched from the
  /// backend here, since the screen just got a 201 from the same endpoint
  /// the router would otherwise re-check.
  void markSalonProfileComplete() {
    state = state.copyWith(hasSalonProfile: true);
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
