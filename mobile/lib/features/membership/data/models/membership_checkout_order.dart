/// Mirrors `CustomerMembershipController::checkout()`'s response shape —
/// the same "gateway order" pattern as Phase 10's `CheckoutOrder`
/// (`gateway_key` is a public/publishable key, never a secret).
class MembershipCheckoutOrder {
  const MembershipCheckoutOrder({
    required this.paymentId,
    required this.idempotencyKey,
    required this.gateway,
    this.gatewayKey,
    this.gatewayOrderId,
    required this.amount,
    required this.currency,
    required this.planId,
    required this.planName,
  });

  factory MembershipCheckoutOrder.fromJson(Map<String, dynamic> json) => MembershipCheckoutOrder(
    paymentId: json['payment_id'] as String,
    idempotencyKey: json['idempotency_key'] as String,
    gateway: json['gateway'] as String,
    gatewayKey: json['gateway_key'] as String?,
    gatewayOrderId: json['gateway_order_id'] as String?,
    amount: num.parse(json['amount'].toString()),
    currency: json['currency'] as String,
    planId: (json['plan'] as Map<String, dynamic>)['id'] as String,
    planName: (json['plan'] as Map<String, dynamic>)['name'] as String,
  );

  final String paymentId;
  final String idempotencyKey;
  final String gateway;
  final String? gatewayKey;
  final String? gatewayOrderId;
  final num amount;
  final String currency;
  final String planId;
  final String planName;
}
