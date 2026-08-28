import 'address.dart';

/// Mirrors `App\Http\Resources\BranchResource`.
class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.slug,
    this.phone,
    this.email,
    required this.address,
    required this.timezone,
    required this.status,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    address: Address.fromJson(json['address'] as Map<String, dynamic>?),
    timezone: json['timezone'] as String? ?? 'UTC',
    status: json['status'] as String,
  );

  final String id;
  final String name;
  final String slug;
  final String? phone;
  final String? email;
  final Address address;
  final String timezone;
  final String status;

  bool get isActive => status == 'active';
}
