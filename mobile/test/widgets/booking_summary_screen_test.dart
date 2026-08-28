import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_summary_screen.dart';
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
  final slot = AvailabilitySlot.fromJson({'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']});

  BookingFlowController seededController(MockBookingRepository repository) {
    final controller = BookingFlowController(repository);
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    controller.setDate(DateTime(2026, 9, 1));
    controller.selectSlot(slot);
    return controller;
  }

  Widget buildApp(BookingFlowController controller) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const BookingSummaryScreen()),
        GoRoute(
          path: '/booking/confirmation',
          builder: (context, state) => const Scaffold(body: Text('Confirmation placeholder')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingFlowControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shows a full review of branch, services, date, time, and estimated total', (tester) async {
    final repository = MockBookingRepository();
    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer((_) async => AvailabilityResult.fromJson({
          'date': '2026-09-01',
          'duration_minutes': 30,
          'buffer_minutes': 0,
          'slots': <dynamic>[],
          'staff': <dynamic>[],
        }));

    await tester.pumpWidget(buildApp(seededController(repository)));
    await tester.pump();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.textContaining('Total (estimated): ₹300'), findsOneWidget);
  });

  testWidgets('tapping Confirm calls createBooking with the selected service/slot', (tester) async {
    final repository = MockBookingRepository();
    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer((_) async => AvailabilityResult.fromJson({
          'date': '2026-09-01',
          'duration_minutes': 30,
          'buffer_minutes': 0,
          'slots': <dynamic>[],
          'staff': <dynamic>[],
        }));
    when(
      () => repository.createBooking(
        branchId: 'br_1',
        date: '2026-09-01',
        startTime: '09:00',
        items: any(named: 'items'),
        notes: any(named: 'notes'),
      ),
    ).thenAnswer(
      (_) async => Booking.fromJson({
        'id': 'bk_1',
        'branch_id': 'br_1',
        'booking_date': '2026-09-01',
        'start_time': '09:00',
        'end_time': '09:30',
        'status': 'pending',
        'subtotal': '300.00',
        'discount': '0.00',
        'tax': '0.00',
        'total': '300.00',
      }),
    );

    await tester.pumpWidget(buildApp(seededController(repository)));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pump();
    await tester.pump();

    verify(
      () => repository.createBooking(
        branchId: 'br_1',
        date: '2026-09-01',
        startTime: '09:00',
        items: any(named: 'items'),
        notes: any(named: 'notes'),
      ),
    ).called(1);
    expect(find.text('Confirmation placeholder'), findsOneWidget);
  });
}
