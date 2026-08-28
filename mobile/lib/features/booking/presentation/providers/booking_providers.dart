import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import 'booking_flow_controller.dart';
import 'booking_flow_state.dart';
import 'my_bookings_controller.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.watch(apiClientProvider)));

final bookingFlowControllerProvider = StateNotifierProvider<BookingFlowController, BookingFlowState>((ref) {
  return BookingFlowController(ref.watch(bookingRepositoryProvider));
});

/// One booking's full detail (with items/status history), keyed by booking id.
final bookingDetailsProvider = FutureProvider.family<Booking, String>((ref, bookingId) {
  return ref.watch(bookingRepositoryProvider).bookingDetails(bookingId);
});

final myBookingsControllerProvider = StateNotifierProvider<MyBookingsController, MyBookingsState>((ref) {
  return MyBookingsController(ref.watch(bookingRepositoryProvider));
});

/// The customer's soonest active (pending/confirmed/checked-in/in-service)
/// booking, for the home screen's "Upcoming appointment" card. A small,
/// separate fetch rather than reusing [myBookingsControllerProvider] so the
/// home tab doesn't depend on the Bookings tab having loaded first.
final upcomingBookingProvider = FutureProvider<Booking?>((ref) async {
  final bookings = await ref.watch(bookingRepositoryProvider).myBookings(page: 1, perPage: 5);
  for (final booking in bookings) {
    if (booking.status.isActive) return booking;
  }
  return null;
});
