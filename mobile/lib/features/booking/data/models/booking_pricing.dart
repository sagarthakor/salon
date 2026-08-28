/// Mirrors the response shape of `PricingBreakdown::toArray()` — returned by
/// both `POST /customer/bookings/price-preview` and `POST /bookings/price-preview`.
/// Read-only: this never creates a booking, and the backend recalculates
/// everything again (never trusting this response) when the booking is
/// actually created. See LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
class BookingPricing {
  const BookingPricing({
    required this.subtotal,
    this.couponCode,
    required this.couponDiscount,
    required this.membershipDiscount,
    required this.loyaltyPointsRedeemed,
    required this.loyaltyDiscount,
    required this.discount,
    required this.tax,
    required this.total,
    this.messages = const [],
  });

  factory BookingPricing.fromJson(Map<String, dynamic> json) => BookingPricing(
    subtotal: num.parse(json['subtotal'].toString()),
    couponCode: json['coupon_code'] as String?,
    couponDiscount: num.parse(json['coupon_discount'].toString()),
    membershipDiscount: num.parse(json['membership_discount'].toString()),
    loyaltyPointsRedeemed: json['loyalty_points_redeemed'] as int? ?? 0,
    loyaltyDiscount: num.parse(json['loyalty_discount'].toString()),
    discount: num.parse(json['discount'].toString()),
    tax: num.parse(json['tax'].toString()),
    total: num.parse(json['total'].toString()),
    messages: json['messages'] is List ? (json['messages'] as List<dynamic>).map((m) => m.toString()).toList() : const [],
  );

  final num subtotal;
  final String? couponCode;
  final num couponDiscount;
  final num membershipDiscount;
  final int loyaltyPointsRedeemed;
  final num loyaltyDiscount;
  final num discount;
  final num tax;
  final num total;
  final List<String> messages;
}
