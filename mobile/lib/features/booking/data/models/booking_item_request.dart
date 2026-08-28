/// One requested `items[]` entry for `POST /bookings` / `POST /customer/bookings`.
/// `staffId` null means "any available staff" — the backend, never the app,
/// makes the final assignment.
class BookingItemRequest {
  const BookingItemRequest({required this.serviceId, this.staffId});

  final String serviceId;
  final String? staffId;

  Map<String, dynamic> toJson() => {'service_id': serviceId, 'staff_id': staffId};
}
