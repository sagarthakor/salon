/// Mirrors `App\Http\Resources\LoyaltyTransactionResource`.
class LoyaltyTransactionEntry {
  const LoyaltyTransactionEntry({
    required this.id,
    required this.type,
    required this.points,
    required this.balanceAfter,
    this.description,
    this.bookingId,
    required this.createdAt,
  });

  factory LoyaltyTransactionEntry.fromJson(Map<String, dynamic> json) => LoyaltyTransactionEntry(
    id: json['id'] as int,
    type: json['type'] as String,
    points: json['points'] as int,
    balanceAfter: json['balance_after'] as int,
    description: json['description'] as String?,
    bookingId: json['booking_id'] as String?,
    createdAt: json['created_at'] as String,
  );

  final int id;
  final String type;
  final int points;
  final int balanceAfter;
  final String? description;
  final String? bookingId;
  final String createdAt;
}
