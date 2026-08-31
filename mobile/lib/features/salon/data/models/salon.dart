import 'address.dart';

/// Mirrors `App\Http\Resources\SalonResource`.
class Salon {
  const Salon({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.genderType,
    this.logo,
    this.coverImage,
    this.phone,
    this.email,
    this.website,
    this.instagramUrl,
    required this.address,
    required this.status,
    this.timezone = 'UTC',
  });

  factory Salon.fromJson(Map<String, dynamic> json) => Salon(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    genderType: json['gender_type'] as String,
    logo: json['logo'] as String?,
    coverImage: json['cover_image'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    website: json['website'] as String?,
    instagramUrl: json['instagram_url'] as String?,
    address: Address.fromJson(json['address'] as Map<String, dynamic>?),
    status: json['status'] as String,
    timezone: json['timezone'] as String? ?? 'UTC',
  );

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String genderType;
  final String? logo;
  final String? coverImage;
  final String? phone;
  final String? email;
  final String? website;
  final String? instagramUrl;
  final Address address;
  final String status;
  final String timezone;
}
