import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/routing/app_router.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/customers/presentation/providers/owner_customer_providers.dart';
import 'package:salon_customer/features/owner/customers/presentation/screens/customer_list_screen.dart';
import 'package:salon_customer/features/owner/dashboard/data/models/dashboard_summary.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/screens/staff_list_screen.dart';
import 'package:salon_customer/features/notifications/presentation/providers/notification_providers.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';

import '../support/fakes.dart';

/// Pre-existing stability bug found during real-device onboarding QA:
/// `StaffListScreen` and `CustomerListScreen` each had a
/// `FloatingActionButton` with no explicit `heroTag`, so both defaulted to
/// the same canonical `_DefaultHeroTag` instance. `OwnerShell`'s
/// `IndexedStack` mounts every tab simultaneously, so both FABs coexisted in
/// the same route subtree — Flutter's Hero controller then threw "multiple
/// heroes share the same tag" whenever an *animated* route transition landed
/// on `/owner` (a redirect-driven initial mount never triggers a Hero flight
/// scan, which is why this went unnoticed by the existing router tests).
void main() {
  late MockAuthRepository authRepository;
  late MockDashboardRepository dashboardRepository;
  late MockBookingRepository bookingRepository;
  late MockStaffRepository staffRepository;
  late MockOwnerCustomerRepository ownerCustomerRepository;
  late MockOwnerSalonRepository ownerSalonRepository;
  late MockNotificationRepository notificationRepository;

  setUp(() {
    authRepository = MockAuthRepository();
    dashboardRepository = MockDashboardRepository();
    bookingRepository = MockBookingRepository();
    staffRepository = MockStaffRepository();
    ownerCustomerRepository = MockOwnerCustomerRepository();
    ownerSalonRepository = MockOwnerSalonRepository();
    notificationRepository = MockNotificationRepository();
  });

  testWidgets("StaffListScreen's FAB and CustomerListScreen's FAB carry distinct, explicit hero tags", (tester) async {
    // Direct, minimal proof of the fix: the two tags a real subtree
    // collision was reported between must now differ and must not be the
    // FloatingActionButton default.
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenAnswer((_) async => []);
    when(
      () => ownerCustomerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(FakeSecureStorage()), staffRepositoryProvider.overrideWithValue(staffRepository)],
        child: const MaterialApp(home: StaffListScreen()),
      ),
    );
    await tester.pump();
    final staffFab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));

    // A bare widget in between forces the previous ProviderScope to fully
    // tear down — pumping a second, differently-overridden ProviderScope
    // directly on top of the first isn't a supported override change.
    await tester.pumpWidget(Container());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          ownerCustomerRepositoryProvider.overrideWithValue(ownerCustomerRepository),
        ],
        child: const MaterialApp(home: CustomerListScreen()),
      ),
    );
    await tester.pump();
    final customerFab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));

    expect(staffFab.heroTag, isNotNull);
    expect(customerFab.heroTag, isNotNull);
    expect(staffFab.heroTag, isNot(equals(customerFab.heroTag)));
  });

  testWidgets('StaffListScreen mounts with its FAB and the FAB still navigates to add-staff', (tester) async {
    when(
      () => staffRepository.list(page: any(named: 'page'), perPage: any(named: 'perPage'), status: any(named: 'status')),
    ).thenAnswer((_) async => []);

    final router = GoRouter(
      initialLocation: '/owner/staff',
      routes: [
        GoRoute(path: '/owner/staff', builder: (context, state) => const StaffListScreen()),
        GoRoute(path: '/owner/staff/new', builder: (context, state) => const Scaffold(body: Text('Add Staff'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(FakeSecureStorage()), staffRepositoryProvider.overrideWithValue(staffRepository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add Staff'), findsOneWidget);
  });

  testWidgets('CustomerListScreen mounts with its FAB and the FAB still navigates to add-customer', (tester) async {
    when(
      () => ownerCustomerRepository.list(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        search: any(named: 'search'),
        status: any(named: 'status'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => []);

    final router = GoRouter(
      initialLocation: '/owner/customers',
      routes: [
        GoRoute(path: '/owner/customers', builder: (context, state) => const CustomerListScreen()),
        GoRoute(path: '/owner/customers/new', builder: (context, state) => const Scaffold(body: Text('Add Customer'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          ownerCustomerRepositoryProvider.overrideWithValue(ownerCustomerRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add Customer'), findsOneWidget);
  });

  testWidgets(
    'both screens coexist inside the real OwnerShell IndexedStack, and an animated transition back into /owner no longer throws',
    (tester) async {
      final secureStorage = FakeSecureStorage();
      secureStorage.saveToken('test-token');
      when(() => authRepository.me()).thenAnswer(
        (_) async => const AppUser(id: 1, name: 'Test Owner', email: 'owner@example.test', role: 'salon_owner'),
      );
      when(() => dashboardRepository.summary()).thenAnswer(
        (_) async => const DashboardSummary(
          date: '2026-08-28',
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
      when(
        () => ownerCustomerRepository.list(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          search: any(named: 'search'),
          status: any(named: 'status'),
          gender: any(named: 'gender'),
        ),
      ).thenAnswer((_) async => []);
      when(() => notificationRepository.unreadCount()).thenAnswer((_) async => 0);
      when(() => ownerSalonRepository.show()).thenAnswer(
        (_) async => const Salon(id: 'salon-1', name: 'Test Salon', slug: 'test-salon', genderType: 'unisex', address: Address(), status: 'active'),
      );

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(secureStorage),
          authRepositoryProvider.overrideWithValue(authRepository),
          dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
          bookingRepositoryProvider.overrideWithValue(bookingRepository),
          staffRepositoryProvider.overrideWithValue(staffRepository),
          ownerCustomerRepositoryProvider.overrideWithValue(ownerCustomerRepository),
          ownerSalonRepositoryProvider.overrideWithValue(ownerSalonRepository),
          notificationRepositoryProvider.overrideWithValue(notificationRepository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: container.read(routerProvider))));
      await tester.pumpAndSettle();

      // Cold start already redirects straight to /owner — no prior route to
      // animate from, so this alone would never have caught the bug (see
      // owner_router_authorization_test.dart, which does exactly this).
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing, reason: 'the Dashboard tab itself has no FAB');

      // Navigate away, then animate back into /owner: this is the exact
      // sequence that previously threw "multiple heroes share the same tag"
      // once OwnerShell's IndexedStack (with both FAB-bearing tabs already
      // built) became the destination of a real transition.
      container.read(routerProvider).go('/owner/salon');
      await tester.pumpAndSettle();
      expect(find.text('Salon'), findsOneWidget);

      container.read(routerProvider).go('/owner');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'the Hero tag collision must no longer be thrown');
      expect(find.text('Dashboard'), findsOneWidget);
    },
  );
}
