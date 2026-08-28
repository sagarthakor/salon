/// A clean display string for a decimal-cast backend amount (e.g. the `num`
/// parsed from `"500.00"`), avoiding Dart's `500.0` artifact for whole
/// numbers while still showing cents when they're non-zero (`"499.50"`).
/// Introduced for the Phase 10 billing screens, where ₹500 is shown
/// prominently enough that the artifact would look unpolished.
String formatMoney(num amount) {
  return amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
}
