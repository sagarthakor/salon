import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../data/models/plan.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(apiClientProvider)),
);

/// The tenant's current subscription — reachable regardless of subscription
/// status (never itself gated by `EnsureActiveSubscription`, see
/// SAAS_BILLING_ARCHITECTURE.md), so this is safe to watch from anywhere in
/// the owner app, including a subscription-expired banner on other screens.
final subscriptionProvider = FutureProvider<Subscription>((ref) {
  return ref.watch(subscriptionRepositoryProvider).show();
});

final subscriptionPlansProvider = FutureProvider<List<Plan>>((ref) {
  return ref.watch(subscriptionRepositoryProvider).plans();
});
