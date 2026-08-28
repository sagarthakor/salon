import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/branch.dart';
import '../../data/models/customer_salon.dart';
import '../../data/repositories/salon_repository.dart';

final salonRepositoryProvider = Provider<SalonRepository>((ref) => SalonRepository(ref.watch(apiClientProvider)));

/// The customer's salons, fetched once per app session and re-fetchable via
/// `ref.invalidate(mySalonsProvider)` (e.g. pull-to-refresh).
final mySalonsProvider = FutureProvider<List<CustomerSalon>>((ref) {
  return ref.watch(salonRepositoryProvider).mySalons();
});

/// The branch the customer is currently booking at, set when they pick one
/// from a salon's branch list and read by every screen in the booking flow.
final selectedBranchProvider = StateProvider<Branch?>((ref) => null);
