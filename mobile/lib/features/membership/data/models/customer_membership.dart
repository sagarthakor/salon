import 'membership_plan.dart';

/// Mirrors `App\Http\Resources\CustomerMembershipResource`.
class CustomerMembership {
  const CustomerMembership({
    required this.id,
    this.plan,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.purchasedAmount,
    required this.currency,
    required this.source,
    required this.isCurrentlyActive,
  });

  factory CustomerMembership.fromJson(Map<String, dynamic> json) => CustomerMembership(
    id: json['id'] as String,
    plan: json['plan'] is Map<String, dynamic> ? MembershipPlan.fromJson(json['plan'] as Map<String, dynamic>) : null,
    status: json['status'] as String,
    startsAt: json['starts_at'] as String,
    expiresAt: json['expires_at'] as String,
    purchasedAmount: num.parse(json['purchased_amount'].toString()),
    currency: json['currency'] as String,
    source: json['source'] as String,
    isCurrentlyActive: json['is_currently_active'] as bool,
  );

  final String id;
  final MembershipPlan? plan;
  final String status;
  final String startsAt;
  final String expiresAt;
  final num purchasedAmount;
  final String currency;
  final String source;
  final bool isCurrentlyActive;
}
