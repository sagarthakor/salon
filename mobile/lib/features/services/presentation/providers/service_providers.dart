import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/branch_services.dart';
import '../../data/repositories/service_repository.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) => ServiceRepository(ref.watch(apiClientProvider)));

/// The active/available service catalog for one branch, optionally narrowed
/// to one audience segment (`male`/`female`/`unisex`/`kids` — see
/// MASTER_CATALOG_ARCHITECTURE.md). Keyed by a `(branchId, audience)` record
/// via `.family` so switching either doesn't require manual cache clearing,
/// and picking a different audience for the same branch is its own cached
/// result rather than overwriting the unfiltered one.
final branchServicesProvider = FutureProvider.family<BranchServices, ({String branchId, String? audience})>((ref, key) {
  return ref.watch(serviceRepositoryProvider).forBranch(key.branchId, audience: key.audience);
});
