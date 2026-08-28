import 'report_json.dart';

/// Mirrors `App\Services\Reports\MembershipReport` (`GET /reports/memberships`).
/// `membershipRevenue` is Phase 12 `membership_payments` — never SaaS
/// subscription revenue.
class MembershipReport {
  const MembershipReport({
    required this.totalPlans,
    required this.membershipsStarted,
    required this.activeMemberships,
    required this.expiredMemberships,
    required this.cancelledMemberships,
    required this.membershipRevenue,
    required this.byPlan,
  });

  factory MembershipReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    final breakdown = Map<String, dynamic>.from(json['breakdown'] as Map? ?? const {});
    return MembershipReport(
      totalPlans: summary['total_plans'] as int,
      membershipsStarted: summary['memberships_started'] as int,
      activeMemberships: summary['active_memberships'] as int,
      expiredMemberships: summary['expired_memberships'] as int,
      cancelledMemberships: summary['cancelled_memberships'] as int,
      membershipRevenue: summary['membership_revenue'] as String,
      byPlan: reportRows(breakdown['by_plan']),
    );
  }

  final int totalPlans;
  final int membershipsStarted;
  final int activeMemberships;
  final int expiredMemberships;
  final int cancelledMemberships;
  final String membershipRevenue;
  final List<Map<String, dynamic>> byPlan;
}
