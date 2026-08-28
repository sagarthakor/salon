/// Mirrors `App\Http\Resources\InvoiceResource`. `items` is a real, billed
/// snapshot (see `App\Models\InvoiceItem`) — never a live re-derivation from
/// the plan's current price.
class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.currency,
    required this.status,
    this.billingPeriodStart,
    this.billingPeriodEnd,
    this.issuedAt,
    this.paidAt,
    this.dueAt,
    this.items = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: json['id'] as String,
    invoiceNumber: json['invoice_number'] as String,
    subtotal: num.parse(json['subtotal'].toString()),
    tax: num.parse(json['tax'].toString()),
    total: num.parse(json['total'].toString()),
    currency: json['currency'] as String,
    status: json['status'] as String,
    billingPeriodStart: json['billing_period_start'] as String?,
    billingPeriodEnd: json['billing_period_end'] as String?,
    issuedAt: json['issued_at'] as String?,
    paidAt: json['paid_at'] as String?,
    dueAt: json['due_at'] as String?,
    items: json['items'] is List
        ? (json['items'] as List<dynamic>).map((i) => InvoiceItemEntry.fromJson(i as Map<String, dynamic>)).toList()
        : const [],
  );

  final String id;
  final String invoiceNumber;
  final num subtotal;
  final num tax;
  final num total;
  final String currency;
  final String status;
  final String? billingPeriodStart;
  final String? billingPeriodEnd;
  final String? issuedAt;
  final String? paidAt;
  final String? dueAt;
  final List<InvoiceItemEntry> items;
}

class InvoiceItemEntry {
  const InvoiceItemEntry({required this.description, required this.quantity, required this.unitAmount, required this.amount});

  factory InvoiceItemEntry.fromJson(Map<String, dynamic> json) => InvoiceItemEntry(
    description: json['description'] as String,
    quantity: json['quantity'] as int,
    unitAmount: num.parse(json['unit_amount'].toString()),
    amount: num.parse(json['amount'].toString()),
  );

  final String description;
  final int quantity;
  final num unitAmount;
  final num amount;
}
