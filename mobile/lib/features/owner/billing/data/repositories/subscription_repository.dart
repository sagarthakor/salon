import '../../../../../core/network/api_client.dart';
import '../models/checkout_order.dart';
import '../models/invoice.dart';
import '../models/payment.dart';
import '../models/plan.dart';
import '../models/subscription.dart';

/// Talks to the Phase 10 billing APIs (`/subscription*`, `/subscription/plans`).
/// `checkout`/`renew` never send an amount/price — only a `plan_id`; the
/// server always resolves the real charge from the database plan. See
/// SAAS_BILLING_ARCHITECTURE.md, "Amount tampering".
class SubscriptionRepository {
  SubscriptionRepository(this._client);

  final ApiClient _client;

  Future<Subscription> show() async {
    final data = await _client.get<Map<String, dynamic>>('/subscription');
    return Subscription.fromJson(data);
  }

  Future<List<Plan>> plans() async {
    final data = await _client.get<List<dynamic>>('/subscription/plans');
    return data.map((p) => Plan.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<CheckoutOrder> checkout(String planId, {String? idempotencyKey}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/subscription/checkout',
      data: {'plan_id': planId},
      headers: idempotencyKey != null ? {'Idempotency-Key': idempotencyKey} : null,
    );
    return CheckoutOrder.fromJson(data);
  }

  Future<CheckoutOrder> renew({String? planId, String? idempotencyKey}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/subscription/renew',
      data: {'plan_id': ?planId},
      headers: idempotencyKey != null ? {'Idempotency-Key': idempotencyKey} : null,
    );
    return CheckoutOrder.fromJson(data);
  }

  /// Only meaningful when a gateway SDK returns `payment_id`/`signature`
  /// directly to the client. The app's own checkout screen instead re-fetches
  /// [show] after returning from the gateway, relying on the server-verified
  /// webhook — see OWNER_APP_ARCHITECTURE.md and the Flutter payment-screen
  /// doc comment. This method is still exercised by the backend's own test
  /// suite and kept available for that SDK-driven path.
  Future<Subscription> verify({required String paymentId, required String gatewayPaymentId, required String gatewaySignature}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/subscription/checkout/verify',
      data: {'payment_id': paymentId, 'gateway_payment_id': gatewayPaymentId, 'gateway_signature': gatewaySignature},
    );
    return Subscription.fromJson(data);
  }

  Future<Subscription> cancel() async {
    final data = await _client.post<Map<String, dynamic>>('/subscription/cancel');
    return Subscription.fromJson(data);
  }

  Future<List<Payment>> payments({int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>('/subscription/payments', queryParameters: {'page': page, 'per_page': perPage});
    return data.map((p) => Payment.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<Invoice>> invoices({int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>('/subscription/invoices', queryParameters: {'page': page, 'per_page': perPage});
    return data.map((i) => Invoice.fromJson(i as Map<String, dynamic>)).toList();
  }
}
