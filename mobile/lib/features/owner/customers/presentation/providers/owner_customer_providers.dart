import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../../../profile/data/models/customer_profile.dart';
import '../../data/models/customer_note_entry.dart';
import '../../data/models/customer_summary.dart';
import '../../data/repositories/owner_customer_repository.dart';

final ownerCustomerRepositoryProvider = Provider<OwnerCustomerRepository>(
  (ref) => OwnerCustomerRepository(ref.watch(apiClientProvider)),
);

final ownerCustomerDetailsProvider = FutureProvider.family<CustomerProfile, String>((ref, id) {
  return ref.watch(ownerCustomerRepositoryProvider).details(id);
});

final ownerCustomerSummaryProvider = FutureProvider.family<CustomerSummary, String>((ref, id) {
  return ref.watch(ownerCustomerRepositoryProvider).summary(id);
});

final ownerCustomerNotesProvider = FutureProvider.family<List<CustomerNoteEntry>, String>((ref, id) {
  return ref.watch(ownerCustomerRepositoryProvider).notes(id);
});
