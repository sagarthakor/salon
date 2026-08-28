import 'report_json.dart';
import 'report_series_point.dart';

/// Mirrors `App\Services\Reports\CustomerReport` (`GET /reports/customers`).
class CustomerReport {
  const CustomerReport({required this.summary, required this.series, required this.topCustomers});

  factory CustomerReport.fromJson(Map<String, dynamic> json) => CustomerReport(
    summary: CustomerSummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map)),
    series: (json['series'] as List? ?? const [])
        .map((e) => ReportSeriesPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    topCustomers: reportRows(json['data']),
  );

  final CustomerSummary summary;
  final List<ReportSeriesPoint> series;
  final List<Map<String, dynamic>> topCustomers;
}

class CustomerSummary {
  const CustomerSummary({
    required this.totalCustomers,
    required this.newCustomers,
    required this.activeCustomers,
    required this.returningCustomers,
    required this.customersWithCompletedBookings,
    required this.customersWithCancelledBookings,
    this.repeatBookingRate,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
    totalCustomers: json['total_customers'] as int,
    newCustomers: json['new_customers'] as int,
    activeCustomers: json['active_customers'] as int,
    returningCustomers: json['returning_customers'] as int,
    customersWithCompletedBookings: json['customers_with_completed_bookings'] as int,
    customersWithCancelledBookings: json['customers_with_cancelled_bookings'] as int,
    repeatBookingRate: (json['repeat_booking_rate'] as num?)?.toDouble(),
  );

  final int totalCustomers;
  final int newCustomers;
  final int activeCustomers;
  final int returningCustomers;
  final int customersWithCompletedBookings;
  final int customersWithCancelledBookings;
  final double? repeatBookingRate;
}
