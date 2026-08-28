import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/routing/app_router.dart';
import 'package:salon_customer/features/auth/data/models/app_role.dart';
import 'package:salon_customer/features/auth/data/models/owner_registration_result.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';

import '../support/fakes.dart';

/// Two things worth proving here that no other test file covers:
///
/// 1. The registration-choice/owner-registration routes are reachable by an
///    unauthenticated session (unlike almost every other route) — a plain
///    router-redirect check, same style as `owner_router_authorization_test.dart`.
/// 2. A successful `registerOwner()` call produces exactly the `AuthState`
///    (authenticated, `salon_owner` role) that router's own redirect logic —
///    already exhaustively tested in `owner_router_authorization_test.dart`
///    for every role, including `salon_owner` → `/owner` — resolves to. This
///    is asserted at the state/role level, not by re-rendering a full page
///    transition from a real `LoginScreen`: form-submission wiring is
///    already covered end-to-end by `register_owner_screen_test.dart`, and
///    combining "registerOwner() yields a salon_owner AuthState" with the
///    separately-proven "salon_owner AuthState -> /owner" is exactly what
///    together proves "successful owner registration navigates to /owner",
///    without needing to re-render a live Hero/page-transition sequence.
void main() {
  late MockAuthRepository authRepository;

  setUp(() {
    authRepository = MockAuthRepository();
  });

  Future<void> pumpSettled(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  testWidgets('an unauthenticated session can reach /register-choice and /register-owner without being redirected to /login', (tester) async {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/register-choice');
    await pumpSettled(tester);
    expect(find.text('Register your Salon'), findsOneWidget);

    container.read(routerProvider).go('/register-owner');
    await pumpSettled(tester);
    expect(find.text('Register your salon'), findsOneWidget);
  });

  test('a successful registerOwner() call produces the exact AuthState that resolves to /owner', () async {
    when(
      () => authRepository.registerOwner(
        name: 'Asha Owner',
        email: 'asha-owner@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Asha Hair Studio',
        slug: null,
      ),
    ).thenAnswer(
      (_) async => const OwnerRegistrationResult(
        user: AppUser(id: 9, name: 'Asha Owner', email: 'asha-owner@example.test', role: 'salon_owner'),
        token: 'owner-token',
        tenantSlug: 'asha-hair-studio',
      ),
    );

    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).registerOwner(
      name: 'Asha Owner',
      email: 'asha-owner@example.test',
      password: 'SecurePassword1!',
      passwordConfirmation: 'SecurePassword1!',
      salonName: 'Asha Hair Studio',
    );

    final authState = container.read(authControllerProvider);
    expect(authState.status, AuthStatus.authenticated);
    expect(authState.user?.role, 'salon_owner');
    // The exact classification `owner_router_authorization_test.dart` relies
    // on to redirect a `salon_owner` session to `/owner`.
    expect(AppRole.fromBackendRole(authState.user!.role), AppRole.ownerAdmin);
  });
}
