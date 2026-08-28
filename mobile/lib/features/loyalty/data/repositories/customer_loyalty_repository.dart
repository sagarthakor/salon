import '../../../../core/network/api_client.dart';
import '../models/loyalty_account.dart';
import '../models/loyalty_transaction.dart';

/// Talks to the customer-facing Phase 12 loyalty APIs
/// (`/customer/loyalty*`).
class CustomerLoyaltyRepository {
  CustomerLoyaltyRepository(this._client);

  final ApiClient _client;

  Future<LoyaltyAccount> account() async {
    final data = await _client.get<Map<String, dynamic>>('/customer/loyalty');
    return LoyaltyAccount.fromJson(data);
  }

  Future<List<LoyaltyTransactionEntry>> transactions({int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>(
      '/customer/loyalty/transactions',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    return data.map((t) => LoyaltyTransactionEntry.fromJson(t as Map<String, dynamic>)).toList();
  }
}
