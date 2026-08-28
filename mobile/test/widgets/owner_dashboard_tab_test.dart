import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/owner/dashboard/data/models/dashboard_summary.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/screens/dashboard_tab.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';

import '../support/fakes.dart';

void main() {
  late MockDashboardRepository dashboardRepository;
  late MockAuthRepository authRepository;
  late MockOwnerSalonRepository ownerSalonRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
        ownerSalonRepositoryProvider.overrideWithValue(ownerSalonRepository),
      ],
      child: const MaterialApp(home: DashboardTab()),
    );
  }

  setUp(() {
    dashboardRepository = MockDashboardRepository();
    authRepository = MockAuthRepository();
    ownerSalonRepository = MockOwnerSalonRepository();
    when(() => authRepository.me()).thenAnswer(
      (_) async => const AppUser(id: 1, name: 'Owner Admin', email: 'owner@example.test', role: 'salon_owner'),
    );
    // Default: an owner who has already completed Salon setup — the
    // "no salon yet" setup-banner case is covered in its own test below.
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
  });

  testWidgets('shows booking counts, revenue, and staff/customer stats from real backend data', (tester) async {
    when(() => dashboardRepository.summary()).thenAnswer(
      (_) async => const DashboardSummary(
        date: '2026-08-23',
        bookingCounts: {'total': 5, 'pending': 2, 'confirmed': 3},
        revenueToday: 1500,
        activeStaff: 3,
        staffOnLeaveToday: 1,
        totalCustomers: 42,
        newCustomersThisMonth: 4,
        nextAppointment: NextAppointment(
          id: 'bk-1',
          bookingDate: '2026-08-23',
          startTime: '15:00',
          status: 'confirmed',
          customerName: 'Anita Rao',
        ),
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('₹1500'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // active staff stat card
    expect(find.text('1 on leave today'), findsOneWidget);
    expect(find.text('+4 this month'), findsOneWidget);
    expect(find.text('2026-08-23 at 15:00'), findsOneWidget);
    expect(find.text('Anita Rao'), findsOneWidget);
  });

  testWidgets('shows "No upcoming appointments" instead of fabricating one when there is none', (tester) async {
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

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No upcoming appointments.'), findsOneWidget);
  });

  testWidgets('shows an error view with retry when the dashboard summary request fails', (tester) async {
    when(() => dashboardRepository.summary()).thenThrow(Exception('network down'));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not load the dashboard.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows a salon setup prompt for a new owner who has no salon yet', (tester) async {
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
    when(() => ownerSalonRepository.show()).thenThrow(
      const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Set up your salon profile'), findsOneWidget);
    expect(find.textContaining('No query results for model'), findsNothing);
  });

  testWidgets('does not show the salon setup prompt for an owner who already has a salon', (tester) async {
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

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Set up your salon profile'), findsNothing);
  });
}
