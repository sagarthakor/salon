import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/loyalty/data/repositories/customer_loyalty_repository.dart';
import 'package:salon_customer/features/membership/data/repositories/customer_membership_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('CustomerMembershipRepository', () {
    late CustomerMembershipRepository repository;

    setUp(() => repository = CustomerMembershipRepository(client));

    test('current() returns null when the backend has no active membership', () async {
      when(() => client.get<Map<String, dynamic>?>('/customer/membership')).thenAnswer((_) async => null);

      expect(await repository.current(), isNull);
    });

    test('checkout() sends only membership_plan_id — never a price', () async {
      when(() => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'payment_id': 'mpay_1',
          'idempotency_key': 'idem_1',
          'gateway': 'razorpay',
          'gateway_order_id': 'order_1',
          'amount': '999.00',
          'currency': 'INR',
          'plan': {'id': 'mp_1', 'name': 'Gold', 'code': 'GOLD'},
        },
      );

      await repository.checkout('mp_1');

      final captured = verify(
        () => client.post<Map<String, dynamic>>('/customer/membership/checkout', data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(captured.keys, ['membership_plan_id']);
      expect(captured['membership_plan_id'], 'mp_1');
    });

    test('verify() sends the payment/gateway confirmation fields', () async {
      when(() => client.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 'cm_1',
          'status': 'active',
          'starts_at': '2026-01-01T00:00:00+00:00',
          'expires_at': '2026-02-01T00:00:00+00:00',
          'purchased_amount': '999.00',
          'currency': 'INR',
          'source': 'purchase',
          'is_currently_active': true,
        },
      );

      final membership = await repository.verify(paymentId: 'mpay_1', gatewayPaymentId: 'pay_1', gatewaySignature: 'sig_1');

      final captured = verify(
        () => client.post<Map<String, dynamic>>('/customer/membership/checkout/verify', data: captureAny(named: 'data')),
      ).captured.single as Map<String, dynamic>;
      expect(captured, {'payment_id': 'mpay_1', 'gateway_payment_id': 'pay_1', 'gateway_signature': 'sig_1'});
      expect(membership.status, 'active');
    });
  });

  group('CustomerLoyaltyRepository', () {
    late CustomerLoyaltyRepository repository;

    setUp(() => repository = CustomerLoyaltyRepository(client));

    test('account() parses the balance', () async {
      when(() => client.get<Map<String, dynamic>>('/customer/loyalty')).thenAnswer(
        (_) async => {'id': 'la_1', 'balance': 120, 'lifetime_earned': 200, 'lifetime_redeemed': 80},
      );

      final account = await repository.account();

      expect(account.balance, 120);
    });

    test('transactions() paginates', () async {
      when(() => client.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async => []);

      await repository.transactions(page: 2, perPage: 10);

      final captured = verify(
        () => client.get<List<dynamic>>('/customer/loyalty/transactions', queryParameters: captureAny(named: 'queryParameters')),
      ).captured.single as Map<String, dynamic>;
      expect(captured['page'], 2);
      expect(captured['per_page'], 10);
    });
  });
}
