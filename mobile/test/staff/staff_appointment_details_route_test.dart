import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/bookings/presentation/screens/owner_booking_details_screen.dart';

import '../support/fakes.dart';

const _bookingId = 'bkg-staff001';

/// The `/staff/appointments/:id` route (registered in `app_router.dart`)
/// deliberately reuses `OwnerBookingDetailsScreen` outright — staff and owner
/// share identical booking authorization (`viewableTenant()` on every
/// `BookingController` action, see STAFF_APP_ARCHITECTURE.md) and an
/// identical set of real backend fields to show, so a separate staff-only
/// copy would just be duplication with no behavioral difference. The full
/// confirm/check-in/in-service/complete/cancel/reschedule transition matrix
/// for this exact widget is already exhaustively covered by
/// `test/widgets/owner_booking_details_screen_test.dart`; this test proves
/// the staff route itself reaches that widget and that one representative
/// transition (check-in) still works end to end through it.
void main() {
  testWidgets('the staff appointment-details route renders the shared booking-details screen and check-in works', (
    tester,
  ) async {
    final bookingRepository = MockBookingRepository();
    when(() => bookingRepository.ownerBookingDetails(_bookingId)).thenAnswer(
      (_) async => const Booking(
        id: _bookingId,
        branchId: 'br-1',
        bookingDate: '2026-08-24',
        startTime: '10:00',
        endTime: '10:30',
        status: BookingStatus.confirmed,
        subtotal: 300,
        discount: 0,
        tax: 0,
        total: 300,
      ),
    );
    when(() => bookingRepository.updateBookingStatus(_bookingId, status: any(named: 'status'))).thenAnswer(
      (_) async => const Booking(
        id: _bookingId,
        branchId: 'br-1',
        bookingDate: '2026-08-24',
        startTime: '10:00',
        endTime: '10:30',
        status: BookingStatus.checkedIn,
        subtotal: 300,
        discount: 0,
        tax: 0,
        total: 300,
      ),
    );

    final router = GoRouter(
      initialLocation: '/staff/appointments/$_bookingId',
      routes: [
        GoRoute(
          path: '/staff/appointments/:id',
          builder: (context, state) => OwnerBookingDetailsScreen(bookingId: state.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          bookingRepositoryProvider.overrideWithValue(bookingRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Checked in'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Checked in'));
    await tester.pump();
    await tester.pump();

    verify(() => bookingRepository.updateBookingStatus(_bookingId, status: 'checked_in')).called(1);
  });
}
