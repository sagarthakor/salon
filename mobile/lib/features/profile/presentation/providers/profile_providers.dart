import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/customer_profile.dart';
import '../../data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));

final customerProfileProvider = FutureProvider<CustomerProfile>((ref) {
  return ref.watch(profileRepositoryProvider).show();
});
