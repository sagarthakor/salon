import '../../../../core/network/api_client.dart';
import '../models/gallery_item.dart';

/// Customer-facing Hair Inspiration gallery (`GET /branches/{branch}/gallery`).
class GalleryRepository {
  GalleryRepository(this._client);

  final ApiClient _client;

  Future<List<GalleryItem>> list(String branchId, {int page = 1, int perPage = 12, String? category}) async {
    final data = await _client.get<List<dynamic>>(
      '/branches/$branchId/gallery',
      queryParameters: {'page': page, 'per_page': perPage, 'category': ?category},
    );
    return data.map((e) => GalleryItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}
