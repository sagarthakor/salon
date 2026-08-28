import 'report_json.dart';

/// Mirrors `App\Services\Reports\StaffReport` (`GET /reports/staff`) — owner
/// only, never reachable by the Staff app.
class StaffReport {
  const StaffReport({required this.totalStaff, required this.activeStaff, required this.staff});

  factory StaffReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    return StaffReport(
      totalStaff: summary['total_staff'] as int,
      activeStaff: summary['active_staff'] as int,
      staff: reportRows(json['data']),
    );
  }

  final int totalStaff;
  final int activeStaff;
  final List<Map<String, dynamic>> staff;
}
