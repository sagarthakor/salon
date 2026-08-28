import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/bookings/presentation/screens/owner_reschedule_screen.dart';

import '../support/fakes.dart';

const _bookingId = 'bkg-00000002';

Booking _booking() => const Booking(
  id: _bookingId,
  branchId: 'br-1',
  bookingDate: '2026-08-23',
  startTime: '10:00',
  endTime: '10:30',
  status: BookingStatus.confirmed,
  subtotal: 500,
  discount: 0,
  tax: 0,
  total: 500,
);

void main() {
  late MockBookingRepository bookingRepository;

  late GoRouter router;

  Widget buildApp() {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('behind'))),
        GoRoute(path: '/reschedule', builder: (context, state) => const OwnerRescheduleScreen(bookingId: _bookingId)),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    bookingRepository = MockBookingRepository();
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking());
  });

  testWidgets(
    'picking a date loads availability, picking a slot and confirming calls ownerRescheduleBooking',
    (tester) async {
      when(
        () => bookingRepository.availability(
          branchId: any(named: 'branchId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          staffId: any(named: 'staffId'),
        ),
      ).thenAnswer(
        (_) async => const AvailabilityResult(
          date: '2026-08-24',
          durationMinutes: 30,
          bufferMinutes: 0,
          slots: [AvailabilitySlot(startTime: '11:00', endTime: '11:30', staffIds: ['stf-1'])],
          staff: [],
        ),
      );
      when(
        () => bookingRepository.ownerRescheduleBooking(_bookingId, date: any(named: 'date'), startTime: any(named: 'startTime')),
      ).thenAnswer((_) async => _booking());

      await tester.pumpWidget(buildApp());
      router.push('/reschedule');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Tap the first date chip in the horizontal date strip (today).
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();
      await tester.pump();

      expect(find.text('11:00 AM'), findsOneWidget);
      await tester.tap(find.text('11:00 AM'));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm reschedule'));
      await tester.pump();
      await tester.pump();

      verify(() => bookingRepository.ownerRescheduleBooking(_bookingId, date: any(named: 'date'), startTime: '11:00')).called(1);
    },
  );

  testWidgets('shows the current booking date/time so the owner knows what they are changing', (tester) async {
    when(
      () => bookingRepository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer(
      (_) async => const AvailabilityResult(
        date: '2026-08-24',
        durationMinutes: 30,
        bufferMinutes: 0,
        slots: [AvailabilitySlot(startTime: '11:00', endTime: '11:30', staffIds: ['stf-1'])],
        staff: [],
      ),
    );

    await tester.pumpWidget(buildApp());
    router.push('/reschedule');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Currently: 2026-08-23 at 10:00'), findsOneWidget);
  });
}
