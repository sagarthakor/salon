/// Mirrors `App\Http\Resources\NotificationResource`. Named `AppNotification`
/// (not `Notification`) to avoid colliding with Flutter's own built-in
/// `Notification` class (the base type for `ScrollNotification` etc, used by
/// `NotificationListener<T>` throughout this codebase).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    data: json['data'] == null ? const {} : Map<String, dynamic>.from(json['data'] as Map),
    isRead: json['is_read'] as bool,
    readAt: json['read_at'] as String?,
    createdAt: json['created_at'] as String,
  );

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final String? readAt;
  final String createdAt;

  /// Typed deep-link target from the backend-resolved payload — see
  /// NotificationMessageBuilder. Never a raw route string; the app decides
  /// the actual route per its own role-aware routing.
  String? get deepLink => data['deep_link'] as String?;

  String? get bookingId => data['booking_id'] as String?;

  AppNotification copyWith({bool? isRead, String? readAt}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    isRead: isRead ?? this.isRead,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );
}
