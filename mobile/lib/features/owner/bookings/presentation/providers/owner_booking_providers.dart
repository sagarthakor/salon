import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../booking/data/models/booking.dart';
import '../../../../booking/presentation/providers/booking_providers.dart';
import 'owner_bookings_controller.dart';

final ownerBookingsControllerProvider = StateNotifierProvider<OwnerBookingsController, OwnerBookingsState>((ref) {
  return OwnerBookingsController(ref.watch(bookingRepositoryProvider));
});

final ownerBookingDetailsProvider = FutureProvider.family<Booking, String>((ref, bookingId) {
  return ref.watch(bookingRepositoryProvider).ownerBookingDetails(bookingId);
});
