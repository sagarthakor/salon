import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/routing/app_router.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/customers/presentation/providers/owner_customer_providers.dart';
import 'package:salon_customer/features/owner/dashboard/data/models/dashboard_summary.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_member.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/notifications/presentation/providers/notification_providers.dart';
import 'package:salon_customer/features/profile/presentation/providers/profile_providers.dart';
import 'package:salon_customer/features/profile/data/models/customer_profile.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';

import '../support/fakes.dart';

/// Real, end-to-end exercise of the [routerProvider] redirect logic in
/// `app_router.dart` — role checks there are UI/navigation-only, but this
/// still verifies the actual behavior a misclassified role would produce
/// (see OWNER_APP_ARCHITECTURE.md: the backend independently authorizes
/// every request no matter what this router decides to show).
void main() {
  late MockAuthRepository authRepository;
  late MockDashboardRepository dashboardRepository;
  late MockBookingRepository bookingRepository;
  late MockStaffRepository staffRepository;
  late MockOwnerCustomerRepository ownerCustomerRepository;
  late MockSalonRepository salonRepository;
  late MockOwnerSalonRepository ownerSalonRepository;
  late MockProfileRepository profileRepository;
  late MockNotificationRepository notificationRepository;

  ProviderContainer buildContainer(String backendRole) {
    final secureStorage = FakeSecureStorage();
    secureStorage.saveToken('test-token');
    when(() => authRepository.me()).thenAnswer(
      (_) async => AppUser(id: 1, name: 'Test User', email: 'test@example.test', role: backendRole),
    );

    // Owner-shell tabs (IndexedStack builds all of them immediately).
    when(() => dashboardRepository.summary()).thenAnswer(
      (_) async => const DashboardSummary(
        date: '2026-08-23',
        bookingCounts: {'total': 0},
        revenueToday: 0,
        activeStaff: 0,
        staffOnLeaveToday: 0,
        totalCustomers: 0,
        newCustomersThisMonth: 0,
      ),
    );
    when(
      () => bookingRepository.ownerBookings(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        date: any(named: 'date'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        staffId: any(named: 'staffId'),
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenAnswer((_) async => []);

    // Staff-shell tabs (IndexedStack builds all of them immediately too).
    when(() => staffRepository.me()).thenAnswer(
      (_) async => const StaffMember(id: 'stf-1', name: 'Test User', gender: 'male', status: 'active'),
    );
    when(() => staffRepository.workingHours('stf-1')).thenAnswer((_) async => []);
    when(() => staffRepository.breaks('stf-1')).thenAnswer((_) async => []);
    when(() => staffRepository.leaves('stf-1')).thenAnswer((_) async => []);
    when(() => staffRepository.services('stf-1')).thenAnswer((_) async => []);
    when(
      () => ownerCustomerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => []);

    // Home-shell tabs.
    when(() => salonRepository.mySalons()).thenAnswer((_) async => []);
    when(() => bookingRepository.myBookings(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);
    when(() => profileRepository.show()).thenAnswer(
      (_) async => const CustomerProfile(id: 'c1', name: 'Test User', phone: '9000000000', status: 'active'),
    );

    // MoreTab (owner), StaffProfileScreen, and ProfileScreen all watch this
    // for their notification-bell badge.
    when(() => notificationRepository.unreadCount()).thenAnswer((_) async => 0);

    // DashboardTab's setup-prompt safety net watches this too — an owner in
    // these router tests already has a Salon (existing-owner behavior must
    // stay unchanged; the "no salon yet" case is covered separately).
    when(() => ownerSalonRepository.show()).thenAnswer(
      (_) async => const Salon(
        id: 'salon-1',
        name: 'Test Salon',
        slug: 'test-salon',
        genderType: 'unisex',
        address: Address(),
        status: 'active',
      ),
    );

    return ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
        authRepositoryProvider.overrideWithValue(authRepository),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
        staffRepositoryProvider.overrideWithValue(staffRepository),
        ownerCustomerRepositoryProvider.overrideWithValue(ownerCustomerRepository),
        salonRepositoryProvider.overrideWithValue(salonRepository),
        ownerSalonRepositoryProvider.overrideWithValue(ownerSalonRepository),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        notificationRepositoryProvider.overrideWithValue(notificationRepository),
      ],
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
    dashboardRepository = MockDashboardRepository();
    bookingRepository = MockBookingRepository();
    staffRepository = MockStaffRepository();
    ownerCustomerRepository = MockOwnerCustomerRepository();
    salonRepository = MockSalonRepository();
    ownerSalonRepository = MockOwnerSalonRepository();
    profileRepository = MockProfileRepository();
    notificationRepository = MockNotificationRepository();
  });

  Future<void> pumpSettled(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('a customer session lands on /home, never /owner', (tester) async {
    final container = buildContainer('customer');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('a customer cannot navigate into /owner — the router redirects back to /home', (tester) async {
    final container = buildContainer('customer');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/owner');
    await pumpSettled(tester);

    expect(find.text('Home'), findsOneWidget, reason: 'the owner-only shell must never render for a customer role');
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('a salon_owner session lands on /owner, never /home', (tester) async {
    final container = buildContainer('salon_owner');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('an owner cannot navigate into customer-only booking screens — redirected back to /owner', (tester) async {
    final container = buildContainer('salon_owner');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/booking/services');
    await pumpSettled(tester);

    expect(find.text('Dashboard'), findsOneWidget, reason: 'the customer booking flow must never render for an owner/admin role');
  });

  testWidgets('a super_admin session is classified the same as salon_owner (ownerAdmin)', (tester) async {
    final container = buildContainer('super_admin');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('a staff session lands on the real staff app at /staff, not the owner or customer app', (tester) async {
    final container = buildContainer('staff');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing, reason: 'the owner dashboard must never render for a staff role');
    expect(find.text('Home'), findsNothing, reason: 'the customer home shell must never render for a staff role');
  });

  testWidgets('a staff session cannot navigate into /owner — the router redirects back to /staff', (tester) async {
    final container = buildContainer('staff');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/owner');
    await pumpSettled(tester);

    expect(find.text('Today'), findsOneWidget, reason: 'the owner shell must never render for a staff role');
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('an owner cannot navigate into /staff — the router redirects back to /owner', (tester) async {
    final container = buildContainer('salon_owner');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    container.read(routerProvider).go('/staff');
    await pumpSettled(tester);

    expect(find.text('Dashboard'), findsOneWidget, reason: 'the staff shell must never render for an owner/admin role');
  });

  testWidgets('an unrecognized backend role is sent to /login, never granted owner or customer navigation', (tester) async {
    final container = buildContainer('some_future_role');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    await pumpSettled(tester);

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Home'), findsNothing);
  });
}
