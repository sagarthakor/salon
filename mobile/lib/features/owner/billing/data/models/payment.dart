/// Mirrors `App\Http\Resources\PaymentResource` — never carries a gateway
/// secret, only public-safe reference fields.
class Payment {
  const Payment({
    required this.id,
    this.invoiceId,
    required this.amount,
    required this.currency,
    required this.status,
    this.paymentMethod,
    required this.gateway,
    this.gatewayOrderId,
    this.gatewayPaymentId,
    this.paidAt,
    this.failedAt,
    this.failureReason,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as String,
    invoiceId: json['invoice_id'] as String?,
    amount: num.parse(json['amount'].toString()),
    currency: json['currency'] as String,
    status: json['status'] as String,
    paymentMethod: json['payment_method'] as String?,
    gateway: json['gateway'] as String,
    gatewayOrderId: json['gateway_order_id'] as String?,
    gatewayPaymentId: json['gateway_payment_id'] as String?,
    paidAt: json['paid_at'] as String?,
    failedAt: json['failed_at'] as String?,
    failureReason: json['failure_reason'] as String?,
    createdAt: json['created_at'] as String?,
  );

  final String id;
  final String? invoiceId;
  final num amount;
  final String currency;
  final String status;
  final String? paymentMethod;
  final String gateway;
  final String? gatewayOrderId;
  final String? gatewayPaymentId;
  final String? paidAt;
  final String? failedAt;
  final String? failureReason;
  final String? createdAt;
}
