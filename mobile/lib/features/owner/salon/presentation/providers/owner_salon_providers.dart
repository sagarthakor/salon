import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../../../salon/data/models/salon.dart';
import '../../data/repositories/owner_salon_repository.dart';

final ownerSalonRepositoryProvider = Provider<OwnerSalonRepository>(
  (ref) => OwnerSalonRepository(ref.watch(apiClientProvider)),
);

final ownerSalonProvider = FutureProvider<Salon>((ref) {
  return ref.watch(ownerSalonRepositoryProvider).show();
});

final ownerSalonSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(ownerSalonRepositoryProvider).settings();
});
