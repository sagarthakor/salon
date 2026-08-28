import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/loyalty_account.dart';
import '../../data/repositories/customer_loyalty_repository.dart';

final customerLoyaltyRepositoryProvider = Provider<CustomerLoyaltyRepository>(
  (ref) => CustomerLoyaltyRepository(ref.watch(apiClientProvider)),
);

final loyaltyAccountProvider = FutureProvider<LoyaltyAccount>((ref) {
  return ref.watch(customerLoyaltyRepositoryProvider).account();
});
