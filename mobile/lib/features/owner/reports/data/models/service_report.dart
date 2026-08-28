import 'report_json.dart';

/// Mirrors `App\Services\Reports\ServiceReport` (`GET /reports/services`).
class ServiceReport {
  const ServiceReport({required this.totalServicesBooked, required this.totalBookings, required this.services, required this.byCategory});

  factory ServiceReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    final breakdown = Map<String, dynamic>.from(json['breakdown'] as Map? ?? const {});
    return ServiceReport(
      totalServicesBooked: summary['total_services_booked'] as int,
      totalBookings: summary['total_bookings'] as int,
      services: reportRows(json['data']),
      byCategory: reportRows(breakdown['by_category']),
    );
  }

  final int totalServicesBooked;
  final int totalBookings;
  final List<Map<String, dynamic>> services;
  final List<Map<String, dynamic>> byCategory;
}
