import '../../../../core/utils/money_format.dart';

/// Mirrors `App\Http\Resources\MembershipPlanResource`. Shared by the
/// owner-side plan management screens and the customer-facing purchase flow.
class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.discountType,
    required this.discountValue,
    this.maximumDiscountAmount,
    required this.isActive,
    this.serviceIds = const [],
    this.categoryIds = const [],
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) => MembershipPlan(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    description: json['description'] as String?,
    price: num.parse(json['price'].toString()),
    currency: json['currency'] as String,
    durationDays: json['duration_days'] as int,
    discountType: json['discount_type'] as String,
    discountValue: num.parse(json['discount_value'].toString()),
    maximumDiscountAmount: json['maximum_discount_amount'] != null ? num.parse(json['maximum_discount_amount'].toString()) : null,
    isActive: json['is_active'] as bool,
    serviceIds: json['service_ids'] is List ? (json['service_ids'] as List<dynamic>).map((e) => e.toString()).toList() : const [],
    categoryIds: json['category_ids'] is List ? (json['category_ids'] as List<dynamic>).map((e) => e.toString()).toList() : const [],
  );

  final String id;
  final String name;
  final String code;
  final String? description;
  final num price;
  final String currency;
  final int durationDays;
  final String discountType;
  final num discountValue;
  final num? maximumDiscountAmount;
  final bool isActive;
  final List<String> serviceIds;
  final List<String> categoryIds;

  String get discountLabel => discountType == 'percentage' ? '${formatMoney(discountValue)}%' : '₹${formatMoney(discountValue)}';
}
