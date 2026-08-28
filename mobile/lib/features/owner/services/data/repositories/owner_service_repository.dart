import 'package:dio/dio.dart';

import '../../../../../core/network/api_client.dart';
import '../../../../services/data/models/salon_service.dart';
import '../../../../services/data/models/service_category.dart';

/// Talks to the Phase 3 service/category APIs (`/services*`,
/// `/service-categories*`) from the owner side.
class OwnerServiceRepository {
  OwnerServiceRepository(this._client);

  final ApiClient _client;

  Future<List<ServiceCategory>> categories({String? branchId}) async {
    final data = await _client.get<List<dynamic>>(
      '/service-categories',
      queryParameters: {'per_page': 100, 'branch_id': ?branchId},
    );
    return data.map((c) => ServiceCategory.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<ServiceCategory> createCategory({
    required String branchId,
    required String name,
    String? description,
    String? status,
    String? imagePath,
  }) async {
    final data = await _client.postMultipart<Map<String, dynamic>>('/service-categories', {
      'branch_id': branchId,
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'status': ?status,
      if (imagePath != null) 'image': await MultipartFile.fromFile(imagePath),
    });
    return ServiceCategory.fromJson(data);
  }

  Future<ServiceCategory> updateCategory(
    String id, {
    required String branchId,
    required String name,
    String? description,
    String? status,
    String? imagePath,
  }) async {
    final data = await _client.postMultipart<Map<String, dynamic>>('/service-categories/$id', {
      'branch_id': branchId,
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'status': ?status,
      if (imagePath != null) 'image': await MultipartFile.fromFile(imagePath),
    }, httpMethodOverride: 'PUT');
    return ServiceCategory.fromJson(data);
  }

  Future<void> deleteCategory(String id) => _client.delete<dynamic>('/service-categories/$id');

  Future<List<SalonService>> services({String? branchId, String? categoryId, String? status, int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>(
      '/services',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'branch_id': ?branchId,
        'category_id': ?categoryId,
        'status': ?status,
      },
    );
    return data.map((s) => SalonService.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<SalonService> serviceDetails(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/services/$id');
    return SalonService.fromJson(data);
  }

  Future<SalonService> createService({
    required String branchId,
    required String categoryId,
    required String name,
    String? description,
    required String gender,
    required String price,
    required int durationMinutes,
    String? status,
    String? imagePath,
  }) async {
    final data = await _client.postMultipart<Map<String, dynamic>>('/services', {
      'branch_id': branchId,
      'category_id': categoryId,
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'gender': gender,
      'price': price,
      'duration_minutes': durationMinutes,
      'status': ?status,
      if (imagePath != null) 'image': await MultipartFile.fromFile(imagePath),
    });
    return SalonService.fromJson(data);
  }

  Future<SalonService> updateService(
    String id, {
    required String branchId,
    required String categoryId,
    required String name,
    String? description,
    required String gender,
    required String price,
    required int durationMinutes,
    String? status,
    String? imagePath,
  }) async {
    final data = await _client.postMultipart<Map<String, dynamic>>('/services/$id', {
      'branch_id': branchId,
      'category_id': categoryId,
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'gender': gender,
      'price': price,
      'duration_minutes': durationMinutes,
      'status': ?status,
      if (imagePath != null) 'image': await MultipartFile.fromFile(imagePath),
    }, httpMethodOverride: 'PUT');
    return SalonService.fromJson(data);
  }

  Future<void> deleteService(String id) => _client.delete<dynamic>('/services/$id');
}
