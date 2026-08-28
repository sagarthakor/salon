import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/branch_services.dart';
import '../../data/repositories/service_repository.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) => ServiceRepository(ref.watch(apiClientProvider)));

/// The active/available service catalog for one branch. Keyed by branch id
/// via `.family` so switching branches doesn't require manual cache clearing.
final branchServicesProvider = FutureProvider.family<BranchServices, String>((ref, branchId) {
  return ref.watch(serviceRepositoryProvider).forBranch(branchId);
});
