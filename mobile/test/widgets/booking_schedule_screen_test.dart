import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_schedule_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';

import '../support/fakes.dart';

void main() {
  const branch = Branch(id: 'br_1', name: 'Main', slug: 'main', address: Address(), timezone: 'UTC', status: 'active');
  const haircut = SalonService(
    id: 'sv_1',
    branchId: 'br_1',
    name: 'Haircut',
    slug: 'haircut',
    gender: 'unisex',
    price: 300,
    durationMinutes: 30,
    status: 'active',
    sortOrder: 0,
  );

  final availability = AvailabilityResult.fromJson({
    'date': '2026-09-01',
    'duration_minutes': 30,
    'buffer_minutes': 0,
    'slots': [
      {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
      {'start_time': '09:15', 'end_time': '09:45', 'staff_ids': ['st_1']},
    ],
    'staff': [
      {'id': 'st_1', 'name': 'Amit'},
    ],
  });

  Widget buildApp(MockBookingRepository repository) {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingFlowControllerProvider.overrideWith((ref) {
          final controller = BookingFlowController(repository);
          controller.selectBranch(branch);
          controller.toggleService(haircut);
          return controller;
        }),
      ],
      child: const MaterialApp(home: BookingScheduleScreen()),
    );
  }

  testWidgets('selecting a date fetches availability and shows slot choices; selecting a slot enables Next', (
    tester,
  ) async {
    final repository = MockBookingRepository();
    when(
      () => repository.availability(
        branchId: 'br_1',
        date: any(named: 'date'),
        serviceIds: ['sv_1'],
        staffId: null,
      ),
    ).thenAnswer((_) async => availability);

    await tester.pumpWidget(buildApp(repository));
    await tester.pump();

    expect(find.text('Choose a date to see available times.'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('9:15 AM'), findsOneWidget);

    final nextButtonBefore = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(nextButtonBefore.onPressed, isNull);

    await tester.tap(find.text('9:00 AM'));
    await tester.pump();

    final nextButtonAfter = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next'));
    expect(nextButtonAfter.onPressed, isNotNull);
  });

  testWidgets('shows an empty state when there are no available slots for the date', (tester) async {
    final repository = MockBookingRepository();
    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer(
      (_) async => AvailabilityResult.fromJson({
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': <dynamic>[],
        'staff': <dynamic>[],
      }),
    );

    await tester.pumpWidget(buildApp(repository));
    // The first ChoiceChip belongs to the date strip (staff row is empty
    // until a date is picked, so no ambiguity yet).
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('No time slots are available for this date. Please try another date.'), findsOneWidget);
  });
}
