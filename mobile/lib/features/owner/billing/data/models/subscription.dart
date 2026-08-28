import 'plan.dart';

/// Mirrors `App\Http\Resources\SubscriptionResource`. [status] is the exact
/// literal backend enum value (`trialing`, `active`, `past_due`,
/// `grace_period`, `cancelled`, `expired`) — see [SubscriptionStatusX] for
/// the six UI states this app must handle (Phase 10 §39).
class Subscription {
  const Subscription({
    required this.id,
    required this.status,
    this.plan,
    this.trialStartsAt,
    this.trialEndsAt,
    this.startsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    this.cancelledAt,
    this.graceEndsAt,
    this.endedAt,
    required this.hasBusinessAccess,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String,
    status: json['status'] as String,
    plan: json['plan'] is Map<String, dynamic> ? Plan.fromJson(json['plan'] as Map<String, dynamic>) : null,
    trialStartsAt: json['trial_starts_at'] as String?,
    trialEndsAt: json['trial_ends_at'] as String?,
    startsAt: json['starts_at'] as String?,
    currentPeriodStart: json['current_period_start'] as String?,
    currentPeriodEnd: json['current_period_end'] as String?,
    cancelAtPeriodEnd: json['cancel_at_period_end'] as bool,
    cancelledAt: json['cancelled_at'] as String?,
    graceEndsAt: json['grace_ends_at'] as String?,
    endedAt: json['ended_at'] as String?,
    hasBusinessAccess: json['has_business_access'] as bool,
  );

  final String id;
  final String status;
  final Plan? plan;
  final String? trialStartsAt;
  final String? trialEndsAt;
  final String? startsAt;
  final String? currentPeriodStart;
  final String? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String? cancelledAt;
  final String? graceEndsAt;
  final String? endedAt;
  final bool hasBusinessAccess;
}

/// UI copy for each of the six subscription states (Phase 10 §39) — the only
/// place these messages are defined, so every screen that shows subscription
/// status stays consistent.
extension SubscriptionStatusX on Subscription {
  String get statusLabel => switch (status) {
    'trialing' => 'Free trial',
    'active' => 'Active',
    'past_due' => 'Payment overdue',
    'grace_period' => 'Renew required',
    'cancelled' => 'Cancelled',
    'expired' => 'Expired',
    _ => status,
  };

  String get statusMessage => switch (status) {
    'trialing' => 'You\'re on a free trial.',
    'active' => 'Your plan is active.',
    'past_due' => 'Your payment is overdue. Please renew to avoid losing access.',
    'grace_period' => 'Please renew your subscription to keep your salon running.',
    'cancelled' => 'Your subscription has been cancelled.',
    'expired' => 'Your subscription has expired. Renew to restore access.',
    _ => '',
  };

  bool get isTerminal => status == 'cancelled' || status == 'expired';
}
