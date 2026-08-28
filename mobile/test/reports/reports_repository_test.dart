import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/owner/reports/data/models/report_filter.dart';
import 'package:salon_customer/features/owner/reports/data/repositories/reports_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;
  late ReportsRepository repository;

  setUp(() {
    client = MockApiClient();
    repository = ReportsRepository(client);
  });

  Map<String, dynamic> summaryOnly(Map<String, dynamic> summary) => {'summary': summary, 'series': [], 'breakdown': {}, 'data': []};

  test('revenue() calls GET /reports/revenue with the filter as query parameters', () async {
    when(() => client.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => summaryOnly({
        'completed_bookings': 0,
        'gross_booking_value': '0.00',
        'discount': '0.00',
        'tax': '0.00',
        'net_revenue': '0.00',
        'average_booking_value': '0.00',
      }),
    );

    await repository.revenue(const ReportFilter(range: 'today', branchId: 'b1'));

    final captured = verify(
      () => client.get<Map<String, dynamic>>('/reports/revenue', queryParameters: captureAny(named: 'queryParameters')),
    ).captured.single as Map<String, dynamic>;
    expect(captured['range'], 'today');
    expect(captured['branch_id'], 'b1');
    expect(captured.containsKey('staff_id'), isFalse);
  });

  test('bookings() calls GET /reports/bookings', () async {
    when(() => client.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => summaryOnly({'total': 0, 'cancellation_rate': 0.0, 'no_show_rate': 0.0}),
    );

    await repository.bookings(const ReportFilter());

    verify(() => client.get<Map<String, dynamic>>('/reports/bookings', queryParameters: any(named: 'queryParameters'))).called(1);
  });

  test('staff() calls GET /reports/staff and forwards pagination/sort parameters', () async {
    when(() => client.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => {'summary': {'total_staff': 0, 'active_staff': 0}, 'data': []},
    );

    await repository.staff(const ReportFilter(page: 2, perPage: 10, sort: 'net_revenue', direction: 'desc'));

    final captured = verify(
      () => client.get<Map<String, dynamic>>('/reports/staff', queryParameters: captureAny(named: 'queryParameters')),
    ).captured.single as Map<String, dynamic>;
    expect(captured['page'], 2);
    expect(captured['per_page'], 10);
    expect(captured['sort'], 'net_revenue');
    expect(captured['direction'], 'desc');
  });

  test('loyalty() calls GET /reports/loyalty', () async {
    when(() => client.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async => {
        'summary': {'points_earned': 0, 'points_redeemed': 0, 'points_expired': 0, 'points_adjusted': 0, 'outstanding_points': 0},
        'data': [],
      },
    );

    await repository.loyalty(const ReportFilter());

    verify(() => client.get<Map<String, dynamic>>('/reports/loyalty', queryParameters: any(named: 'queryParameters'))).called(1);
  });
}
