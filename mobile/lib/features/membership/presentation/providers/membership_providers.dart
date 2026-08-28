import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../data/models/customer_membership.dart';
import '../../data/models/membership_plan.dart';
import '../../data/repositories/customer_membership_repository.dart';

final customerMembershipRepositoryProvider = Provider<CustomerMembershipRepository>(
  (ref) => CustomerMembershipRepository(ref.watch(apiClientProvider)),
);

final currentMembershipProvider = FutureProvider<CustomerMembership?>((ref) {
  return ref.watch(customerMembershipRepositoryProvider).current();
});

/// Plans are scoped by branch on the backend (see
/// `CustomerMembershipController::plans()`); reuses whichever branch the
/// customer already selected for booking, falling back to their first
/// salon's first branch — the same single-salon assumption
/// `ProfileRepository`/this app's customer surface already makes elsewhere.
final membershipPlansProvider = FutureProvider<List<MembershipPlan>>((ref) async {
  final selectedBranch = ref.watch(selectedBranchProvider);
  final branchId = selectedBranch?.id ?? (await ref.watch(mySalonsProvider.future)).firstOrNull?.branches.firstOrNull?.id;
  if (branchId == null) return [];

  return ref.watch(customerMembershipRepositoryProvider).plans(branchId);
});
