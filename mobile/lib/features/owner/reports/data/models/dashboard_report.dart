/// Mirrors `App\Services\Reports\DashboardReport` — the Reports section's
/// date-range-flexible overview (`GET /reports/dashboard`). Distinct from
/// `DashboardSummary` (Phase 8's fixed-to-today Home tab widget).
class DashboardReportSummary {
  const DashboardReportSummary({
    required this.rangeFrom,
    required this.rangeTo,
    required this.bookings,
    required this.revenue,
    required this.activeStaff,
    required this.totalCustomers,
    this.nextAppointment,
  });

  factory DashboardReportSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    final range = summary['range'] as Map<String, dynamic>;
    return DashboardReportSummary(
      rangeFrom: range['from'] as String,
      rangeTo: range['to'] as String,
      bookings: Map<String, dynamic>.from(summary['bookings'] as Map),
      revenue: Map<String, dynamic>.from(summary['revenue'] as Map),
      activeStaff: summary['active_staff'] as int,
      totalCustomers: summary['total_customers'] as int,
      nextAppointment: summary['next_appointment'] as Map<String, dynamic>?,
    );
  }

  final String rangeFrom;
  final String rangeTo;
  final Map<String, dynamic> bookings;
  final Map<String, dynamic> revenue;
  final int activeStaff;
  final int totalCustomers;
  final Map<String, dynamic>? nextAppointment;

  int bookingCount(String status) => (bookings[status] as num?)?.toInt() ?? 0;
  String get netRevenue => revenue['net_revenue']?.toString() ?? '0.00';
}
