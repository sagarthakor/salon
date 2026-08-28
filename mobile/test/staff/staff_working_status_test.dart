import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_schedule.dart';
import 'package:salon_customer/features/staff/data/staff_working_status.dart';

void main() {
  // A Monday: 2026-08-24 was a Monday. DateTime.weekday for Monday is 1,
  // matching this app's `dayOfWeek == 1` convention (0 = Sunday).
  final monday10am = DateTime(2026, 8, 24, 10, 0);

  const workingHours = [
    StaffWorkingHourEntry(dayOfWeek: 1, isWorking: true, startTime: '09:00', endTime: '18:00'),
    StaffWorkingHourEntry(dayOfWeek: 0, isWorking: false),
  ];

  group('deriveStaffWorkingStatus', () {
    test('workingNow when today is a working day, within hours, no break, no leave', () {
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: const [], leaves: const []);
      expect(status, StaffWorkingStatus.workingNow);
    });

    test('offToday when today has no working-hours entry marked as working', () {
      final sunday = DateTime(2026, 8, 23, 10, 0); // the day before, a Sunday
      final status = deriveStaffWorkingStatus(now: sunday, workingHours: workingHours, breaks: const [], leaves: const []);
      expect(status, StaffWorkingStatus.offToday);
    });

    test('onBreak when the current time falls within a break on the current day', () {
      const breaks = [StaffBreakEntry(id: 1, dayOfWeek: 1, startTime: '09:30', endTime: '10:30')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: breaks, leaves: const []);
      expect(status, StaffWorkingStatus.onBreak);
    });

    test('a break just after the current time does not count as on-break', () {
      const breaks = [StaffBreakEntry(id: 1, dayOfWeek: 1, startTime: '10:01', endTime: '10:30')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: breaks, leaves: const []);
      expect(status, StaffWorkingStatus.workingNow);
    });

    test('onLeave takes priority over everything else when an approved leave covers today', () {
      const leaves = [StaffLeaveEntry(id: 1, startDate: '2026-08-24', endDate: '2026-08-24', status: 'approved')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: const [], leaves: leaves);
      expect(status, StaffWorkingStatus.onLeave);
    });

    test('a pending leave still counts as on-leave (mirrors the backend excluding only rejected leave)', () {
      const leaves = [StaffLeaveEntry(id: 1, startDate: '2026-08-24', endDate: '2026-08-24', status: 'pending')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: const [], leaves: leaves);
      expect(status, StaffWorkingStatus.onLeave);
    });

    test('a rejected leave is ignored entirely', () {
      const leaves = [StaffLeaveEntry(id: 1, startDate: '2026-08-24', endDate: '2026-08-24', status: 'rejected')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: const [], leaves: leaves);
      expect(status, StaffWorkingStatus.workingNow);
    });

    test('a leave range that does not cover today is ignored', () {
      const leaves = [StaffLeaveEntry(id: 1, startDate: '2026-09-01', endDate: '2026-09-05', status: 'approved')];
      final status = deriveStaffWorkingStatus(now: monday10am, workingHours: workingHours, breaks: const [], leaves: leaves);
      expect(status, StaffWorkingStatus.workingNow);
    });
  });
}
