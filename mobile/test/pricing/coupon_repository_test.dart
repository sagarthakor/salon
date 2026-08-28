import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/owner/pricing/data/repositories/coupon_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;
  late CouponRepository repository;

  setUp(() {
    client = MockApiClient();
    repository = CouponRepository(client);
  });

  test('create() posts the exact payload given, never fabricating extra fields', () async {
    when(() => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => {
        'id': 'cp_1',
        'code': 'WELCOME10',
        'name': 'Welcome',
        'discount_type': 'percentage',
        'discount_value': '10.00',
        'usage_count': 0,
        'is_active': true,
        'first_booking_only': false,
      },
    );

    final payload = {'code': 'WELCOME10', 'name': 'Welcome', 'discount_type': 'percentage', 'discount_value': 10};
    final coupon = await repository.create(payload);

    final captured = verify(() => client.post<Map<String, dynamic>>('/coupons', data: captureAny(named: 'data'))).captured.single;
    expect(captured, payload);
    expect(coupon.code, 'WELCOME10');
  });

  test('activate()/deactivate() hit the dedicated endpoints', () async {
    when(() => client.post<Map<String, dynamic>>(any())).thenAnswer(
      (_) async => {
        'id': 'cp_1',
        'code': 'WELCOME10',
        'name': 'Welcome',
        'discount_type': 'percentage',
        'discount_value': '10.00',
        'usage_count': 0,
        'is_active': false,
        'first_booking_only': false,
      },
    );

    await repository.activate('cp_1');
    await repository.deactivate('cp_1');

    verify(() => client.post<Map<String, dynamic>>('/coupons/cp_1/activate')).called(1);
    verify(() => client.post<Map<String, dynamic>>('/coupons/cp_1/deactivate')).called(1);
  });

  test('list() requests the given filters', () async {
    when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => []);

    await repository.list(isActive: true, search: 'welcome');

    final captured = verify(
      () => client.get<List<dynamic>>('/coupons', queryParameters: captureAny(named: 'queryParameters')),
    ).captured.single as Map<String, dynamic>;
    expect(captured['is_active'], true);
    expect(captured['search'], 'welcome');
  });
}
