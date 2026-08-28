import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/reports/data/models/booking_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/branch_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/customer_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/dashboard_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/report_filter.dart';
import 'package:salon_customer/features/owner/reports/data/models/report_series_point.dart';
import 'package:salon_customer/features/owner/reports/data/models/revenue_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/service_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/staff_report.dart';

void main() {
  group('ReportSeriesPoint.fromJson', () {
    test('parses numeric and string-encoded metric values, skipping the date key', () {
      final point = ReportSeriesPoint.fromJson({'date': '2026-08-01', 'revenue': '500.00', 'bookings': 3});
      expect(point.date, '2026-08-01');
      expect(point.valueFor('revenue'), 500.0);
      expect(point.valueFor('bookings'), 3);
      expect(point.valueFor('missing'), 0);
    });
  });

  group('ReportFilter', () {
    test('toQueryParameters omits every unset filter rather than sending literal nulls', () {
      const filter = ReportFilter();
      final query = filter.toQueryParameters();
      expect(query['range'], 'this_month');
      expect(query.containsKey('branch_id'), isFalse);
      expect(query.containsKey('staff_id'), isFalse);
      expect(query['page'], 1);
      expect(query['per_page'], 20);
    });

    test('toQueryParameters includes filters that are actually set', () {
      const filter = ReportFilter(range: 'custom', from: '2026-08-01', to: '2026-08-31', branchId: 'b1');
      final query = filter.toQueryParameters();
      expect(query['range'], 'custom');
      expect(query['from'], '2026-08-01');
      expect(query['to'], '2026-08-31');
      expect(query['branch_id'], 'b1');
    });

    test('copyWith clearBranchId removes a previously-set branch filter', () {
      const filter = ReportFilter(branchId: 'b1');
      final cleared = filter.copyWith(clearBranchId: true);
      expect(cleared.branchId, isNull);
    });
  });

  group('RevenueReport.fromJson', () {
    test('parses summary, series, and every breakdown list', () {
      final report = RevenueReport.fromJson({
        'summary': {
          'completed_bookings': 2,
          'gross_booking_value': '1500.00',
          'discount': '100.00',
          'tax': '0.00',
          'net_revenue': '1400.00',
          'average_booking_value': '700.00',
        },
        'series': [
          {'date': '2026-08-01', 'revenue': '500.00'},
        ],
        'breakdown': {
          'by_branch': [
            {'branch_id': 'br1', 'branch_name': 'Main', 'revenue': '1400.00'},
          ],
          'by_staff': [
            {'staff_id': 's1', 'staff_name': 'Amit', 'net_revenue': '700.00'},
          ],
          'by_service': [
            {'service_id': 'sv1', 'service_name': 'Haircut', 'net_value': '300.00'},
          ],
        },
      });

      expect(report.summary.completedBookings, 2);
      expect(report.summary.netRevenue, '1400.00');
      expect(report.series.single.valueFor('revenue'), 500.0);
      expect(report.byBranch.single['branch_name'], 'Main');
      expect(report.byStaff.single['staff_name'], 'Amit');
      expect(report.byService.single['service_name'], 'Haircut');
    });
  });

  group('BookingReport.fromJson', () {
    test('exposes status counts via countFor and the cancellation breakdown', () {
      final report = BookingReport.fromJson({
        'summary': {'total': 4, 'completed': 2, 'cancelled': 1, 'no_show': 1, 'cancellation_rate': 0.25, 'no_show_rate': 0.25},
        'series': [],
        'breakdown': {
          'by_branch': [],
          'cancellation_reasons': [
            {'reason': 'Customer request', 'count': 1},
          ],
        },
      });

      expect(report.summary.total, 4);
      expect(report.summary.countFor('completed'), 2);
      expect(report.summary.countFor('unknown_status'), 0);
      expect(report.summary.cancellationRate, 0.25);
      expect(report.cancellationReasons.single['reason'], 'Customer request');
    });
  });

  group('CustomerReport.fromJson', () {
    test('repeatBookingRate is null when the backend omits it (no completed bookings)', () {
      final report = CustomerReport.fromJson({
        'summary': {
          'total_customers': 5,
          'new_customers': 1,
          'active_customers': 2,
          'returning_customers': 1,
          'customers_with_completed_bookings': 0,
          'customers_with_cancelled_bookings': 0,
          'repeat_booking_rate': null,
        },
        'series': [],
        'data': [],
      });

      expect(report.summary.repeatBookingRate, isNull);
      expect(report.topCustomers, isEmpty);
    });
  });

  group('ServiceReport.fromJson', () {
    test('parses the services list and category breakdown', () {
      final report = ServiceReport.fromJson({
        'summary': {'total_services_booked': 1, 'total_bookings': 3},
        'data': [
          {'service_id': 'sv1', 'service_name': 'Haircut', 'bookings': 3},
        ],
        'breakdown': {
          'by_category': [
            {'category_id': 'c1', 'category_name': 'Hair', 'bookings': 3},
          ],
        },
      });

      expect(report.totalServicesBooked, 1);
      expect(report.services.single['service_name'], 'Haircut');
      expect(report.byCategory.single['category_name'], 'Hair');
    });
  });

  group('StaffReport.fromJson', () {
    test('parses staff performance rows including a null utilization_percent', () {
      final report = StaffReport.fromJson({
        'summary': {'total_staff': 1, 'active_staff': 1},
        'data': [
          {'staff_id': 's1', 'staff_name': 'Amit', 'utilization_percent': null},
        ],
      });

      expect(report.staff.single['staff_name'], 'Amit');
      expect(report.staff.single['utilization_percent'], isNull);
    });
  });

  group('BranchReport.fromJson', () {
    test('includes a branch with zero bookings', () {
      final report = BranchReport.fromJson({
        'summary': {'total_branches': 2, 'total_bookings': 3, 'total_revenue': '900.00'},
        'data': [
          {'branch_id': 'b1', 'bookings': 3},
          {'branch_id': 'b2', 'bookings': 0},
        ],
      });

      expect(report.totalBranches, 2);
      expect(report.branches.firstWhere((b) => b['branch_id'] == 'b2')['bookings'], 0);
    });
  });

  group('DashboardReportSummary.fromJson', () {
    test('parses the range-flexible overview including bookings/revenue maps', () {
      final summary = DashboardReportSummary.fromJson({
        'summary': {
          'range': {'preset': 'this_month', 'from': '2026-08-01', 'to': '2026-08-31'},
          'bookings': {'total': 4, 'completed': 2},
          'revenue': {'net_revenue': '900.00'},
          'active_staff': 1,
          'total_customers': 5,
          'next_appointment': null,
        },
      });

      expect(summary.rangeFrom, '2026-08-01');
      expect(summary.bookingCount('completed'), 2);
      expect(summary.netRevenue, '900.00');
      expect(summary.nextAppointment, isNull);
    });
  });
}
