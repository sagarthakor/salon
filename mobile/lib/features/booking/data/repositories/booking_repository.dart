import '../../../../core/network/api_client.dart';
import '../models/availability.dart';
import '../models/booking.dart';
import '../models/booking_item_request.dart';
import '../models/booking_pricing.dart';

/// Talks to the Phase 6 availability endpoint and the Phase 6/7 customer
/// booking endpoints (`/customer/bookings*`). Availability is never computed
/// locally — every slot shown to the customer came from this repository.
class BookingRepository {
  BookingRepository(this._client);

  final ApiClient _client;

  Future<AvailabilityResult> availability({
    required String branchId,
    required String date,
    required List<String> serviceIds,
    String? staffId,
  }) async {
    // Built manually rather than via Dio's `queryParameters` map: Laravel
    // only parses repeated `key[]=a&key[]=b` into an array, and Dio's list
    // query-param encoding is not guaranteed to match that exact form.
    final buffer = StringBuffer('/branches/$branchId/availability?date=${Uri.encodeQueryComponent(date)}');
    for (final id in serviceIds) {
      buffer.write('&service_ids[]=${Uri.encodeQueryComponent(id)}');
    }
    if (staffId != null) {
      buffer.write('&staff_id=${Uri.encodeQueryComponent(staffId)}');
    }
    final data = await _client.get<Map<String, dynamic>>(buffer.toString());
    return AvailabilityResult.fromJson(data);
  }

  Future<Booking> createBooking({
    required String branchId,
    required String date,
    required String startTime,
    required List<BookingItemRequest> items,
    String? notes,
    String? couponCode,
    int? loyaltyPointsToRedeem,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/bookings',
      data: {
        'branch_id': branchId,
        'date': date,
        'start_time': startTime,
        'items': items.map((i) => i.toJson()).toList(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'coupon_code': ?couponCode,
        'loyalty_points_to_redeem': ?loyaltyPointsToRedeem,
      },
    );
    return Booking.fromJson(data);
  }

  /// Read-only — never creates a booking. See BookingPricing.
  Future<BookingPricing> pricePreview({
    required String branchId,
    required List<String> serviceIds,
    String? couponCode,
    int? loyaltyPointsToRedeem,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/bookings/price-preview',
      data: {
        'branch_id': branchId,
        'service_ids': serviceIds,
        'coupon_code': ?couponCode,
        'loyalty_points_to_redeem': ?loyaltyPointsToRedeem,
      },
    );
    return BookingPricing.fromJson(data);
  }

  Future<List<Booking>> myBookings({int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>(
      '/customer/bookings',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    return data.map((b) => Booking.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<Booking> bookingDetails(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/customer/bookings/$id');
    return Booking.fromJson(data);
  }

  Future<Booking> cancelBooking(String id, {String? reason}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/bookings/$id/cancel',
      data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return Booking.fromJson(data);
  }

  Future<Booking> rescheduleBooking(String id, {required String date, required String startTime}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/customer/bookings/$id/reschedule',
      data: {'date': date, 'start_time': startTime},
    );
    return Booking.fromJson(data);
  }

  // --- Owner/staff surface (Phase 8) — same envelope/model, different base path ---
  // and owner cancel/reschedule always bypass the cancellation window (never a
  // client-supplied flag — see BOOKING_ENGINE.md).

  Future<List<Booking>> ownerBookings({
    int page = 1,
    int perPage = 20,
    String? date,
    String? status,
    String? branchId,
    String? staffId,
    String? customerId,
  }) async {
    final data = await _client.get<List<dynamic>>(
      '/bookings',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'date': ?date,
        'status': ?status,
        'branch_id': ?branchId,
        'staff_id': ?staffId,
        'customer_id': ?customerId,
      },
    );
    return data.map((b) => Booking.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<Booking> ownerBookingDetails(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/bookings/$id');
    return Booking.fromJson(data);
  }

  Future<Booking> confirmBooking(String id) async {
    final data = await _client.post<Map<String, dynamic>>('/bookings/$id/confirm');
    return Booking.fromJson(data);
  }

  /// [status] must be one the backend accepts on `PATCH /bookings/{id}`:
  /// `checked_in`, `in_service`, `completed`, or `no_show` — `confirmed` and
  /// `cancelled` have their own dedicated endpoints/methods.
  Future<Booking> updateBookingStatus(String id, {String? status, String? notes}) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/bookings/$id',
      data: {'status': ?status, 'notes': ?notes},
    );
    return Booking.fromJson(data);
  }

  Future<Booking> ownerCancelBooking(String id, {String? reason}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/bookings/$id/cancel',
      data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return Booking.fromJson(data);
  }

  Future<Booking> ownerRescheduleBooking(String id, {required String date, required String startTime}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/bookings/$id/reschedule',
      data: {'date': date, 'start_time': startTime},
    );
    return Booking.fromJson(data);
  }
}
