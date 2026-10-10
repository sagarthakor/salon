import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/gallery/data/models/gallery_item.dart';
import 'package:salon_customer/features/gallery/data/repositories/gallery_repository.dart';
import 'package:salon_customer/features/owner/gallery/data/repositories/owner_gallery_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> itemJson({String playback = 'native', String? videoUrl = 'https://x.test/v.mp4', bool hasNative = true, Map<String, dynamic>? service}) => {
  'id': 'm1',
  'media_type': 'video',
  'category': 'haircut',
  'category_label': 'Haircut',
  'caption': 'Layers',
  'branch_id': null,
  'service': service,
  'instagram_url': 'https://www.instagram.com/reel/AAA/',
  'has_native_video': hasNative,
  'video_url': videoUrl,
  'thumbnail_url': 'https://x.test/t.jpg',
  'playback': playback,
  'sort_order': 2,
};

void main() {
  group('GalleryItem.fromJson', () {
    test('a hosted video is playable and parses the linked service', () {
      final item = GalleryItem.fromJson(itemJson(service: {'id': 's1', 'name': 'Haircut', 'branch_id': 'b1'}));
      expect(item.playback, GalleryPlayback.native);
      expect(item.isPlayable, isTrue);
      expect(item.service?.id, 's1');
      expect(item.categoryLabel, 'Haircut');
      // Customer payloads omit owner-only fields; they default sensibly.
      expect(item.isActive, isTrue);
    });

    test('an Instagram-only item is never playable, even if a url were present', () {
      final item = GalleryItem.fromJson(itemJson(playback: 'instagram', hasNative: false, videoUrl: null));
      expect(item.playback, GalleryPlayback.instagram);
      expect(item.isPlayable, isFalse);
      expect(GalleryItem.fromJson(itemJson(playback: 'instagram', videoUrl: 'https://x.test/v.mp4')).isPlayable, isFalse);
    });

    test('unknown playback values degrade to none, never native', () {
      expect(GalleryItem.fromJson(itemJson(playback: 'weird')).playback, GalleryPlayback.none);
      expect(GalleryItem.fromJson(itemJson(playback: 'native', videoUrl: null)).isPlayable, isFalse);
    });

    test('owner payload carries source and visibility', () {
      final item = GalleryItem.fromJson({...itemJson(), 'source': 'upload', 'is_active': false});
      expect(item.source, 'upload');
      expect(item.isActive, isFalse);
    });
  });

  test('InstagramConnectionStatus parses without any token field', () {
    final status = InstagramConnectionStatus.fromJson({
      'configured': true,
      'connected': true,
      'needs_reconnect': true,
      'username': 'nil_hairport_unisex',
      'last_error': 'expired',
    });
    expect(status.connected && status.needsReconnect, isTrue);
    expect(status.username, 'nil_hairport_unisex');
  });

  group('GalleryRepository', () {
    test('list() requests the branch gallery with page, size and category', () async {
      final client = MockApiClient();
      when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => [itemJson()]);

      final result = await GalleryRepository(client).list('br1', page: 2, perPage: 12, category: 'styling');

      expect(result.single.id, 'm1');
      final captured = verify(() => client.get<List<dynamic>>('/branches/br1/gallery', queryParameters: captureAny(named: 'queryParameters'))).captured.single as Map<String, dynamic>;
      expect(captured, {'page': 2, 'per_page': 12, 'category': 'styling'});
    });

    test('list() omits the category filter when none is chosen', () async {
      final client = MockApiClient();
      when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => []);

      await GalleryRepository(client).list('br1');

      final captured = verify(() => client.get<List<dynamic>>(any(), queryParameters: captureAny(named: 'queryParameters'))).captured.single as Map<String, dynamic>;
      expect(captured.containsKey('category'), isFalse);
    });
  });

  group('OwnerGalleryRepository', () {
    late MockApiClient client;
    late OwnerGalleryRepository repository;

    setUp(() {
      client = MockApiClient();
      repository = OwnerGalleryRepository(client);
    });

    test('create() with an Instagram link posts multipart with 1/0 booleans and no video', () async {
      when(() => client.postMultipart<Map<String, dynamic>>(any(), any(), httpMethodOverride: any(named: 'httpMethodOverride'))).thenAnswer((_) async => {...itemJson(playback: 'instagram', hasNative: false, videoUrl: null), 'source': 'instagram'});

      final item = await repository.create(instagramUrl: 'https://www.instagram.com/reel/AAA/', caption: 'Hi', isActive: false);

      expect(item.playback, GalleryPlayback.instagram);
      final fields = verify(() => client.postMultipart<Map<String, dynamic>>('/salon-media', captureAny(), httpMethodOverride: any(named: 'httpMethodOverride'))).captured.single as Map<String, dynamic>;
      expect(fields['instagram_url'], 'https://www.instagram.com/reel/AAA/');
      expect(fields['is_active'], 0);
      expect(fields.containsKey('video'), isFalse);
    });

    test('update() without files sends a JSON patch, clearing the service explicitly', () async {
      when(() => client.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((_) async => itemJson());

      await repository.update('m1', caption: 'New', clearService: true, isActive: true);

      final data = verify(() => client.patch<Map<String, dynamic>>('/salon-media/m1', data: captureAny(named: 'data'))).captured.single as Map<String, dynamic>;
      expect(data['caption'], 'New');
      expect(data.containsKey('service_id'), isTrue);
      expect(data['service_id'], isNull);
      expect(data['is_active'], true);
    });

    test('reorder() posts the ordered ids', () async {
      when(() => client.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer((_) async => null);
      await repository.reorder(['b', 'a']);
      verify(() => client.post<dynamic>('/salon-media/reorder', data: {'ids': ['b', 'a']})).called(1);
    });

    test('instagramConnectUrl() returns the authorization url', () async {
      when(() => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((_) async => {'authorization_url': 'https://www.instagram.com/oauth/authorize?x=1'});
      expect(await repository.instagramConnectUrl(), startsWith('https://www.instagram.com/oauth/authorize'));
    });
  });
}
