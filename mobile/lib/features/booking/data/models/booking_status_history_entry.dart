import 'booking_status.dart';

/// Mirrors `App\Http\Resources\BookingStatusHistoryResource`.
class BookingStatusHistoryEntry {
  const BookingStatusHistoryEntry({
    required this.id,
    this.fromStatus,
    required this.toStatus,
    this.changedBy,
    this.reason,
    this.createdAt,
  });

  factory BookingStatusHistoryEntry.fromJson(Map<String, dynamic> json) => BookingStatusHistoryEntry(
    id: json['id'] as int,
    fromStatus: json['from_status'] != null ? BookingStatus.fromApi(json['from_status'] as String) : null,
    toStatus: BookingStatus.fromApi(json['to_status'] as String),
    changedBy: json['changed_by'] as int?,
    reason: json['reason'] as String?,
    createdAt: json['created_at'] as String?,
  );

  final int id;
  final BookingStatus? fromStatus;
  final BookingStatus toStatus;
  final int? changedBy;
  final String? reason;
  final String? createdAt;
}
