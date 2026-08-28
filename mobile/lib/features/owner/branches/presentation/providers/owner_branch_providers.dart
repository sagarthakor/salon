import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../../../salon/data/models/branch.dart';
import '../../data/models/branch_working_hour_entry.dart';
import '../../data/repositories/owner_branch_repository.dart';

final ownerBranchRepositoryProvider = Provider<OwnerBranchRepository>(
  (ref) => OwnerBranchRepository(ref.watch(apiClientProvider)),
);

final ownerBranchesProvider = FutureProvider<List<Branch>>((ref) {
  return ref.watch(ownerBranchRepositoryProvider).list();
});

final ownerBranchDetailsProvider = FutureProvider.family<Branch, String>((ref, id) {
  return ref.watch(ownerBranchRepositoryProvider).details(id);
});

final branchWorkingHoursProvider = FutureProvider.family<List<BranchWorkingHourEntry>, String>((ref, branchId) {
  return ref.watch(ownerBranchRepositoryProvider).workingHours(branchId);
});

final branchHolidaysProvider = FutureProvider.family((ref, String branchId) {
  return ref.watch(ownerBranchRepositoryProvider).holidays(branchId);
});
