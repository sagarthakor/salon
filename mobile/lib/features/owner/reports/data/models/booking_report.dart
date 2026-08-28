import 'report_json.dart';
import 'report_series_point.dart';

/// Mirrors `App\Services\Reports\BookingReport` (`GET /reports/bookings`) —
/// status counts/rates, the status trend, and (folded in, see the backend
/// class doc) the cancellation breakdown.
class BookingReport {
  const BookingReport({required this.summary, required this.series, required this.byBranch, required this.cancellationReasons});

  factory BookingReport.fromJson(Map<String, dynamic> json) {
    final breakdown = Map<String, dynamic>.from(json['breakdown'] as Map? ?? const {});
    return BookingReport(
      summary: BookingSummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map)),
      series: (json['series'] as List? ?? const [])
          .map((e) => ReportSeriesPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      byBranch: reportRows(breakdown['by_branch']),
      cancellationReasons: reportRows(breakdown['cancellation_reasons']),
    );
  }

  final BookingSummary summary;
  final List<ReportSeriesPoint> series;
  final List<Map<String, dynamic>> byBranch;
  final List<Map<String, dynamic>> cancellationReasons;
}

class BookingSummary {
  const BookingSummary({
    required this.total,
    required this.counts,
    required this.cancellationRate,
    required this.noShowRate,
  });

  factory BookingSummary.fromJson(Map<String, dynamic> json) => BookingSummary(
    total: json['total'] as int,
    counts: Map<String, dynamic>.from(json),
    cancellationRate: (json['cancellation_rate'] as num).toDouble(),
    noShowRate: (json['no_show_rate'] as num).toDouble(),
  );

  final int total;
  final Map<String, dynamic> counts;
  final double cancellationRate;
  final double noShowRate;

  int countFor(String status) => (counts[status] as num?)?.toInt() ?? 0;
}
