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

  Widget buildApp() {
    final router = GoRouter(
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
}
