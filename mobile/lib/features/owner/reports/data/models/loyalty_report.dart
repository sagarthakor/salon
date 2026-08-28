import 'report_json.dart';

/// Mirrors `App\Services\Reports\LoyaltyReport` (`GET /reports/loyalty`) —
/// every figure read from the transaction ledger, not the current balance.
class LoyaltyReport {
  const LoyaltyReport({
    required this.pointsEarned,
    required this.pointsRedeemed,
    required this.pointsExpired,
    required this.pointsAdjusted,
    required this.outstandingPoints,
    required this.transactions,
  });

  factory LoyaltyReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    return LoyaltyReport(
      pointsEarned: summary['points_earned'] as int,
      pointsRedeemed: summary['points_redeemed'] as int,
      pointsExpired: summary['points_expired'] as int,
      pointsAdjusted: summary['points_adjusted'] as int,
      outstandingPoints: summary['outstanding_points'] as int,
      transactions: reportRows(json['data']),
    );
  }

  final int pointsEarned;
  final int pointsRedeemed;
  final int pointsExpired;
  final int pointsAdjusted;
  final int outstandingPoints;
  final List<Map<String, dynamic>> transactions;
}
