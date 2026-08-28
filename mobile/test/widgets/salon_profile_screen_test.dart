import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';
import 'package:salon_customer/features/owner/salon/presentation/screens/salon_profile_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';

import '../support/fakes.dart';

/// Covers the bug fixed after real-device testing surfaced it: a freshly
/// self-registered owner (Tenant + trial, no Salon yet) must be offered a
/// CREATE form here instead of the raw
/// "No query results for model [App\Models\Salon]." error. See
/// OWNER_APP_ARCHITECTURE.md, "Owner onboarding: salon setup".
void main() {
  late MockOwnerSalonRepository salonRepository;
  late MockAuthRepository authRepository;
  late GoRouter router;

  Widget buildApp() {
    router = GoRouter(
      initialLocation: '/owner/salon',
      routes: [
        GoRoute(path: '/owner/salon', builder: (context, state) => const SalonProfileScreen()),
        GoRoute(path: '/owner', builder: (context, state) => const Scaffold(body: Text('Owner Dashboard'))),
        GoRoute(path: '/owner/salon/settings', builder: (context, state) => const Scaffold(body: Text('Settings'))),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
        ownerSalonRepositoryProvider.overrideWithValue(salonRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    salonRepository = MockOwnerSalonRepository();
    authRepository = MockAuthRepository();
    when(() => authRepository.me()).thenAnswer(
      (_) async => const AppUser(id: 1, name: 'Owner Admin', email: 'owner@example.test', role: 'salon_owner'),
    );
  });

  testWidgets('an existing salon renders the edit form pre-filled, not the create form', (tester) async {
    when(() => salonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Royal Gents',
        slug: 'royal-gents',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Royal Gents'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Create salon profile'), findsNothing);
  });

  testWidgets('a 404 (no salon yet) shows the create form, never the raw backend error', (tester) async {
    when(() => salonRepository.show()).thenThrow(
      const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Create salon profile'), findsOneWidget);
    expect(find.textContaining('No query results for model'), findsNothing);
    expect(find.textContaining("Let's set up your salon"), findsOneWidget);
  });

  testWidgets('submitting the create form calls create(), not update()', (tester) async {
    when(() => salonRepository.show()).thenThrow(
      const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
    );
    when(
      () => salonRepository.create(
        name: any(named: 'name'),
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: any(named: 'instagramUrl'),
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
      ),
    ).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'New Salon',
        slug: 'new-salon',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Salon name'), 'New Salon');
    await tester.ensureVisible(find.text('Create salon profile'));
    await tester.tap(find.text('Create salon profile'));
    await tester.pump();
    await tester.pump();

    verify(
      () => salonRepository.create(
        name: 'New Salon',
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: any(named: 'instagramUrl'),
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
      ),
    ).called(1);
    verifyNever(() => salonRepository.update(name: any(named: 'name'), genderType: any(named: 'genderType')));
    expect(find.text('Owner Dashboard'), findsOneWidget);
  });

  testWidgets('displays the existing salon Instagram URL, pre-filled — separate from any service Instagram link', (tester) async {
    when(() => salonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        instagramUrl: 'https://www.instagram.com/primehairstudio/',
        address: Address(),
        status: 'active',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'https://www.instagram.com/primehairstudio/'), findsOneWidget);
  });

  testWidgets('owner can add a salon Instagram URL and save it', (tester) async {
    when(() => salonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );
    when(
      () => salonRepository.update(
        name: any(named: 'name'),
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: any(named: 'instagramUrl'),
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
        status: any(named: 'status'),
      ),
    ).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        instagramUrl: 'https://www.instagram.com/primehairstudio/',
        address: Address(),
        status: 'active',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Instagram profile (optional)'),
      'https://www.instagram.com/primehairstudio/',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => salonRepository.update(
        name: 'Prime Hair Studio',
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: 'https://www.instagram.com/primehairstudio/',
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
        status: any(named: 'status'),
      ),
    ).called(1);
  });

  testWidgets('owner can clear an existing Instagram URL to remove it', (tester) async {
    when(() => salonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        instagramUrl: 'https://www.instagram.com/primehairstudio/',
        address: Address(),
        status: 'active',
      ),
    );
    when(
      () => salonRepository.update(
        name: any(named: 'name'),
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: any(named: 'instagramUrl'),
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
        status: any(named: 'status'),
      ),
    ).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Instagram profile (optional)'), '');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => salonRepository.update(
        name: 'Prime Hair Studio',
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: '',
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
        status: any(named: 'status'),
      ),
    ).called(1);
  });

  testWidgets('shows the server-side field error for an invalid Instagram URL', (tester) async {
    when(() => salonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Prime Hair Studio',
        slug: 'prime-hair-studio',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );
    when(
      () => salonRepository.update(
        name: any(named: 'name'),
        genderType: any(named: 'genderType'),
        description: any(named: 'description'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        website: any(named: 'website'),
        instagramUrl: any(named: 'instagramUrl'),
        addressLine1: any(named: 'addressLine1'),
        city: any(named: 'city'),
        timezone: any(named: 'timezone'),
        status: any(named: 'status'),
      ),
    ).thenThrow(
      const ApiException(
        message: 'The submitted data is invalid.',
        type: ApiErrorType.validation,
        statusCode: 422,
        fieldErrors: {
          'instagram_url': ['The Instagram URL must be a valid instagram.com profile link.'],
        },
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Instagram profile (optional)'),
      'https://www.facebook.com/primehairstudio/',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('The Instagram URL must be a valid instagram.com profile link.'), findsOneWidget);
  });

  group('real-device bug fix: settings icon reachability', () {
    // Root cause of the raw "No query results for model [App\Models\Salon]"
    // error real-device testing found: Booking Settings requires a Salon
    // to exist (`SalonController::settings()`), but the icon reaching it
    // was shown unconditionally, even while the owner was still filling in
    // the CREATE form. See MASTER_CATALOG_ARCHITECTURE.md, "Onboarding UI
    // safety".
    testWidgets('does not show the settings icon while creating a new salon profile', (tester) async {
      when(() => salonRepository.show()).thenThrow(
        const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('shows the settings icon once an existing salon has loaded', (tester) async {
      when(() => salonRepository.show()).thenAnswer(
        (_) async => const Salon(
          id: 'salon-1',
          name: 'Royal Gents',
          slug: 'royal-gents',
          genderType: 'unisex',
          address: Address(),
          status: 'active',
        ),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });
  });

  group('real-device bug fix: salon state refreshes without an app restart', () {
    // The other half of the real-device fix: the backend now provisions the
    // Salon (and its default branch/catalog) atomically inside POST /salon,
    // so `show()` must resolve the fresh Salon on its very next call — the
    // exact call `ref.invalidate(ownerSalonProvider)` triggers — with no
    // app restart in between. Before this fix, restarting the app was the
    // only way this ever worked on the real device.
    testWidgets('after creating a salon, navigating back to this screen shows the fresh salon immediately, not the create form again', (tester) async {
      var salonCreated = false;
      when(() => salonRepository.show()).thenAnswer((_) async {
        if (!salonCreated) {
          throw const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404);
        }
        return const Salon(id: 'salon-9', name: 'Sunny Unisex Salon', slug: 'sunny-unisex-salon', genderType: 'unisex', address: Address(), status: 'active');
      });
      when(
        () => salonRepository.create(
          name: any(named: 'name'),
          genderType: any(named: 'genderType'),
          description: any(named: 'description'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          website: any(named: 'website'),
          instagramUrl: any(named: 'instagramUrl'),
          addressLine1: any(named: 'addressLine1'),
          city: any(named: 'city'),
          timezone: any(named: 'timezone'),
        ),
      ).thenAnswer((_) async {
        salonCreated = true;
        return const Salon(id: 'salon-9', name: 'Sunny Unisex Salon', slug: 'sunny-unisex-salon', genderType: 'unisex', address: Address(), status: 'active');
      });

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();
      expect(find.text('Create salon profile'), findsOneWidget, reason: 'no salon yet');

      await tester.enterText(find.widgetWithText(TextFormField, 'Salon name'), 'Sunny Unisex Salon');
      await tester.ensureVisible(find.text('Create salon profile'));
      await tester.tap(find.text('Create salon profile'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Owner Dashboard'), findsOneWidget, reason: 'create() succeeded and navigated away');

      // Simulate the owner tapping back into Salon (e.g. from the dashboard
      // setup banner, or the More tab) in the very same app session.
      router.go('/owner/salon');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Sunny Unisex Salon'), findsOneWidget, reason: 'the freshly created salon must load without a restart');
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Create salon profile'), findsNothing);
      expect(find.textContaining('No query results for model'), findsNothing);
      expect(find.textContaining('App\\Models\\Salon'), findsNothing);
    });
  });
}
