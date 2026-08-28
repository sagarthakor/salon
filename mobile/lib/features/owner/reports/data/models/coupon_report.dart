import 'report_json.dart';

/// Mirrors `App\Services\Reports\CouponReport` (`GET /reports/coupons`).
class CouponReport {
  const CouponReport({required this.couponsUsed, required this.totalTimesUsed, required this.totalDiscountGiven, required this.coupons});

  factory CouponReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    return CouponReport(
      couponsUsed: summary['coupons_used'] as int,
      totalTimesUsed: summary['total_times_used'] as int,
      totalDiscountGiven: summary['total_discount_given'] as String,
      coupons: reportRows(json['data']),
    );
  }

  final int couponsUsed;
  final int totalTimesUsed;
  final String totalDiscountGiven;
  final List<Map<String, dynamic>> coupons;
}
