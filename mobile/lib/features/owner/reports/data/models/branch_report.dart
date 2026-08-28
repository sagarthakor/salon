import 'report_json.dart';

/// Mirrors `App\Services\Reports\BranchReport` (`GET /reports/branches`) —
/// every tenant branch appears, including ones with zero bookings.
class BranchReport {
  const BranchReport({required this.totalBranches, required this.totalBookings, required this.totalRevenue, required this.branches});

  factory BranchReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    return BranchReport(
      totalBranches: summary['total_branches'] as int,
      totalBookings: summary['total_bookings'] as int,
      totalRevenue: summary['total_revenue'] as String,
      branches: reportRows(json['data']),
    );
  }

  final int totalBranches;
  final int totalBookings;
  final String totalRevenue;
  final List<Map<String, dynamic>> branches;
}
