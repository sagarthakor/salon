import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/routing/app_router.dart';
import 'package:salon_customer/features/auth/data/models/app_role.dart';
import 'package:salon_customer/features/auth/data/models/owner_registration_result.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';

import '../support/fakes.dart';

/// Two things worth proving here that no other test file covers:
///
/// 1. The registration-choice/owner-registration routes are reachable by an
///    unauthenticated session (unlike almost every other route) — a plain
///    router-redirect check, same style as `owner_router_authorization_test.dart`.
/// 2. A successful `registerOwner()` call produces exactly the `AuthState`
///    (authenticated, `salon_owner` role, `hasSalonProfile: false`) that the
///    router's own redirect logic resolves to `/owner/salon` (Salon setup)
///    rather than `/owner` — a brand-new owner has no Salon yet (see
///    "Owner onboarding: salon setup" in OWNER_APP_ARCHITECTURE.md). This is
///    asserted both at the state level here and via a full router redirect
///    below (`owner_router_authorization_test.dart` separately covers the
///    ordinary `salon_owner` -> `/owner` case for an owner who already has
///    one, i.e. `hasSalonProfile` unset).
void main() {
  late MockAuthRepository authRepository;
  late MockOwnerSalonRepository ownerSalonRepository;

  setUp(() {
    authRepository = MockAuthRepository();
    ownerSalonRepository = MockOwnerSalonRepository();
    // The Salon Profile screen this test lands on watches this repository —
    // a freshly registered owner genuinely has no Salon yet, so GET /salon
    // 404s, same as production.
    when(() => ownerSalonRepository.show()).thenThrow(
      const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
    );
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
    // Deterministic — a just-created tenant can never have a Salon yet, so
    // this never re-fetches from the backend. Drives the router redirect
    // below.
    expect(authState.hasSalonProfile, isFalse);
  });

  testWidgets('a freshly-registered owner with no salon yet lands on Salon setup, not the dashboard', (tester) async {
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
        ownerSalonRepositoryProvider.overrideWithValue(ownerSalonRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    await container.read(authControllerProvider.notifier).registerOwner(
      name: 'Asha Owner',
      email: 'asha-owner@example.test',
      password: 'SecurePassword1!',
      passwordConfirmation: 'SecurePassword1!',
      salonName: 'Asha Hair Studio',
    );
    await pumpSettled(tester);

    expect(find.text('Salon'), findsOneWidget, reason: 'should land on SalonProfileScreen, not the owner dashboard');
    expect(find.text('Dashboard'), findsNothing);
  });
}
