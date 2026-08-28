import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/branch.dart';
import '../../data/models/customer_salon.dart';
import '../../data/models/salon.dart';
import '../../data/repositories/salon_repository.dart';

final salonRepositoryProvider = Provider<SalonRepository>((ref) => SalonRepository(ref.watch(apiClientProvider)));

/// The customer's salons, fetched once per app session and re-fetchable via
/// `ref.invalidate(mySalonsProvider)` (e.g. pull-to-refresh).
final mySalonsProvider = FutureProvider<List<CustomerSalon>>((ref) {
  return ref.watch(salonRepositoryProvider).mySalons();
});

/// Every active salon the customer can discover — independent of any prior
/// relationship. This is the Customer Dashboard's "Find a Salon" list.
final discoverSalonsProvider = FutureProvider<List<Salon>>((ref) {
  return ref.watch(salonRepositoryProvider).discoverSalons();
});

/// Active branches for one discovered salon, keyed by salon id.
final salonBranchesProvider = FutureProvider.family<List<Branch>, String>((ref, salonId) {
  return ref.watch(salonRepositoryProvider).branchesForSalon(salonId);
});

/// The branch the customer is currently booking at, set when they pick one
/// from a salon's branch list and read by every screen in the booking flow.
final selectedBranchProvider = StateProvider<Branch?>((ref) => null);

/// The audience segment (`male`/`female`/`unisex`/`kids`) the customer chose
/// on the audience-selection step, right after picking a branch — the
/// customer dashboard's "Men / Women / Unisex / Kids" entry point. See
/// MASTER_CATALOG_ARCHITECTURE.md.
final selectedAudienceProvider = StateProvider<String?>((ref) => null);
