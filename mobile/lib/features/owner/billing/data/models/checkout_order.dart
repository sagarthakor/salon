/// The response of `POST /subscription/checkout` / `POST /subscription/renew`
/// — everything the app needs to open the gateway's checkout, and nothing
/// else (no secret ever appears here; `gatewayKey` is Razorpay's public/
/// publishable key). `amount`/`currency` are always the server-resolved
/// plan price — this app never sends a price to the backend, only a plan id.
class CheckoutOrder {
  const CheckoutOrder({
    required this.paymentId,
    required this.idempotencyKey,
    required this.gateway,
    this.gatewayKey,
    this.gatewayOrderId,
    required this.amount,
    required this.currency,
    required this.planName,
  });

  factory CheckoutOrder.fromJson(Map<String, dynamic> json) => CheckoutOrder(
    paymentId: json['payment_id'] as String,
    idempotencyKey: json['idempotency_key'] as String,
    gateway: json['gateway'] as String,
    gatewayKey: json['gateway_key'] as String?,
    gatewayOrderId: json['gateway_order_id'] as String?,
    amount: num.parse(json['amount'].toString()),
    currency: json['currency'] as String,
    planName: (json['plan'] as Map<String, dynamic>)['name'] as String,
  );

  final String paymentId;
  final String idempotencyKey;
  final String gateway;
  final String? gatewayKey;
  final String? gatewayOrderId;
  final num amount;
  final String currency;
  final String planName;
}
