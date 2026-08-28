import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/owner/dashboard/data/models/dashboard_summary.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:salon_customer/features/owner/dashboard/presentation/screens/dashboard_tab.dart';

import '../support/fakes.dart';

void main() {
  late MockDashboardRepository dashboardRepository;
  late MockAuthRepository authRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
      ],
      child: const MaterialApp(home: DashboardTab()),
    );
  }

  setUp(() {
    dashboardRepository = MockDashboardRepository();
    authRepository = MockAuthRepository();
    when(() => authRepository.me()).thenAnswer(
      (_) async => const AppUser(id: 1, name: 'Owner Admin', email: 'owner@example.test', role: 'salon_owner'),
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
}
