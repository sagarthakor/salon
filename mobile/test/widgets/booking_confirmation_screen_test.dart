import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_confirmation_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('shows the real backend-assigned booking id, date, status, and total', (tester) async {
    final booking = Booking.fromJson({
      'id': 'bk_real_id_123',
      'branch_id': 'br_1',
      'booking_date': '2026-09-01',
      'start_time': '09:00',
      'end_time': '09:30',
      'status': 'pending',
      'subtotal': '300.00',
      'discount': '0.00',
      'tax': '0.00',
      'total': '300.00',
    });

    final repository = MockBookingRepository();
    final controller = _SeededController(repository, booking);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          bookingFlowControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: BookingConfirmationScreen()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('bk_real_id_123'), findsOneWidget);
    expect(find.textContaining('2026-09-01 at 09:00'), findsOneWidget);
    expect(find.textContaining('Pending'), findsOneWidget);
    expect(find.textContaining('₹300'), findsWidgets);
    // Never a client-generated confirmation number distinct from the backend id.
    expect(find.textContaining('CONF-'), findsNothing);
  });
}

class _SeededController extends BookingFlowController {
  _SeededController(super.repository, Booking booking) {
    state = state.copyWith(createdBooking: booking);
  }
}
