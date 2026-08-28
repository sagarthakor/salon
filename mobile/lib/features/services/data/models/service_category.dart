/// Mirrors `App\Http\Resources\ServiceCategoryResource`.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.branchId,
    required this.name,
    required this.slug,
    this.description,
    this.image,
    required this.status,
    required this.sortOrder,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) => ServiceCategory(
    id: json['id'] as String,
    branchId: json['branch_id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    image: json['image'] as String?,
    status: json['status'] as String,
    sortOrder: json['sort_order'] as int? ?? 0,
  );

  final String id;
  final String branchId;
  final String name;
  final String slug;
  final String? description;
  final String? image;
  final String status;
  final int sortOrder;
}
