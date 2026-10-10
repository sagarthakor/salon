import 'package:dio/dio.dart';

import '../../../../../core/network/api_client.dart';
import '../../../../gallery/data/models/gallery_item.dart';

/// Owner-side gallery + Instagram connection APIs (`/salon-media*`,
/// `/instagram/*`). The Instagram access token never reaches the app.
class OwnerGalleryRepository {
  OwnerGalleryRepository(this._client);

  final ApiClient _client;

  Future<List<GalleryItem>> list({int page = 1, int perPage = 100}) async {
    final data = await _client.get<List<dynamic>>('/salon-media', queryParameters: {'page': page, 'per_page': perPage});
    return data.map((e) => GalleryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<GalleryItem> details(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/salon-media/$id');
    return GalleryItem.fromJson(data);
  }

  /// Creates an item from an uploaded original video and/or an Instagram link.
  Future<GalleryItem> create({
    String? videoPath,
    String? thumbnailPath,
    String? instagramUrl,
    String? caption,
    String? category,
    String? serviceId,
    bool isActive = true,
  }) async {
    final data = await _client.postMultipart<Map<String, dynamic>>('/salon-media', {
      if (videoPath != null) 'video': await MultipartFile.fromFile(videoPath),
      if (thumbnailPath != null) 'thumbnail': await MultipartFile.fromFile(thumbnailPath),
      if (instagramUrl != null && instagramUrl.isNotEmpty) 'instagram_url': instagramUrl,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
      'category': ?category,
      'service_id': ?serviceId,
      // Laravel's `boolean` rule accepts 1/0, not "true"/"false", in a form body.
      'is_active': isActive ? 1 : 0,
    });
    return GalleryItem.fromJson(data);
  }

  Future<GalleryItem> update(
    String id, {
    String? caption,
    String? category,
    bool clearCategory = false,
    String? serviceId,
    bool clearService = false,
    String? instagramUrl,
    bool? isActive,
    String? videoPath,
    String? thumbnailPath,
    bool removeVideo = false,
    bool removeThumbnail = false,
  }) async {
    final hasFile = videoPath != null || thumbnailPath != null;
    final fields = <String, dynamic>{
      'caption': ?caption,
      if (clearCategory) 'category': null else 'category': ?category,
      if (clearService) 'service_id': null else 'service_id': ?serviceId,
      'instagram_url': ?instagramUrl,
      if (isActive != null) 'is_active': hasFile ? (isActive ? 1 : 0) : isActive,
      if (removeVideo) 'remove_video': hasFile ? 1 : true,
      if (removeThumbnail) 'remove_thumbnail': hasFile ? 1 : true,
    };
    if (hasFile) {
      // A multipart body can't carry null; an empty value reads as null server-side.
      fields.updateAll((key, value) => value ?? '');
      final data = await _client.postMultipart<Map<String, dynamic>>('/salon-media/$id', {
        ...fields,
        if (videoPath != null) 'video': await MultipartFile.fromFile(videoPath),
        if (thumbnailPath != null) 'thumbnail': await MultipartFile.fromFile(thumbnailPath),
      }, httpMethodOverride: 'PUT');
      return GalleryItem.fromJson(data);
    }
    final data = await _client.patch<Map<String, dynamic>>('/salon-media/$id', data: fields);
    return GalleryItem.fromJson(data);
  }

  Future<void> delete(String id) => _client.delete<dynamic>('/salon-media/$id');

  Future<void> reorder(List<String> orderedIds) => _client.post<dynamic>('/salon-media/reorder', data: {'ids': orderedIds});

  Future<InstagramConnectionStatus> instagramStatus() async {
    final data = await _client.get<Map<String, dynamic>>('/instagram/connection');
    return InstagramConnectionStatus.fromJson(data);
  }

  /// Returns the official Instagram authorization URL to open in the browser.
  Future<String> instagramConnectUrl() async {
    final data = await _client.post<Map<String, dynamic>>('/instagram/connect');
    return data['authorization_url'] as String;
  }

  Future<InstagramConnectionStatus> instagramDisconnect() async {
    final data = await _client.delete<Map<String, dynamic>>('/instagram/connection');
    return InstagramConnectionStatus.fromJson(data);
  }

  Future<InstagramSyncResult> instagramSync() async {
    final data = await _client.post<Map<String, dynamic>>('/instagram/sync');
    return InstagramSyncResult.fromJson(data);
  }
}
