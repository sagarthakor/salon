/// Mirrors `App\Enums\ServiceAudience` — the customer dashboard's "Men /
/// Women / Unisex / Kids" entry point and the `audience` query param both
/// `GET /services` and `GET /branches/{branch}/services` accept. See
/// MASTER_CATALOG_ARCHITECTURE.md.
enum ServiceAudience {
  male('male', 'Men', '👨'),
  female('female', 'Women', '👩'),
  unisex('unisex', 'Unisex', '⚪'),
  kids('kids', 'Kids', '👶');

  const ServiceAudience(this.apiValue, this.label, this.emoji);

  final String apiValue;
  final String label;
  final String emoji;
}
