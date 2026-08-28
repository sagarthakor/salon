import '../../../../core/network/api_client.dart';
import '../models/branch.dart';
import '../models/customer_salon.dart';
import '../models/salon.dart';

/// Talks to the customer salon endpoints. `mySalons()` (`GET
/// /customer/salons`) lists salons the customer already has a
/// `customer_profiles` relationship with — kept for existing callers.
/// `discoverSalons()`/`branchesForSalon()` are the public salon-discovery
/// endpoints: cross-tenant, no membership required. See
/// CUSTOMER_ARCHITECTURE.md, "Customer discovery and first-time booking".
class SalonRepository {
  SalonRepository(this._client);

  final ApiClient _client;

  Future<List<CustomerSalon>> mySalons() async {
    final data = await _client.get<List<dynamic>>('/customer/salons');
    return data.map((e) => CustomerSalon.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// All customer-discoverable (active) salons, across every tenant — no
  /// prior relationship with any of them required.
  Future<List<Salon>> discoverSalons() async {
    final data = await _client.get<List<dynamic>>('/customer/discover-salons');
    return data.map((e) => Salon.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Active branches for a salon picked from [discoverSalons] — the backend
  /// resolves the salon's tenant server-side from [salonId], never from
  /// anything else the client sends.
  Future<List<Branch>> branchesForSalon(String salonId) async {
    final data = await _client.get<List<dynamic>>('/customer/salons/$salonId/branches');
    return data.map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList();
  }
}
