import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/bookings/presentation/screens/owner_booking_details_screen.dart';

import '../support/fakes.dart';

const _bookingId = 'bkg-00000001';

Booking _booking(BookingStatus status) => Booking(
  id: _bookingId,
  branchId: 'br-1',
  bookingDate: '2026-08-23',
  startTime: '10:00',
  endTime: '10:30',
  status: status,
  subtotal: 500,
  discount: 0,
  tax: 0,
  total: 500,
);

void main() {
  late MockBookingRepository bookingRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      ],
      child: const MaterialApp(home: OwnerBookingDetailsScreen(bookingId: _bookingId)),
    );
  }

  setUp(() {
    bookingRepository = MockBookingRepository();
  });

  testWidgets('a pending booking offers Confirm and Cancelled next actions, and Confirm calls confirmBooking', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.pending));
    when(() => bookingRepository.confirmBooking(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.confirmed));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Confirmed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cancelled'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmed'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.confirmBooking(_bookingId)).called(1);
  });

  testWidgets('a confirmed booking offers Checked in, and tapping it calls updateBookingStatus(checked_in)', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.confirmed));
    when(
      () => bookingRepository.updateBookingStatus(_bookingId, status: any(named: 'status')),
    ).thenAnswer((_) async => _booking(BookingStatus.checkedIn));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Checked in'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.updateBookingStatus(_bookingId, status: 'checked_in')).called(1);
  });

  testWidgets('a checked-in booking offers In service, and tapping it calls updateBookingStatus(in_service)', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.checkedIn));
    when(
      () => bookingRepository.updateBookingStatus(_bookingId, status: any(named: 'status')),
    ).thenAnswer((_) async => _booking(BookingStatus.inService));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'In service'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.updateBookingStatus(_bookingId, status: 'in_service')).called(1);
  });

  testWidgets('an in-service booking offers Completed, and tapping it calls updateBookingStatus(completed)', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.inService));
    when(
      () => bookingRepository.updateBookingStatus(_bookingId, status: any(named: 'status')),
    ).thenAnswer((_) async => _booking(BookingStatus.completed));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Completed'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.updateBookingStatus(_bookingId, status: 'completed')).called(1);
  });

  testWidgets('cancelling prompts for a reason and calls ownerCancelBooking, bypassing any cancellation window', (
    tester,
  ) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.confirmed));
    when(
      () => bookingRepository.ownerCancelBooking(_bookingId, reason: any(named: 'reason')),
    ).thenAnswer((_) async => _booking(BookingStatus.cancelled));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Cancelled'));
    await tester.pump();

    expect(find.text('Cancel booking?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Customer requested');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.ownerCancelBooking(_bookingId, reason: 'Customer requested')).called(1);
  });

  testWidgets('a terminal (completed) booking offers no next actions and no reschedule option', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.completed));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Actions'), findsNothing);
    expect(find.text('Reschedule'), findsNothing);
  });

  testWidgets('an upcoming (pending) booking shows a Reschedule button', (tester) async {
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer((_) async => _booking(BookingStatus.pending));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Reschedule'), findsOneWidget);
  });
}
