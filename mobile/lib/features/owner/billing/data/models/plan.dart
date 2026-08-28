import '../../../../../core/utils/money_format.dart';

/// Mirrors `App\Http\Resources\PlanResource`. `amount`/`billing_interval` are
/// always read from here (the database plan) — never hard-coded anywhere in
/// this app, including this model. See SAAS_BILLING_ARCHITECTURE.md.
class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    required this.amount,
    required this.currency,
    required this.billingInterval,
    required this.billingIntervalCount,
    required this.trialDays,
    required this.isActive,
  });

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    description: json['description'] as String?,
    amount: num.parse(json['amount'].toString()),
    currency: json['currency'] as String,
    billingInterval: json['billing_interval'] as String,
    billingIntervalCount: json['billing_interval_count'] as int,
    trialDays: json['trial_days'] as int,
    isActive: json['is_active'] as bool,
  );

  final String id;
  final String name;
  final String code;
  final String? description;
  final num amount;
  final String currency;
  final String billingInterval;
  final int billingIntervalCount;
  final int trialDays;
  final bool isActive;

  /// e.g. "500.00 INR / month" — built from real plan fields, never a
  /// hard-coded price string.
  String get billingSummary {
    final intervalLabel = billingIntervalCount == 1 ? billingInterval : '$billingIntervalCount ${billingInterval}s';

    return '$currency ${formatMoney(amount)} / $intervalLabel';
  }
}
