import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../owner/staff/data/models/staff_member.dart';
import '../../../owner/staff/presentation/providers/staff_providers.dart';

/// The signed-in staff member's own profile, resolved via `GET /staff/me`
/// (never a client-supplied id — see STAFF_APP_ARCHITECTURE.md). Every other
/// staff-app screen watches this first and only proceeds once it resolves;
/// a 404 here means the account has no staff profile linked in this tenant,
/// shown as a real configuration error rather than silently created.
final staffMeProvider = FutureProvider<StaffMember>((ref) {
  return ref.watch(staffRepositoryProvider).me();
});
