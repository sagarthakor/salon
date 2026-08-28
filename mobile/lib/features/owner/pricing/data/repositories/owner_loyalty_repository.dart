import '../../../../../core/network/api_client.dart';
import '../../../../loyalty/data/models/loyalty_account.dart';
import '../../../../loyalty/data/models/loyalty_transaction.dart';
import '../../../../profile/data/models/customer_profile.dart';

/// Talks to the Phase 12 owner loyalty-management APIs (`/loyalty/customers*`).
class OwnerLoyaltyRepository {
  OwnerLoyaltyRepository(this._client);

  final ApiClient _client;

  /// Accounts with a non-zero balance, optionally filtered by customer
  /// name/phone — used for the owner's "search a customer's loyalty
  /// balance" screen. Includes the customer relation (eager-loaded by the
  /// backend) so the list can show a name, not just an id.
  Future<List<LoyaltyAccountSearchResult>> search({int page = 1, int perPage = 20, String? query}) async {
    final data = await _client.get<List<dynamic>>(
      '/loyalty/customers',
      queryParameters: {'page': page, 'per_page': perPage, 'search': ?query},
    );
    return data.map((a) => LoyaltyAccountSearchResult.fromJson(a as Map<String, dynamic>)).toList();
  }

  Future<LoyaltyAccount> account(String customerId) async {
    final data = await _client.get<Map<String, dynamic>>('/loyalty/customers/$customerId');
    return LoyaltyAccount.fromJson(data);
  }

  Future<List<LoyaltyTransactionEntry>> transactions(String customerId, {int page = 1, int perPage = 20}) async {
    final data = await _client.get<List<dynamic>>(
      '/loyalty/customers/$customerId/transactions',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    return data.map((t) => LoyaltyTransactionEntry.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<LoyaltyTransactionEntry> adjust(String customerId, {required int points, required String reason}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/loyalty/customers/$customerId/adjust',
      data: {'points': points, 'reason': reason},
    );
    return LoyaltyTransactionEntry.fromJson(data);
  }
}

/// The backend's `LoyaltyAccountResource` doesn't itself carry the
/// customer's name (it's tenant/customer-scoped by URL, not by response
/// body), but the owner search list needs one to be usable — the backend
/// eager-loads `customer` on that one endpoint only. Kept as its own small
/// type rather than bolting an optional field onto `LoyaltyAccount` (which
/// the customer-facing screen never has this data for).
class LoyaltyAccountSearchResult {
  const LoyaltyAccountSearchResult({required this.account, required this.customer});

  factory LoyaltyAccountSearchResult.fromJson(Map<String, dynamic> json) => LoyaltyAccountSearchResult(
    account: LoyaltyAccount.fromJson(json),
    customer: json['customer'] is Map<String, dynamic> ? CustomerProfile.fromJson(json['customer'] as Map<String, dynamic>) : null,
  );

  final LoyaltyAccount account;
  final CustomerProfile? customer;
}
