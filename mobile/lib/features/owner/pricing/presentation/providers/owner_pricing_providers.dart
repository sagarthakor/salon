import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../data/models/coupon.dart';
import '../../data/repositories/coupon_repository.dart';
import '../../data/repositories/owner_loyalty_repository.dart';
import '../../data/repositories/owner_membership_plan_repository.dart';
import '../../data/repositories/owner_membership_repository.dart';

final couponRepositoryProvider = Provider<CouponRepository>((ref) => CouponRepository(ref.watch(apiClientProvider)));

final couponsProvider = FutureProvider<List<Coupon>>((ref) => ref.watch(couponRepositoryProvider).list());

final ownerMembershipPlanRepositoryProvider = Provider<OwnerMembershipPlanRepository>(
  (ref) => OwnerMembershipPlanRepository(ref.watch(apiClientProvider)),
);

final ownerMembershipPlansProvider = FutureProvider((ref) => ref.watch(ownerMembershipPlanRepositoryProvider).list());

final ownerMembershipRepositoryProvider = Provider<OwnerMembershipRepository>(
  (ref) => OwnerMembershipRepository(ref.watch(apiClientProvider)),
);

final ownerMembershipsProvider = FutureProvider((ref) => ref.watch(ownerMembershipRepositoryProvider).list());

final ownerLoyaltyRepositoryProvider = Provider<OwnerLoyaltyRepository>(
  (ref) => OwnerLoyaltyRepository(ref.watch(apiClientProvider)),
);

final loyaltySearchProvider = FutureProvider.family<List<LoyaltyAccountSearchResult>, String>(
  (ref, query) => ref.watch(ownerLoyaltyRepositoryProvider).search(query: query.isEmpty ? null : query),
);
