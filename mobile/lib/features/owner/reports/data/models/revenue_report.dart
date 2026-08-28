import 'report_json.dart';
import 'report_series_point.dart';

/// Mirrors `App\Services\Reports\RevenueReport` (`GET /reports/revenue`).
class RevenueReport {
  const RevenueReport({required this.summary, required this.series, required this.byBranch, required this.byStaff, required this.byService});

  factory RevenueReport.fromJson(Map<String, dynamic> json) {
    final breakdown = Map<String, dynamic>.from(json['breakdown'] as Map? ?? const {});
    return RevenueReport(
      summary: RevenueSummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map)),
      series: (json['series'] as List? ?? const [])
          .map((e) => ReportSeriesPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      byBranch: reportRows(breakdown['by_branch']),
      byStaff: reportRows(breakdown['by_staff']),
      byService: reportRows(breakdown['by_service']),
    );
  }

  final RevenueSummary summary;
  final List<ReportSeriesPoint> series;
  final List<Map<String, dynamic>> byBranch;
  final List<Map<String, dynamic>> byStaff;
  final List<Map<String, dynamic>> byService;
}

class RevenueSummary {
  const RevenueSummary({
    required this.completedBookings,
    required this.grossBookingValue,
    required this.discount,
    required this.netRevenue,
    required this.averageBookingValue,
  });

  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
    completedBookings: json['completed_bookings'] as int,
    grossBookingValue: json['gross_booking_value'] as String,
    discount: json['discount'] as String,
    netRevenue: json['net_revenue'] as String,
    averageBookingValue: json['average_booking_value'] as String,
  );

  final int completedBookings;
  final String grossBookingValue;
  final String discount;
  final String netRevenue;
  final String averageBookingValue;
}
