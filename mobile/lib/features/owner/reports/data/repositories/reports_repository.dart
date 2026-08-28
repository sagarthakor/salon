import '../../../../../core/network/api_client.dart';
import '../models/booking_report.dart';
import '../models/branch_report.dart';
import '../models/coupon_report.dart';
import '../models/customer_report.dart';
import '../models/dashboard_report.dart';
import '../models/loyalty_report.dart';
import '../models/membership_report.dart';
import '../models/report_filter.dart';
import '../models/revenue_report.dart';
import '../models/service_report.dart';
import '../models/staff_report.dart';

/// All ten `/reports/*` reads (Phase 13). Every computation happens on the
/// backend (`App\Services\Reports\*`) — this repository only sends the
/// filter as query parameters and parses the response, never aggregates
/// anything itself. See REPORTING_ANALYTICS_ARCHITECTURE.md.
class ReportsRepository {
  ReportsRepository(this._client);

  final ApiClient _client;

  Future<DashboardReportSummary> dashboard(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/dashboard', queryParameters: filter.toQueryParameters());
    return DashboardReportSummary.fromJson(data);
  }

  Future<RevenueReport> revenue(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/revenue', queryParameters: filter.toQueryParameters());
    return RevenueReport.fromJson(data);
  }

  Future<BookingReport> bookings(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/bookings', queryParameters: filter.toQueryParameters());
    return BookingReport.fromJson(data);
  }

  Future<CustomerReport> customers(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/customers', queryParameters: filter.toQueryParameters());
    return CustomerReport.fromJson(data);
  }

  Future<ServiceReport> services(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/services', queryParameters: filter.toQueryParameters());
    return ServiceReport.fromJson(data);
  }

  Future<StaffReport> staff(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/staff', queryParameters: filter.toQueryParameters());
    return StaffReport.fromJson(data);
  }

  Future<BranchReport> branches(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/branches', queryParameters: filter.toQueryParameters());
    return BranchReport.fromJson(data);
  }

  Future<CouponReport> coupons(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/coupons', queryParameters: filter.toQueryParameters());
    return CouponReport.fromJson(data);
  }

  Future<MembershipReport> memberships(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/memberships', queryParameters: filter.toQueryParameters());
    return MembershipReport.fromJson(data);
  }

  Future<LoyaltyReport> loyalty(ReportFilter filter) async {
    final data = await _client.get<Map<String, dynamic>>('/reports/loyalty', queryParameters: filter.toQueryParameters());
    return LoyaltyReport.fromJson(data);
  }
}
