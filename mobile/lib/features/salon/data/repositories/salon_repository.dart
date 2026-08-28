import '../../../../core/network/api_client.dart';
import '../models/customer_salon.dart';

/// Talks to `GET /customer/salons` — the salons the authenticated customer
/// already has a relationship with. See CUSTOMER_ARCHITECTURE.md and
/// MOBILE_API_INTEGRATION.md for why there is no broader salon-discovery
/// endpoint yet.
class SalonRepository {
  SalonRepository(this._client);

  final ApiClient _client;

  Future<List<CustomerSalon>> mySalons() async {
    final data = await _client.get<List<dynamic>>('/customer/salons');
    return data.map((e) => CustomerSalon.fromJson(e as Map<String, dynamic>)).toList();
  }
}
