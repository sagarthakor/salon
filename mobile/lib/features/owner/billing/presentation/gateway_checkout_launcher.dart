import 'package:url_launcher/url_launcher.dart';

import '../data/models/checkout_order.dart';

/// Opens the gateway's own checkout UI for [order] in the device's browser.
///
/// This is the one deliberately isolated integration point where this app
/// would swap in a native gateway SDK (e.g. `razorpay_flutter`) if one were
/// available/buildable in the target environment — see
/// SAAS_BILLING_ARCHITECTURE.md, "Flutter payment flow", for why a
/// browser-based hosted checkout was used instead in this phase: a real
/// native SDK could not be verified to build in this sandboxed environment
/// (its legacy Gradle toolchain requires Maven artifact downloads this
/// environment has no network access for — see `flutter build apk --debug`
/// being a hard requirement this phase never compromises on). Nothing about
/// the *security* of the flow depends on this choice: the payment is still
/// only ever confirmed via the server-verified webhook/verify endpoint,
/// never by anything this function returns.
///
/// Because a browser redirect can't hand `razorpay_payment_id`/`signature`
/// back into this Flutter app without deep-linking (out of scope here), the
/// checkout screen never calls `SubscriptionRepository.verify()` after this
/// — it re-fetches `GET /subscription` instead, trusting only what the
/// server's webhook has already confirmed. See `PaymentCheckoutScreen`.
Future<bool> openGatewayCheckout(CheckoutOrder order) async {
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
