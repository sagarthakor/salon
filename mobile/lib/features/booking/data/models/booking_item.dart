/// Mirrors `App\Http\Resources\BookingItemResource`. Prices/duration here are
/// the historical snapshot taken at booking time, not the service's current
/// values.
class BookingItem {
  const BookingItem({
    required this.id,
    this.serviceId,
    required this.staffId,
    this.staffName,
    required this.serviceName,
    required this.servicePrice,
    required this.serviceDurationMinutes,
    required this.quantity,
    required this.startTime,
    required this.endTime,
    required this.subtotal,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) => BookingItem(
    id: json['id'] as int,
    serviceId: json['service_id'] as String?,
    staffId: json['staff_id'] as String,
    staffName: json['staff_name'] as String?,
    serviceName: json['service_name'] as String,
    servicePrice: num.parse(json['service_price'].toString()),
    serviceDurationMinutes: json['service_duration_minutes'] as int,
    quantity: json['quantity'] as int? ?? 1,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    subtotal: num.parse(json['subtotal'].toString()),
  );

  final int id;
  final String? serviceId;
  final String staffId;
  final String? staffName;
  final String serviceName;
  final num servicePrice;
  final int serviceDurationMinutes;
  final int quantity;
  final String startTime;
  final String endTime;
  final num subtotal;
}
