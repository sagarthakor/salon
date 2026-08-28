import 'salon_service.dart';
import 'service_category.dart';

/// Mirrors the response of `GET /branches/{branch}/services`.
class BranchServices {
  const BranchServices({required this.categories, required this.services});

  factory BranchServices.fromJson(Map<String, dynamic> json) => BranchServices(
    categories: (json['categories'] as List<dynamic>)
        .map((c) => ServiceCategory.fromJson(c as Map<String, dynamic>))
        .toList(),
    services: (json['services'] as List<dynamic>)
        .map((s) => SalonService.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  final List<ServiceCategory> categories;
  final List<SalonService> services;

  /// Active services for one category, in the order the backend returned them.
  List<SalonService> forCategory(String categoryId) =>
      services.where((s) => s.category?.id == categoryId).toList();
}
