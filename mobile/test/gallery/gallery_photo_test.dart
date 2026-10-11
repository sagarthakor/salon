import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/gallery/data/models/gallery_item.dart';

void main() {
  test('a photo item parses as an image: not playable, with its full-size url', () {
    final photo = GalleryItem.fromJson({
      'id': 'p1', 'media_type': 'photo', 'playback': 'image', 'has_native_video': false,
      'image_url': 'https://x.test/p.jpg', 'thumbnail_url': 'https://x.test/p.jpg',
    });
    expect(photo.playback, GalleryPlayback.image);
    expect(photo.isPhoto, isTrue);
    expect(photo.isPlayable, isFalse);
    expect(photo.imageUrl, 'https://x.test/p.jpg');
  });

  test('videos and Instagram items are not photos', () {
    final video = GalleryItem.fromJson({'id': 'v', 'playback': 'native', 'has_native_video': true, 'video_url': 'https://x.test/v.mp4'});
    expect(video.isPhoto, isFalse);
    expect(video.imageUrl, isNull);
  });
}
