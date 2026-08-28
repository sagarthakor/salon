import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/owner/customers/data/repositories/owner_customer_repository.dart';
import 'package:salon_customer/features/owner/dashboard/data/repositories/dashboard_repository.dart';
import 'package:salon_customer/features/owner/staff/data/repositories/staff_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('DashboardRepository.summary', () {
    test('calls GET /dashboard/summary and parses the real envelope returned', () async {
      when(() => client.get<Map<String, dynamic>>('/dashboard/summary')).thenAnswer(
        (_) async => {
          'date': '2026-08-23',
          'bookings': {'total': 3},
          'revenue_today': '499.00',
          'next_appointment': null,
          'staff': {'active': 2, 'on_leave_today': 0},
          'customers': {'total': 10, 'new_this_month': 1},
        },
      );

      final summary = await DashboardRepository(client).summary();

      expect(summary.date, '2026-08-23');
      expect(summary.totalBookingsToday, 3);
      verify(() => client.get<Map<String, dynamic>>('/dashboard/summary')).called(1);
    });
  });

  group('StaffRepository.list', () {
    test('omits status/branch_id from the query entirely when both filters are null', () async {
      when(
        () => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => <dynamic>[]);

      await StaffRepository(client).list();

      final captured =
          verify(
                () => client.get<List<dynamic>>(any(), queryParameters: captureAny(named: 'queryParameters')),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('status'), isFalse, reason: 'a null filter must never be sent as a literal null');
      expect(captured.containsKey('branch_id'), isFalse);
      expect(captured['page'], 1);
      expect(captured['per_page'], 20);
    });

    test('includes status/branch_id in the query when filters are actually provided', () async {
      when(
        () => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => <dynamic>[]);

      await StaffRepository(client).list(status: 'active', branchId: 'br-1');

      final captured =
          verify(
                () => client.get<List<dynamic>>(any(), queryParameters: captureAny(named: 'queryParameters')),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['status'], 'active');
      expect(captured['branch_id'], 'br-1');
    });
  });

  group('OwnerCustomerRepository.create', () {
    test('omits gender/date_of_birth/status when not provided, never sending literal nulls', () async {
      when(
        () => client.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => {'id': 'c1', 'name': 'Test', 'phone': '9999999999', 'status': 'active'});

      await OwnerCustomerRepository(client).create(name: 'Test', phone: '9999999999');

      final captured =
          verify(() => client.post<Map<String, dynamic>>(any(), data: captureAny(named: 'data'))).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('gender'), isFalse);
      expect(captured.containsKey('date_of_birth'), isFalse);
      expect(captured.containsKey('status'), isFalse);
      expect(captured['name'], 'Test');
      expect(captured['phone'], '9999999999');
    });
  });
}
