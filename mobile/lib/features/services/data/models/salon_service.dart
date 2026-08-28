import 'service_category.dart';

/// Mirrors `App\Http\Resources\ServiceResource`. Named `SalonService` (not
/// `Service`) to avoid colliding with Dart/Flutter's own `Service` types.
class SalonService {
  const SalonService({
    required this.id,
    required this.branchId,
    this.category,
    required this.name,
    required this.slug,
    this.description,
    required this.gender,
    this.audience,
    required this.price,
    required this.durationMinutes,
    this.imageUrl,
    this.instagramUrl,
    required this.status,
    required this.sortOrder,
  });

  factory SalonService.fromJson(Map<String, dynamic> json) => SalonService(
    id: json['id'] as String,
    branchId: json['branch_id'] as String,
    category: json['category'] is Map<String, dynamic>
        ? ServiceCategory.fromJson(json['category'] as Map<String, dynamic>)
        : null,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    gender: json['gender'] as String,
    audience: json['audience'] as String?,
    price: num.parse(json['price'].toString()),
    durationMinutes: json['duration_minutes'] as int,
    imageUrl: json['image_url'] as String?,
    instagramUrl: json['instagram_url'] as String?,
    status: json['status'] as String,
    sortOrder: json['sort_order'] as int? ?? 0,
  );

  final String id;
  final String branchId;
  final ServiceCategory? category;
  final String name;
  final String slug;
  final String? description;
  final String gender;

  /// `male`/`female`/`unisex`/`kids` — the master-catalog segmentation the
  /// customer dashboard's "Men / Women / Unisex / Kids" entry point filters
  /// by. `null` for a service that predates (or was created outside) the
  /// master catalog feature. See MASTER_CATALOG_ARCHITECTURE.md.
  final String? audience;
  final num price;
  final int durationMinutes;
  final String? imageUrl;
  final String? instagramUrl;
  final String status;
  final int sortOrder;

  bool get isActive => status == 'active';
}
