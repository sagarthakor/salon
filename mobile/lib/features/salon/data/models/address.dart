/// Mirrors the nested `address` object present on both `SalonResource` and
/// `BranchResource`.
class Address {
  const Address({this.line1, this.line2, this.city, this.state, this.country, this.postalCode});

  factory Address.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Address();
    return Address(
      line1: json['line_1'] as String?,
      line2: json['line_2'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
    );
  }

  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;

  /// A single display-ready line, skipping any missing parts.
  String get singleLine => [line1, line2, city, state, postalCode, country]
      .where((part) => part != null && part.trim().isNotEmpty)
      .join(', ');

  bool get isEmpty => singleLine.isEmpty;
}
