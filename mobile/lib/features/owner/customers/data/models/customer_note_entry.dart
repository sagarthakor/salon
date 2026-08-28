/// Mirrors `App\Http\Resources\CustomerNoteResource`. Owner/super-admin only
/// on the backend — never fetched or shown anywhere in the customer-facing
/// app (see CUSTOMER_ARCHITECTURE.md).
class CustomerNoteEntry {
  const CustomerNoteEntry({required this.id, required this.body, this.authorName, this.createdAt});

  factory CustomerNoteEntry.fromJson(Map<String, dynamic> json) => CustomerNoteEntry(
    id: json['id'] as int,
    body: json['body'] as String,
    authorName: json['author'] != null ? (json['author'] as Map<String, dynamic>)['name'] as String? : null,
    createdAt: json['created_at'] as String?,
  );

  final int id;
  final String body;
  final String? authorName;
  final String? createdAt;
}
