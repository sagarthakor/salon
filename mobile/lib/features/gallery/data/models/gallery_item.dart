/// How the app should present a gallery item. Mirrors the backend's
/// `playback` field: only [native] items get a play button.
enum GalleryPlayback {
  /// A salon-hosted video the in-app player can stream.
  native,

  /// Instagram-only: show the thumbnail with a "View on Instagram" link-out.
  instagram,

  /// An owner-uploaded photo: shown full-size in the viewer.
  image,

  /// Neither a hosted video nor a link — nothing to open.
  none;

  static GalleryPlayback parse(String? value) => switch (value) {
    'native' => GalleryPlayback.native,
    'instagram' => GalleryPlayback.instagram,
    'image' => GalleryPlayback.image,
    _ => GalleryPlayback.none,
  };
}

/// Gallery categories, in display order. `value` is what the API filters on.
const galleryCategories = <({String value, String label})>[
  (value: 'haircut', label: 'Haircut'),
  (value: 'hair_colour', label: 'Hair Colour'),
  (value: 'highlights', label: 'Highlights'),
  (value: 'styling', label: 'Styling'),
  (value: 'transformation', label: 'Transformation'),
  (value: 'other', label: 'Other'),
];

class GalleryService {
  const GalleryService({required this.id, required this.name, this.branchId});

  factory GalleryService.fromJson(Map<String, dynamic> json) =>
      GalleryService(id: json['id'] as String, name: json['name'] as String, branchId: json['branch_id'] as String?);

  final String id;
  final String name;
  final String? branchId;
}

/// Mirrors `App\Http\Resources\SalonMediaResource` (owner) and
/// `CustomerSalonMediaResource` (public) — the latter simply omits
/// [source]/[isActive], which default here.
class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.mediaType,
    this.category,
    this.categoryLabel,
    this.caption,
    this.branchId,
    this.service,
    this.instagramUrl,
    required this.hasNativeVideo,
    this.videoUrl,
    this.thumbnailUrl,
    this.imageUrl,
    required this.playback,
    this.sortOrder = 0,
    this.source = 'instagram',
    this.isActive = true,
  });

  factory GalleryItem.fromJson(Map<String, dynamic> json) => GalleryItem(
    id: json['id'] as String,
    mediaType: json['media_type'] as String? ?? 'video',
    category: json['category'] as String?,
    categoryLabel: json['category_label'] as String?,
    caption: json['caption'] as String?,
    branchId: json['branch_id'] as String?,
    service: json['service'] is Map<String, dynamic>
        ? GalleryService.fromJson(json['service'] as Map<String, dynamic>)
        : null,
    instagramUrl: json['instagram_url'] as String?,
    hasNativeVideo: json['has_native_video'] as bool? ?? false,
    videoUrl: json['video_url'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    imageUrl: json['image_url'] as String?,
    playback: GalleryPlayback.parse(json['playback'] as String?),
    sortOrder: json['sort_order'] as int? ?? 0,
    source: json['source'] as String? ?? 'instagram',
    isActive: json['is_active'] as bool? ?? true,
  );

  final String id;
  final String mediaType;
  final String? category;
  final String? categoryLabel;
  final String? caption;
  final String? branchId;
  final GalleryService? service;
  final String? instagramUrl;
  final bool hasNativeVideo;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? imageUrl;
  final GalleryPlayback playback;
  final int sortOrder;
  final String source;
  final bool isActive;

  bool get isPhoto => playback == GalleryPlayback.image;

  /// True only when the in-app player can actually play this item.
  bool get isPlayable => playback == GalleryPlayback.native && videoUrl != null;
}

/// Result of `POST /instagram/sync`.
class InstagramSyncResult {
  const InstagramSyncResult({required this.created, required this.updated, required this.skipped});

  factory InstagramSyncResult.fromJson(Map<String, dynamic> json) => InstagramSyncResult(
    created: json['created'] as int? ?? 0,
    updated: json['updated'] as int? ?? 0,
    skipped: json['skipped'] as int? ?? 0,
  );

  final int created;
  final int updated;
  final int skipped;
}

/// Mirrors `GET /instagram/connection`. Never carries a token — the backend
/// never sends one.
class InstagramConnectionStatus {
  const InstagramConnectionStatus({
    required this.configured,
    required this.connected,
    required this.needsReconnect,
    this.username,
    this.lastSyncedAt,
    this.tokenExpiresAt,
    this.lastError,
  });

  factory InstagramConnectionStatus.fromJson(Map<String, dynamic> json) => InstagramConnectionStatus(
    configured: json['configured'] as bool? ?? false,
    connected: json['connected'] as bool? ?? false,
    needsReconnect: json['needs_reconnect'] as bool? ?? false,
    username: json['username'] as String?,
    lastSyncedAt: json['last_synced_at'] as String?,
    tokenExpiresAt: json['token_expires_at'] as String?,
    lastError: json['last_error'] as String?,
  );

  final bool configured;
  final bool connected;
  final bool needsReconnect;
  final String? username;
  final String? lastSyncedAt;
  final String? tokenExpiresAt;
  final String? lastError;
}
