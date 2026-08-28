import 'branch.dart';
import 'salon.dart';

/// Mirrors the response of `GET /customer/salons` — one entry per tenant the
/// authenticated user already has a `customer_profiles` relationship with
/// (created by salon staff; see CUSTOMER_ARCHITECTURE.md). This is not a
/// public salon directory: a brand-new user with no existing relationship to
/// any salon will see an empty list here.
class CustomerSalon {
  const CustomerSalon({required this.tenantSlug, this.salon, required this.branches});

  factory CustomerSalon.fromJson(Map<String, dynamic> json) => CustomerSalon(
    tenantSlug: json['tenant_slug'] as String,
    salon: json['salon'] != null ? Salon.fromJson(json['salon'] as Map<String, dynamic>) : null,
    branches: (json['branches'] as List<dynamic>)
        .map((b) => Branch.fromJson(b as Map<String, dynamic>))
        .toList(),
  );

  final String tenantSlug;
  final Salon? salon;
  final List<Branch> branches;
}
