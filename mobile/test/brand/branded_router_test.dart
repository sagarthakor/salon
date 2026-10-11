import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/brand/brand_config.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/routing/app_router.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/notifications/presentation/providers/notification_providers.dart';
import 'package:salon_customer/features/profile/data/models/customer_profile.dart';
import 'package:salon_customer/features/profile/presentation/providers/profile_providers.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';

import '../support/fakes.dart';

/// End-to-end exercise of `app_router.dart`'s branded-app behavior (see
/// `BrandConfig.singleSalon`): no discovery UI, owner/staff routes absent
/// even by direct navigation, and a non-customer account seeing a plain
/// explainer instead of a nonexistent owner/staff shell. Every test in this
/// file runs with the same `BrandConfig.current` (set once, restored once)
/// so it never contaminates other test files' assumption that the default
/// build (`BrandConfig.standard`) is what's active.
void main() {
  final original = BrandConfig.current;

  setUpAll(() => BrandConfig.current = BrandConfig.nilHairPort);
  tearDownAll(() => BrandConfig.current = original);

  late MockAuthRepository authRepository;
  late MockSalonRepository salonRepository;
  late MockBookingRepository bookingRepository;
  late MockProfileRepository profileRepository;
  late MockNotificationRepository notificationRepository;

  const testSalon = Salon(
    id: 'salon-nil-hair-port',
    name: 'Nil Hair Port Unisex',
    slug: 'nil-hair-port-unisex',
    genderType: 'unisex',
    address: Address(line1: '12 MG Road', city: 'Surat'),
    status: 'active',
  );

  ProviderContainer buildContainer(String backendRole) {
    final secureStorage = FakeSecureStorage();
    secureStorage.saveToken('test-token');
    when(() => authRepository.me()).thenAnswer(
      (_) async => AppUser(id: 1, name: 'Test User', email: 'test@example.test', role: backendRole),
    );
    when(() => salonRepository.salonForTenant(any())).thenAnswer((_) async => testSalon);
    when(() => bookingRepository.myBookings(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);
    when(() => profileRepository.show()).thenAnswer(
      (_) async => const CustomerProfile(id: 'c1', name: 'Test User', phone: '9000000000', status: 'active'),
    );
    when(() => notificationRepository.unreadCount()).thenAnswer((_) async => 0);

    return ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
        authRepositoryProvider.overrideWithValue(authRepository),
        salonRepositoryProvider.overrideWithValue(salonRepository),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        notificationRepositoryProvider.overrideWithValue(notificationRepository),
      ],
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
    salonRepository = MockSalonRepository();
    bookingRepository = MockBookingRepository();
    profileRepository = MockProfileRepository();
    notificationRepository = MockNotificationRepository();
  });

  Future<void> pumpSettled(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('a customer session on the branded app shows Nil Hair Port branding, never salon discovery', (tester) async {
    final container = buildContainer('customer');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Nil Hair Port Unisex'), findsOneWidget);
    expect(find.text('Book Now'), findsOneWidget);
    expect(find.text('Find a Salon'), findsNothing, reason: 'the branded app must never show the multi-tenant discovery UI');
    expect(find.text('Search salons'), findsNothing);
  });

  testWidgets('a customer on the branded app cannot reach /owner — it does not exist in this build', (tester) async {
    final container = buildContainer('customer');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/owner');
    await pumpSettled(tester);

    expect(find.text('Nil Hair Port Unisex'), findsOneWidget, reason: 'must redirect straight back to the branded home, never an owner shell');
  });

  testWidgets('an owner account signing into the branded app sees a customers-only explainer, not the owner shell', (tester) async {
    final container = buildContainer('salon_owner');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Nil Hair Port Unisex is for customers only'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('a staff account signing into the branded app also sees the customers-only explainer', (tester) async {
    final container = buildContainer('staff');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Nil Hair Port Unisex is for customers only'), findsOneWidget);
  });
}
