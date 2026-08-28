import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../data/models/staff_member.dart';
import '../../data/models/staff_schedule.dart';
import '../../data/repositories/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository(ref.watch(apiClientProvider)));

/// Full active staff list — used by pickers (e.g. the bookings filter sheet)
/// where a simple one-shot fetch is enough; the dedicated staff list screen
/// uses `StaffListController` below for pagination/status filtering.
final staffListProvider = FutureProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).list(perPage: 100);
});

final staffDetailsProvider = FutureProvider.family<StaffMember, String>((ref, staffId) {
  return ref.watch(staffRepositoryProvider).details(staffId);
});

final staffServicesProvider = FutureProvider.family((ref, String staffId) {
  return ref.watch(staffRepositoryProvider).services(staffId);
});

final staffWorkingHoursProvider = FutureProvider.family<List<StaffWorkingHourEntry>, String>((ref, staffId) {
  return ref.watch(staffRepositoryProvider).workingHours(staffId);
});

final staffBreaksProvider = FutureProvider.family<List<StaffBreakEntry>, String>((ref, staffId) {
  return ref.watch(staffRepositoryProvider).breaks(staffId);
});

final staffLeavesProvider = FutureProvider.family<List<StaffLeaveEntry>, String>((ref, staffId) {
  return ref.watch(staffRepositoryProvider).leaves(staffId);
});
