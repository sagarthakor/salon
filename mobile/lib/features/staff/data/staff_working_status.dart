import '../../owner/staff/data/models/staff_schedule.dart';

/// Derived (never fetched, never fabricated) "what is this staff member
/// doing right now" state for the Today tab — computed entirely from real
/// working-hours/breaks/leave rows already fetched from the backend plus the
/// device clock. See STAFF_APP_ARCHITECTURE.md for why this is a pure
/// client-side derivation rather than a new backend endpoint.
enum StaffWorkingStatus { onLeave, offToday, onBreak, workingNow }

extension StaffWorkingStatusLabel on StaffWorkingStatus {
  String get label => switch (this) {
    StaffWorkingStatus.onLeave => 'On leave today',
    StaffWorkingStatus.offToday => 'Off today',
    StaffWorkingStatus.onBreak => 'Currently on break',
    StaffWorkingStatus.workingNow => 'Working now',
  };
}

StaffWorkingStatus deriveStaffWorkingStatus({
  required DateTime now,
  required List<StaffWorkingHourEntry> workingHours,
  required List<StaffBreakEntry> breaks,
  required List<StaffLeaveEntry> leaves,
}) {
  final today = _apiDate(now);
  final onLeave = leaves.any(
    (leave) => leave.status != 'rejected' && today.compareTo(leave.startDate) >= 0 && today.compareTo(leave.endDate) <= 0,
  );
  if (onLeave) return StaffWorkingStatus.onLeave;

  // Matches the backend's Carbon/PHP convention (0 = Sunday … 6 = Saturday):
  // Dart's DateTime.weekday is 1 = Monday … 7 = Sunday, so `% 7` maps Sunday
  // to 0 and leaves every other day unchanged.
  final dayOfWeek = now.weekday % 7;
  final isWorkingToday = workingHours.any((hour) => hour.dayOfWeek == dayOfWeek && hour.isWorking);
  if (!isWorkingToday) return StaffWorkingStatus.offToday;

  final nowHHmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  final onBreak = breaks.any(
    (b) => b.dayOfWeek == dayOfWeek && nowHHmm.compareTo(b.startTime) >= 0 && nowHHmm.compareTo(b.endTime) < 0,
  );
  if (onBreak) return StaffWorkingStatus.onBreak;

  return StaffWorkingStatus.workingNow;
}

String _apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
