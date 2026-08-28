import 'package:url_launcher/url_launcher.dart';

import '../data/models/membership_checkout_order.dart';

/// Same browser-based hosted-checkout approach as
/// `gateway_checkout_launcher.dart` (Phase 10) — see that file for why a
/// native Razorpay SDK isn't used in this sandboxed build environment.
/// Because a browser redirect can't hand `gateway_payment_id`/`signature`
/// back into the app, `MembershipCheckoutScreen` never calls
/// `CustomerMembershipRepository.verify()` itself — it polls
/// `GET /customer/membership` instead, trusting only what the server's
/// webhook has already confirmed (see `PaymentWebhookController`).
Future<bool> openMembershipGatewayCheckout(MembershipCheckoutOrder order) async {
  final uri = Uri.parse('https://api.razorpay.com/v1/checkout/embedded').replace(
    queryParameters: {
      'key_id': order.gatewayKey ?? '',
      'order_id': order.gatewayOrderId ?? '',
      'amount': (order.amount * 100).round().toString(),
      'currency': order.currency,
    },
  );

  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
