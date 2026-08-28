import 'package:url_launcher/url_launcher.dart';

/// Opens an Instagram URL — a service's post/reel/video reference, or a
/// salon's official profile link (see `home_tab.dart`'s `_SalonCard`) — in
/// the device's Instagram app or browser. Same `url_launcher` +
/// `LaunchMode.externalApplication` pattern already used for the Razorpay
/// checkout flow (see `gateway_checkout_launcher.dart`). The backend already
/// validated this is a real `https://instagram.com/...` link (see
/// `App\Support\InstagramUrl`); this function never downloads, scrapes, or
/// otherwise inspects the destination — it only hands the URL to the OS.
Future<bool> openInstagramUrl(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
