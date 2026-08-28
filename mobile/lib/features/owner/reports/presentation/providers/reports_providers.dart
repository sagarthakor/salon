import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/providers.dart';
import '../../data/models/report_filter.dart';
import '../../data/repositories/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) => ReportsRepository(ref.watch(apiClientProvider)));

/// Shared across every report screen in the Reports section, so switching
/// from e.g. Revenue to Bookings keeps the same date range/branch filter
/// instead of resetting it (see instruction #49).
final reportFilterProvider = StateProvider<ReportFilter>((ref) => const ReportFilter());

final dashboardReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).dashboard(ref.watch(reportFilterProvider));
});

final revenueReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).revenue(ref.watch(reportFilterProvider));
});

final bookingReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).bookings(ref.watch(reportFilterProvider));
});

final customerReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).customers(ref.watch(reportFilterProvider));
});

final serviceReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).services(ref.watch(reportFilterProvider));
});

final staffReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).staff(ref.watch(reportFilterProvider));
});

final branchReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).branches(ref.watch(reportFilterProvider));
});

final couponReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).coupons(ref.watch(reportFilterProvider));
});

final membershipReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).memberships(ref.watch(reportFilterProvider));
});

final loyaltyReportProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(reportsRepositoryProvider).loyalty(ref.watch(reportFilterProvider));
});
