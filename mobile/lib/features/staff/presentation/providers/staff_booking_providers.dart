import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_format.dart';
import '../../../booking/data/models/booking.dart';
import '../../../booking/presentation/providers/booking_providers.dart';
import '../../../owner/bookings/presentation/providers/owner_bookings_controller.dart';

/// "My Appointments" — the exact same paginated, filterable owner booking
/// list (`BookingRepository.ownerBookings`, real `viewableTenant()`
/// authorization — staff and owner get identical booking access per Phase 6,
/// see STAFF_APP_ARCHITECTURE.md) permanently pinned to the signed-in staff
/// member's own `staff_id`. One instance per staff id, so switching accounts
/// never leaks a stale list.
final staffAppointmentsControllerProvider =
    StateNotifierProvider.autoDispose.family<OwnerBookingsController, OwnerBookingsState, String>((ref, staffId) {
      return OwnerBookingsController(
        ref.watch(bookingRepositoryProvider),
        initialFilters: OwnerBookingFilters(staffId: staffId),
      );
    });

/// Today's appointments for the "Today" tab — a single bounded-size fetch
/// (a real day's bookings for one staff member), not the paginated list
/// above. Every count/next-appointment shown on that tab is derived from
/// this real, already-authorized response, never fabricated client-side.
final staffTodayBookingsProvider = FutureProvider.autoDispose.family<List<Booking>, String>((ref, staffId) {
  return ref
      .watch(bookingRepositoryProvider)
      .ownerBookings(staffId: staffId, date: toApiDate(DateTime.now()), perPage: 100);
});
