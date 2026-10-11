/// The gallery item ("Book This Style") that inspired a booking. Held in the
/// booking flow while the customer books, and returned on the created booking
/// as `style` (`App\Http\Resources\BookingResource`). [mediaId] is null once
/// the salon has deleted the gallery item; [label] is a server-side snapshot.
class BookingStyle {
  const BookingStyle({this.mediaId, this.label, this.categoryLabel, this.thumbnailUrl});

  factory BookingStyle.fromJson(Map<String, dynamic> json) => BookingStyle(
    mediaId: json['id'] as String?,
    label: json['label'] as String?,
    categoryLabel: json['category_label'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
  );

  final String? mediaId;
  final String? label;
  final String? categoryLabel;
  final String? thumbnailUrl;

  /// What to show the customer: the caption snapshot, else the category.
  String get title => (label != null && label!.isNotEmpty) ? label! : (categoryLabel ?? 'Selected style');
}
