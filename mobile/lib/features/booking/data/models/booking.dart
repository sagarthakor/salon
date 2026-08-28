import '../../../profile/data/models/customer_profile.dart';
import 'booking_item.dart';
import 'booking_status.dart';
import 'booking_status_history_entry.dart';

/// Mirrors `App\Http\Resources\BookingResource`. `items`/`customer`/
/// `statusHistory` are only present on the backend when the controller
/// eager-loaded them (list endpoints omit them for payload size; `show`
/// endpoints include them) — see MOBILE_API_INTEGRATION.md.
class Booking {
  const Booking({
    required this.id,
    required this.branchId,
    this.customer,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.couponCode,
    this.couponDiscount = 0,
    this.membershipDiscount = 0,
    this.loyaltyPointsRedeemed = 0,
    this.loyaltyDiscount = 0,
    this.loyaltyPointsEarned = 0,
    this.notes,
    this.cancellationReason,
    this.cancelledAt,
    this.items = const [],
    this.statusHistory = const [],
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: json['id'] as String,
    branchId: json['branch_id'] as String,
    customer: json['customer'] is Map<String, dynamic>
        ? CustomerProfile.fromJson(json['customer'] as Map<String, dynamic>)
        : null,
    bookingDate: json['booking_date'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    status: BookingStatus.fromApi(json['status'] as String),
    subtotal: num.parse(json['subtotal'].toString()),
    discount: num.parse(json['discount'].toString()),
    tax: num.parse(json['tax'].toString()),
    total: num.parse(json['total'].toString()),
    couponCode: json['coupon_code'] as String?,
    couponDiscount: num.parse((json['coupon_discount'] ?? 0).toString()),
    membershipDiscount: num.parse((json['membership_discount'] ?? 0).toString()),
    loyaltyPointsRedeemed: json['loyalty_points_redeemed'] as int? ?? 0,
    loyaltyDiscount: num.parse((json['loyalty_discount'] ?? 0).toString()),
    loyaltyPointsEarned: json['loyalty_points_earned'] as int? ?? 0,
    notes: json['notes'] as String?,
    cancellationReason: json['cancellation_reason'] as String?,
    cancelledAt: json['cancelled_at'] as String?,
    items: json['items'] is List
        ? (json['items'] as List<dynamic>).map((i) => BookingItem.fromJson(i as Map<String, dynamic>)).toList()
        : const [],
    statusHistory: json['status_history'] is List
        ? (json['status_history'] as List<dynamic>)
              .map((h) => BookingStatusHistoryEntry.fromJson(h as Map<String, dynamic>))
              .toList()
        : const [],
  );

  final String id;
  final String branchId;
  final CustomerProfile? customer;
  final String bookingDate;
  final String startTime;
  final String endTime;
  final BookingStatus status;
  final num subtotal;
  final num discount;
  final num tax;
  final num total;
  final String? couponCode;
  final num couponDiscount;
  final num membershipDiscount;
  final int loyaltyPointsRedeemed;
  final num loyaltyDiscount;
  final int loyaltyPointsEarned;
  final String? notes;
  final String? cancellationReason;
  final String? cancelledAt;
  final List<BookingItem> items;
  final List<BookingStatusHistoryEntry> statusHistory;
}
