import '../../../../../core/utils/money_format.dart';

/// Mirrors `App\Http\Resources\CouponResource`.
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.minimumBookingAmount,
    this.maximumDiscountAmount,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.usageLimitPerCustomer,
    required this.usageCount,
    required this.isActive,
    required this.firstBookingOnly,
    this.serviceIds = const [],
    this.categoryIds = const [],
  });

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    discountType: json['discount_type'] as String,
    discountValue: num.parse(json['discount_value'].toString()),
    minimumBookingAmount: json['minimum_booking_amount'] != null ? num.parse(json['minimum_booking_amount'].toString()) : null,
    maximumDiscountAmount: json['maximum_discount_amount'] != null ? num.parse(json['maximum_discount_amount'].toString()) : null,
    startsAt: json['starts_at'] as String?,
    expiresAt: json['expires_at'] as String?,
    usageLimit: json['usage_limit'] as int?,
    usageLimitPerCustomer: json['usage_limit_per_customer'] as int?,
    usageCount: json['usage_count'] as int,
    isActive: json['is_active'] as bool,
    firstBookingOnly: json['first_booking_only'] as bool,
    serviceIds: json['service_ids'] is List ? (json['service_ids'] as List<dynamic>).map((e) => e.toString()).toList() : const [],
    categoryIds: json['category_ids'] is List ? (json['category_ids'] as List<dynamic>).map((e) => e.toString()).toList() : const [],
  );

  final String id;
  final String code;
  final String name;
  final String? description;
  final String discountType;
  final num discountValue;
  final num? minimumBookingAmount;
  final num? maximumDiscountAmount;
  final String? startsAt;
  final String? expiresAt;
  final int? usageLimit;
  final int? usageLimitPerCustomer;
  final int usageCount;
  final bool isActive;
  final bool firstBookingOnly;
  final List<String> serviceIds;
  final List<String> categoryIds;

  String get discountLabel => discountType == 'percentage' ? '${formatMoney(discountValue)}%' : '₹${formatMoney(discountValue)}';
}
